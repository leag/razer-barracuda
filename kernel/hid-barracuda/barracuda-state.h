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

/*
 * A cable report that changes a known state; the first value after a link,
 * including the driver's own GET reply, does not count.
 */
static inline bool barracuda_cable_changed(int previous, int value)
{
	return previous >= 0 && previous != value;
}

enum barracuda_supply_action {
	BARRACUDA_SUPPLY_NONE,
	BARRACUDA_SUPPLY_REGISTER,
	BARRACUDA_SUPPLY_UNREGISTER,
	BARRACUDA_SUPPLY_NOTIFY,
};

/*
 * Like hid-corsair-void, the battery exists only while the headset is linked.
 * An unknown link (startup, resume) keeps the current registration.
 */
static inline enum barracuda_supply_action
barracuda_supply_action(int linked, bool registered)
{
	if (linked == 1)
		return registered ? BARRACUDA_SUPPLY_NOTIFY : BARRACUDA_SUPPLY_REGISTER;
	if (linked == 0)
		return registered ? BARRACUDA_SUPPLY_UNREGISTER : BARRACUDA_SUPPLY_NONE;
	return registered ? BARRACUDA_SUPPLY_NOTIFY : BARRACUDA_SUPPLY_NONE;
}

#endif
