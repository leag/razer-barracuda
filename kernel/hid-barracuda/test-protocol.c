/* SPDX-License-Identifier: MIT */
#include <assert.h>
#include <stdio.h>
#include "barracuda-protocol.h"

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
	barracuda_feed(s, report, sizeof(report), collect, r);
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
		barracuda_feed(&s, report, 5, collect, &r);
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
		barracuda_feed(&s, report, i, collect, &r);
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
	barracuda_feed(&s, report, sizeof(report), collect, &r);
	chunk(&s, &r, battery, sizeof(battery));
	assert(r.count == 1);
	/* Feed every possible transport length and byte under sanitizers. */
	for (j = 0; j < 256; j++) {
		memset(report, j, sizeof(report));
		for (i = 0; i <= sizeof(report); i++)
			barracuda_feed(&s, report, i, collect, &r);
	}
	puts("Barracuda protocol tests passed");
	return 0;
}
