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

static struct kunit_case barracuda_test_cases[] = {
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
	{}
};

static struct kunit_suite barracuda_test_suite = {
	.name = "hid_razer_barracuda",
	.test_cases = barracuda_test_cases,
};

kunit_test_suite(barracuda_test_suite);
