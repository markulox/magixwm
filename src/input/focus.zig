const wlr = @import("wlroots");

const Server = @import("../server.zig").Server;
const Toplevel = @import("../scene/toplevel.zig").Toplevel;

fn toplevelFromSurface(surface: *wlr.Surface) ?*Toplevel {
    const xdg_surface = wlr.XdgSurface.tryFromWlrSurface(surface) orelse return null;
    const scene_tree = @as(?*wlr.SceneTree, @ptrCast(@alignCast(xdg_surface.data))) orelse return null;
    return @as(?*Toplevel, @ptrCast(@alignCast(scene_tree.node.data)));
}

pub fn activateToplevel(server: *Server, toplevel: *Toplevel, surface: *wlr.Surface) void {
    if (server.seat.keyboard_state.focused_surface) |previous_surface| {
        if (previous_surface == surface) return;

        if (toplevelFromSurface(previous_surface)) |previous_toplevel| {
            if (previous_toplevel != toplevel) {
                previous_toplevel.notifyUnfocus();
            }
        } else if (wlr.XdgSurface.tryFromWlrSurface(previous_surface)) |xdg_surface| {
            if (xdg_surface.role_data.toplevel) |xdg_toplevel| {
                _ = xdg_toplevel.setActivated(false);
            }
        }
    }

    toplevel.scene_tree.node.raiseToTop();
    toplevel.link.remove();
    server.toplevels.prepend(toplevel);

    toplevel.notifyFocus();

    const wlr_keyboard = server.seat.getKeyboard() orelse return;
    server.seat.keyboardNotifyEnter(
        surface,
        wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
        &wlr_keyboard.modifiers,
    );
}
