/*
 * copyfile() pipeline over an in-memory payload: optional AES decryption, one of
 * gzip/xz/zstd/lz4 decompression, sha256 and cpio checksum.
 * Input: [selector byte][payload]; selector picks the pipeline stages.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "swupdate.h"
#include "swupdate_aes.h"
#include "util.h"

#define MAX_LEN (256 * 1024)
#define MAX_OUTPUT (4 * 1024 * 1024)

static const enum compression_type comp[] = {
	COMPRESSED_FALSE, COMPRESSED_ZLIB, COMPRESSED_XZ,
	COMPRESSED_ZSTD, COMPRESSED_LZ4, COMPRESSED_TRUE,
};

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc;
	(void)argv;
	loglevel = OFF;
	return 0;
}

static int sink(void *out, const void *buf, size_t len)
{
	size_t *total = out;

	(void)buf;
	*total += len;
	return *total > MAX_OUTPUT ? -EFBIG : 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	static unsigned char hash[32] = { 1, 2, 3, 4, 5, 6, 7, 8 };
	struct swupdate_copy cp;
	uint64_t offs = 0;
	uint32_t chksum = 0;
	size_t total = 0;
	unsigned char *payload;
	uint8_t sel;

	if (size < 1 || size > MAX_LEN)
		return -1;
	sel = data[0];
	size--;
	payload = malloc(size ? size : 1);
	if (!payload)
		return -1;
	memcpy(payload, data + 1, size);

	memset(&cp, 0, sizeof(cp));
	cp.fdin = -1;
	cp.inbuf = payload;
	cp.callback = sink;
	cp.out = &total;
	cp.nbytes = size;
	cp.offs = &offs;
	cp.compressed = comp[(sel & 7) % ARRAY_SIZE(comp)];
	if (sel & 0x08) {
		cp.encrypted = true;
		cp.cipher = AES_CBC_128;
		cp.imgaes = "000102030405060708090a0b0c0d0e0f";
		cp.imgivt = "0f0e0d0c0b0a09080706050403020100";
	}
	if (sel & 0x10)
		cp.hash = hash;
	if (sel & 0x20)
		cp.checksum = &chksum;

	copyfile(&cp);
	free(payload);
	return 0;
}
