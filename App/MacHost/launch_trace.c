/*
 Runs before Swift / libc static init for this executable (dyld loads this TU early).
 If you still see no stderr and no marker files, this binary is not what was launched.
 Writes: /tmp/grizzyclaw_mac_xcode_launched.txt and $HOME/grizzyclaw_mac_xcode_launched.txt
 */
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void write_marker(const char *path) {
    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd >= 0) {
        const char ok[] = "ok\n";
        (void)write(fd, ok, sizeof(ok) - 1);
        (void)close(fd);
    }
}

__attribute__((constructor))
static void grizzy_launch_trace_xcode_app(void) {
    const char msg[] = "GrizzyClawMac: launch_trace.c constructor (before Swift)\n";
    (void)write(STDERR_FILENO, msg, sizeof(msg) - 1);

    write_marker("/tmp/grizzyclaw_mac_xcode_launched.txt");

    const char *home = getenv("HOME");
    if (home && home[0]) {
        char path[PATH_MAX];
        int n = snprintf(path, sizeof(path), "%s/grizzyclaw_mac_xcode_launched.txt", home);
        if (n > 0 && (size_t)n < sizeof(path)) {
            write_marker(path);
        }
    }
}
