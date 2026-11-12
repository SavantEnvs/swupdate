/* Version string comparison: "<left>\0<right>" (semver, 4-number and lexicographic forms). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "swupdate.h"
#include "semver.h"
#include "util.h"

#define MAX_LEN 4096

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc;
	(void)argv;
	loglevel = OFF;
	return 0;
}

static char *dup_exact(const uint8_t *s, size_t n)
{
	char *p = malloc(n + 1);

	if (p) {
		memcpy(p, s, n);
		p[n] = '\0';
	}
	return p;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	const uint8_t *sep;
	size_t llen;
	char *l, *r;
	semver_t sv = {};
	char rendered[SWUPDATE_GENERAL_STRING_SIZE];

	if (size > MAX_LEN)
		return -1;
	sep = memchr(data, '\0', size);
	llen = sep ? (size_t)(sep - data) : size;
	l = dup_exact(data, llen);
	r = dup_exact(sep ? sep + 1 : data + size, sep ? size - llen - 1 : 0);
	if (!l || !r) {
		free(l);
		free(r);
		return -1;
	}

	compare_versions(l, r);
	compare_versions(r, l);

	semver_is_valid(l);
	if (!semver_parse(l, &sv)) {
		/* compare_versions() renders into a SWUPDATE_GENERAL_STRING_SIZE buffer at trace level;
		 * versions from sw-description are shorter than that field */
		rendered[0] = '\0';
		if (llen < sizeof(rendered))
			semver_render(&sv, rendered);
		semver_numeric(&sv);
		semver_free(&sv);
	}
	semver_clean(r);

	free(l);
	free(r);
	return 0;
}
