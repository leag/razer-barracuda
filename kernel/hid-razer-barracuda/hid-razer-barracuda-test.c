// SPDX-License-Identifier: GPL-2.0-only OR MIT
/*
 * KUnit tests for the Razer Barracuda X (2022) driver
 *
 * Copyright (c) 2026 Luis Atala <luis.atala@gmail.com>
 */

#include <kunit/test.h>

/* Unsolicited 58% battery report. */
static const u8 barracuda_test_battery[] = {
	0x50, 0x49, 0x08, 0xf8, 0x71, 0x71, 0x41, 0x00, 0x04, 0x00,
	0x21, 0x02, 0x01, 0x3a,
};

/* E3 reply: headset linked. */
static const u8 barracuda_test_e3[] = {
	0x50, 0x49, 0x0e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00,
	0xe3, 0x01,
};

/* Reply to the battery GET: 100%. */
static const u8 barracuda_test_battery_reply[] = {
	0x50, 0x49, 0x08, 0x11, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00,
	0x21, 0x01, 0x01, 0x64,
};

static struct barracuda *barracuda_test_alloc(struct kunit *test)
{
	struct barracuda *b = kunit_kzalloc(test, sizeof(*b), GFP_KERNEL);

	KUNIT_ASSERT_NOT_NULL(test, b);
	barracuda_init(b, NULL);
	return b;
}

static void barracuda_test_reset(struct barracuda *b)
{
	barracuda_state_reset(&b->state);
	b->frame_used = 0;
}

static void barracuda_test_chunk(struct barracuda *b, const u8 *data,
				 unsigned int count)
{
	u8 report[BARRACUDA_REPORT_SIZE] = { BARRACUDA_REPORT_ID, BARRACUDA_TUNNEL };

	report[2] = count;
	memcpy(report + 3, data, count);
	barracuda_feed(b, report, sizeof(report));
}

/* Every split point, with a media-key report between the two chunks. */
static void barracuda_test_split(struct kunit *test)
{
	static const u8 media[] = { 0x02, 0x00, 0x02, 0x00, 0x00 };
	const u8 *msg = barracuda_test_battery;
	struct barracuda *b = barracuda_test_alloc(test);
	unsigned int i;

	for (i = 1; i < sizeof(barracuda_test_battery); i++) {
		barracuda_test_reset(b);
		barracuda_test_chunk(b, msg, i);
		KUNIT_EXPECT_EQ(test, b->state.capacity, BARRACUDA_UNKNOWN);
		barracuda_feed(b, media, sizeof(media));
		barracuda_test_chunk(b, msg + i, sizeof(barracuda_test_battery) - i);
		KUNIT_EXPECT_EQ(test, b->state.capacity, 58);
	}
}

/* Every value byte: invalid percentages and enums are never accepted. */
static void barracuda_test_values(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[sizeof(barracuda_test_battery)];
	unsigned int i;

	memcpy(data, barracuda_test_battery, sizeof(data));
	for (i = 0; i < 256; i++) {
		data[13] = i;

		data[10] = BARRACUDA_PARAM_LINK;
		barracuda_test_reset(b);
		barracuda_test_chunk(b, data, sizeof(data));
		KUNIT_EXPECT_EQ(test, b->state.linked,
				i <= 1 ? (int)i : BARRACUDA_UNKNOWN);

		data[10] = BARRACUDA_PARAM_BATTERY;
		barracuda_test_reset(b);
		barracuda_test_chunk(b, data, sizeof(data));
		KUNIT_EXPECT_EQ(test, b->state.capacity,
				i <= 100 ? (int)i : BARRACUDA_UNKNOWN);

		data[10] = BARRACUDA_PARAM_CABLE;
		barracuda_test_reset(b);
		barracuda_test_chunk(b, data, sizeof(data));
		KUNIT_EXPECT_EQ(test, b->state.external_power,
				i <= 1 ? (int)i : BARRACUDA_UNKNOWN);
	}
}

/* E3 is link evidence; E6 and acknowledgments are not. */
static void barracuda_test_link_query(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[sizeof(barracuda_test_e3)];

	barracuda_test_chunk(b, barracuda_test_e3, sizeof(barracuda_test_e3));
	KUNIT_EXPECT_EQ(test, b->state.linked, 1);

	memcpy(data, barracuda_test_e3, sizeof(data));
	data[10] = 0xe6;
	barracuda_test_reset(b);
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.linked, BARRACUDA_UNKNOWN);

	data[2] = 0x01;
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.linked, BARRACUDA_UNKNOWN);
}

/* Corrupted magic, family and payload markers produce no telemetry. */
static void barracuda_test_malformed(struct kunit *test)
{
	static const unsigned int offsets[] = { 0, 1, 2, 10, 11, 12 };
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[sizeof(barracuda_test_battery)];
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(offsets); i++) {
		memcpy(data, barracuda_test_battery, sizeof(data));
		data[offsets[i]] = 0xff;
		barracuda_test_reset(b);
		barracuda_test_chunk(b, data, sizeof(data));
		KUNIT_EXPECT_EQ(test, b->state.capacity, BARRACUDA_UNKNOWN);
	}
}

/* A report shorter than its chunk count is dropped, not read as padding. */
static void barracuda_test_truncated(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 report[BARRACUDA_REPORT_SIZE] = { BARRACUDA_REPORT_ID, BARRACUDA_TUNNEL,
					     sizeof(barracuda_test_battery) };
	unsigned int i;

	memcpy(report + 3, barracuda_test_battery, sizeof(barracuda_test_battery));
	for (i = 0; i < 3 + sizeof(barracuda_test_battery); i++) {
		barracuda_test_reset(b);
		barracuda_feed(b, report, i);
		KUNIT_EXPECT_EQ(test, b->state.capacity, BARRACUDA_UNKNOWN);
	}
}

static void barracuda_test_two_frames(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[2 * sizeof(barracuda_test_battery)];

	memcpy(data, barracuda_test_battery, sizeof(barracuda_test_battery));
	memcpy(data + 14, barracuda_test_battery, sizeof(barracuda_test_battery));
	data[14 + 10] = BARRACUDA_PARAM_CABLE;
	data[14 + 13] = 1;
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.capacity, 58);
	KUNIT_EXPECT_EQ(test, b->state.external_power, 1);
}

/* Oversized frames and chunks, then arbitrary input, recover boundedly. */
static void barracuda_test_recovery(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[sizeof(barracuda_test_battery)];
	u8 report[BARRACUDA_REPORT_SIZE] = { BARRACUDA_REPORT_ID, BARRACUDA_TUNNEL,
					     BARRACUDA_CHUNK_MAX + 1 };
	unsigned int i, j;

	memcpy(data, barracuda_test_battery, sizeof(data));
	data[8] = 0xff;
	data[9] = 0xff;
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->frame_used, 0U);
	KUNIT_EXPECT_EQ(test, b->state.capacity, BARRACUDA_UNKNOWN);

	barracuda_feed(b, report, sizeof(report));
	barracuda_test_chunk(b, barracuda_test_battery,
			     sizeof(barracuda_test_battery));
	KUNIT_EXPECT_EQ(test, b->state.capacity, 58);

	for (j = 0; j < 256; j++) {
		memset(report, j, sizeof(report));
		for (i = 0; i <= sizeof(report); i++)
			barracuda_feed(b, report, i);
		KUNIT_EXPECT_LE(test, b->frame_used, (unsigned int)BARRACUDA_FRAME_MAX);
	}
}

static void barracuda_test_state(struct kunit *test)
{
	struct barracuda_state s;

	barracuda_state_reset(&s);
	barracuda_state_event(&s, BARRACUDA_CAPACITY, 68);
	KUNIT_EXPECT_EQ(test, s.linked, BARRACUDA_UNKNOWN);
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	KUNIT_EXPECT_EQ(test, s.capacity, 68);

	/* Disconnect clears the cable and keeps the last percentage. */
	barracuda_state_event(&s, BARRACUDA_EXTERNAL_POWER, 1);
	barracuda_state_event(&s, BARRACUDA_LINK, 0);
	KUNIT_EXPECT_EQ(test, s.capacity, 68);
	KUNIT_EXPECT_EQ(test, s.external_power, BARRACUDA_UNKNOWN);

	/* No telemetry is accepted while disconnected. */
	KUNIT_EXPECT_FALSE(test, barracuda_state_event(&s, BARRACUDA_CAPACITY, 99));
	KUNIT_EXPECT_EQ(test, s.capacity, 68);

	/* Suspend makes the link unknown and keeps the last percentage. */
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	barracuda_state_event(&s, BARRACUDA_EXTERNAL_POWER, 1);
	barracuda_state_suspend(&s);
	KUNIT_EXPECT_EQ(test, s.linked, BARRACUDA_UNKNOWN);
	KUNIT_EXPECT_EQ(test, s.capacity, 68);
	KUNIT_EXPECT_EQ(test, s.external_power, BARRACUDA_UNKNOWN);

	barracuda_state_reset(&s);
	KUNIT_EXPECT_EQ(test, s.capacity, BARRACUDA_UNKNOWN);
}

static void barracuda_test_supply_action(struct kunit *test)
{
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(1, false),
			BARRACUDA_SUPPLY_REGISTER);
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(1, true),
			BARRACUDA_SUPPLY_NOTIFY);
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(0, true),
			BARRACUDA_SUPPLY_UNREGISTER);
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(0, false),
			BARRACUDA_SUPPLY_NONE);
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(BARRACUDA_UNKNOWN, false),
			BARRACUDA_SUPPLY_NONE);
	KUNIT_EXPECT_EQ(test, barracuda_supply_action(BARRACUDA_UNKNOWN, true),
			BARRACUDA_SUPPLY_NOTIFY);
}

/* GET replies update telemetry; only the op-02 report is link evidence. */
static void barracuda_test_get_replies(struct kunit *test)
{
	const u8 *reply = barracuda_test_battery_reply;
	struct barracuda *b = barracuda_test_alloc(test);
	u8 data[sizeof(barracuda_test_battery_reply)];
	unsigned int op;

	KUNIT_EXPECT_EQ(test, barracuda_customer_reply(reply, 14, 0x21), 100);
	KUNIT_EXPECT_EQ(test, barracuda_customer_reply(reply, 14, 0x2a), -1);
	KUNIT_EXPECT_EQ(test, barracuda_customer_reply(reply, 13, 0x21), -1);
	barracuda_test_chunk(b, reply, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.capacity, 100);

	memcpy(data, reply, sizeof(data));
	data[10] = BARRACUDA_PARAM_CABLE;
	data[13] = 1;
	for (op = 0; op < 256; op++) {
		data[11] = op;
		barracuda_test_reset(b);
		barracuda_test_chunk(b, data, sizeof(data));
		KUNIT_EXPECT_EQ(test, b->state.external_power,
				op == 1 || op == 2 ? 1 : BARRACUDA_UNKNOWN);
		KUNIT_EXPECT_EQ(test, barracuda_customer_reply(data, 14, 0x2a),
				op == 1 ? 1 : -1);
	}

	data[10] = BARRACUDA_PARAM_LINK;
	data[11] = BARRACUDA_OP_REPLY;
	barracuda_test_reset(b);
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.linked, BARRACUDA_UNKNOWN);
	data[11] = BARRACUDA_OP_REPORT;
	barracuda_test_chunk(b, data, sizeof(data));
	KUNIT_EXPECT_EQ(test, b->state.linked, 1);
}

static void barracuda_test_cable_changed(struct kunit *test)
{
	KUNIT_EXPECT_FALSE(test, barracuda_cable_changed(BARRACUDA_UNKNOWN, 0));
	KUNIT_EXPECT_FALSE(test, barracuda_cable_changed(BARRACUDA_UNKNOWN, 1));
	KUNIT_EXPECT_FALSE(test, barracuda_cable_changed(0, 0));
	KUNIT_EXPECT_FALSE(test, barracuda_cable_changed(1, 1));
	KUNIT_EXPECT_TRUE(test, barracuda_cable_changed(0, 1));
	KUNIT_EXPECT_TRUE(test, barracuda_cable_changed(1, 0));
}

static void barracuda_test_voltage(struct kunit *test)
{
	static const u8 charging[] = { 0x68, 0x10, 0x00, 0x00 };
	static const u8 resting[] = { 0xfa, 0x0e, 0x00, 0x00 };
	/* The dongle's own reading on the local route is not a battery voltage. */
	static const u8 local[] = { 0x35, 0x01, 0x00, 0x00 };
	static const u8 zero[] = { 0x00, 0x00, 0x00, 0x00 };

	KUNIT_EXPECT_EQ(test, barracuda_voltage_mv(charging, 4), 4200);
	KUNIT_EXPECT_EQ(test, barracuda_voltage_mv(resting, 4), 3834);
	KUNIT_EXPECT_EQ(test, barracuda_voltage_mv(local, 4), -1);
	KUNIT_EXPECT_EQ(test, barracuda_voltage_mv(zero, 4), -1);
	KUNIT_EXPECT_EQ(test, barracuda_voltage_mv(charging, 1), -1);
}

static void barracuda_test_ack(struct kunit *test)
{
	static const u8 ack[] = {
		0x50, 0x49, 0x01, 0xc0, 0x48, 0x1f, 0x0a, 0x00, 0x03, 0x00,
		0x0e, 0xaa, 0x00,
	};
	static const u8 e0[] = {
		0x50, 0x49, 0x0e, 0xf5, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00,
		0xe0, 0x01,
	};
	const u8 *result;
	u8 failed[sizeof(ack)];

	KUNIT_EXPECT_EQ(test, barracuda_ack(ack, 13, 0x0e, 0x2a, &result), 0);
	KUNIT_EXPECT_EQ(test, barracuda_ack(ack, 13, 0x0e, 0x2b, &result), -1);
	KUNIT_EXPECT_EQ(test, barracuda_ack(ack, 13, 0x06, 0x2a, &result), -1);
	KUNIT_EXPECT_EQ(test, barracuda_ack(ack, 12, 0x0e, 0x2a, &result), -1);
	memcpy(failed, ack, sizeof(ack));
	failed[12] = 1;
	KUNIT_EXPECT_EQ(test, barracuda_ack(failed, 13, 0x0e, 0x2a, &result), -2);
	KUNIT_EXPECT_EQ(test, barracuda_link_reply(e0, 12, 0xe0), 1);
	KUNIT_EXPECT_EQ(test, barracuda_link_reply(e0, 12, 0xe6), -1);
	KUNIT_EXPECT_EQ(test, barracuda_link_reply(e0, 11, 0xe0), -1);
}

/* A pending query completes only on its matching reply. */
static void barracuda_test_match_reply(struct kunit *test)
{
	static const u8 voltage[] = {
		0x50, 0x49, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00,
		0x06, 0xe1, 0x00, 0x68, 0x10, 0x00, 0x00,
	};
	static const u8 ack[] = {
		0x50, 0x49, 0x01, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00,
		0x0e, 0xe2, 0x00,
	};
	static const u8 e0[] = {
		0x50, 0x49, 0x0e, 0xc5, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00,
		0xe0, 0x01,
	};
	struct barracuda *b = barracuda_test_alloc(test);

	/* Family 0x08 GET replies are not acknowledged and match directly. */
	b->waiting = true;
	b->want_param = BARRACUDA_PARAM_CABLE;
	b->reply_value = -ETIMEDOUT;
	barracuda_test_chunk(b, barracuda_test_battery_reply,
			     sizeof(barracuda_test_battery_reply));
	KUNIT_EXPECT_TRUE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, -ETIMEDOUT);

	b->want_param = BARRACUDA_PARAM_BATTERY;
	barracuda_test_chunk(b, barracuda_test_battery_reply,
			     sizeof(barracuda_test_battery_reply));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, 100);

	/*
	 * A route reply counts only after the acknowledgment that echoes the
	 * sequence, so a reply left over from a timed-out query is ignored.
	 */
	b->waiting = true;
	b->acked = false;
	b->want_family = BARRACUDA_FAMILY_LINK;
	b->want_seq = 0x62;
	b->want_param = 0;
	b->want_command = BARRACUDA_CMD_GET_ROUTE;
	b->reply_value = -ETIMEDOUT;
	barracuda_test_chunk(b, e0, sizeof(e0));
	KUNIT_EXPECT_TRUE(test, b->waiting);
	KUNIT_EXPECT_FALSE(test, b->acked);
	barracuda_test_chunk(b, ack, sizeof(ack));
	KUNIT_EXPECT_TRUE(test, b->waiting);
	KUNIT_EXPECT_TRUE(test, b->acked);
	barracuda_test_chunk(b, e0, sizeof(e0));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, 1);
	b->want_command = 0;

	b->waiting = true;
	b->acked = false;
	b->want_param = 0;
	b->want_family = BARRACUDA_FAMILY_DIAG;
	b->want_seq = 0x61;
	barracuda_test_chunk(b, voltage, sizeof(voltage));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, 4200);
}

/* A fake transport checks locking and answers through the real reply matcher. */
struct barracuda_test_transport {
	struct barracuda b;
	struct kunit *test;
	unsigned int writes;
	bool fail;
	u8 route;
};

static int barracuda_test_output(struct hid_device *hdev, u8 *buf, size_t len)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	struct barracuda_test_transport *t = container_of(b, typeof(*t), b);
	u8 ack[] = { 0x50, 0x49, 1, 0, 0, 0, 0, 0, 3, 0, 0x0e, 0, 0 };
	u8 data[] = { 0x50, 0x49, 0x0e, 0, 0, 0, 0, 0, 2, 0, 0, 0 };
	unsigned long flags;

	KUNIT_EXPECT_TRUE(t->test, mutex_is_locked(&b->route_lock));
	t->writes++;
	if (t->fail)
		return -EIO;
	ack[11] = buf[6] | 0x80;
	data[10] = buf[8];
	switch (buf[8]) {
	case BARRACUDA_CMD_GET_LINK:
		data[11] = 1;
		break;
	case BARRACUDA_CMD_GET_TRANSPORT:
		data[11] = BARRACUDA_TRANSPORT_HEADSET;
		break;
	case BARRACUDA_CMD_SET_ROUTE:
		t->route = buf[9];
		break;
	case BARRACUDA_CMD_GET_ROUTE:
		data[11] = t->route;
		break;
	}
	spin_lock_irqsave(&b->lock, flags);
	barracuda_frame(b, ack, sizeof(ack));
	barracuda_frame(b, data, sizeof(data));
	spin_unlock_irqrestore(&b->lock, flags);
	return len;
}

static const struct hid_ll_driver barracuda_test_ll = {
	.output_report = barracuda_test_output,
};

static void barracuda_test_destroy_hid(void *data)
{
	hid_destroy_device(data);
}

static struct barracuda_test_transport *barracuda_test_transport_alloc(struct kunit *test)
{
	struct barracuda_test_transport *t;
	struct hid_device *hdev;
	int ret;

	t = kunit_kzalloc(test, sizeof(*t), GFP_KERNEL);
	KUNIT_ASSERT_NOT_NULL(test, t);
	hdev = hid_allocate_device();
	KUNIT_ASSERT_NOT_ERR_OR_NULL(test, hdev);
	ret = kunit_add_action_or_reset(test, barracuda_test_destroy_hid, hdev);
	KUNIT_ASSERT_EQ(test, ret, 0);
	t->test = test;
	barracuda_init(&t->b, hdev);
	hid_set_drvdata(hdev, &t->b);
	hdev->ll_driver = &barracuda_test_ll;
	return t;
}

static void barracuda_test_startup_transaction(struct kunit *test)
{
	struct barracuda_test_transport *t = barracuda_test_transport_alloc(test);
	struct barracuda *b = &t->b;
	unsigned int i;

	barracuda_link_query(&b->link_work.work);
	KUNIT_EXPECT_EQ(test, t->writes, 1);
	KUNIT_EXPECT_EQ(test, b->state.linked, 1);
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_FALSE(test, delayed_work_pending(&b->link_work));

	barracuda_state_reset(&b->state);
	b->attempts = 0;
	t->writes = 0;
	t->fail = true;
	for (i = 0; i < BARRACUDA_LINK_ATTEMPTS; i++) {
		barracuda_link_query(&b->link_work.work);
		KUNIT_EXPECT_EQ(test, b->state.linked, BARRACUDA_UNKNOWN);
		KUNIT_EXPECT_EQ(test, delayed_work_pending(&b->link_work),
				i + 1 < BARRACUDA_LINK_ATTEMPTS);
		cancel_delayed_work_sync(&b->link_work);
	}
	barracuda_link_query(&b->link_work.work);
	KUNIT_EXPECT_EQ(test, t->writes, BARRACUDA_LINK_ATTEMPTS);
}

static void barracuda_test_stopping_transaction(struct kunit *test)
{
	struct barracuda_test_transport *t = barracuda_test_transport_alloc(test);
	struct barracuda *b = &t->b;

	b->stopping = true;
	barracuda_link_query(&b->link_work.work);
	KUNIT_EXPECT_EQ(test, b->attempts, 0);
	mutex_lock(&b->route_lock);
	KUNIT_EXPECT_EQ(test, barracuda_get(b, BARRACUDA_CMD_GET_LINK), -ESHUTDOWN);
	KUNIT_EXPECT_EQ(test, t->writes, 0);
	/* Cleanup remains possible while normal requests are rejected. */
	t->route = BARRACUDA_ROUTE_REMOTE;
	KUNIT_EXPECT_TRUE(test, barracuda_route_end(b, true));
	KUNIT_EXPECT_EQ(test, t->writes, 2);
	KUNIT_EXPECT_EQ(test, t->route, BARRACUDA_ROUTE_LOCAL);
	KUNIT_EXPECT_FALSE(test, b->restoring_route);
	mutex_unlock(&b->route_lock);
}

static void barracuda_test_failed_route(struct kunit *test)
{
	struct barracuda_test_transport *t = barracuda_test_transport_alloc(test);
	struct barracuda *b = &t->b;
	unsigned long flags;
	bool selected;

	t->fail = true;
	mutex_lock(&b->route_lock);
	KUNIT_EXPECT_FALSE(test, barracuda_route_end(b, true));
	KUNIT_EXPECT_EQ(test, t->writes, 2);
	KUNIT_EXPECT_TRUE(test, b->route_failed);
	KUNIT_EXPECT_FALSE(test, b->restoring_route);
	mutex_unlock(&b->route_lock);
	t->fail = false;
	t->writes = 0;
	spin_lock_irqsave(&b->lock, flags);
	barracuda_event(b, BARRACUDA_LINK, 1);
	spin_unlock_irqrestore(&b->lock, flags);
	KUNIT_EXPECT_TRUE(test, b->route_failed);

	mutex_lock(&b->route_lock);
	t->route = BARRACUDA_ROUTE_REMOTE;
	KUNIT_EXPECT_EQ(test, barracuda_route_begin(b, &selected), -EIO);
	KUNIT_EXPECT_FALSE(test, selected);
	KUNIT_EXPECT_TRUE(test, b->route_failed);
	KUNIT_EXPECT_EQ(test, t->writes, 1);
	/* A failed verification must not clear the latch either. */
	t->fail = true;
	KUNIT_EXPECT_EQ(test, barracuda_route_begin(b, &selected), -EIO);
	KUNIT_EXPECT_TRUE(test, b->route_failed);
	t->fail = false;
	t->route = BARRACUDA_ROUTE_LOCAL;
	KUNIT_EXPECT_EQ(test, barracuda_route_begin(b, &selected), 0);
	KUNIT_EXPECT_TRUE(test, selected);
	KUNIT_EXPECT_FALSE(test, b->route_failed);
	KUNIT_EXPECT_TRUE(test, barracuda_route_end(b, selected));
	mutex_unlock(&b->route_lock);
}

static void barracuda_test_poweroff(struct kunit *test)
{
	static const u8 payload[] = { 0x08, 0x00, 0x02 };
	static const u8 expected[] = {
		0x01, 0x80, 0x08, 0x50, 0x41, 0x07, 0x60,
		0x03, 0x08, 0x00, 0x02,
	};
	u8 report[BARRACUDA_REPORT_SIZE];
	unsigned int i;

	barracuda_fill(report, BARRACUDA_FAMILY_MMI, 0x60,
		       payload, sizeof(payload));
	KUNIT_EXPECT_MEMEQ(test, report, expected, sizeof(expected));
	for (i = sizeof(expected); i < sizeof(report); i++)
		KUNIT_EXPECT_EQ(test, report[i], 0);
}

static void barracuda_test_poweroff_guards(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	struct hid_device *hdev;
	struct device *dev;

	hdev = kunit_kzalloc(test, sizeof(*hdev), GFP_KERNEL);
	KUNIT_ASSERT_NOT_NULL(test, hdev);
	hid_set_drvdata(hdev, b);
	dev = &hdev->dev;
	KUNIT_EXPECT_EQ(test, headset_poweroff_store(dev, NULL, "0", 1), -EINVAL);
	KUNIT_EXPECT_EQ(test, headset_poweroff_store(dev, NULL, "1", 1), -ENOTCONN);
	b->state.linked = 0;
	KUNIT_EXPECT_EQ(test, headset_poweroff_store(dev, NULL, "1", 1), -ENOTCONN);
	b->state.linked = 1;
	b->stopping = true;
	KUNIT_EXPECT_EQ(test, headset_poweroff_store(dev, NULL, "1", 1), -ENOTCONN);
	mutex_lock(&b->route_lock);
	KUNIT_EXPECT_EQ(test, headset_poweroff_store(dev, NULL, "1", 1), -EBUSY);
	mutex_unlock(&b->route_lock);
}

static void barracuda_test_read_length_ack(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 reply[] = {
		0x50, 0x49, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x07, 0x00, 0x06, 0xe0, 0x00, 0xf0, 0x00, 0x00, 0x00,
	};

	b->want_family = BARRACUDA_FAMILY_DIAG;
	b->want_seq = 0x60;
	b->read_length = true;
	b->waiting = true;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, 0);
	b->waiting = true;
	reply[13] = 0;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_EQ(test, b->reply_value, -EPROTO);
}

static void barracuda_test_settings_allowlist(struct kunit *test)
{
	u8 eq[] = { 0x93, 0, 1, 7 };
	u8 bands[] = { 0x95, 0, 10, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 };
	u8 firmware[] = { 0x22, 0, 1, 0 };
	u8 idle[] = { 0xac, 0, 1, 15 };

	KUNIT_EXPECT_TRUE(test, barracuda_setting_valid(eq, sizeof(eq)));
	eq[3] = 3;
	KUNIT_EXPECT_FALSE(test, barracuda_setting_valid(eq, sizeof(eq)));
	KUNIT_EXPECT_FALSE(test, barracuda_setting_valid(eq, 3));
	KUNIT_EXPECT_TRUE(test, barracuda_setting_valid(bands, sizeof(bands)));
	bands[12] = 11;
	KUNIT_EXPECT_FALSE(test, barracuda_setting_valid(bands, sizeof(bands)));
	KUNIT_EXPECT_FALSE(test,
			   barracuda_setting_valid(firmware, sizeof(firmware)));
	KUNIT_EXPECT_TRUE(test, barracuda_setting_valid(idle, sizeof(idle)));
	idle[3] = 255;
	KUNIT_EXPECT_FALSE(test, barracuda_setting_valid(idle, sizeof(idle)));
}

static void barracuda_test_settings_reply(struct kunit *test)
{
	struct barracuda *b = barracuda_test_alloc(test);
	u8 reply[] = { 0x50, 0x49, 8, 3, 0, 0, 0, 0, 4, 0,
		       0x93, 1, 1, 0 };

	b->want_param = 0x93;
	b->settings_waiting = true;
	b->waiting = true;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, 0);
	KUNIT_EXPECT_EQ(test, b->settings_size, 1);
	b->waiting = true;
	reply[10] = 0x94;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_TRUE(test, b->waiting);
	reply[10] = 0x93;
	reply[11] = 2;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_TRUE(test, b->waiting);
	reply[11] = 1;
	reply[13] = 255;
	barracuda_test_chunk(b, reply, sizeof(reply));
	KUNIT_EXPECT_FALSE(test, b->waiting);
	KUNIT_EXPECT_EQ(test, b->reply_value, -EREMOTEIO);
	b->want_param = 0x15;
	reply[10] = 0x15;
	KUNIT_EXPECT_EQ(test,
			barracuda_setting_reply(b, reply, sizeof(reply)), -1);
}

static struct kunit_case barracuda_test_cases[] = {
	KUNIT_CASE(barracuda_test_settings_allowlist),
	KUNIT_CASE(barracuda_test_settings_reply),
	KUNIT_CASE(barracuda_test_startup_transaction),
	KUNIT_CASE(barracuda_test_stopping_transaction),
	KUNIT_CASE(barracuda_test_failed_route),
	KUNIT_CASE(barracuda_test_split),
	KUNIT_CASE(barracuda_test_values),
	KUNIT_CASE(barracuda_test_link_query),
	KUNIT_CASE(barracuda_test_malformed),
	KUNIT_CASE(barracuda_test_truncated),
	KUNIT_CASE(barracuda_test_two_frames),
	KUNIT_CASE(barracuda_test_recovery),
	KUNIT_CASE(barracuda_test_state),
	KUNIT_CASE(barracuda_test_supply_action),
	KUNIT_CASE(barracuda_test_get_replies),
	KUNIT_CASE(barracuda_test_cable_changed),
	KUNIT_CASE(barracuda_test_voltage),
	KUNIT_CASE(barracuda_test_ack),
	KUNIT_CASE(barracuda_test_match_reply),
	KUNIT_CASE(barracuda_test_poweroff),
	KUNIT_CASE(barracuda_test_poweroff_guards),
	KUNIT_CASE(barracuda_test_read_length_ack),
	{}
};

static struct kunit_suite barracuda_test_suite = {
	.name = "hid_razer_barracuda",
	.test_cases = barracuda_test_cases,
};

kunit_test_suite(barracuda_test_suite);
