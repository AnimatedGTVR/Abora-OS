#include <stdio.h>
#include <string.h>

#include "guard.h"

static const char usage[] = "usage: downgrade-guard [--allow-downgrade] <current-version> <selected-ref>";

int main(int argc, char **argv)
{
    bool allow_downgrade = false;
    int first = 1;

    if (argc > 1 && strcmp(argv[1], "--allow-downgrade") == 0) {
        allow_downgrade = true;
        first = 2;
    }
    if (argc - first != 2) {
        fprintf(stderr, "%s\n", usage);
        return 2;
    }
    if (guard_allows(argv[first], argv[first + 1], allow_downgrade)) {
        puts("allow");
        return 0;
    }
    puts("block");
    return 1;
}
