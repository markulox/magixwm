const std = @import("std");
const Io = std.Io;

const wlr = @import("wlroots");
const magixwm = @import("magixwm");

const gpa = std.heap.c_allocator;
pub fn main(init: std.process.Init) anyerror!void {
    wlr.log.init(.info, null);

    var server: magixwm.Server = undefined;
    try server.init();
    defer server.deinit();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    const argv = init.minimal.args.vector;
    if (argv.len >= 2) {
        var env_map = try init.minimal.environ.createMap(gpa);
        defer env_map.deinit();
        try env_map.put("WAYLAND_DISPLAY", socket);

        const cmd = std.mem.span(argv[1]);
        _ = try std.process.spawn(init.io, .{
            .argv = &.{ "/bin/sh", "-c", cmd },
            .environ_map = &env_map,
        });
    }

    try server.backend.start();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});
    server.wl_server.run();
}
