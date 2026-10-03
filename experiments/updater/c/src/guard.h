/* Spec: experiments/updater/shared/README.md */
#ifndef ABORA_DOWNGRADE_GUARD_H
#define ABORA_DOWNGRADE_GUARD_H

#include <stdbool.h>
#include <stddef.h>

/* Writes the base version of `tag` into `out` ("v4.1-DEMO2" -> "4.1").
 * Returns false if `out_size` is too small; `out` is then left empty. */
bool tag_base_version(const char *tag, char *out, size_t out_size);

/* Numeric versions sort before non-numeric refs; returns <0, 0 or >0. */
int compare_dotted_versions(const char *a, const char *b);

bool version_less_than(const char *a, const char *b);

/* True if updating from `current` to `selected_ref` may proceed. */
bool guard_allows(const char *current, const char *selected_ref, bool allow_downgrade);

#endif
