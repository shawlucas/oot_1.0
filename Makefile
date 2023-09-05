MAKEFLAGS += --no-builtin-rules

# Ensure the build fails if a piped command fails
SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c

# Build options can either be changed by modifying the makefile, or by building with 'make SETTING=value'

# If COMPARE is 1, check the output md5sum after building
COMPARE ?= 1
# If NON_MATCHING is 1, define the NON_MATCHING C flag when building
NON_MATCHING ?= 0
# If ORIG_COMPILER is 1, compile with QEMU_IRIX and the original compiler
ORIG_COMPILER ?= 0
# If COMPILER is "gcc", compile with GCC instead of IDO.
COMPILER ?= ido

CFLAGS ?=
CPPFLAGS ?=

# Number of threads to disassmble, extract, and compress with
N_THREADS ?= $(shell nproc)

# ORIG_COMPILER cannot be combined with a non-IDO compiler. Check for this case and error out if found.
ifneq ($(COMPILER),ido)
	ifeq ($(ORIG_COMPILER),1)
		$(error ORIG_COMPILER can only be used with the IDO compiler. Please check your Makefile variables and try again)
	endif
endif

ifeq ($(COMPILER),gcc)
	CFLAGS += -DCOMPILER_GCC
	CPPFLAGS += -DCOMPILER_GCC
	NON_MATCHING := 1
endif

# Set prefix to mips binutils binaries (mips-linux-gnu-ld => 'mips-linux-gnu-') - Change at your own risk!
# In nearly all cases, not having 'mips-linux-gnu-*' binaries on the PATH is indicative of missing dependencies
MIPS_BINUTILS_PREFIX ?= mips-linux-gnu-

ifeq ($(NON_MATCHING),1)
	CFLAGS += -DNON_MATCHING -DAVOID_UB
	CPPFLAGS += -DNON_MATCHING -DAVOID_UB
	COMPARE := 0
endif

# rom compression flags
COMPFLAGS := --in oot.us.rev1.rom_uncompressed.z64 --out oot.us.rev1.rom.z64 --codec yaz --dma 0x7430,1526 --compress 10-14,27-1509 --skip 942,944,946,948,950,952,954,956,958,960,962,964,966,968,970,972,974,976,978,980,982,984,986,988,990,992,994,996,998,1000,1002,1004 --threads 16 --only-stdout

ifneq ($(NON_MATCHING),1)
	COMPFLAGS += --matching
endif

PROJECT_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

MAKE = make
CPPFLAGS += -fno-dollars-in-identifiers -P

ifeq ($(OS),Windows_NT)
		DETECTED_OS=windows
else
		UNAME_S := $(shell uname -s)
		ifeq ($(UNAME_S),Linux)
				DETECTED_OS=linux
		endif
		ifeq ($(UNAME_S),Darwin)
				DETECTED_OS=macos
				MAKE=gmake
				CPPFLAGS += -xc++
		endif
endif

N_THREADS ?= $(shell nproc)

#### Tools ####
ifneq ($(shell type $(MIPS_BINUTILS_PREFIX)ld >/dev/null 2>/dev/null; echo $$?), 0)
	$(error Unable to find $(MIPS_BINUTILS_PREFIX)ld. Please install or build MIPS binutils, commonly mips-linux-gnu. (or set MIPS_BINUTILS_PREFIX if your MIPS binutils install uses another prefix))
endif

# Detect compiler and set variables appropriately.
ifeq ($(COMPILER),gcc)
	CC       := $(MIPS_BINUTILS_PREFIX)gcc
else
ifeq ($(COMPILER),ido)
	CC       := tools/ido_recomp/$(DETECTED_OS)/7.1/cc
	CC_OLD   := tools/ido_recomp/$(DETECTED_OS)/5.3/cc
else
$(error Unsupported compiler. Please use either ido or gcc as the COMPILER variable.)
endif
endif

# if ORIG_COMPILER is 1, check that either QEMU_IRIX is set or qemu-irix package installed
ifeq ($(ORIG_COMPILER),1)
	ifndef QEMU_IRIX
		QEMU_IRIX := $(shell which qemu-irix)
		ifeq (, $(QEMU_IRIX))
			$(error Please install qemu-irix package or set QEMU_IRIX env var to the full qemu-irix binary path)
		endif
	endif
	CC        = $(QEMU_IRIX) -L tools/ido7.1_compiler tools/ido7.1_compiler/usr/bin/cc
	CC_OLD    = $(QEMU_IRIX) -L tools/ido5.3_compiler tools/ido5.3_compiler/usr/bin/cc
endif

AS         := $(MIPS_BINUTILS_PREFIX)as
LD         := $(MIPS_BINUTILS_PREFIX)ld
OBJCOPY    := $(MIPS_BINUTILS_PREFIX)objcopy
OBJDUMP    := $(MIPS_BINUTILS_PREFIX)objdump
EMULATOR   ?= 
EMU_FLAGS  ?= 

INC        := -Iinclude -Isrc -Ibuild -I.

# Check code syntax with host compiler
CHECK_WARNINGS := -Wall -Wextra -Wno-format-security -Wno-unknown-pragmas -Wno-unused-parameter -Wno-unused-variable -Wno-missing-braces

CPP        := cpp
MKLDSCRIPT := tools/mkldscript
MKDMADATA  := tools/mkdmadata
ELF2ROM    := tools/elf2rom
ZAPD       := tools/ZAPD/ZAPD.out
FADO       := tools/fado/fado.elf
Z64COMPRESS := tools/z64compress/z64compress

ifeq ($(COMPILER),gcc)
	OPTFLAGS := -Os -ffast-math -fno-unsafe-math-optimizations
else
	OPTFLAGS := -O2
endif

ASFLAGS := -march=vr4300 -32 -no-pad-sections -Iinclude

ifeq ($(COMPILER),gcc)
	CFLAGS += -G 0 -nostdinc $(INC) -march=vr4300 -mfix4300 -mabi=32 -mno-abicalls -mdivide-breaks -fno-zero-initialized-in-bss -fno-toplevel-reorder -ffreestanding -fno-common -fno-merge-constants -mno-explicit-relocs -mno-split-addresses $(CHECK_WARNINGS) -funsigned-char
	MIPS_VERSION := -mips3
else
	# we support Microsoft extensions such as anonymous structs, which the compiler does support but warns for their usage. Surpress the warnings with -woff.
	CFLAGS += -G 0 -non_shared -fullwarn -verbose -Xcpluscomm $(INC) -Wab,-r4300_mul -woff 516,649,838,712
	MIPS_VERSION := -mips2
endif

ifeq ($(COMPILER),ido)
	# Have CC_CHECK pretend to be a MIPS compiler
	MIPS_BUILTIN_DEFS := -D_MIPS_ISA_MIPS2=2 -D_MIPS_ISA=_MIPS_ISA_MIPS2 -D_ABIO32=1 -D_MIPS_SIM=_ABIO32 -D_MIPS_SZINT=32 -D_MIPS_SZLONG=32 -D_MIPS_SZPTR=32
	CC_CHECK  = gcc -fno-builtin -fsyntax-only -funsigned-char -std=gnu90 -D_LANGUAGE_C -DNON_MATCHING $(MIPS_BUILTIN_DEFS) $(INC) $(CHECK_WARNINGS)
	ifeq ($(shell getconf LONG_BIT), 32)
		# Work around memory allocation bug in QEMU
		export QEMU_GUEST_BASE := 1
	else
		# Ensure that gcc (warning check) treats the code as 32-bit
		CC_CHECK += -m32
	endif
else
	CC_CHECK  = @:
endif

OBJDUMP_FLAGS := -d -r -z -Mreg-names=32

# ROM image
ROMC := oot.us.rev1.rom.z64
ROM := $(ROMC:.rom.z64=.rom_uncompressed.z64)
ELF := $(ROM:.z64=.elf)
# description of ROM segments
SPEC := spec

ASM_DIRS := asm

ifeq ($(COMPILER),ido)
SRC_DIRS := $(shell find src -type d -not -path src/gcc_fix)
else
SRC_DIRS := $(shell find src -type d)
endif

S_FILES		  := $(foreach dir, $(ASM_DIRS), $(wildcard $(dir)/*.s))
O_FILES       := $(foreach f,$(wildcard baserom/*),build/$f.o) \
				 $(foreach f, $(S_FILES:.s=.o), build/$f)

# create build directories
$(shell mkdir -p build/baserom $(foreach dir, $(SRC_DIRS) $(ASM_DIRS), build/$(dir)))

ifeq ($(COMPILER),ido)
endif

#### Main Targets ###

uncompressed: $(ROM)
ifeq ($(COMPARE),1)
	@md5sum $(ROM)
endif

compressed: $(ROMC)
ifeq ($(COMPARE),1)
	@md5sum $(ROMC)
endif

clean:
	$(RM) -r $(ROM) $(ELF) build

distclean: clean
	$(RM) -r baserom/
	$(MAKE) -C tools distclean

setup:
	$(MAKE) -C tools
	python3 extract_baserom.py

.PHONY: all setup run distclean

#### Various Recipes ####

$(ROM): $(ELF)
	$(ELF2ROM) -cic 6105 $< $@

$(ROMC): $(ROM)
	$(Z64COMPRESS) $(COMPFLAGS)

$(ELF): $(O_FILES) $(OVL_RELOC_FILES) build/ldscript.txt
	$(LD) -T build/ldscript.txt --no-check-sections --accept-unknown-input-arch --emit-relocs -Map build/z64.map -o $@

build/$(SPEC): $(SPEC)
	$(CPP) $(CPPFLAGS) $< > $@

build/ldscript.txt: build/$(SPEC)
	$(MKLDSCRIPT) $< $@

#build/dmadata_table_spec.h: build/$(SPEC)
#	$(MKDMADATA) $< $@

#build/dmadata.o: build/dmadata_table_spec.h

build/asm/%.o: asm/%.s
	$(AS) $(ASFLAGS) $< -o $@

build/baserom/%.o: baserom/%
	$(OBJCOPY) -I binary -O elf32-big $< $@

