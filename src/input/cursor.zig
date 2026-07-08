const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../server.zig").Server;
const Toplevel = @import("../scene/toplevel.zig").Toplevel;
const focus = @import("focus.zig");

pub const Cursor = struct {
    server: *Server,
    wlr_cursor: *wlr.Cursor,
    cursor_mgr: *wlr.XcursorManager,

    motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(handleMotion),
    motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(handleMotionAbsolute),
    button: wl.Listener(*wlr.Pointer.event.Button) = .init(handleButton),
    axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(handleAxis),
    frame: wl.Listener(*wlr.Cursor) = .init(handleFrame),
    request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(handleRequestSetCursor),

    mode: enum { passthrough, move, resize } = .passthrough,
    grabbed_view: ?*Toplevel = null,
    grab_x: f64 = 0,
    grab_y: f64 = 0,
    grab_box: wlr.Box = undefined,
    resize_edges: wlr.Edges = .{},
    title_bar_grab: bool = false,

    pub fn init(server: *Server, output_layout: *wlr.OutputLayout) !Cursor {
        const wlr_cursor = try wlr.Cursor.create();
        errdefer wlr_cursor.destroy();

        const cursor_mgr = try wlr.XcursorManager.create(null, 24);
        errdefer cursor_mgr.destroy();

        wlr_cursor.attachOutputLayout(output_layout);
        try cursor_mgr.load(1);

        return .{
            .server = server,
            .wlr_cursor = wlr_cursor,
            .cursor_mgr = cursor_mgr,
        };
    }

    pub fn attach(cursor: *Cursor) void {
        cursor.server.seat.events.request_set_cursor.add(&cursor.request_set_cursor);
        cursor.wlr_cursor.events.motion.add(&cursor.motion);
        cursor.wlr_cursor.events.motion_absolute.add(&cursor.motion_absolute);
        cursor.wlr_cursor.events.button.add(&cursor.button);
        cursor.wlr_cursor.events.axis.add(&cursor.axis);
        cursor.wlr_cursor.events.frame.add(&cursor.frame);
    }

    pub fn deinit(cursor: *Cursor) void {
        cursor.request_set_cursor.link.remove();
        cursor.motion.link.remove();
        cursor.motion_absolute.link.remove();
        cursor.button.link.remove();
        cursor.axis.link.remove();
        cursor.frame.link.remove();

        cursor.wlr_cursor.destroy();
        cursor.cursor_mgr.destroy();
    }

    pub fn attachInputDevice(cursor: *Cursor, device: *wlr.InputDevice) void {
        cursor.wlr_cursor.attachInputDevice(device);
    }

    pub fn beginMove(cursor: *Cursor, toplevel: *Toplevel) void {
        cursor.grabbed_view = toplevel;
        cursor.mode = .move;
        cursor.title_bar_grab = false;
        cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(toplevel.x));
        cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(toplevel.y));
    }

    pub fn beginTitleBarMove(cursor: *Cursor, toplevel: *Toplevel) void {
        cursor.beginMove(toplevel);
        cursor.title_bar_grab = true;
    }

    pub fn beginResize(cursor: *Cursor, toplevel: *Toplevel, edges: wlr.Edges) void {
        cursor.grabbed_view = toplevel;
        cursor.mode = .resize;
        cursor.title_bar_grab = false;
        cursor.resize_edges = edges;

        const box = toplevel.xdg_toplevel.base.geometry;

        const border_x = toplevel.x + box.x + if (edges.right) box.width else 0;
        const border_y = toplevel.y + box.y + if (edges.bottom) box.height else 0;
        cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(border_x));
        cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(border_y));

        cursor.grab_box = box;
        cursor.grab_box.x += toplevel.x;
        cursor.grab_box.y += toplevel.y;
    }

    fn handleRequestSetCursor(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
        event: *wlr.Seat.event.RequestSetCursor,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("request_set_cursor", listener);
        if (event.seat_client == cursor.server.seat.pointer_state.focused_client)
            cursor.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    }

    fn handleMotion(
        listener: *wl.Listener(*wlr.Pointer.event.Motion),
        event: *wlr.Pointer.event.Motion,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("motion", listener);
        cursor.wlr_cursor.move(event.device, event.delta_x, event.delta_y);
        cursor.processMotion(event.time_msec);
    }

    fn handleMotionAbsolute(
        listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
        event: *wlr.Pointer.event.MotionAbsolute,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("motion_absolute", listener);
        cursor.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
        cursor.processMotion(event.time_msec);
    }

    fn processMotion(cursor: *Cursor, time_msec: u32) void {
        const server = cursor.server;
        switch (cursor.mode) {
            .passthrough => if (server.viewAt(cursor.wlr_cursor.x, cursor.wlr_cursor.y)) |res| {
                server.seat.pointerNotifyEnter(res.surface, res.sx, res.sy);
                server.seat.pointerNotifyMotion(time_msec, res.sx, res.sy);
            } else {
                cursor.wlr_cursor.setXcursor(cursor.cursor_mgr, "default");
                server.seat.pointerClearFocus();
            },
            .move => {
                const toplevel = cursor.grabbed_view.?;
                toplevel.x = @as(i32, @intFromFloat(cursor.wlr_cursor.x - cursor.grab_x));
                toplevel.y = @as(i32, @intFromFloat(cursor.wlr_cursor.y - cursor.grab_y));
                toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);
            },
            .resize => {
                const toplevel = cursor.grabbed_view.?;
                const border_x = @as(i32, @intFromFloat(cursor.wlr_cursor.x - cursor.grab_x));
                const border_y = @as(i32, @intFromFloat(cursor.wlr_cursor.y - cursor.grab_y));

                var new_left = cursor.grab_box.x;
                var new_right = cursor.grab_box.x + cursor.grab_box.width;
                var new_top = cursor.grab_box.y;
                var new_bottom = cursor.grab_box.y + cursor.grab_box.height;

                if (cursor.resize_edges.top) {
                    new_top = border_y;
                    if (new_top >= new_bottom)
                        new_top = new_bottom - 1;
                } else if (cursor.resize_edges.bottom) {
                    new_bottom = border_y;
                    if (new_bottom <= new_top)
                        new_bottom = new_top + 1;
                }

                if (cursor.resize_edges.left) {
                    new_left = border_x;
                    if (new_left >= new_right)
                        new_left = new_right - 1;
                } else if (cursor.resize_edges.right) {
                    new_right = border_x;
                    if (new_right <= new_left)
                        new_right = new_left + 1;
                }

                toplevel.setPosition(
                    new_left - toplevel.xdg_toplevel.base.geometry.x,
                    new_top - toplevel.xdg_toplevel.base.geometry.y,
                );

                const new_width = new_right - new_left;
                const new_height = new_bottom - new_top;
                toplevel.setSize(new_width, new_height);
            },
        }
    }

    fn handleButton(
        listener: *wl.Listener(*wlr.Pointer.event.Button),
        event: *wlr.Pointer.event.Button,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("button", listener);
        const server = cursor.server;

        if (event.state == .pressed) {
            if (server.titleBarAt(cursor.wlr_cursor.x, cursor.wlr_cursor.y)) |toplevel| {
                focus.activateToplevel(server, toplevel, toplevel.xdg_toplevel.base.surface);
                cursor.beginTitleBarMove(toplevel);
                return;
            }
        }

        const title_bar_grab = cursor.title_bar_grab;
        if (event.state == .released) {
            std.debug.print("Mouse event: Release\n", .{});
            cursor.mode = .passthrough;
            cursor.grabbed_view = null;
            cursor.title_bar_grab = false;
            if (title_bar_grab) return;

            _ = server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
        } else if (event.state == .pressed) {
            _ = server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
            std.debug.print("Mouse event: Pressed\n", .{});
            if (server.viewAt(cursor.wlr_cursor.x, cursor.wlr_cursor.y)) |res| {
                focus.activateToplevel(server, res.toplevel, res.surface);
            }
        }
    }

    fn handleAxis(
        listener: *wl.Listener(*wlr.Pointer.event.Axis),
        event: *wlr.Pointer.event.Axis,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("axis", listener);
        cursor.server.seat.pointerNotifyAxis(
            event.time_msec,
            event.orientation,
            event.delta,
            event.delta_discrete,
            event.source,
            event.relative_direction,
        );
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
        const cursor: *Cursor = @fieldParentPtr("frame", listener);
        cursor.server.seat.pointerNotifyFrame();
    }
};
