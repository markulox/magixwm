const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

pub const Decoration = struct {
    const preferred_mode: wlr.XdgToplevelDecorationV1.Mode = .server_side;
    pub const title_bar_height = 30;
    pub const title_bar_y = -title_bar_height;
    pub const title_bar_animation_duration_ms = 90;

    pub const TitleBarAnimation = struct {
        active: bool = false,
        started_msec: u64 = 0,
        duration_msec: u32 = title_bar_animation_duration_ms,
        from_height: c_int = title_bar_height,
        to_height: c_int = 0,
    };

    xdg_decoration: ?*wlr.XdgToplevelDecorationV1 = null,
    title_bar: ?*wlr.SceneRect = null,
    destroy: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(handleDestroy),
    isShown: bool = true,
    title_bar_animation: TitleBarAnimation = .{},

    pub fn titleBarHeight(is_shown: bool) c_int {
        return if (is_shown) title_bar_height else 0;
    }

    pub fn animatedTitleBarHeight(from: c_int, to: c_int, elapsed_msec: u64, duration_msec: u32) c_int {
        if (duration_msec == 0 or elapsed_msec >= duration_msec) return to;

        const from_i64 = @as(i64, from);
        const delta = @as(i64, to) - from_i64;
        const elapsed = @as(i64, @intCast(elapsed_msec));
        const duration = @as(i64, duration_msec);

        return @as(c_int, @intCast(from_i64 + @divTrunc(delta * elapsed, duration)));
    }

    pub fn createTitleBar(decoration: *Decoration, scene_tree: *wlr.SceneTree) void {
        const color = [4]f32{ 0.17, 0.17, 0.17, 1.0 };
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
        _ = xdg_decoration.setMode(Decoration.preferred_mode);
    }

    fn layoutTitleBar(decoration: *Decoration, width: i32) void {
        const title_bar = decoration.title_bar orelse return;

        const height = if (decoration.title_bar_animation.active)
            title_bar.height
        else
            titleBarHeight(decoration.isShown);

        if (width > 0) {
            title_bar.setSize(width, height);
        }
        positionTitleBar(title_bar, height);
    }

    pub fn isAnimating(decoration: *const Decoration) bool {
        return decoration.title_bar_animation.active;
    }

    pub fn currentTitleBarHeight(decoration: *const Decoration) c_int {
        const title_bar = decoration.title_bar orelse return titleBarHeight(decoration.isShown);
        return title_bar.height;
    }

    pub fn startShowAnimation(decoration: *Decoration, now_msec: u64) void {
        const title_bar = decoration.title_bar orelse return;

        decoration.isShown = true;
        decoration.title_bar_animation = .{
            .active = true,
            .started_msec = now_msec,
            .from_height = 0,
            .to_height = title_bar.height,
        };
    }

    pub fn startHideAnimation(decoration: *Decoration, now_msec: u64) void {
        const title_bar = decoration.title_bar orelse return;

        decoration.isShown = false;
        decoration.title_bar_animation = .{
            .active = true,
            .started_msec = now_msec,
            .from_height = title_bar.height,
            .to_height = 0,
        };
    }

    pub fn updateTitleBarAnimation(decoration: *Decoration, now_msec: u64) bool {
        var animation = &decoration.title_bar_animation;
        if (!animation.active) return false;

        const title_bar = decoration.title_bar orelse {
            animation.active = false;
            return false;
        };

        const elapsed = now_msec -| animation.started_msec;
        const height = animatedTitleBarHeight(
            animation.from_height,
            animation.to_height,
            elapsed,
            animation.duration_msec,
        );
        title_bar.setSize(title_bar.width, height);
        positionTitleBar(title_bar, height);

        if (elapsed >= animation.duration_msec) {
            animation.active = false;
            title_bar.setSize(title_bar.width, animation.to_height);
            positionTitleBar(title_bar, animation.to_height);
        }

        return true;
    }

    pub fn hide(self: *Decoration) void {
        const title_bar = self.title_bar orelse return;

        self.isShown = false;
        self.title_bar_animation.active = false;
        title_bar.setSize(title_bar.width, 0);
        positionTitleBar(title_bar, 0);
    }

    pub fn show(self: *Decoration) void {
        const title_bar = self.title_bar orelse return;

        self.isShown = true;
        self.title_bar_animation.active = false;
        title_bar.setSize(title_bar.width, title_bar_height);
        positionTitleBar(title_bar, title_bar_height);
    }

    fn positionTitleBar(title_bar: *wlr.SceneRect, height: c_int) void {
        title_bar.node.setPosition(0, -height);
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

test "titleBarHeight follows visibility" {
    try std.testing.expectEqual(@as(c_int, Decoration.title_bar_height), Decoration.titleBarHeight(true));
    try std.testing.expectEqual(@as(c_int, 0), Decoration.titleBarHeight(false));
}

test "animatedTitleBarHeight interpolates and clamps" {
    try std.testing.expectEqual(@as(c_int, 30), Decoration.animatedTitleBarHeight(30, 0, 0, 120));
    try std.testing.expectEqual(@as(c_int, 15), Decoration.animatedTitleBarHeight(30, 0, 60, 120));
    try std.testing.expectEqual(@as(c_int, 0), Decoration.animatedTitleBarHeight(30, 0, 120, 120));
    try std.testing.expectEqual(@as(c_int, 0), Decoration.animatedTitleBarHeight(30, 0, 200, 120));
}
