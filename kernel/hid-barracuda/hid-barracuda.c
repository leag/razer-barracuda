// SPDX-License-Identifier: MIT
/* Razer Barracuda X (2022) USB HID battery support. */
#include <linux/completion.h>
#include <linux/hid.h>
#include <linux/input.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/usb.h>
#include <linux/version.h>
#include <linux/workqueue.h>

#include "barracuda-state.h"

#define BARRACUDA_VENDOR 0x1532
#define BARRACUDA_PRODUCT 0x0552
#define BARRACUDA_MIN_POLL 30

/* Like bq27xxx_battery: seconds between refreshes while linked; 0 disables. */
static unsigned int poll_interval = 360;
module_param(poll_interval, uint, 0644);
MODULE_PARM_DESC(poll_interval,
		 "battery, cable and voltage refresh interval in seconds while linked (0 disables, minimum 30)");

/* Like bq27xxx_battery's 5 s cache: reading voltage_now re-reads older values. */
static unsigned int voltage_max_age = 60;
module_param(voltage_max_age, uint, 0644);
MODULE_PARM_DESC(voltage_max_age,
		 "seconds a voltage_now reading stays valid before a read queries the headset (0: refreshes only)");

struct barracuda {
	struct hid_device *hdev;
	/* Registered only while linked; guarded by supply_lock. */
	struct power_supply *battery;
	struct mutex supply_lock;
	struct work_struct supply_work;
	int wireless_reported;	/* last wireless_status link value, or unknown */
	struct power_supply_desc desc;
	spinlock_t lock;
	struct barracuda_stream stream;
	struct delayed_work query_work;
	struct delayed_work refresh_work;
	struct barracuda_state state;
	unsigned long fragment_at;
	unsigned int attempts;
	bool stopped;
	bool stopping;
	bool changed;
	bool refresh_due;
	/* One outstanding driver query, correlated in barracuda_frame(). */
	struct completion reply_done;
	bool waiting;
	u8 want_family;
	u8 want_seq;
	u8 want_command;
	u8 want_param;
	u8 seq;
	int reply_value;
	/* Last headset voltage and when it was read; -1 if unknown. */
	int voltage_mv;
	unsigned long voltage_at;
	/* Serializes remote-route sequences; one query slot is shared. */
	struct mutex route_lock;
	/* A failed restoration stops remote-route use until the next link. */
	bool route_failed;
	/*
	 * Headset link as jack switches, like hid-playstation's "Headset Jack":
	 * the dongle is a UAC1 device without jack detection of its own.
	 */
	struct input_dev *jack;
	int jack_report;	/* link value to report, or BARRACUDA_UNKNOWN */
};

static void barracuda_voltage_on_demand(struct barracuda *b);

static enum power_supply_property barracuda_properties[] = {
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
	unsigned long flags;
	bool present, capacity_valid;
	int ret = 0;

	/* May sleep, like bq27xxx_battery's cache refresh in get_property. */
	if (prop == POWER_SUPPLY_PROP_VOLTAGE_NOW)
		barracuda_voltage_on_demand(b);
	spin_lock_irqsave(&b->lock, flags);
	present = barracuda_state_present(&b->state);
	capacity_valid = present && b->state.capacity >= 0;
	switch (prop) {
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = present;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		if (!capacity_valid)
			ret = -ENODATA;
		else
			val->intval = b->state.capacity;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		if (!present || b->voltage_mv < 0)
			ret = -ENODATA;
		else
			val->intval = b->voltage_mv * 1000;
		break;
	case POWER_SUPPLY_PROP_CAPACITY_LEVEL:
		/* Keep discovery possible while precise capacity is unavailable. */
		val->intval = POWER_SUPPLY_CAPACITY_LEVEL_UNKNOWN;
		break;
	case POWER_SUPPLY_PROP_STATUS:
		val->intval = POWER_SUPPLY_STATUS_UNKNOWN;
		if (!present || b->state.external_power < 0)
			break;
		if (!b->state.external_power)
			val->intval = POWER_SUPPLY_STATUS_DISCHARGING;
		else if (capacity_valid && b->state.capacity < 100)
			val->intval = POWER_SUPPLY_STATUS_CHARGING;
		/* The headset never signals termination; plugged in at 100% is shown full. */
		else if (capacity_valid)
			val->intval = POWER_SUPPLY_STATUS_FULL;
		break;
	case POWER_SUPPLY_PROP_SCOPE:
		val->intval = POWER_SUPPLY_SCOPE_DEVICE;
		break;
	case POWER_SUPPLY_PROP_MODEL_NAME:
		val->strval = "Razer Barracuda X (2022)";
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		val->strval = "Razer";
		break;
	default:
		ret = -EINVAL;
	}
	spin_unlock_irqrestore(&b->lock, flags);
	return ret;
}

/* Called under lock from the bounded stream decoder. */
static void barracuda_event(void *context, enum barracuda_event event, int value)
{
	struct barracuda *b = context;
	int cable = b->state.external_power;

	if (!barracuda_state_event(&b->state, event, value))
		return;
	/* Plugging or unplugging changes the voltage; read it again soon. */
	if (event == BARRACUDA_EXTERNAL_POWER && !b->stopping &&
	    barracuda_cable_changed(cable, value))
		b->refresh_due = true;
	b->changed = true;
	if (event == BARRACUDA_LINK && value == 1 && !b->stopping) {
		b->refresh_due = true;
		b->route_failed = false;
	}
	/* Only confirmed transitions; unknown keeps the last reported state. */
	if (event == BARRACUDA_LINK)
		b->jack_report = value;
}

/* Called under lock for every complete frame; completes a pending query. */
static void barracuda_frame(void *context, const unsigned char *p, unsigned int size)
{
	struct barracuda *b = context;
	const unsigned char *result;
	int len;

	if (!b->waiting)
		return;
	if (b->want_command) {
		len = barracuda_link_reply(p, size, b->want_command);
	} else if (b->want_param) {
		/* The value itself reaches the state through barracuda_decode(). */
		len = barracuda_customer_reply(p, size, b->want_param);
	} else {
		len = barracuda_ack(p, size, b->want_family, b->want_seq, &result);
		if (len >= 0 && b->want_family == 6) {
			/* Family-6 results carry a value; only GET_BATTERY is sent. */
			len = barracuda_voltage_mv(result, len);
			if (len < 0)
				len = -EPROTO;
		} else if (len >= 0) {
			len = 0;
		} else if (len == -2) {
			len = -EPROTO;
		}
	}
	if (len == -1)
		return;
	b->reply_value = len;
	b->waiting = false;
	complete(&b->reply_done);
}

static int barracuda_raw_event(struct hid_device *hdev, struct hid_report *report,
			      u8 *data, int size)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;
	bool changed, refresh;
	int jack;

	if (size <= 0 || data[0] != 1 || report->type != HID_INPUT_REPORT)
		return 0;
	spin_lock_irqsave(&b->lock, flags);
	if (b->stopped) {
		spin_unlock_irqrestore(&b->lock, flags);
		return 0;
	}
	if (b->stream.used && time_after(jiffies, b->fragment_at + 2 * HZ))
		b->stream.used = 0;
	b->changed = false;
	barracuda_feed(&b->stream, data, size, barracuda_event, barracuda_frame, b);
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
	/* Registering, removing and notifying the battery may sleep. */
	if (changed)
		schedule_work(&b->supply_work);
	if (refresh) {
		/* Bring a pending periodic refresh forward; safe in this context. */
		cancel_delayed_work(&b->refresh_work);
		schedule_delayed_work(&b->refresh_work, 3 * HZ);
	}
	/* Preserve hidraw and the normal media-key input path. */
	return 0;
}

static void barracuda_query(struct work_struct *work)
{
	struct barracuda *b = container_of(to_delayed_work(work),
					 struct barracuda, query_work);
	unsigned long flags;
	u8 *buf;
	int ret;

	/* USB transfers require a DMA-safe buffer, not a stack buffer. */
	buf = kzalloc(64, GFP_KERNEL);
	if (!buf)
		return;
	spin_lock_irqsave(&b->lock, flags);
	if (b->stopped || b->state.linked != BARRACUDA_UNKNOWN || b->attempts >= 3) {
		spin_unlock_irqrestore(&b->lock, flags);
		kfree(buf);
		return;
	}
	b->attempts++;
	memcpy(buf, "\x01\x80\x06\x50\x41\x0e", 6);
	buf[6] = b->attempts;
	buf[7] = 1;
	buf[8] = 0xe3;
	spin_unlock_irqrestore(&b->lock, flags);
	ret = hid_hw_output_report(b->hdev, buf, 64);
	kfree(buf);
	/* Failed writes/timeouts retain unknown state and passive monitoring. */
	spin_lock_irqsave(&b->lock, flags);
	if (ret == 64 && !b->stopped && b->state.linked == BARRACUDA_UNKNOWN &&
	    b->attempts < 3)
		schedule_delayed_work(&b->query_work, 2 * HZ);
	spin_unlock_irqrestore(&b->lock, flags);
}

/* Send one query and wait for its correlated reply; sleeps (workqueue only). */
static int barracuda_request(struct barracuda *b, u8 family, const u8 *payload,
			     u8 len, u8 reply_command, u8 reply_param)
{
	unsigned long flags;
	unsigned int n;
	u8 *buf, seq;
	int ret;

	buf = kzalloc(64, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;
	/* Stay clear of the startup E3 query and userspace sequence numbers. */
	b->seq = b->seq < 0x60 || b->seq >= 0x7f ? 0x60 : b->seq + 1;
	seq = b->seq;
	memcpy(buf, "\x01\x80\x00\x50\x41", 5);
	buf[5] = family;
	buf[6] = seq;
	buf[7] = len;
	n = family == 6 ? 9 : 8;	/* family 6 uses a 16-bit length */
	memcpy(buf + n, payload, len);
	buf[2] = n + len - 3;
	spin_lock_irqsave(&b->lock, flags);
	b->want_family = family;
	b->want_seq = seq;
	b->want_command = reply_command;
	b->want_param = reply_param;
	b->reply_value = -ETIMEDOUT;
	reinit_completion(&b->reply_done);
	b->waiting = true;
	spin_unlock_irqrestore(&b->lock, flags);
	ret = hid_hw_output_report(b->hdev, buf, 64);
	kfree(buf);
	if (ret == 64)
		wait_for_completion_timeout(&b->reply_done, 2 * HZ);
	spin_lock_irqsave(&b->lock, flags);
	b->waiting = false;
	ret = ret == 64 ? b->reply_value : -EIO;
	spin_unlock_irqrestore(&b->lock, flags);
	return ret;
}

static int barracuda_get(struct barracuda *b, u8 command)
{
	return barracuda_request(b, 0x0e, &command, 1, command, 0);
}

/* E1 selects the volatile diagnostic destination; E0 reads it back. */
static int barracuda_set_route(struct barracuda *b, u8 remote)
{
	const u8 payload[2] = { 0xe1, remote };
	int ret = barracuda_request(b, 0x0e, payload, sizeof(payload), 0, 0);

	if (ret)
		return ret;
	return barracuda_get(b, 0xe0) == remote ? 0 : -EPROTO;
}

static bool barracuda_refresh_wanted(struct barracuda *b);

/* Queue the next periodic refresh while linked. */
static void barracuda_schedule_poll(struct barracuda *b)
{
	unsigned int interval = READ_ONCE(poll_interval);

	if (!interval || !barracuda_refresh_wanted(b))
		return;
	schedule_delayed_work(&b->refresh_work,
			      max(interval, (unsigned int)BARRACUDA_MIN_POLL) * HZ);
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

/* Family-8 customer GET: PARAM, op 00 (request), no data. */
static int barracuda_customer_get(struct barracuda *b, u8 param)
{
	const u8 payload[3] = { param, 0, 0 };

	return barracuda_request(b, 8, payload, sizeof(payload), 0, param);
}

/*
 * On each confirmed link, ask the headset for its battery percentage and
 * cable state. The dongle answers these GETs only on the temporary remote
 * diagnostic route (validated on 2026-09-24); the local route is always
 * restored. Replies are decoded like the headset's own reports.
 */
/*
 * Select the remote diagnostic route using the existing headset transport
 * (E6 bit 0x08; never created). Caller holds route_lock. On failure nothing
 * was changed, except after a partial E1 01, which barracuda_remote_end() undoes.
 */
static int barracuda_remote_begin(struct barracuda *b, bool *selected)
{
	int status;

	*selected = false;
	if (READ_ONCE(b->route_failed))
		return -EIO;
	status = barracuda_get(b, 0xe6);
	if (status < 0 || !(status & 0x08) || barracuda_get(b, 0xe0) != 0)
		return -ENODEV;
	*selected = true;	/* restore even if E1 01 fails part-way */
	return barracuda_set_route(b, 1);
}

/* Always restore the local route, retrying once; returns false on failure. */
static bool barracuda_remote_end(struct barracuda *b, bool selected)
{
	int attempt;

	if (!selected)
		return true;
	for (attempt = 0; attempt < 2; attempt++)
		if (!barracuda_set_route(b, 0))
			return true;
	WRITE_ONCE(b->route_failed, true);
	hid_warn(b->hdev, "could not restore the local diagnostic route\n");
	return false;
}

static int barracuda_read_voltage(struct barracuda *b)
{
	static const u8 voltage_query[] = { BARRACUDA_GET_VOLTAGE };

	return barracuda_request(b, 6, voltage_query, sizeof(voltage_query), 0, 0);
}

static void barracuda_store_voltage(struct barracuda *b, int mv)
{
	unsigned long flags;

	spin_lock_irqsave(&b->lock, flags);
	b->voltage_mv = mv;
	b->voltage_at = jiffies;
	spin_unlock_irqrestore(&b->lock, flags);
}

/*
 * On each confirmed link, cable change and poll_interval, ask the headset for
 * its battery percentage, cable state and voltage. The dongle answers only on
 * the temporary remote diagnostic route (validated on 2026-09-24); the local
 * route is always restored. GET replies are decoded like the headset's reports.
 */
static void barracuda_refresh(struct work_struct *work)
{
	struct barracuda *b = container_of(to_delayed_work(work),
					 struct barracuda, refresh_work);
	int battery = -1, cable = -1, mv = -1;
	bool selected, restored;

	if (!barracuda_refresh_wanted(b))
		return;
	mutex_lock(&b->route_lock);
	if (!barracuda_remote_begin(b, &selected)) {
		battery = barracuda_customer_get(b, BARRACUDA_GET_BATTERY);
		cable = barracuda_customer_get(b, BARRACUDA_GET_CABLE);
		mv = barracuda_read_voltage(b);
	}
	restored = barracuda_remote_end(b, selected);
	mutex_unlock(&b->route_lock);
	hid_dbg(b->hdev, "refreshed battery %d, cable %d, %d mV\n", battery, cable, mv);
	if (mv >= 0) {
		barracuda_store_voltage(b, mv);
		schedule_work(&b->supply_work);
	}
	if (restored)
		barracuda_schedule_poll(b);
}

/* Re-read a voltage older than voltage_max_age when voltage_now is read. */
static void barracuda_voltage_on_demand(struct barracuda *b)
{
	unsigned int max_age = READ_ONCE(voltage_max_age);
	unsigned long flags;
	bool stale, selected;
	int mv = -1;

	if (!max_age)
		return;
	spin_lock_irqsave(&b->lock, flags);
	stale = !b->stopping && barracuda_state_present(&b->state) &&
		(b->voltage_mv < 0 || time_after(jiffies, b->voltage_at + max_age * HZ));
	spin_unlock_irqrestore(&b->lock, flags);
	/* A running refresh is about to store a fresh value; do not wait for it. */
	if (!stale || !mutex_trylock(&b->route_lock))
		return;
	if (!barracuda_remote_begin(b, &selected))
		mv = barracuda_read_voltage(b);
	barracuda_remote_end(b, selected);
	mutex_unlock(&b->route_lock);
	if (mv >= 0)
		barracuda_store_voltage(b, mv);
}

/*
 * Standard USB wireless_status (sysfs-bus-usb), like hid-corsair-void: lets
 * userspace treat the headset as absent while the dongle has no link.
 */
static void barracuda_set_wireless_status(struct barracuda *b, int linked)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	struct usb_interface *intf = to_usb_interface(b->hdev->dev.parent);

	if (linked < 0 || linked == b->wireless_reported)
		return;
	b->wireless_reported = linked;
	usb_set_wireless_status(intf, linked ? USB_WIRELESS_STATUS_CONNECTED :
					       USB_WIRELESS_STATUS_DISCONNECTED);
#endif
}

/* Apply the link to the battery registration, or notify UPower of changes. */
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
		if (IS_ERR(battery))
			hid_warn(b->hdev, "could not register battery: %ld\n", PTR_ERR(battery));
		else
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

/* Parented to the HID device so a sound driver can match the same USB device. */
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
	jack->id.bustype = hdev->bus;
	jack->id.vendor = hdev->vendor;
	jack->id.product = hdev->product;
	jack->id.version = hdev->version;
	jack->uniq = hdev->uniq;
	input_set_capability(jack, EV_SW, SW_HEADPHONE_INSERT);
	input_set_capability(jack, EV_SW, SW_MICROPHONE_INSERT);
	b->jack = jack;
	return input_register_device(jack);
}

static int barracuda_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct usb_interface *intf = to_usb_interface(hdev->dev.parent);
	struct barracuda *b;
	int ret;

	if (intf->cur_altsetting->desc.bInterfaceNumber != 3)
		return -ENODEV;
	b = devm_kzalloc(&hdev->dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;
	b->hdev = hdev;
	b->voltage_mv = -1;
	b->jack_report = BARRACUDA_UNKNOWN;
	b->wireless_reported = BARRACUDA_UNKNOWN;
	mutex_init(&b->route_lock);
	mutex_init(&b->supply_lock);
	INIT_WORK(&b->supply_work, barracuda_supply_work);
	barracuda_state_reset(&b->state);
	spin_lock_init(&b->lock);
	INIT_DELAYED_WORK(&b->query_work, barracuda_query);
	INIT_DELAYED_WORK(&b->refresh_work, barracuda_refresh);
	init_completion(&b->reply_done);
	hid_set_drvdata(hdev, b);
	ret = hid_parse(hdev);
	if (ret)
		return ret;
	b->desc.name = devm_kasprintf(&hdev->dev, GFP_KERNEL,
				     "barracuda-%s-battery", dev_name(&hdev->dev));
	if (!b->desc.name)
		return -ENOMEM;
	b->desc.type = POWER_SUPPLY_TYPE_BATTERY;
	b->desc.properties = barracuda_properties;
	b->desc.num_properties = ARRAY_SIZE(barracuda_properties);
	b->desc.get_property = barracuda_get_property;
	/* The battery is registered by barracuda_supply_work() once linked. */
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
	schedule_delayed_work(&b->query_work, HZ);
	return 0;
}

static void barracuda_stop(struct barracuda *b)
{
	unsigned long flags;

	/* Let a running refresh finish and restore the route while replies flow. */
	spin_lock_irqsave(&b->lock, flags);
	b->stopping = true;
	spin_unlock_irqrestore(&b->lock, flags);
	cancel_delayed_work_sync(&b->refresh_work);
	spin_lock_irqsave(&b->lock, flags);
	b->stopped = true;
	spin_unlock_irqrestore(&b->lock, flags);
	cancel_delayed_work_sync(&b->query_work);
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

#ifdef CONFIG_PM
static int barracuda_suspend(struct hid_device *hdev, pm_message_t message)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;

	barracuda_stop(b);
	spin_lock_irqsave(&b->lock, flags);
	barracuda_state_suspend(&b->state);
	b->stream.used = 0;
	spin_unlock_irqrestore(&b->lock, flags);
	/* The link is unknown now: keep the battery, reported as not present. */
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
	b->stream.used = 0;
	b->attempts = 0;
	spin_unlock_irqrestore(&b->lock, flags);
	schedule_delayed_work(&b->query_work, HZ);
	return 0;
}
#endif

static const struct hid_device_id barracuda_devices[] = {
	{ HID_USB_DEVICE(BARRACUDA_VENDOR, BARRACUDA_PRODUCT) },
	{ }
};
MODULE_DEVICE_TABLE(hid, barracuda_devices);

static struct hid_driver barracuda_driver = {
	.name = "barracuda-battery",
	.id_table = barracuda_devices,
	.probe = barracuda_probe,
	.remove = barracuda_remove,
	.raw_event = barracuda_raw_event,
#ifdef CONFIG_PM
	.suspend = barracuda_suspend,
	.resume = barracuda_resume,
	.reset_resume = barracuda_resume,
#endif
};
module_hid_driver(barracuda_driver);

MODULE_LICENSE("Dual MIT/GPL");
MODULE_DESCRIPTION("Razer Barracuda X (2022) HID battery driver");
MODULE_VERSION("0.2.1");
