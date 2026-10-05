// SPDX-License-Identifier: GPL-2.0-only OR MIT
/*
 * HID driver for the Razer Barracuda X (2022) 2.4 GHz USB dongle
 *
 * The dongle tunnels vendor messages between the host and the headset over
 * HID report 1 of its HID interface. This driver tracks the headset's wireless
 * link and battery and exposes them as a power supply that exists only while
 * the headset is linked, as the USB wireless_status attribute and as headset
 * jack switches. USB audio stays with snd-usb-audio.
 *
 * Copyright (c) 2026 Luis Atala <luis.atala@gmail.com>
 */

#include <linux/completion.h>
#include <linux/device.h>
#include <linux/hid.h>
#include <linux/hex.h>
#include <linux/input.h>
#include <linux/jiffies.h>
#include <linux/lockdep.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/usb.h>
#include <linux/workqueue.h>

#include "hid-ids.h"

#define BARRACUDA_HID_INTERFACE		3

/*
 * Report 1 carries a tunnel chunk: 01 80 COUNT DATA[COUNT]. Chunks form a
 * stream of frames. Host frames start with "PA", device frames with "PI":
 *
 *   50 41 FAMILY SEQ LEN PAYLOAD            (family 0x06: 16-bit LEN)
 *   50 49 FAMILY SEQ ID[4] LEN16 DATA
 */
#define BARRACUDA_REPORT_ID		0x01
#define BARRACUDA_TUNNEL		0x80
#define BARRACUDA_REPORT_SIZE		64
#define BARRACUDA_CHUNK_MAX		(BARRACUDA_REPORT_SIZE - 3)
#define BARRACUDA_FRAME_MAX		256
#define BARRACUDA_FRAME_HEADER		10

#define BARRACUDA_FAMILY_ACK		0x01
#define BARRACUDA_FAMILY_DIAG		0x06
#define BARRACUDA_FAMILY_MMI		0x07
#define BARRACUDA_FAMILY_CUSTOMER	0x08
#define BARRACUDA_FAMILY_LINK		0x0e

/* Family 0x0e commands; replies are 02 00 CMD VALUE. */
#define BARRACUDA_CMD_GET_ROUTE		0xe0
#define BARRACUDA_CMD_SET_ROUTE		0xe1
#define BARRACUDA_CMD_GET_LINK		0xe3
#define BARRACUDA_CMD_GET_TRANSPORT	0xe6
#define BARRACUDA_ROUTE_LOCAL		0x00
#define BARRACUDA_ROUTE_REMOTE		0x01
#define BARRACUDA_TRANSPORT_HEADSET	0x08

/* Family 0x08 headset parameters: 04 00 PARAM OP 01 VALUE. */
#define BARRACUDA_PARAM_LINK		0x20
#define BARRACUDA_PARAM_BATTERY		0x21
#define BARRACUDA_PARAM_CABLE		0x2a
#define BARRACUDA_OP_GET		0x00
#define BARRACUDA_OP_REPLY		0x01
#define BARRACUDA_OP_REPORT		0x02

/* Family 0x06 battery voltage query; the result is little-endian mV. */
#define BARRACUDA_DIAG_GET_BATTERY	0x31
#define BARRACUDA_VOLTAGE_MIN_MV	2500
#define BARRACUDA_VOLTAGE_MAX_MV	4500

/* Serialized queries share one sequence range. */
#define BARRACUDA_LINK_ATTEMPTS		3
#define BARRACUDA_SEQ_FIRST		0x60
#define BARRACUDA_SEQ_LAST		0x7f

#define BARRACUDA_LINK_DELAY		(2 * HZ)
#define BARRACUDA_REPLY_TIMEOUT		(2 * HZ)
#define BARRACUDA_FRAGMENT_TIMEOUT	(2 * HZ)
#define BARRACUDA_REFRESH_DELAY		(3 * HZ)
#define BARRACUDA_POLL_INTERVAL		(360 * HZ)

#define BARRACUDA_UNKNOWN		(-1)

enum barracuda_event {
	BARRACUDA_LINK,
	BARRACUDA_CAPACITY,
	BARRACUDA_EXTERNAL_POWER,
};

enum barracuda_supply_action {
	BARRACUDA_SUPPLY_NONE,
	BARRACUDA_SUPPLY_REGISTER,
	BARRACUDA_SUPPLY_UNREGISTER,
	BARRACUDA_SUPPLY_NOTIFY,
};

struct barracuda_state {
	int linked;
	int capacity;
	int external_power;
};

struct barracuda {
	struct hid_device *hdev;

	/* Protects the fields below up to route_lock; taken from raw_event. */
	spinlock_t lock;
	u8 frame[BARRACUDA_FRAME_MAX];
	unsigned int frame_used;
	unsigned int frame_expected;
	unsigned long fragment_at;
	struct barracuda_state state;
	int voltage_mv;
	unsigned int attempts;
	bool stopping;
	bool stopped;
	bool changed;
	bool refresh_due;
	int jack_report;
	/* Cleared only after the local route has been verified. */
	bool route_failed;
	/*
	 * The one outstanding query, matched in barracuda_match_reply(). Data
	 * replies carry a device counter, not the query sequence; only the
	 * acknowledgment echoes it, so a route reply counts after its
	 * acknowledgment. Family 0x08 GET replies are not acknowledged.
	 */
	bool waiting;
	bool acked;
	bool read_length;
	u8 want_family;
	u8 want_seq;
	u8 want_command;
	u8 want_param;
	int reply_value;
	struct completion reply_done;

	/* Serializes query sequences and protects seq. */
	struct mutex route_lock;
	bool restoring_route;
	u8 seq;
	/* Explicit settings transactions; reads return the last reply only. */
	bool settings_waiting;
	u32 settings_token;
	u8 settings_data[203];
	u8 settings_size;

	/* Serializes battery registration; battery exists only while linked. */
	struct mutex supply_lock;
	struct power_supply *battery;
	struct power_supply_desc desc;
	int wireless_reported;

	struct input_dev *jack;
	struct delayed_work link_work;
	struct delayed_work refresh_work;
	struct work_struct supply_work;
};

static void barracuda_state_reset(struct barracuda_state *s)
{
	s->linked = BARRACUDA_UNKNOWN;
	s->capacity = BARRACUDA_UNKNOWN;
	s->external_power = BARRACUDA_UNKNOWN;
}

/* Suspend makes the link and cable unknown; the last percentage is kept. */
static void barracuda_state_suspend(struct barracuda_state *s)
{
	s->linked = BARRACUDA_UNKNOWN;
	s->external_power = BARRACUDA_UNKNOWN;
}

/* Returns true if the event changed what the power supply reports. */
static bool barracuda_state_event(struct barracuda_state *s,
				  enum barracuda_event event, int value)
{
	bool changed;

	if (event == BARRACUDA_LINK) {
		changed = s->linked != value;
		s->linked = value;
		if (!value)
			s->external_power = BARRACUDA_UNKNOWN;
		return changed;
	}
	if (s->linked == 0)
		return false;
	if (event == BARRACUDA_CAPACITY)
		s->capacity = value;
	else
		s->external_power = value;
	return true;
}

/* The first cable value after a link, including a GET reply, is no change. */
static bool barracuda_cable_changed(int previous, int value)
{
	return previous >= 0 && previous != value;
}

/* An unknown link (startup, resume) neither registers nor removes the battery. */
static enum barracuda_supply_action
barracuda_supply_action(int linked, bool registered)
{
	if (linked == 1)
		return registered ? BARRACUDA_SUPPLY_NOTIFY : BARRACUDA_SUPPLY_REGISTER;
	if (linked == 0)
		return registered ? BARRACUDA_SUPPLY_UNREGISTER : BARRACUDA_SUPPLY_NONE;
	return registered ? BARRACUDA_SUPPLY_NOTIFY : BARRACUDA_SUPPLY_NONE;
}

/* Family 0x0e reply 02 00 CMD VALUE; returns VALUE or -1 if unrelated. */
static int barracuda_link_reply(const u8 *p, unsigned int size, u8 command)
{
	if (size != 12 || p[2] != BARRACUDA_FAMILY_LINK || p[8] != 2 ||
	    p[9] != 0 || p[10] != command)
		return -1;
	return p[11];
}

/* Family 0x08 GET reply 04 00 PARAM 01 01 VALUE; returns VALUE or -1. */
static int barracuda_customer_reply(const u8 *p, unsigned int size, u8 param)
{
	if (size != 14 || p[2] != BARRACUDA_FAMILY_CUSTOMER || p[8] != 4 ||
	    p[9] != 0 || p[10] != param || p[11] != BARRACUDA_OP_REPLY ||
	    p[12] != 1)
		return -1;
	return p[13];
}

/* The allowlist excludes firmware, storage, microphone and reset commands. */
static bool barracuda_setting_valid(const u8 *p, unsigned int size)
{
	unsigned int i;

	if (size < 3 || p[1] || size != 3U + p[2])
		return false;
	switch (p[0]) {
	case 0x13:
	case 0x14:
	case 0x15:
	case 0x27:
	case 0x2c:
	case 0x2d:
		return size == 3;
	case 0x93:
		return size == 4 && (p[3] == 0 || p[3] == 7 || p[3] == 8 ||
				     p[3] == 9 || p[3] == 255);
	case 0x94:
	case 0xa7:
		return size == 4 && p[3] <= 1;
	case 0xac:
		return size == 4 && (p[3] == 0 || p[3] == 5 || p[3] == 15 ||
				     p[3] == 30 || p[3] == 45 || p[3] == 60);
	case 0xad:
		return size == 9;
	case 0x95:
		if (size != 13)
			return false;
		for (i = 3; i < size; i++)
			if (p[i] > 10)
				return false;
		return true;
	default:
		return false;
	}
}

static int barracuda_setting_reply(struct barracuda *b, const u8 *p,
				   unsigned int size)
{
	unsigned int len;

	if (size < 13 || p[2] != BARRACUDA_FAMILY_CUSTOMER ||
	    p[10] != b->want_param || p[11] != BARRACUDA_OP_REPLY)
		return -1;
	len = p[12];
	if (len > sizeof(b->settings_data) || size != 13 + len ||
	    p[8] != 3 + len || p[9])
		return -1;
	if (b->want_param == 0x15) {
		if (len != 10)
			return -1;
	} else if (b->want_param != 0x2d && len != 1) {
		return -1;
	}
	memcpy(b->settings_data, p + 13, len);
	b->settings_size = len;
	return b->want_param & 0x80 && p[13] ? -EREMOTEIO : 0;
}

/*
 * Acknowledgment FAMILY SEQ|80 STATUS RESULT. Returns the result length and
 * sets *result, -1 if unrelated or -2 if the device reported a failure.
 */
static int barracuda_ack(const u8 *p, unsigned int size, u8 family, u8 seq,
			 const u8 **result)
{
	if (size < 13 || p[2] != BARRACUDA_FAMILY_ACK || p[10] != family ||
	    p[11] != (seq | 0x80))
		return -1;
	if (p[12])
		return -2;
	*result = p + 13;
	return size - 13;
}

/* Returns the voltage in mV, or -1 if it is not a plausible battery voltage. */
static int barracuda_voltage_mv(const u8 *result, int size)
{
	int mv;

	if (size < 2)
		return -1;
	mv = result[0] | result[1] << 8;
	if (mv < BARRACUDA_VOLTAGE_MIN_MV || mv > BARRACUDA_VOLTAGE_MAX_MV)
		return -1;
	return mv;
}

/*
 * Decode link, battery and cable messages. Only the E3 reply and the
 * unsolicited 0x20 report are link evidence; GET replies are not.
 */
static bool barracuda_decode(const u8 *p, unsigned int size,
			     enum barracuda_event *event, int *value)
{
	int link = barracuda_link_reply(p, size, BARRACUDA_CMD_GET_LINK);

	if (link == 0 || link == 1) {
		*event = BARRACUDA_LINK;
		*value = link;
		return true;
	}
	if (size != 14 || p[2] != BARRACUDA_FAMILY_CUSTOMER || p[8] != 4 ||
	    p[9] != 0 || p[12] != 1 ||
	    (p[11] != BARRACUDA_OP_REPORT && p[11] != BARRACUDA_OP_REPLY))
		return false;

	*value = p[13];
	switch (p[10]) {
	case BARRACUDA_PARAM_LINK:
		*event = BARRACUDA_LINK;
		return p[11] == BARRACUDA_OP_REPORT && p[13] <= 1;
	case BARRACUDA_PARAM_BATTERY:
		*event = BARRACUDA_CAPACITY;
		return p[13] <= 100;
	case BARRACUDA_PARAM_CABLE:
		*event = BARRACUDA_EXTERNAL_POWER;
		return p[13] <= 1;
	}
	return false;
}

/* Called with b->lock held for every decoded event. */
static void barracuda_event(struct barracuda *b, enum barracuda_event event,
			    int value)
{
	int cable = b->state.external_power;

	if (!barracuda_state_event(&b->state, event, value))
		return;
	b->changed = true;
	if (event == BARRACUDA_EXTERNAL_POWER && !b->stopping &&
	    barracuda_cable_changed(cable, value))
		b->refresh_due = true;
	if (event == BARRACUDA_LINK) {
		b->jack_report = value;
		if (value == 1 && !b->stopping)
			b->refresh_due = true;
	}
}

/* Called with b->lock held for every frame; completes a pending query. */
static void barracuda_match_reply(struct barracuda *b, const u8 *p,
				  unsigned int size)
{
	const u8 *result;
	int ret;

	if (!b->waiting)
		return;
	if (b->settings_waiting) {
		ret = barracuda_setting_reply(b, p, size);
	} else if (b->want_param) {
		/* The value itself reaches the state through barracuda_decode(). */
		ret = barracuda_customer_reply(p, size, b->want_param);
	} else if (!b->acked) {
		ret = barracuda_ack(p, size, b->want_family, b->want_seq, &result);
		if (ret == -1)
			return;
		if (ret >= 0 && b->want_command) {
			/* A stale reply to an earlier query is ignored until here. */
			b->acked = true;
			return;
		}
		if (ret == -2) {
			ret = -EPROTO;
		} else if (b->read_length) {
			ret = ret == 4 && result[0] == 0xf0 &&
			      !result[1] && !result[2] && !result[3] ?
			      0 : -EPROTO;
		} else if (b->want_family == BARRACUDA_FAMILY_DIAG) {
			ret = barracuda_voltage_mv(result, ret);
			if (ret < 0)
				ret = -EPROTO;
		} else {
			ret = 0;
		}
	} else {
		ret = barracuda_link_reply(p, size, b->want_command);
	}
	if (ret == -1)
		return;
	b->reply_value = ret;
	b->waiting = false;
	complete(&b->reply_done);
}

static void barracuda_frame(struct barracuda *b, const u8 *p, unsigned int size)
{
	enum barracuda_event event;
	int value;

	if (barracuda_decode(p, size, &event, &value))
		barracuda_event(b, event, value);
	barracuda_match_reply(b, p, size);
}

/*
 * Reassemble frames from tunnel chunks, called with b->lock held. Other
 * reports, such as media keys, may arrive between chunks. After corruption
 * the stream restarts at the next chunk rather than scanning payload bytes
 * for a header.
 */
static void barracuda_feed(struct barracuda *b, const u8 *report,
			   unsigned int size)
{
	unsigned int i, count;

	if (!size || report[0] != BARRACUDA_REPORT_ID)
		return;
	if (size < 3 || report[1] != BARRACUDA_TUNNEL ||
	    report[2] > BARRACUDA_CHUNK_MAX || size < 3U + report[2]) {
		b->frame_used = 0;
		return;
	}
	count = report[2];
	for (i = 0; i < count; i++) {
		b->frame[b->frame_used++] = report[3 + i];
		if ((b->frame_used == 1 && b->frame[0] != 0x50) ||
		    (b->frame_used == 2 && b->frame[1] != 0x49)) {
			b->frame_used = 0;
			return;
		}
		if (b->frame_used == BARRACUDA_FRAME_HEADER) {
			b->frame_expected = BARRACUDA_FRAME_HEADER + b->frame[8] +
					    (b->frame[9] << 8);
			if (b->frame_expected > BARRACUDA_FRAME_MAX) {
				b->frame_used = 0;
				return;
			}
		}
		if (b->frame_used >= BARRACUDA_FRAME_HEADER &&
		    b->frame_used == b->frame_expected) {
			barracuda_frame(b, b->frame, b->frame_used);
			b->frame_used = 0;
		}
	}
}

static int barracuda_raw_event(struct hid_device *hdev,
			       struct hid_report *report, u8 *data, int size)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;
	bool changed, refresh;
	int jack;

	if (report->type != HID_INPUT_REPORT || size <= 0 ||
	    data[0] != BARRACUDA_REPORT_ID)
		return 0;

	spin_lock_irqsave(&b->lock, flags);
	if (b->stopped) {
		spin_unlock_irqrestore(&b->lock, flags);
		return 0;
	}
	if (b->frame_used &&
	    time_after(jiffies, b->fragment_at + BARRACUDA_FRAGMENT_TIMEOUT))
		b->frame_used = 0;
	b->changed = false;
	barracuda_feed(b, data, size);
	b->fragment_at = jiffies;
	changed = b->changed;
	refresh = b->refresh_due;
	b->refresh_due = false;
	jack = b->jack_report;
	b->jack_report = BARRACUDA_UNKNOWN;
	spin_unlock_irqrestore(&b->lock, flags);

	if (jack != BARRACUDA_UNKNOWN) {
		input_report_switch(b->jack, SW_HEADPHONE_INSERT, jack);
		input_report_switch(b->jack, SW_MICROPHONE_INSERT, jack);
		input_sync(b->jack);
	}
	/* Registering and notifying the power supply may sleep. */
	if (changed)
		schedule_work(&b->supply_work);
	if (refresh)
		mod_delayed_work(system_long_wq, &b->refresh_work,
				 BARRACUDA_REFRESH_DELAY);

	/* Leave the report to hidraw and the media-key input path. */
	return 0;
}

static void barracuda_fill(u8 *buf, u8 family, u8 seq, const u8 *payload,
			   u8 len)
{
	/* Family 0x06 has a 16-bit length; the others an 8-bit one. */
	unsigned int start = family == BARRACUDA_FAMILY_DIAG ? 9 : 8;

	memset(buf, 0, BARRACUDA_REPORT_SIZE);
	buf[0] = BARRACUDA_REPORT_ID;
	buf[1] = BARRACUDA_TUNNEL;
	buf[2] = start + len - 3;
	buf[3] = 0x50;
	buf[4] = 0x41;
	buf[5] = family;
	buf[6] = seq;
	buf[7] = len;
	memcpy(buf + start, payload, len);
}

/* Send one query and wait for its matching reply. */
static int barracuda_request(struct barracuda *b, u8 family, const u8 *payload,
			     u8 len, u8 reply_command, u8 reply_param)
{
	struct completion *done = &b->reply_done;
	unsigned long flags;
	u8 *buf;
	int ret, waited = 0;

	lockdep_assert_held(&b->route_lock);

	buf = kmalloc(BARRACUDA_REPORT_SIZE, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;
	if (b->seq < BARRACUDA_SEQ_FIRST || b->seq >= BARRACUDA_SEQ_LAST)
		b->seq = BARRACUDA_SEQ_FIRST;
	else
		b->seq++;
	barracuda_fill(buf, family, b->seq, payload, len);

	spin_lock_irqsave(&b->lock, flags);
	if (b->stopping && !b->restoring_route) {
		spin_unlock_irqrestore(&b->lock, flags);
		kfree(buf);
		return -ESHUTDOWN;
	}
	b->read_length = family == BARRACUDA_FAMILY_DIAG &&
			 payload[0] == 0x25;
	b->want_family = family;
	b->want_seq = b->seq;
	b->want_command = reply_command;
	b->want_param = reply_param;
	b->reply_value = -ETIMEDOUT;
	reinit_completion(&b->reply_done);
	b->acked = false;
	b->waiting = true;
	spin_unlock_irqrestore(&b->lock, flags);

	ret = hid_hw_output_report(b->hdev, buf, BARRACUDA_REPORT_SIZE);
	kfree(buf);
	if (ret == BARRACUDA_REPORT_SIZE) {
		if (b->restoring_route)
			waited = wait_for_completion_timeout(done,
							     BARRACUDA_REPLY_TIMEOUT);
		else
			waited = wait_for_completion_interruptible_timeout(done,
									   BARRACUDA_REPLY_TIMEOUT);
	}

	spin_lock_irqsave(&b->lock, flags);
	b->waiting = false;
	ret = ret == BARRACUDA_REPORT_SIZE ?
		(waited < 0 ? waited : b->reply_value) : -EIO;
	spin_unlock_irqrestore(&b->lock, flags);
	return ret;
}

static int barracuda_get(struct barracuda *b, u8 command)
{
	return barracuda_request(b, BARRACUDA_FAMILY_LINK, &command, 1,
				 command, 0);
}

/* Serialize the entire startup exchange, including its response wait. */
static void barracuda_link_query(struct work_struct *work)
{
	struct barracuda *b = container_of(to_delayed_work(work),
					   struct barracuda, link_work);
	unsigned long flags, next, now;

	mutex_lock(&b->route_lock);
	spin_lock_irqsave(&b->lock, flags);
	if (b->stopping || b->state.linked != BARRACUDA_UNKNOWN ||
	    b->attempts >= BARRACUDA_LINK_ATTEMPTS) {
		spin_unlock_irqrestore(&b->lock, flags);
		goto out;
	}
	b->attempts++;
	next = jiffies + BARRACUDA_LINK_DELAY;
	spin_unlock_irqrestore(&b->lock, flags);

	barracuda_get(b, BARRACUDA_CMD_GET_LINK);

	spin_lock_irqsave(&b->lock, flags);
	now = jiffies;
	if (!b->stopping && b->state.linked == BARRACUDA_UNKNOWN &&
	    b->attempts < BARRACUDA_LINK_ATTEMPTS)
		schedule_delayed_work(&b->link_work,
				      time_before(now, next) ? next - now : 0);
	spin_unlock_irqrestore(&b->lock, flags);
out:
	mutex_unlock(&b->route_lock);
}

/* E1 selects the volatile destination of diagnostic queries; E0 reads it. */
static int barracuda_set_route(struct barracuda *b, u8 route)
{
	const u8 payload[] = { BARRACUDA_CMD_SET_ROUTE, route };
	int ret;

	ret = barracuda_request(b, BARRACUDA_FAMILY_LINK, payload,
				sizeof(payload), 0, 0);
	if (ret)
		return ret;
	return barracuda_get(b, BARRACUDA_CMD_GET_ROUTE) == route ? 0 : -EPROTO;
}

/*
 * The dongle forwards battery queries to the headset only while diagnostic
 * queries are routed to it. Select that route over the existing headset
 * transport (E6 bit 0x08, never created here). *selected tells
 * barracuda_route_end() whether the route may have changed.
 */
static int barracuda_route_begin(struct barracuda *b, bool *selected)
{
	unsigned long flags;
	bool failed;
	int transport;

	lockdep_assert_held(&b->route_lock);

	*selected = false;
	spin_lock_irqsave(&b->lock, flags);
	failed = b->route_failed;
	spin_unlock_irqrestore(&b->lock, flags);
	if (failed) {
		/* A link event is not evidence that route restoration succeeded. */
		if (barracuda_get(b, BARRACUDA_CMD_GET_ROUTE) != BARRACUDA_ROUTE_LOCAL)
			return -EIO;
		spin_lock_irqsave(&b->lock, flags);
		b->route_failed = false;
		spin_unlock_irqrestore(&b->lock, flags);
	}
	transport = barracuda_get(b, BARRACUDA_CMD_GET_TRANSPORT);
	if (transport < 0 || !(transport & BARRACUDA_TRANSPORT_HEADSET) ||
	    barracuda_get(b, BARRACUDA_CMD_GET_ROUTE) != BARRACUDA_ROUTE_LOCAL)
		return -ENODEV;
	*selected = true;
	return barracuda_set_route(b, BARRACUDA_ROUTE_REMOTE);
}

/*
 * Restore the local route, retrying once. If that fails, stop using the
 * route until a query verifies it is local. Returns false on failure.
 */
static bool barracuda_route_end(struct barracuda *b, bool selected)
{
	unsigned long flags;
	int attempt;

	lockdep_assert_held(&b->route_lock);

	if (!selected)
		return true;
	b->restoring_route = true;
	for (attempt = 0; attempt < 2; attempt++) {
		if (!barracuda_set_route(b, BARRACUDA_ROUTE_LOCAL)) {
			spin_lock_irqsave(&b->lock, flags);
			b->route_failed = false;
			spin_unlock_irqrestore(&b->lock, flags);
			b->restoring_route = false;
			return true;
		}
	}
	b->restoring_route = false;
	spin_lock_irqsave(&b->lock, flags);
	b->route_failed = true;
	spin_unlock_irqrestore(&b->lock, flags);
	hid_warn(b->hdev, "could not restore the local diagnostic route\n");
	return false;
}

static int barracuda_customer_get(struct barracuda *b, u8 param)
{
	const u8 payload[] = { param, BARRACUDA_OP_GET, 0 };

	return barracuda_request(b, BARRACUDA_FAMILY_CUSTOMER, payload,
				 sizeof(payload), 0, param);
}

static int barracuda_read_voltage(struct barracuda *b)
{
	static const u8 payload[] = { BARRACUDA_DIAG_GET_BATTERY };

	return barracuda_request(b, BARRACUDA_FAMILY_DIAG, payload,
				 sizeof(payload), 0, 0);
}

static bool barracuda_refresh_wanted(struct barracuda *b)
{
	unsigned long flags;
	bool wanted;

	spin_lock_irqsave(&b->lock, flags);
	wanted = !b->stopping && b->state.linked == 1;
	spin_unlock_irqrestore(&b->lock, flags);
	return wanted;
}

/*
 * The headset reports its battery only when the percentage changes. On each
 * confirmed link, after cable changes and periodically while linked, ask for
 * the percentage, cable state and voltage. Replies to the percentage and cable
 * GETs are decoded like the headset's own reports.
 */
static void barracuda_refresh(struct work_struct *work)
{
	struct barracuda *b = container_of(to_delayed_work(work),
					   struct barracuda, refresh_work);
	int battery = -1, cable = -1, mv = -1;
	unsigned long flags;
	bool selected, restored;

	if (!barracuda_refresh_wanted(b))
		return;

	/* Suspend and removal wait for this: stop early, but restore the route. */
	mutex_lock(&b->route_lock);
	if (!barracuda_route_begin(b, &selected) && barracuda_refresh_wanted(b)) {
		battery = barracuda_customer_get(b, BARRACUDA_PARAM_BATTERY);
		if (barracuda_refresh_wanted(b))
			cable = barracuda_customer_get(b, BARRACUDA_PARAM_CABLE);
		if (barracuda_refresh_wanted(b))
			mv = barracuda_read_voltage(b);
	}
	restored = barracuda_route_end(b, selected);
	mutex_unlock(&b->route_lock);

	hid_dbg(b->hdev, "refresh: battery %d, cable %d, %d mV\n",
		battery, cable, mv);
	if (mv >= 0) {
		spin_lock_irqsave(&b->lock, flags);
		b->voltage_mv = mv;
		spin_unlock_irqrestore(&b->lock, flags);
		schedule_work(&b->supply_work);
	}
	if (restored && barracuda_refresh_wanted(b))
		queue_delayed_work(system_long_wq, &b->refresh_work,
				   BARRACUDA_POLL_INTERVAL);
}

/* Only an explicit sysfs write sends this one-shot headset command. */
static ssize_t headset_poweroff_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	static const u8 read_length[] = {
		0x25, 0x34, 0x12, 0x5a, 0x5a, 0x01, 0x00,
		0x00, 0x00, 0xf0, 0x00, 0x00, 0x00,
	};
	static const u8 poweroff[] = { 0x08, 0x00, 0x02 };
	struct barracuda *b = hid_get_drvdata(to_hid_device(dev));
	bool selected = false;
	int ret;

	if (!sysfs_streq(buf, "1"))
		return -EINVAL;
	if (!mutex_trylock(&b->route_lock))
		return -EBUSY;
	if (!barracuda_refresh_wanted(b)) {
		ret = -ENOTCONN;
		goto out;
	}
	ret = barracuda_get(b, BARRACUDA_CMD_GET_LINK);
	if (ret != 1) {
		ret = ret < 0 ? ret : -ENOTCONN;
		goto out;
	}
	ret = barracuda_route_begin(b, &selected);
	if (ret)
		goto out;
	ret = barracuda_request(b, BARRACUDA_FAMILY_DIAG, read_length,
				sizeof(read_length), 0, 0);
	if (ret)
		goto out;
	ret = barracuda_request(b, BARRACUDA_FAMILY_MMI, poweroff,
				sizeof(poweroff), 0, 0);
	/* Once sent, neither timeout nor a signal may restart shutdown. */
	if (ret == -ETIMEDOUT || ret == -ERESTARTSYS)
		ret = 0;
out:
	if (!barracuda_route_end(b, selected))
		ret = -EIO;
	mutex_unlock(&b->route_lock);
	return ret ? ret : count;
}
static DEVICE_ATTR_WO(headset_poweroff);

/* Token plus hex payload. No query is ever sent by reading this attribute. */
static ssize_t headset_settings_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	static const u8 read_length[] = {
		0x25, 0x34, 0x12, 0x5a, 0x5a, 0x01, 0x00,
		0x00, 0x00, 0xf0, 0x00, 0x00, 0x00,
	};
	struct barracuda *b = hid_get_drvdata(to_hid_device(dev));
	unsigned long flags;
	u8 payload[13], token[4];
	unsigned int size;
	bool selected = false;
	int ret;

	if (count < 15 || count > 36 || buf[8] != ' ')
		return -EINVAL;
	size = count - 9;
	if (buf[count - 1] == '\n')
		size--;
	if (size % 2 || size / 2 > sizeof(payload) ||
	    hex2bin(token, buf, sizeof(token)) ||
	    hex2bin(payload, buf + 9, size / 2) ||
	    !barracuda_setting_valid(payload, size / 2))
		return -EINVAL;
	if (!mutex_trylock(&b->route_lock))
		return -EBUSY;
	if (!barracuda_refresh_wanted(b)) {
		ret = -ENOTCONN;
		goto out;
	}
	ret = barracuda_get(b, BARRACUDA_CMD_GET_LINK);
	if (ret != 1) {
		ret = ret < 0 ? ret : -ENOTCONN;
		goto out;
	}
	ret = barracuda_route_begin(b, &selected);
	if (ret)
		goto out;
	ret = barracuda_request(b, BARRACUDA_FAMILY_DIAG, read_length,
				sizeof(read_length), 0, 0);
	if (ret)
		goto out;
	spin_lock_irqsave(&b->lock, flags);
	b->settings_waiting = true;
	b->settings_size = 0;
	spin_unlock_irqrestore(&b->lock, flags);
	ret = barracuda_request(b, BARRACUDA_FAMILY_CUSTOMER, payload,
				size / 2, 0, payload[0]);
	spin_lock_irqsave(&b->lock, flags);
	b->settings_waiting = false;
	spin_unlock_irqrestore(&b->lock, flags);
out:
	if (!barracuda_route_end(b, selected))
		ret = -EIO;
	if (!ret)
		b->settings_token = (u32)token[0] << 24 | token[1] << 16 |
				    token[2] << 8 | token[3];
	else
		b->settings_size = 0;
	mutex_unlock(&b->route_lock);
	return ret ? ret : count;
}

static ssize_t headset_settings_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	struct barracuda *b = hid_get_drvdata(to_hid_device(dev));
	ssize_t ret;

	if (mutex_lock_interruptible(&b->route_lock))
		return -ERESTARTSYS;
	ret = sysfs_emit(buf, "%08x %*phN\n", b->settings_token,
			 b->settings_size, b->settings_data);
	mutex_unlock(&b->route_lock);
	return ret;
}
static DEVICE_ATTR_RW(headset_settings);

static struct attribute *barracuda_attrs[] = {
	&dev_attr_headset_poweroff.attr,
	&dev_attr_headset_settings.attr,
	NULL,
};
ATTRIBUTE_GROUPS(barracuda);

static const enum power_supply_property barracuda_properties[] = {
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CAPACITY_LEVEL,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_SCOPE,
	POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_MANUFACTURER,
};

static int barracuda_get_property(struct power_supply *psy,
				  enum power_supply_property prop,
				  union power_supply_propval *val)
{
	struct barracuda *b = power_supply_get_drvdata(psy);
	bool present, capacity_valid;
	unsigned long flags;
	int ret = 0;

	spin_lock_irqsave(&b->lock, flags);
	present = b->state.linked == 1;
	capacity_valid = present && b->state.capacity >= 0;
	switch (prop) {
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = present;
		break;
	case POWER_SUPPLY_PROP_STATUS:
		val->intval = POWER_SUPPLY_STATUS_UNKNOWN;
		if (!present || b->state.external_power < 0)
			break;
		/*
		 * The headset never reports charge termination; a cable with
		 * no percentage yet is charging.
		 */
		if (!b->state.external_power)
			val->intval = POWER_SUPPLY_STATUS_DISCHARGING;
		else if (capacity_valid && b->state.capacity >= 100)
			val->intval = POWER_SUPPLY_STATUS_FULL;
		else
			val->intval = POWER_SUPPLY_STATUS_CHARGING;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		if (capacity_valid)
			val->intval = b->state.capacity;
		else
			ret = -ENODATA;
		break;
	case POWER_SUPPLY_PROP_CAPACITY_LEVEL:
		/*
		 * Userspace needs a readable level to list the battery before the
		 * first percentage arrives, which may take minutes.
		 */
		val->intval = POWER_SUPPLY_CAPACITY_LEVEL_UNKNOWN;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		if (present && b->voltage_mv >= 0)
			val->intval = b->voltage_mv * 1000;
		else
			ret = -ENODATA;
		break;
	case POWER_SUPPLY_PROP_SCOPE:
		val->intval = POWER_SUPPLY_SCOPE_DEVICE;
		break;
	case POWER_SUPPLY_PROP_MODEL_NAME:
		/* The headset's name; the USB strings name the dongle and its chip vendor. */
		val->strval = "Razer Barracuda X (2022)";
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		val->strval = "Razer";
		break;
	default:
		ret = -EINVAL;
		break;
	}
	spin_unlock_irqrestore(&b->lock, flags);
	return ret;
}

static void barracuda_set_wireless_status(struct barracuda *b, int linked)
{
	struct usb_interface *intf = to_usb_interface(b->hdev->dev.parent);

	if (linked < 0 || linked == b->wireless_reported)
		return;
	b->wireless_reported = linked;
	usb_set_wireless_status(intf, linked ? USB_WIRELESS_STATUS_CONNECTED :
					       USB_WIRELESS_STATUS_DISCONNECTED);
}

static void barracuda_supply_work(struct work_struct *work)
{
	struct barracuda *b = container_of(work, struct barracuda, supply_work);
	struct power_supply_config config = { .drv_data = b };
	struct power_supply *battery;
	unsigned long flags;
	bool stopping;
	int linked;

	spin_lock_irqsave(&b->lock, flags);
	linked = b->state.linked;
	stopping = b->stopping;
	spin_unlock_irqrestore(&b->lock, flags);

	mutex_lock(&b->supply_lock);
	switch (barracuda_supply_action(linked, b->battery)) {
	case BARRACUDA_SUPPLY_REGISTER:
		if (stopping)
			break;
		battery = power_supply_register(&b->hdev->dev, &b->desc, &config);
		if (IS_ERR(battery)) {
			hid_warn(b->hdev, "failed to register battery: %pe\n",
				 battery);
			break;
		}
		power_supply_powers(battery, &b->hdev->dev);
		b->battery = battery;
		break;
	case BARRACUDA_SUPPLY_UNREGISTER:
		power_supply_unregister(b->battery);
		b->battery = NULL;
		break;
	case BARRACUDA_SUPPLY_NOTIFY:
		power_supply_changed(b->battery);
		break;
	case BARRACUDA_SUPPLY_NONE:
		break;
	}
	barracuda_set_wireless_status(b, linked);
	mutex_unlock(&b->supply_lock);
}

/*
 * The dongle is a UAC1 device without jack detection. Report the headset link
 * as jack switches on an input device under the same USB device, so that a
 * sound driver can create jack controls from it.
 */
static int barracuda_jack_create(struct barracuda *b)
{
	struct hid_device *hdev = b->hdev;
	struct input_dev *jack;

	jack = devm_input_allocate_device(&hdev->dev);
	if (!jack)
		return -ENOMEM;
	jack->name = devm_kasprintf(&hdev->dev, GFP_KERNEL, "%s Headset Jack",
				    hdev->name);
	if (!jack->name)
		return -ENOMEM;
	jack->phys = hdev->phys;
	jack->uniq = hdev->uniq;
	jack->id.bustype = hdev->bus;
	jack->id.vendor = hdev->vendor;
	jack->id.product = hdev->product;
	jack->id.version = hdev->version;
	input_set_capability(jack, EV_SW, SW_HEADPHONE_INSERT);
	input_set_capability(jack, EV_SW, SW_MICROPHONE_INSERT);
	b->jack = jack;
	return input_register_device(jack);
}

static void barracuda_init(struct barracuda *b, struct hid_device *hdev)
{
	b->hdev = hdev;
	spin_lock_init(&b->lock);
	mutex_init(&b->route_lock);
	mutex_init(&b->supply_lock);
	init_completion(&b->reply_done);
	barracuda_state_reset(&b->state);
	b->voltage_mv = BARRACUDA_UNKNOWN;
	b->jack_report = BARRACUDA_UNKNOWN;
	b->wireless_reported = BARRACUDA_UNKNOWN;
	INIT_DELAYED_WORK(&b->link_work, barracuda_link_query);
	INIT_DELAYED_WORK(&b->refresh_work, barracuda_refresh);
	INIT_WORK(&b->supply_work, barracuda_supply_work);
}

static int barracuda_probe(struct hid_device *hdev,
			   const struct hid_device_id *id)
{
	struct usb_interface *intf;
	struct barracuda *b;
	int ret;

	if (!hid_is_usb(hdev))
		return -EINVAL;
	intf = to_usb_interface(hdev->dev.parent);
	if (intf->cur_altsetting->desc.bInterfaceNumber != BARRACUDA_HID_INTERFACE)
		return -ENODEV;

	b = devm_kzalloc(&hdev->dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;
	barracuda_init(b, hdev);
	hid_set_drvdata(hdev, b);

	ret = hid_parse(hdev);
	if (ret)
		return ret;

	b->desc.name = devm_kasprintf(&hdev->dev, GFP_KERNEL,
				      "razer-barracuda-%s-battery",
				      dev_name(&hdev->dev));
	if (!b->desc.name)
		return -ENOMEM;
	b->desc.type = POWER_SUPPLY_TYPE_BATTERY;
	b->desc.properties = barracuda_properties;
	b->desc.num_properties = ARRAY_SIZE(barracuda_properties);
	b->desc.get_property = barracuda_get_property;

	ret = barracuda_jack_create(b);
	if (ret)
		return ret;

	ret = hid_hw_start(hdev, HID_CONNECT_DEFAULT);
	if (ret)
		return ret;
	ret = hid_hw_open(hdev);
	if (ret) {
		hid_hw_stop(hdev);
		return ret;
	}

	/* The battery is registered by barracuda_supply_work() once linked. */
	schedule_delayed_work(&b->link_work, HZ);
	return 0;
}

static void barracuda_stop(struct barracuda *b)
{
	unsigned long flags;

	/* A running refresh still needs replies to restore the route. */
	spin_lock_irqsave(&b->lock, flags);
	b->stopping = true;
	spin_unlock_irqrestore(&b->lock, flags);
	cancel_delayed_work_sync(&b->link_work);
	cancel_delayed_work_sync(&b->refresh_work);
	/* Wait for an explicit control to finish restoring the route. */
	mutex_lock(&b->route_lock);
	mutex_unlock(&b->route_lock);

	spin_lock_irqsave(&b->lock, flags);
	b->stopped = true;
	spin_unlock_irqrestore(&b->lock, flags);
	cancel_work_sync(&b->supply_work);
}

static void barracuda_remove(struct hid_device *hdev)
{
	struct barracuda *b = hid_get_drvdata(hdev);

	barracuda_stop(b);
	mutex_lock(&b->supply_lock);
	if (b->battery)
		power_supply_unregister(b->battery);
	b->battery = NULL;
	mutex_unlock(&b->supply_lock);
	hid_hw_close(hdev);
	hid_hw_stop(hdev);
}

static int barracuda_suspend(struct hid_device *hdev, pm_message_t message)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;

	barracuda_stop(b);
	spin_lock_irqsave(&b->lock, flags);
	barracuda_state_suspend(&b->state);
	b->frame_used = 0;
	spin_unlock_irqrestore(&b->lock, flags);

	/* The link is unknown: keep the battery, reported as not present. */
	mutex_lock(&b->supply_lock);
	if (b->battery)
		power_supply_changed(b->battery);
	mutex_unlock(&b->supply_lock);
	return 0;
}

static int barracuda_resume(struct hid_device *hdev)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;

	spin_lock_irqsave(&b->lock, flags);
	b->stopped = false;
	b->stopping = false;
	barracuda_state_suspend(&b->state);
	b->frame_used = 0;
	b->attempts = 0;
	spin_unlock_irqrestore(&b->lock, flags);
	schedule_delayed_work(&b->link_work, HZ);
	return 0;
}

static const struct hid_device_id barracuda_devices[] = {
	{ HID_USB_DEVICE(USB_VENDOR_ID_RAZER,
			 USB_DEVICE_ID_RAZER_BARRACUDA_X_2022) },
	{ }
};
MODULE_DEVICE_TABLE(hid, barracuda_devices);

static struct hid_driver barracuda_driver = {
	.name = "razer-barracuda",
	.id_table = barracuda_devices,
	.probe = barracuda_probe,
	.remove = barracuda_remove,
	.raw_event = barracuda_raw_event,
	.suspend = pm_ptr(barracuda_suspend),
	.resume = pm_ptr(barracuda_resume),
	.reset_resume = pm_ptr(barracuda_resume),
	.driver.dev_groups = barracuda_groups,
};
module_hid_driver(barracuda_driver);

#if IS_ENABLED(CONFIG_HID_RAZER_BARRACUDA_KUNIT_TEST)
#include "hid-razer-barracuda-test.c"
#endif

MODULE_AUTHOR("Luis Atala <luis.atala@gmail.com>");
MODULE_DESCRIPTION("HID driver for the Razer Barracuda X (2022) dongle");
MODULE_LICENSE("Dual MIT/GPL");
