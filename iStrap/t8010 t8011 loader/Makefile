SDK_INCLUDE_DIR=$(shell xcrun -sdk iphoneos --show-sdk-path)/usr/include

CC=xcrun -sdk iphoneos clang
CFLAGS=-target aarch64-none-elf -D__arm64__ -Wall -static -nostdlib -I$(SDK_INCLUDE_DIR) -Os

LD=/usr/local/opt/llvm/bin/ld.lld
LDFLAGS=linkerScript.ld

DEPS=../common/util.h

OBJS=start.o loader.o ttbr0_hooker.o util.o

NAME=t8010_t8011_iStrap_loader

ELF=$(NAME).elf
BIN=../build/$(NAME).bin

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: %.S $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: ../common/%.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.elf: $(OBJS) linkerScript.ld
	$(LD) -o $(ELF) $(OBJS) $(LDFLAGS)

../build/%.bin: $(ELF)
	/usr/local/opt/binutils/bin/gobjcopy -Obinary $< $@

iStrap_loader: $(BIN)

PHONY: clean
clean:
	rm -rf $(ELF) $(BIN) $(OBJS)
