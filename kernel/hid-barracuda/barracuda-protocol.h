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

static inline void barracuda_decode(const unsigned char *p, unsigned int size,
				    barracuda_notify_fn notify, void *context)
{
	if (size == 12 && p[2] == 0x0e && p[8] == 2 && p[9] == 0 &&
	    p[10] == 0xe3 && p[11] <= 1) {
		notify(context, BARRACUDA_LINK, p[11]);
		return;
	}
	if (size != 14 || p[2] != 8 || p[8] != 4 || p[9] != 0 ||
	    p[11] != 2 || p[12] != 1)
		return;

	switch (p[10]) {
	case 0x20:
		if (p[13] <= 1)
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
				 barracuda_notify_fn notify, void *context)
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
			s->used = 0;
		}
	}
}

#endif
