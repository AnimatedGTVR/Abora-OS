/* TAP test runner over the shared vectors in ../shared. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/guard.h"

#define LINE_MAX_LEN 1024
#define FIELDS_MAX 4

static int test_number;
static int failures;

static void report(bool ok, const char *description)
{
    test_number++;
    if (!ok)
        failures++;
    printf("%s %d - %s\n", ok ? "ok" : "not ok", test_number, description);
}

/* Splits `line` in place on tabs. Returns the number of fields. */
static int split_tabs(char *line, char *fields[])
{
    int count = 0;
    char *cursor = line;

    line[strcspn(line, "\r\n")] = '\0';
    for (;;) {
        char *tab = strchr(cursor, '\t');
        if (count == FIELDS_MAX)
            return FIELDS_MAX + 1;
        fields[count++] = cursor;
        if (tab == NULL)
            return count;
        *tab = '\0';
        cursor = tab + 1;
    }
}

typedef void (*case_fn)(char *fields[]);

static void run_file(const char *name, int expected_fields, case_fn check)
{
    char path[256];
    char line[LINE_MAX_LEN];
    int line_number = 0;
    int cases = 0;
    FILE *file;

    snprintf(path, sizeof path, "../shared/%s", name);
    file = fopen(path, "r");
    if (file == NULL) {
        printf("Bail out! cannot open %s\n", path);
        exit(1);
    }
    while (fgets(line, sizeof line, file) != NULL) {
        char *fields[FIELDS_MAX + 1];
        line_number++;
        if (line[0] == '#' || strspn(line, " \t\r\n") == strlen(line))
            continue;
        if (split_tabs(line, fields) != expected_fields) {
            printf("Bail out! %s:%d: expected %d tab-separated fields\n", path, line_number, expected_fields);
            exit(1);
        }
        check(fields);
        cases++;
    }
    fclose(file);
    if (cases == 0) {
        printf("Bail out! %s has no cases\n", path);
        exit(1);
    }
}

static void check_tag_base(char *fields[])
{
    char got[LINE_MAX_LEN];
    char description[LINE_MAX_LEN * 3];

    tag_base_version(fields[0], got, sizeof got);
    snprintf(description, sizeof description, "tag_base_version(\"%s\") = \"%s\", want \"%s\"",
             fields[0], got, fields[1]);
    report(strcmp(got, fields[1]) == 0, description);
}

static void check_allows(char *fields[])
{
    bool allow_downgrade = strcmp(fields[2], "yes") == 0;
    bool want = strcmp(fields[3], "allow") == 0;
    bool got = guard_allows(fields[0], fields[1], allow_downgrade);
    char description[LINE_MAX_LEN * 2];

    snprintf(description, sizeof description, "%s -> %s allow_downgrade=%s: %s",
             fields[0], fields[1], fields[2], got ? "allow" : "block");
    report(got == want, description);
}

int main(void)
{
    run_file("tag-base-cases.tsv", 2, check_tag_base);
    run_file("downgrade-cases.tsv", 4, check_allows);
    printf("1..%d\n", test_number);
    return failures == 0 ? 0 : 1;
}
