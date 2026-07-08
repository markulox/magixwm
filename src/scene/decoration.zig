const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

pub const Decoration = struct {
    const preferred_mode: wlr.XdgToplevelDecorationV1.Mode = .server_side;

    xdg_decoration: ?*wlr.XdgToplevelDecorationV1 = null,
    title_bar: ?*wlr.SceneRect = null,
    destroy: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(handleDestroy),

    pub fn createTitleBar(decoration: *Decoration, scene_tree: *wlr.SceneTree) void {
        const color = [4]f32{ 0.1, 0.1, 0.1, 1.0 };
        const title_bar = scene_tree.createSceneRect(10, 10, &color) catch |err| {
            std.debug.print("<!> Draw title bar error: {}", .{err});
            return;
        };

        title_bar.setSize(0, 0);
        decoration.title_bar = title_bar;
    }

    pub fn setXdgDecoration(
        decoration: *Decoration,
        xdg_decoration: *wlr.XdgToplevelDecorationV1,
    ) void {
        if (decoration.xdg_decoration != null) {
            decoration.destroy.link.remove();
        }
        decoration.xdg_decoration = xdg_decoration;
        xdg_decoration.events.destroy.add(&decoration.destroy);
        decoration.configureXdg(xdg_decoration.toplevel.base.initialized);
    }

    pub fn handleCommit(decoration: *Decoration, xdg_toplevel: *wlr.XdgToplevel) void {
        decoration.configureXdg(xdg_toplevel.base.initialized);
        decoration.layoutTitleBar(xdg_toplevel.base.geometry.width);
    }

    pub fn deinit(decoration: *Decoration) void {
        if (decoration.xdg_decoration != null) {
            decoration.destroy.link.remove();
            decoration.xdg_decoration = null;
        }
    }

    fn configureXdg(decoration: *Decoration, initialized: bool) void {
        if (!initialized) return;
        const xdg_decoration = decoration.xdg_decoration orelse return;

        _ = xdg_decoration.setMode(preferred_mode);
    }

    fn layoutTitleBar(decoration: *Decoration, width: i32) void {
        const title_bar = decoration.title_bar orelse return;

        if (width > 0) {
            title_bar.setSize(width, 10);
        }
        title_bar.node.setPosition(0, -10);
    }

    fn handleDestroy(
        listener: *wl.Listener(*wlr.XdgToplevelDecorationV1),
        _: *wlr.XdgToplevelDecorationV1,
    ) void {
        const decoration: *Decoration = @fieldParentPtr("destroy", listener);

        decoration.destroy.link.remove();
        decoration.xdg_decoration = null;
    }
};
