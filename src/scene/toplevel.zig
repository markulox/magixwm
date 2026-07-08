const Server = @import("../server.zig").Server;
const std = @import("std");
const posix = std.posix;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Decoration = @import("decoration.zig").Decoration;
const focus = @import("../input/focus.zig");
const timestamp = @import("../utils/time.zig").timestamp;

const gpa = std.heap.c_allocator;

const dbgprint = std.debug.print;

pub const Toplevel = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    xdg_toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,
    client_tree: *wlr.SceneTree,
    decoration: Decoration = .{},

    x: i32 = 2,
    y: i32 = 40,

    size_width: i32 = 0,
    size_height: i32 = 0,
    pending_hide_animation: bool = false,
    pending_show_clip: bool = false,
    pending_hide_height: i32 = 0,
    show_animation_start_y: i32 = 0,
    hide_animation_start_y: i32 = 0,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(void) = .init(handleDestroy),
    request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(handleRequestMove),
    request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(handleRequestResize),

    pub fn notifyFocus(self: *Toplevel) void {
        const was_animating = self.decoration.isAnimating();
        const was_hidden = !self.decoration.isShown;
        var configure_now = true;
        self.pending_hide_animation = false;
        self.pending_show_clip = false;
        self.setClientOffset(0);
        self.clearClientClip();

        _ = self.xdg_toplevel.setActivated(true);
        self.decoration.show();
        if (was_animating) {
            self.setPosition(self.x, self.hide_animation_start_y);
        } else if (was_hidden) {
            self.show_animation_start_y = self.y;
            self.decoration.startShowAnimation(nowMsec());
            self.setPosition(self.x, self.y + Decoration.title_bar_height);
            self.server.scheduleFrame();
            configure_now = false;
        } else {
            self.setScenePosition(self.x, self.y);
        }

        const title = self.xdg_toplevel.title orelse "??";
        if (configure_now) {
            self.configureSize(self.size_width, self.size_height);
        }
        dbgprint("Window {s} focused\n", .{title});
    }

    pub fn notifyUnfocus(self: *Toplevel) void {
        const was_shown = self.decoration.isShown;

        _ = self.xdg_toplevel.setActivated(false);
        const title = self.xdg_toplevel.title orelse "??";
        dbgprint("Window {s} unfocused\n", .{title});

        if (was_shown) {
            self.pending_hide_animation = true;
            self.pending_hide_height = self.size_height + Decoration.title_bar_height;
            self.hide_animation_start_y = self.y;
            self.configureSize(self.size_width, self.pending_hide_height);
        }
    }

    pub fn updateAnimations(self: *Toplevel, now_msec: u64) bool {
        if (!self.decoration.updateTitleBarAnimation(now_msec)) return false;

        const height = self.decoration.currentTitleBarHeight();
        if (self.decoration.isShown) {
            self.setScenePosition(self.x, self.show_animation_start_y + height);
            self.setClientClip((self.size_height + Decoration.title_bar_height) - height);
        } else {
            self.setClientOffset(height);
            self.setClientClip(self.pending_hide_height - height);
        }

        if (!self.decoration.isAnimating()) {
            if (self.decoration.isShown) {
                self.setPosition(self.x, self.show_animation_start_y + Decoration.title_bar_height);
                self.setClientClip(self.size_height);
                self.pending_show_clip = true;
                self.configureSize(self.size_width, self.size_height);
            } else {
                self.setClientOffset(0);
                self.clearClientClip();
            }
        }

        return true;
    }

    pub fn titleBarContains(toplevel: *Toplevel, lx: f64, ly: f64) bool {
        return titleBarContainsBounds(
            toplevel.decoration.isShown,
            toplevel.xdg_toplevel.base.geometry.width,
            toplevel.x,
            toplevel.y,
            lx,
            ly,
        );
    }

    pub fn titleBarContainsBounds(is_shown: bool, width: i32, x: i32, y: i32, lx: f64, ly: f64) bool {
        if (!is_shown or width <= 0) return false;

        const left = @as(f64, @floatFromInt(x));
        const top = @as(f64, @floatFromInt(y + Decoration.title_bar_y));
        const right = left + @as(f64, @floatFromInt(width));
        const bottom = top + @as(f64, @floatFromInt(Decoration.title_bar_height));

        return lx >= left and lx < right and ly >= top and ly < bottom;
    }

    pub fn setSize(self: *Toplevel, width: i32, height: i32) void {
        self.size_height = height;
        self.size_width = width;
        self.configureSize(width, height);
    }

    pub fn configureSize(self: *Toplevel, width: i32, height: i32) void {
        _ = self.xdg_toplevel.setSize(width, height);
    }

    pub fn setPosition(self: *Toplevel, x: i32, y: i32) void {
        self.x = x;
        self.y = y;
        self.setScenePosition(x, y);
    }

    fn setScenePosition(self: *Toplevel, x: i32, y: i32) void {
        const x_c_int = @as(c_int, @intCast(x));
        const y_c_int = @as(c_int, @intCast(y));
        _ = self.scene_tree.node.setPosition(x_c_int, y_c_int);
    }

    fn setClientOffset(self: *Toplevel, y: c_int) void {
        self.client_tree.node.setPosition(0, y);
    }

    fn setClientClip(self: *Toplevel, height: c_int) void {
        if (height <= 0) {
            self.clearClientClip();
            return;
        }

        const geometry = self.xdg_toplevel.base.geometry;
        var clip = wlr.Box{
            .x = 0,
            .y = 0,
            .width = if (self.size_width > 0) self.size_width else geometry.width,
            .height = height,
        };
        self.client_tree.node.subsurfaceTreeSetClip(&clip);
    }

    fn clearClientClip(self: *Toplevel) void {
        self.client_tree.node.subsurfaceTreeSetClip(null);
    }

    fn nowMsec() u64 {
        const now = timestamp();
        return (@as(u64, @intCast(now.sec)) * std.time.ms_per_s) +
            @as(u64, @intCast(@divTrunc(now.nsec, std.time.ns_per_ms)));
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const toplevel: *Toplevel = @fieldParentPtr("commit", listener);

        if (toplevel.xdg_toplevel.base.initial_commit) {
            dbgprint("<I> Window spawned\n", .{});
            toplevel.x = 100;
            toplevel.y = 70;
            _ = toplevel.setSize(860, 640);
            toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);
        }
        toplevel.decoration.handleCommit(toplevel.xdg_toplevel);

        if (toplevel.pending_show_clip and
            toplevel.xdg_toplevel.base.geometry.height <= toplevel.size_height)
        {
            toplevel.pending_show_clip = false;
            toplevel.clearClientClip();
        }

        if (toplevel.pending_hide_animation and
            toplevel.xdg_toplevel.base.geometry.height >= toplevel.pending_hide_height)
        {
            toplevel.pending_hide_animation = false;
            toplevel.setPosition(toplevel.x, toplevel.hide_animation_start_y - Decoration.title_bar_height);
            toplevel.setClientOffset(Decoration.title_bar_height);
            toplevel.setClientClip(toplevel.pending_hide_height - Decoration.title_bar_height);
            toplevel.decoration.startHideAnimation(nowMsec(), 0);
            toplevel.server.scheduleFrame();
        }
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("map", listener);
        toplevel.server.toplevels.prepend(toplevel);
        focus.activateToplevel(toplevel.server, toplevel, toplevel.xdg_toplevel.base.surface);
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("unmap", listener);
        const title = toplevel.xdg_toplevel.title orelse "nothing";
        dbgprint("<I> unmap! {s}\n", .{title});
        toplevel.link.remove();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("destroy", listener);

        toplevel.commit.link.remove();
        toplevel.map.link.remove();
        toplevel.unmap.link.remove();
        toplevel.destroy.link.remove();
        toplevel.request_move.link.remove();
        toplevel.request_resize.link.remove();
        toplevel.decoration.deinit();
        toplevel.scene_tree.node.destroy();

        gpa.destroy(toplevel);
    }

    fn handleRequestMove(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
        _: *wlr.XdgToplevel.event.Move,
    ) void {
        dbgprint("request move", .{});
        const toplevel: *Toplevel = @fieldParentPtr("request_move", listener);
        toplevel.server.cursor.beginMove(toplevel);
    }

    fn handleRequestResize(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
        event: *wlr.XdgToplevel.event.Resize,
    ) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_resize", listener);
        toplevel.server.cursor.beginResize(toplevel, event.edges);
    }
};

test "titleBarContainsBounds matches visible title bar geometry" {
    try std.testing.expect(Toplevel.titleBarContainsBounds(true, 200, 100, 70, 100, 38));
    try std.testing.expect(Toplevel.titleBarContainsBounds(true, 200, 100, 70, 299.9, 69.9));
}

test "titleBarContainsBounds excludes hidden empty and out of bounds title bars" {
    try std.testing.expect(!Toplevel.titleBarContainsBounds(false, 200, 100, 70, 120, 50));
    try std.testing.expect(!Toplevel.titleBarContainsBounds(true, 0, 100, 70, 100, 38));
    try std.testing.expect(!Toplevel.titleBarContainsBounds(true, 200, 100, 70, 99.9, 50));
    try std.testing.expect(!Toplevel.titleBarContainsBounds(true, 200, 100, 70, 300, 50));
    try std.testing.expect(!Toplevel.titleBarContainsBounds(true, 200, 100, 70, 120, 37.9));
    try std.testing.expect(!Toplevel.titleBarContainsBounds(true, 200, 100, 70, 120, 70));
}
