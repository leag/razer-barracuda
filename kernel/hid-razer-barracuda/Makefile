# SPDX-License-Identifier: GPL-2.0-only OR MIT
obj-m += hid-razer-barracuda.o
KDIR ?= /lib/modules/$(shell uname -r)/build
ifneq ($(shell sed -n 's/^CONFIG_CC_IS_CLANG=y/yes/p' $(KDIR)/.config),)
KERNEL_TOOLS = LLVM=1
endif

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(KERNEL_TOOLS) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
