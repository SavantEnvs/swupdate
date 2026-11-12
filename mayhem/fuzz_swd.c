/* sw-description parser: libconfig (default) or JSON (-DSWD_JSON). */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "swupdate.h"
#include "parsers.h"
#include "installer.h"
#include "util.h"

#define MAX_LEN (64 * 1024)

static char path[4096];

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	const char *base = getenv("TMPDIR");
	char dir[4096];

	(void)argc;
	(void)argv;
	snprintf(dir, sizeof(dir), "%s/swd-fuzz-XXXXXX",
		 (base && base[0]) ? base : "/tmp");
	if (!mkdtemp(dir))
		return 0;
	/* cleanup_files() unlinks <TMPDIR>/<name from sw-description>: keep it private */
	setenv("TMPDIR", dir, 1);
	snprintf(path, sizeof(path), "%s/sw-description", dir);
	loglevel = OFF;
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct swupdate_cfg sw;
	char *error = NULL;
	int fd;

	if (!path[0] || size > MAX_LEN)
		return -1;
	/* "@include" makes libconfig read other files: result would not depend on the input only */
	if (memmem(data, size, "@include", 8))
		return -1;

	fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
	if (fd < 0)
		return -1;
	if (write(fd, data, size) != (ssize_t)size) {
		close(fd);
		return -1;
	}
	close(fd);

	memset(&sw, 0, sizeof(sw));
	LIST_INIT(&sw.images);
	LIST_INIT(&sw.hardware);
	LIST_INIT(&sw.scripts);
	LIST_INIT(&sw.bootloader);
	LIST_INIT(&sw.vars);
	LIST_INIT(&sw.extprocs);
	LIST_INIT(&sw.swupdate_types);
	LIST_INIT(&sw.external_urls);
	LIST_INIT(&sw.installed_sw_list);
	/* set, so that the parser does not read /etc/hwrevision */
	strlcpy(sw.hw.boardname, "board", sizeof(sw.hw.boardname));
	strlcpy(sw.hw.revision, "1.0", sizeof(sw.hw.revision));

#ifdef SWD_JSON
	parse_json(&sw, path, &error);
#else
	parse_cfg(&sw, path, &error);
#endif
	free(error);
	cleanup_files(&sw);
	return 0;
}
