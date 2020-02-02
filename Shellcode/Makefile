CC=xcrun -sdk iphoneos clang
CFLAGS=-target arm64-apple-darwin -Wall

FILES=checkm8_arm64.bin usb_0xA1_2_arm64.bin t8010_t8011_disable_wxn_arm64.bin

%.o: %.S
	$(CC) -c -o $@ $< $(CFLAGS)

%.bin: %.o
	/usr/local/opt/binutils/bin/gobjcopy -Obinary $< $@

all: $(FILES)

PHONY: clean
clean:
	rm -rf $(FILES)
