const std = @import("std");
const posix = std.posix;
pub fn timestamp() posix.timespec {
    var timespec: posix.timespec = undefined;
    switch (posix.errno(posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &timespec))) {
        .SUCCESS => return timespec,
        else => @panic("CLOCK_MONOTONIC not supported"),
    }
}
