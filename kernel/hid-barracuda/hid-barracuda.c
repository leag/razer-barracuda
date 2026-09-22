// SPDX-License-Identifier: MIT
/* Razer Barracuda X (2022) USB HID battery support. */
#include <linux/hid.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/usb.h>
#include <linux/workqueue.h>

#include "barracuda-state.h"

#define BARRACUDA_VENDOR 0x1532
#define BARRACUDA_PRODUCT 0x0552

struct barracuda {
	struct hid_device *hdev;
	struct power_supply *battery;
	struct power_supply_desc desc;
	spinlock_t lock;
	struct barracuda_stream stream;
	struct delayed_work query_work;
	struct barracuda_state state;
	unsigned long fragment_at;
	unsigned int attempts;
	bool stopped;
	bool changed;
};

static enum power_supply_property barracuda_properties[] = {
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CAPACITY_LEVEL,
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
		/* A plugged-in 100% report does not prove charge termination. */
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

	if (!barracuda_state_event(&b->state, event, value))
		return;
	b->changed = true;
}

static int barracuda_raw_event(struct hid_device *hdev, struct hid_report *report,
			      u8 *data, int size)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;
	bool changed;

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
	barracuda_feed(&b->stream, data, size, barracuda_event, b);
	b->fragment_at = jiffies;
	changed = b->changed;
	spin_unlock_irqrestore(&b->lock, flags);
	if (changed)
		power_supply_changed(b->battery);
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

static int barracuda_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct power_supply_config config = {};
	struct usb_interface *intf = to_usb_interface(hdev->dev.parent);
	struct barracuda *b;
	int ret;

	if (intf->cur_altsetting->desc.bInterfaceNumber != 3)
		return -ENODEV;
	b = devm_kzalloc(&hdev->dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;
	b->hdev = hdev;
	barracuda_state_reset(&b->state);
	spin_lock_init(&b->lock);
	INIT_DELAYED_WORK(&b->query_work, barracuda_query);
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
	config.drv_data = b;
	b->battery = devm_power_supply_register(&hdev->dev, &b->desc, &config);
	if (IS_ERR(b->battery))
		return PTR_ERR(b->battery);
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

	spin_lock_irqsave(&b->lock, flags);
	b->stopped = true;
	spin_unlock_irqrestore(&b->lock, flags);
	cancel_delayed_work_sync(&b->query_work);
}

static void barracuda_remove(struct hid_device *hdev)
{
	struct barracuda *b = hid_get_drvdata(hdev);

	barracuda_stop(b);
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
	power_supply_changed(b->battery);
	return 0;
}

static int barracuda_resume(struct hid_device *hdev)
{
	struct barracuda *b = hid_get_drvdata(hdev);
	unsigned long flags;

	spin_lock_irqsave(&b->lock, flags);
	b->stopped = false;
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
MODULE_VERSION("0.1.3");
