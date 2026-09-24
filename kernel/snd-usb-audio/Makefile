# SPDX-License-Identifier: MIT
# Builds the downloaded sound/usb tree (GPL-2.0) with the Barracuda jack quirk.
KDIR ?= /lib/modules/$(shell uname -r)/build
ifneq ($(shell sed -n 's/^CONFIG_CC_IS_CLANG=y/yes/p' $(KDIR)/.config),)
KERNEL_TOOLS = LLVM=1
endif

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/sound/usb $(KERNEL_TOOLS) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/sound/usb clean
