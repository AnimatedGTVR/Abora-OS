#include "guard.h"

#include <stdlib.h>
#include <string.h>

#define PART_MAX 2147483647L

bool tag_base_version(const char *tag, char *out, size_t out_size)
{
    const char *stripped = tag[0] == 'v' ? tag + 1 : tag;
    size_t len;

    if (stripped[0] >= '0' && stripped[0] <= '9') {
        /* Keep [0-9]+(\.[0-9]+)*: a dot only counts if a digit follows it. */
        len = 0;
        for (;;) {
            while (stripped[len] >= '0' && stripped[len] <= '9')
                len++;
            if (stripped[len] != '.' || stripped[len + 1] < '0' || stripped[len + 1] > '9')
                break;
            len++;
        }
    } else {
        len = strlen(stripped);
    }

    if (len >= out_size) {
        if (out_size > 0)
            out[0] = '\0';
        return false;
    }
    memcpy(out, stripped, len);
    out[len] = '\0';
    return true;
}

/* Parses one dot-separated part starting at *cursor. Advances *cursor past the
 * part and its trailing dot. Returns false if the part is not a decimal integer
 * that fits in a signed 32-bit int. */
static bool next_part(const char **cursor, long *value)
{
    const char *p = *cursor;
    long result = 0;

    if (*p < '0' || *p > '9')
        return false;
    for (; *p >= '0' && *p <= '9'; p++) {
        result = result * 10 + (*p - '0');
        if (result > PART_MAX)
            return false;
    }
    if (*p == '.') {
        p++;
        if (*p == '\0')
            return false;
    } else if (*p != '\0') {
        return false;
    }
    *cursor = p;
    *value = result;
    return true;
}

static bool is_numeric(const char *version)
{
    long ignored;

    if (*version == '\0')
        return false;
    while (*version != '\0') {
        if (!next_part(&version, &ignored))
            return false;
    }
    return true;
}

int compare_dotted_versions(const char *a, const char *b)
{
    bool a_numeric = is_numeric(a);
    bool b_numeric = is_numeric(b);

    if (a_numeric != b_numeric)
        return a_numeric ? -1 : 1;
    if (!a_numeric) {
        int cmp = strcmp(a, b);
        return (cmp > 0) - (cmp < 0);
    }

    /* Both are validated, so next_part cannot fail; missing parts count as 0. */
    while (*a != '\0' || *b != '\0') {
        long av = 0, bv = 0;
        if (*a != '\0')
            next_part(&a, &av);
        if (*b != '\0')
            next_part(&b, &bv);
        if (av != bv)
            return av < bv ? -1 : 1;
    }
    return 0;
}

bool version_less_than(const char *a, const char *b)
{
    return strcmp(a, b) != 0 && compare_dotted_versions(a, b) < 0;
}

bool guard_allows(const char *current, const char *selected_ref, bool allow_downgrade)
{
    size_t size;
    char *base;
    bool allowed;

    if (strcmp(selected_ref, "edge") == 0 || allow_downgrade)
        return true;

    /* The base version is never longer than the ref it came from. */
    size = strlen(selected_ref) + 1;
    base = malloc(size);
    if (base == NULL)
        return false; /* fail closed: an unknown answer must not permit a downgrade */
    tag_base_version(selected_ref, base, size);
    allowed = !version_less_than(base, current);
    free(base);
    return allowed;
}
