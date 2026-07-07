const xkb = @import("xkbcommon");

const Server = @import("../server.zig").Server;
const Toplevel = @import("../scene/toplevel.zig").Toplevel;

/// Assumes the modifier used for compositor keybinds is pressed.
/// Returns true if the key was handled.
pub fn handle(server: *Server, key: xkb.Keysym) bool {
    switch (@intFromEnum(key)) {
        // Exit the compositor
        xkb.Keysym.Escape => server.wl_server.terminate(),
        // Focus the next toplevel in the stack, pushing the current top to the back
        xkb.Keysym.F1 => {
            if (server.toplevels.length() < 2) return true;
            const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.prev.?);
            server.requestFocusView(toplevel, toplevel.xdg_toplevel.base.surface);
        },
        else => return false,
    }

    return true;
}
