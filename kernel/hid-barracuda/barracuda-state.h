/* SPDX-License-Identifier: MIT */
#ifndef BARRACUDA_STATE_H
#define BARRACUDA_STATE_H

#include "barracuda-protocol.h"

struct barracuda_state {
	int linked;
	int capacity;
	int external_power;
};

static inline void barracuda_state_reset(struct barracuda_state *s)
{
	s->linked = BARRACUDA_UNKNOWN;
	s->capacity = BARRACUDA_UNKNOWN;
	s->external_power = BARRACUDA_UNKNOWN;
}

static inline bool barracuda_state_present(const struct barracuda_state *s)
{
	return s->linked == 1;
}

/* Suspend invalidates the link and cable state, not the last percentage. */
static inline void barracuda_state_suspend(struct barracuda_state *s)
{
	s->linked = BARRACUDA_UNKNOWN;
	s->external_power = BARRACUDA_UNKNOWN;
}

/* A percentage is the last observation until replaced or the driver resets. */
static inline bool barracuda_state_event(struct barracuda_state *s,
					enum barracuda_event event, int value)
{
	if (event == BARRACUDA_LINK) {
		bool changed = s->linked != value;

		s->linked = value;
		if (!value)
			s->external_power = BARRACUDA_UNKNOWN;
		return changed;
	}
	if (s->linked == 0)
		return false;
	if (event == BARRACUDA_CAPACITY)
		s->capacity = value;
	else if (event == BARRACUDA_EXTERNAL_POWER)
		s->external_power = value;
	return true;
}

#endif
