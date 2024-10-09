# Klipper build system
#
# Copyright (C) 2016-2020  Kevin O'Connor <kevin@koconnor.net>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

# Output directory
OUT=out/

# Kconfig includes
export KCONFIG_CONFIG     := $(CURDIR)/.config
-include $(KCONFIG_CONFIG)

# Common command definitions
CC=$(CROSS_PREFIX)gcc
AS=$(CROSS_PREFIX)as
LD=$(CROSS_PREFIX)ld
OBJCOPY=$(CROSS_PREFIX)objcopy
OBJDUMP=$(CROSS_PREFIX)objdump
STRIP=$(CROSS_PREFIX)strip
CPP=$(CROSS_PREFIX)cpp
PYTHON=python3

# Source files
src-y =
dirs-y = src

# Default compiler flags

CPPFLAGS = -I$(OUT) -P -MD -MT $@

CFLAGS += -O3
CFLAGS += -g0
#CFLAGS += -g
#CFLAGS += -ggdb3

CFLAGS += -flto=80
CFLAGS += -fwhole-program
CFLAGS += -fno-use-linker-plugin 

CFLAGS += -ffunction-sections
CFLAGS += -fdata-sections
CFLAGS += -fsection-anchors

CFLAGS += -fno-delete-null-pointer-checks

CFLAGS += -ffreestanding

CFLAGS += -Wl,-O2
CFLAGS += -Wl,-Map=$@.map
CFLAGS += -Wl,--gc-sections

CFLAGS += -std=gnu11

CFLAGS += -Wall
CFLAGS += -Wextra

CFLAGS += -Wno-array-bounds
CFLAGS += -Wno-implicit-int
CFLAGS += -Wno-old-style-declaration
CFLAGS += -Wno-sign-compare
CFLAGS += -Wno-unused-parameter

CFLAGS += -I$(OUT)
CFLAGS += -Isrc
CFLAGS += -I$(OUT)board-generic
CFLAGS += -MD

OBJS_klipper.elf += $(patsubst %.c,$(OUT)src/%.o,$(src-y))
OBJS_klipper.elf += $(OUT)compile_time_request.o

CFLAGS_klipper.elf += $(CFLAGS)

# Default targets
target-y := $(OUT)klipper.elf

all:

# Include board specific makefile
include src/Makefile
-include src/$(patsubst "%",%,$(CONFIG_BOARD_DIRECTORY))/Makefile

################ Main build rules

$(OUT)%.o: %.c $(OUT)autoconf.h
	@echo "  Compiling $@"
	$(Q)$(CC) $(CFLAGS) -c $< -o $@

$(OUT)%.ld: %.lds.S $(OUT)autoconf.h
	@echo "  Preprocessing $@"
	$(Q)$(CPP) -I$(OUT) -P -MD -MT $@ $< -o $@

$(OUT)klipper.elf: $(OBJS_klipper.elf)
	@echo "  Linking $@"
	$(Q)$(CC) $(OBJS_klipper.elf) $(CFLAGS_klipper.elf) -o $@
	$(Q)scripts/check-gcc.sh $@ $(OUT)compile_time_request.o

################ Compile time requests

$(OUT)%.o.ctr: $(OUT)%.o
	$(Q)$(OBJCOPY) -j '.compile_time_request' -O binary $^ $@

$(OUT)compile_time_request.o: $(patsubst %.c,$(OUT)src/%.o.ctr,$(src-y)) ./scripts/buildcommands.py
	@echo "  Building $@"
	$(Q)cat $(patsubst %.c,$(OUT)src/%.o.ctr,$(src-y)) | tr -s '\0' '\n' > $(OUT)compile_time_request.txt
	$(Q)$(PYTHON) ./scripts/buildcommands.py -d $(OUT)klipper.dict -t "$(CC);$(AS);$(LD);$(OBJCOPY);$(OBJDUMP);$(STRIP)" $(OUT)compile_time_request.txt $(OUT)compile_time_request.c
	$(Q)$(CC) $(CFLAGS) -c $(OUT)compile_time_request.c -o $@

################ Auto generation of "board/" include file link

create-board-link:
	@echo "  Creating symbolic link $(OUT)board"
	$(Q)mkdir -p $(addprefix $(OUT),$(dirs-y))
	$(Q)rm -f $(OUT)*.d $(patsubst %,$(OUT)%/*.d,$(dirs-y))
	$(Q)rm -f $(OUT)board
	$(Q)ln -sf $(CURDIR)/src/$(CONFIG_BOARD_DIRECTORY) $(OUT)board
	$(Q)mkdir -p $(OUT)board-generic
	$(Q)rm -f $(OUT)board-generic/board
	$(Q)ln -sf $(CURDIR)/src/generic $(OUT)board-generic/board

# Hack to rebuild OUT directory and reload make dependencies on Kconfig change
$(OUT)board-link: $(KCONFIG_CONFIG)
	$(Q)mkdir -p $(OUT)
	$(Q)echo "# Makefile board-link rule" > $@
	$(Q)$(MAKE) create-board-link
include $(OUT)board-link

################ Kconfig rules

$(OUT)autoconf.h: $(KCONFIG_CONFIG)
	@echo "  Building $@"
	$(Q)mkdir -p $(OUT)
	$(Q) KCONFIG_AUTOHEADER=$@ $(PYTHON) lib/kconfiglib/genconfig.py src/Kconfig

$(KCONFIG_CONFIG) olddefconfig: src/Kconfig
	$(Q)$(PYTHON) lib/kconfiglib/olddefconfig.py src/Kconfig

menuconfig:
	$(Q)$(PYTHON) lib/kconfiglib/menuconfig.py src/Kconfig

################ Generic rules

# Make definitions
.PHONY : all clean distclean olddefconfig menuconfig create-board-link FORCE
.DELETE_ON_ERROR:

all: $(target-y)

clean:
	$(Q)rm -rf $(OUT)

distclean: clean
	$(Q)rm -f .config .config.old

-include $(OUT)*.d $(patsubst %,$(OUT)%/*.d,$(dirs-y))
