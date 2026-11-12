/* CPIO newc/crc header and filename parsing of the .swu stream. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "swupdate.h"
#include "cpiohdr.h"
#include "util.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc;
	(void)argv;
	loglevel = OFF;
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct filehdr fhdr;
	unsigned char *hdr;
	uint64_t offset = 0;
	size_t n;
	int fd;

	/* the caller in core/cpio_utils.c passes a filename-sized buffer, not an exact one */
	hdr = calloc(1, sizeof(fhdr.filename));
	if (!hdr)
		return -1;
	n = size < sizeof(struct new_ascii_header) ? size : sizeof(struct new_ascii_header);
	memcpy(hdr, data, n);
	memset(&fhdr, 0, sizeof(fhdr));
	if (!get_cpiohdr(hdr, &fhdr))
		swupdate_verify_chksum((uint32_t)fhdr.chksum, &fhdr);
	free(hdr);

	fd = memfd_create("cpio", 0);
	if (fd < 0)
		return -1;
	if (size && write(fd, data, size) != (ssize_t)size) {
		close(fd);
		return -1;
	}

	memset(&fhdr, 0, sizeof(fhdr));
	lseek(fd, 0, SEEK_SET);
	extract_cpio_header(fd, &fhdr, &offset);

	/* second pass from an input-derived start offset */
	if (size) {
		memset(&fhdr, 0, sizeof(fhdr));
		extract_img_from_cpio(fd, data[0] % 64, &fhdr);
	}
	close(fd);
	return 0;
}
