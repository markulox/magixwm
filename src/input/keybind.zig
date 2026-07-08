const std = @import("std");
const xkb = @import("xkbcommon");

const Server = @import("../server.zig").Server;
const Toplevel = @import("../scene/toplevel.zig").Toplevel;
const focus = @import("focus.zig");

const dbgprint = std.debug.print;

pub const Action = enum {
    quit,
    focus_next,
};

pub fn actionForKey(key: xkb.Keysym) ?Action {
    return switch (@intFromEnum(key)) {
        xkb.Keysym.Escape => .quit,
        xkb.Keysym.s => .focus_next,
        else => null,
    };
}

/// !!!Assumes the modifier used for compositor keybinds is pressed.
/// Returns true if the key was handled.
pub fn handle(server: *Server, key: xkb.Keysym) bool {
    switch (actionForKey(key) orelse return false) {
        // Exit the compositor
        .quit => {
            server.wl_server.terminate();
            dbgprint("Escape!!\n", .{});
        },
        // Focus the next toplevel in the stack, pushing the current top to the back
        .focus_next => {
            if (server.toplevels.length() < 2) return true;
            const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.prev.?);
            focus.activateToplevel(server, toplevel, toplevel.xdg_toplevel.base.surface);
            dbgprint("Switch!!\n", .{});
        },
    }

    return true;
}

test "actionForKey maps compositor keybinds" {
    try std.testing.expectEqual(Action.quit, actionForKey(@enumFromInt(xkb.Keysym.Escape)).?);
    try std.testing.expectEqual(Action.focus_next, actionForKey(@enumFromInt(xkb.Keysym.s)).?);
}

test "actionForKey returns null for unbound keys" {
    try std.testing.expect(actionForKey(@enumFromInt(xkb.Keysym.Return)) == null);
}
