const Server = @import("../server.zig").Server;
const std = @import("std");
const posix = std.posix;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Decoration = @import("decoration.zig").Decoration;
const focus = @import("../input/focus.zig");

const gpa = std.heap.c_allocator;

const dbgprint = std.debug.print;

pub const Toplevel = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    xdg_toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,
    decoration: Decoration = .{},

    x: i32 = 2,
    y: i32 = 40,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(void) = .init(handleDestroy),
    request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(handleRequestMove),
    request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(handleRequestResize),

    pub fn notifyFocus(toplevel: *Toplevel) void {
        _ = toplevel.xdg_toplevel.setActivated(true);
    }

    pub fn notifyUnfocus(toplevel: *Toplevel) void {
        _ = toplevel.xdg_toplevel.setActivated(false);
        const title = toplevel.xdg_toplevel.title orelse "??";
        dbgprint("Window {s} unfocused", .{title});
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const toplevel: *Toplevel = @fieldParentPtr("commit", listener);

        if (toplevel.xdg_toplevel.base.initial_commit) {
            dbgprint("<I> Window spawned\n", .{});
            _ = toplevel.xdg_toplevel.setSize(0, 0);
        }
        toplevel.decoration.handleCommit(toplevel.xdg_toplevel);
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
