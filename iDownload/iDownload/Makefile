CC=xcrun -sdk iphoneos clang
CFLAGS=-target arm64-apple-darwin -arch arm64 -Wall -nostdlib -fno-stack-protector -DiOS
LDFLAGS=-target arm64-apple-darwin -arch arm64 -dead-strip -framework Foundation

OBJS=main.o
DEPS=iDownload.entitlements

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

%.o: %.S $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

iDiskMounter: $(OBJS)
	$(CC) -o ../build/iDownload $(OBJS) $(LDFLAGS)
	codesign -s - --entitlements iDownload.entitlements ../build/iDownload
	cat ../build/iDownload | python -c "import sys, zlib; print zlib.compress(sys.stdin.read(), 9)" > ../build/iDownload.z

PHONY: clean
clean:
	rm -f $(OBJS) ../build/iDownload ../build/iDownload.z
