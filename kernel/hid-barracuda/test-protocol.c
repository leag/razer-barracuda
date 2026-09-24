/* SPDX-License-Identifier: MIT */
#include <assert.h>
#include <stdio.h>
#include "barracuda-state.h"

struct results {
	unsigned int count;
	enum barracuda_event event;
	int value;
};

static void collect(void *context, enum barracuda_event event, int value)
{
	struct results *r = context;

	r->count++;
	r->event = event;
	r->value = value;
}

static void chunk(struct barracuda_stream *s, struct results *r,
		  const unsigned char *data, unsigned int n)
{
	unsigned char report[64] = { 1, 0x80 };

	assert(n <= 61);
	report[2] = n;
	memcpy(report + 3, data, n);
	barracuda_feed(s, report, sizeof(report), collect, NULL, r);
}

static void test_reconnect(void)
{
	struct barracuda_state s;

	barracuda_state_reset(&s);
	assert(!barracuda_state_present(&s));
	barracuda_state_event(&s, BARRACUDA_CAPACITY, 68);
	assert(!barracuda_state_present(&s));
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	assert(barracuda_state_present(&s) && s.capacity == 68);
	barracuda_state_event(&s, BARRACUDA_EXTERNAL_POWER, 1);
	barracuda_state_event(&s, BARRACUDA_LINK, 0);
	assert(!barracuda_state_present(&s));
	assert(s.capacity == 68 && s.external_power == BARRACUDA_UNKNOWN);
	barracuda_state_event(&s, BARRACUDA_CAPACITY, 99);
	assert(s.capacity == 68);
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	assert(barracuda_state_present(&s) && s.capacity == 68);
	assert(s.external_power == BARRACUDA_UNKNOWN);
	/* Suspend preserves the last percentage without confirming connectivity. */
	barracuda_state_suspend(&s);
	assert(!barracuda_state_present(&s) && s.capacity == 68);
	assert(s.external_power == BARRACUDA_UNKNOWN);
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	assert(barracuda_state_present(&s) && s.capacity == 68);
	barracuda_state_event(&s, BARRACUDA_CAPACITY, 67);
	assert(s.capacity == 67);
	/* Missing percentage must not hide a confirmed connected headset. */
	s.capacity = BARRACUDA_UNKNOWN;
	assert(barracuda_state_present(&s));
	barracuda_state_reset(&s);
	assert(s.capacity == BARRACUDA_UNKNOWN);
	barracuda_state_event(&s, BARRACUDA_LINK, 1);
	assert(barracuda_state_present(&s) && s.capacity == BARRACUDA_UNKNOWN);
}


static void test_customer_get_replies(void)
{
	/* Replies captured on 1532:0552 on 2026-09-24 through the remote route. */
	const unsigned char battery[] = { 0x50, 0x49, 8, 0x11, 0, 0, 0, 0, 4, 0,
		0x21, 1, 1, 0x64 };
	unsigned char data[14];
	struct barracuda_stream st = { 0 };
	struct results r = { 0 };
	unsigned int op;

	assert(barracuda_customer_reply(battery, sizeof(battery), 0x21) == 100);
	assert(barracuda_customer_reply(battery, sizeof(battery), 0x2a) == -1);
	assert(barracuda_customer_reply(battery, sizeof(battery) - 1, 0x21) == -1);
	chunk(&st, &r, battery, sizeof(battery));
	assert(r.count == 1 && r.event == BARRACUDA_CAPACITY && r.value == 100);
	memcpy(data, battery, sizeof(data));
	data[10] = 0x2a;
	for (op = 0; op < 256; op++) {
		data[11] = op;
		data[13] = 1;
		r.count = 0;
		chunk(&st, &r, data, sizeof(data));
		assert(r.count == (unsigned int)(op == 1 || op == 2));
		assert(!r.count || (r.event == BARRACUDA_EXTERNAL_POWER && r.value == 1));
		data[11] = op;
		assert((barracuda_customer_reply(data, sizeof(data), 0x2a) == 1) == (op == 1));
	}
	/* A GET reply is never link evidence; only the op-02 report is. */
	data[10] = 0x20;
	data[11] = 1;
	r.count = 0;
	chunk(&st, &r, data, sizeof(data));
	assert(r.count == 0);
	data[11] = 2;
	chunk(&st, &r, data, sizeof(data));
	assert(r.count == 1 && r.event == BARRACUDA_LINK && r.value == 1);
}

static void test_replies(void)
{
	const unsigned char ack[] = { 0x50, 0x49, 1, 0xc0, 0x48, 0x1f, 0x0a, 0, 3, 0,
		0x0e, 0xaa, 0 };
	const unsigned char e0[] = { 0x50, 0x49, 0x0e, 0xf5, 0, 0, 0, 0, 2, 0, 0xe0, 1 };
	const unsigned char *result = NULL;
	unsigned char failed[sizeof(ack)];

	assert(barracuda_ack(ack, sizeof(ack), 0x0e, 0x2a, &result) == 0);
	assert(barracuda_ack(ack, sizeof(ack), 0x0e, 0x2b, &result) == -1);
	assert(barracuda_ack(ack, sizeof(ack), 0x06, 0x2a, &result) == -1);
	assert(barracuda_ack(ack, sizeof(ack) - 1, 0x0e, 0x2a, &result) == -1);
	memcpy(failed, ack, sizeof(ack));
	failed[12] = 1;
	assert(barracuda_ack(failed, sizeof(failed), 0x0e, 0x2a, &result) == -2);
	assert(barracuda_link_reply(e0, sizeof(e0), 0xe0) == 1);
	assert(barracuda_link_reply(e0, sizeof(e0), 0xe6) == -1);
	assert(barracuda_link_reply(e0, sizeof(e0) - 1, 0xe0) == -1);
}

int main(void)
{
	const unsigned char battery[] = {
		0x50, 0x49, 8, 0xf8, 0x71, 0x71, 0x41, 0, 4, 0,
		0x21, 2, 1, 58
	};
	const unsigned char e3[] = { 0x50, 0x49, 0x0e, 0, 0, 0, 0, 0,
		2, 0, 0xe3, 1 };
	struct barracuda_stream s = { 0 };
	struct results r = { 0 };
	unsigned char data[64], report[64], combined[28];
	unsigned int i, j;

	/* Every split point, including media keys interleaved between chunks. */
	for (i = 1; i < sizeof(battery); i++) {
		memset(&s, 0, sizeof(s));
		memset(&r, 0, sizeof(r));
		chunk(&s, &r, battery, i);
		assert(r.count == 0);
		memcpy(report, "\x02\x00\x02\x00\x00", 5);
		barracuda_feed(&s, report, 5, collect, NULL, &r);
		chunk(&s, &r, battery + i, sizeof(battery) - i);
		assert(r.count == 1 && r.event == BARRACUDA_CAPACITY && r.value == 58);
	}

	/* All byte values: never accept invalid percentages or link/charge enums. */
	for (j = 0; j < 3; j++) {
		const unsigned char selectors[] = { 0x20, 0x21, 0x2a };

		for (i = 0; i < 256; i++) {
			memcpy(data, battery, sizeof(battery));
			data[10] = selectors[j];
			data[13] = i;
			r.count = 0;
			chunk(&s, &r, data, sizeof(battery));
			assert(r.count == (unsigned int)(i <= (j == 1 ? 100 : 1)));
		}
	}
	/* E6 and success acknowledgments are not physical link evidence. */
	r.count = 0;
	chunk(&s, &r, e3, sizeof(e3));
	assert(r.count == 1 && r.event == BARRACUDA_LINK && r.value == 1);
	memcpy(data, e3, sizeof(e3));
	data[10] = 0xe6;
	r.count = 0;
	chunk(&s, &r, data, sizeof(e3));
	data[2] = 1;
	chunk(&s, &r, data, sizeof(e3));
	assert(r.count == 0);

	/* Malformed magic, type and payload markers must not emit telemetry. */
	for (i = 0; i < 6; i++) {
		const unsigned int offsets[] = { 0, 1, 2, 10, 11, 12 };

		memset(&s, 0, sizeof(s));
		memcpy(data, battery, sizeof(battery));
		data[offsets[i]] = 0xff;
		r.count = 0;
		chunk(&s, &r, data, sizeof(battery));
		assert(r.count == 0);
	}
	/* Truncated HID chunk discards pending state instead of consuming padding. */
	for (i = 0; i < 17; i++) {
		memset(&s, 0, sizeof(s));
		r.count = 0;
		memcpy(report, "\x01\x80\x0e", 3);
		memcpy(report + 3, battery, sizeof(battery));
		barracuda_feed(&s, report, i, collect, NULL, &r);
		assert(r.count == 0);
	}
	/* Several messages in one transport chunk. */
	memset(&s, 0, sizeof(s));
	memcpy(combined, battery, 14);
	memcpy(combined + 14, battery, 14);
	combined[24] = 0x2a;
	combined[27] = 1;
	r.count = 0;
	chunk(&s, &r, combined, sizeof(combined));
	assert(r.count == 2 && r.event == BARRACUDA_EXTERNAL_POWER && r.value == 1);

	/* Oversized frames, oversized chunks and corrupted streams recover boundedly. */
	memcpy(data, battery, sizeof(battery));
	data[8] = 0xff;
	data[9] = 0xff;
	r.count = 0;
	chunk(&s, &r, data, sizeof(battery));
	assert(s.used == 0 && r.count == 0);
	memset(report, 0, sizeof(report));
	report[0] = 1;
	report[1] = 0x80;
	report[2] = 62;
	barracuda_feed(&s, report, sizeof(report), collect, NULL, &r);
	chunk(&s, &r, battery, sizeof(battery));
	assert(r.count == 1);
	/* Feed every possible transport length and byte under sanitizers. */
	for (j = 0; j < 256; j++) {
		memset(report, j, sizeof(report));
		for (i = 0; i <= sizeof(report); i++)
			barracuda_feed(&s, report, i, collect, NULL, &r);
	}
	test_reconnect();
	test_customer_get_replies();
	test_replies();
	puts("Barracuda protocol tests passed");
	return 0;
}
