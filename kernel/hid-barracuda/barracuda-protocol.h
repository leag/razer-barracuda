/* SPDX-License-Identifier: MIT */
#ifndef BARRACUDA_PROTOCOL_H
#define BARRACUDA_PROTOCOL_H

#ifdef __KERNEL__
#include <linux/string.h>
#include <linux/types.h>
#else
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#endif

#define BARRACUDA_FRAME_MAX 256
#define BARRACUDA_UNKNOWN (-1)

enum barracuda_event {
	BARRACUDA_LINK,
	BARRACUDA_CAPACITY,
	BARRACUDA_EXTERNAL_POWER,
};

struct barracuda_stream {
	unsigned char data[BARRACUDA_FRAME_MAX];
	unsigned int used;
	unsigned int expected;
};

typedef void (*barracuda_notify_fn)(void *, enum barracuda_event, int);
/* Receives every complete PI frame; used to correlate the driver's own queries. */
typedef void (*barracuda_frame_fn)(void *, const unsigned char *, unsigned int);

/*
 * Family-8 customer GET: PARAM, op 00 (request), no data. Frame layout from
 * https://github.com/TarikTopalovic/razer-barracuda-2.4-linux (1532:053C).
 */
#define BARRACUDA_GET_BATTERY 0x21
#define BARRACUDA_GET_CABLE 0x2a

/* Family-6 GET_BATTERY (0x31) result: little-endian millivolts, -1 if implausible. */
#define BARRACUDA_GET_VOLTAGE 0x31
static inline int barracuda_voltage_mv(const unsigned char *result, int size)
{
	int mv;

	if (size < 2)
		return -1;
	mv = result[0] | result[1] << 8;
	return mv >= 2500 && mv <= 4500 ? mv : -1;
}

/*
 * Correlated acknowledgment `PI 01 .. LEN16 FAMILY SEQ|80 STATUS RESULT`.
 * Returns the result length and sets *result, -1 if unrelated, -2 on failure.
 */
static inline int barracuda_ack(const unsigned char *p, unsigned int size,
				unsigned char family, unsigned char seq,
				const unsigned char **result)
{
	if (size < 13 || p[2] != 1 || p[10] != family || p[11] != (seq | 0x80))
		return -1;
	if (p[12] != 0)
		return -2;
	*result = p + 13;
	return size - 13;
}

/* Family-8 customer GET reply `PI 08 .. 04 00 PARAM 01 01 VALUE`; -1 if unrelated. */
static inline int barracuda_customer_reply(const unsigned char *p, unsigned int size,
					   unsigned char param)
{
	if (size != 14 || p[2] != 8 || p[8] != 4 || p[9] != 0 || p[10] != param ||
	    p[11] != 1 || p[12] != 1)
		return -1;
	return p[13];
}

/* Family-14 getter reply `PI 0e .. 02 00 CMD VALUE`; -1 if unrelated. */
static inline int barracuda_link_reply(const unsigned char *p, unsigned int size,
				       unsigned char command)
{
	if (size != 12 || p[2] != 0x0e || p[8] != 2 || p[9] != 0 || p[10] != command)
		return -1;
	return p[11];
}

static inline void barracuda_decode(const unsigned char *p, unsigned int size,
				    barracuda_notify_fn notify, void *context)
{
	if (size == 12 && p[2] == 0x0e && p[8] == 2 && p[9] == 0 &&
	    p[10] == 0xe3 && p[11] <= 1) {
		notify(context, BARRACUDA_LINK, p[11]);
		return;
	}
	/* Op 02 is an unsolicited report, op 01 the reply to a customer GET. */
	if (size != 14 || p[2] != 8 || p[8] != 4 || p[9] != 0 ||
	    (p[11] != 2 && p[11] != 1) || p[12] != 1)
		return;

	switch (p[10]) {
	case 0x20:
		/* Link evidence only from the validated unsolicited report. */
		if (p[11] == 2 && p[13] <= 1)
			notify(context, BARRACUDA_LINK, p[13]);
		break;
	case 0x21:
		if (p[13] <= 100)
			notify(context, BARRACUDA_CAPACITY, p[13]);
		break;
	case 0x2a:
		if (p[13] <= 1)
			notify(context, BARRACUDA_EXTERNAL_POWER, p[13]);
		break;
	}
}

/* Do not scan arbitrary payload bytes for a new header after corruption. */
static inline void barracuda_feed(struct barracuda_stream *s,
				 const unsigned char *report, unsigned int size,
				 barracuda_notify_fn notify, barracuda_frame_fn frame,
				 void *context)
{
	unsigned int i, count;

	/* Media reports are passed through and may interleave stream fragments. */
	if (!size || report[0] != 1)
		return;
	if (size < 3 || report[1] != 0x80 || report[2] > 61 ||
	    size < 3U + report[2]) {
		s->used = 0;
		return;
	}
	count = report[2];
	for (i = 0; i < count; i++) {
		s->data[s->used++] = report[3 + i];
		if ((s->used == 1 && s->data[0] != 0x50) ||
		    (s->used == 2 && s->data[1] != 0x49)) {
			s->used = 0;
			return;
		}
		if (s->used == 10) {
			s->expected = 10U + s->data[8] + (s->data[9] << 8);
			if (s->expected > sizeof(s->data)) {
				s->used = 0;
				return;
			}
		}
		if (s->used >= 10 && s->used == s->expected) {
			barracuda_decode(s->data, s->used, notify, context);
			if (frame)
				frame(context, s->data, s->used);
			s->used = 0;
		}
	}
}

#endif
