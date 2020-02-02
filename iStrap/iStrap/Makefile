SDK_INCLUDE_DIR=$(shell xcrun -sdk iphoneos --show-sdk-path)/usr/include

CC=xcrun -sdk iphoneos clang
CFLAGS=-target aarch64-linux-elf -D__arm64__ -Wall -static -nostdlib -I$(SDK_INCLUDE_DIR) -Iinclude -Os

LDFLAGS=-target aarch64-linux-elf -fuse-ld=/usr/local/opt/llvm/bin/ld.lld -static -nostdlib linkerScript.ld -Llib -dead-strip -fpie

DEPS=../common/util.h

OBJS=main.o util.o
OBJS_LIBC=string_and_mem.o deviceTree.o patch.o shellcode.o suid_patch.o patchfinder.o miniz_tinfl.o

OBJS_2X=framebuffer@2x.o
OBJS_4X=framebuffer@4x.o

NAME=iStrap

ELF=$(NAME)@2x.elf $(NAME)@4x.elf
BIN=../build/$(NAME)@2x.bin ../build/$(NAME)@4x.bin

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%@2x.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS) -DSCALE_FACTOR=2

%@4x.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS) -DSCALE_FACTOR=4

%.o: %.S $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: ../common/%.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: small_libc/%.c
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: miniz/%.c
	$(CC) -c -o $@ $< $(CFLAGS)

%@2x.elf: $(OBJS) $(OBJS_LIBC) $(OBJS_2X) linkerScript.ld
	$(CC) -o $@ $(OBJS) $(OBJS_LIBC) $(OBJS_2X) $(LDFLAGS)

%@4x.elf: $(OBJS) $(OBJS_LIBC) $(OBJS_4X) linkerScript.ld
	$(CC) -o $@ $(OBJS) $(OBJS_LIBC) $(OBJS_4X) $(LDFLAGS)

../build/%.bin: %.elf
	/usr/local/opt/binutils/bin/gobjcopy -Obinary $< $@

iStrap: $(BIN)

PHONY: clean
clean:
	rm -rf $(ELF) $(BIN) $(OBJS) $(OBJS_LIBC) $(OBJS_2X) $(OBJS_4X)
