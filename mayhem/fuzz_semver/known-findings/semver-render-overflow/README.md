# semver_render() overflows its destination

`semver_render(semver_t *x, char *dest)` (`core/semver.c`) builds the string with `strcat`/`concat_char`
and takes no length. `compare_versions()` (`core/artifacts_versions.c`, trace log level) passes a
`SWUPDATE_GENERAL_STRING_SIZE` (256) stack buffer. The rendering is longer than the input
(`"-ccc..."` renders as `"0.0.0-ccc..."`), so a 253-byte version that still fits the 256-byte version
field of sw-description overflows `left_rendered`/`right_rendered`.

Reproduce: `/mayhem/fuzz_semver-standalone mayhem/fuzz_semver/known-findings/semver-render-overflow/reproducer`
(ASan: stack-buffer-overflow WRITE in `strcat` <- `concat_char` <- `semver_render`).

Impact: stack overflow with attacker-controlled bytes when `loglevel >= TRACELEVEL` and the version
comes from an untrusted sw-description / installed-versions file.

Fix: give `semver_render` a size argument (`snprintf`-style) and pass `sizeof(buf)` from
`compare_versions`.
