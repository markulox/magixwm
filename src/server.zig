const std = @import("std");
const posix = std.posix;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Toplevel = @import("./scene/toplevel.zig").Toplevel;
const Keyboard = @import("./input/keyboard.zig").Keyboard;
const Cursor = @import("./input/cursor.zig").Cursor;
const Popup = @import("./scene/popup.zig").Popup;
const Output = @import("./scene/output.zig").Output;

pub const Server = struct {
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    renderer: *wlr.Renderer,
    allocator: *wlr.Allocator,
    scene: *wlr.Scene,

    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    new_output: wl.Listener(*wlr.Output) = .init(newOutput),

    xdg_shell: *wlr.XdgShell,
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(newXdgToplevel),
    new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(newXdgPopup),
    xdg_decoration_manager: *wlr.XdgDecorationManagerV1,
    new_xdg_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(newXdgToplevelDecoration),
    toplevels: wl.list.Head(Toplevel, .link) = undefined,

    seat: *wlr.Seat,
    new_input: wl.Listener(*wlr.InputDevice) = .init(newInput),
    request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(requestSetSelection),
    keyboards: wl.list.Head(Keyboard, .link) = undefined,

    cursor: Cursor,

    pub fn init(server: *Server) !void {
        const wl_server = try wl.Server.create();
        const loop = wl_server.getEventLoop();
        const backend = try wlr.Backend.autocreate(loop, null);
        const renderer = try wlr.Renderer.autocreate(backend);
        const output_layout = try wlr.OutputLayout.create(wl_server);
        const scene = try wlr.Scene.create();
        server.* = .{
            .wl_server = wl_server,
            .backend = backend,
            .renderer = renderer,
            .allocator = try wlr.Allocator.autocreate(backend, renderer),
            .scene = scene,
            .output_layout = output_layout,
            .scene_output_layout = try scene.attachOutputLayout(output_layout),
            .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
            .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server),
            .seat = try wlr.Seat.create(wl_server, "default"),
            .cursor = try Cursor.init(server, output_layout),
        };

        try server.renderer.initServer(wl_server);

        _ = try wlr.Compositor.create(server.wl_server, 6, server.renderer);
        _ = try wlr.Subcompositor.create(server.wl_server);
        _ = try wlr.DataDeviceManager.create(server.wl_server);

        server.backend.events.new_output.add(&server.new_output);

        server.xdg_shell.events.new_toplevel.add(&server.new_xdg_toplevel);
        server.xdg_shell.events.new_popup.add(&server.new_xdg_popup);
        server.xdg_decoration_manager.events.new_toplevel_decoration.add(&server.new_xdg_toplevel_decoration);
        server.toplevels.init();

        server.backend.events.new_input.add(&server.new_input);
        server.seat.events.request_set_selection.add(&server.request_set_selection);
        server.keyboards.init();

        server.cursor.attach();
    }

    pub fn deinit(server: *Server) void {
        server.wl_server.destroyClients();

        server.new_input.link.remove();
        server.new_output.link.remove();

        server.new_xdg_toplevel.link.remove();
        server.new_xdg_popup.link.remove();
        server.new_xdg_toplevel_decoration.link.remove();
        server.request_set_selection.link.remove();
        server.cursor.deinit();

        server.backend.destroy();
        server.wl_server.destroy();
    }

    fn newOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const server: *Server = @fieldParentPtr("new_output", listener);

        if (!wlr_output.initRender(server.allocator, server.renderer)) return;

        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(true);
        if (wlr_output.preferredMode()) |mode| {
            state.setMode(mode);
        }
        if (!wlr_output.commitState(&state)) return;

        Output.create(server, wlr_output) catch {
            std.log.err("failed to allocate new output", .{});
            wlr_output.destroy();
            return;
        };
    }

    fn newXdgToplevel(listener: *wl.Listener(*wlr.XdgToplevel), xdg_toplevel: *wlr.XdgToplevel) void {
        const server: *Server = @fieldParentPtr("new_xdg_toplevel", listener);
        const xdg_surface = xdg_toplevel.base;

        // Don't add the toplevel to server.toplevels until it is mapped
        const toplevel = gpa.create(Toplevel) catch {
            std.log.err("failed to allocate new toplevel", .{});
            return;
        };

        toplevel.* = .{
            .server = server,
            .xdg_toplevel = xdg_toplevel,
            .scene_tree = server.scene.tree.createSceneXdgSurface(xdg_surface) catch {
                gpa.destroy(toplevel);
                std.log.err("failed to allocate new toplevel", .{});
                return;
            },
        };
        toplevel.scene_tree.node.data = toplevel;
        xdg_surface.data = toplevel.scene_tree;

        toplevel.decoration.createTitleBar(toplevel.scene_tree);

        xdg_surface.surface.events.commit.add(&toplevel.commit);
        xdg_surface.surface.events.map.add(&toplevel.map);
        xdg_surface.surface.events.unmap.add(&toplevel.unmap);
        xdg_toplevel.events.destroy.add(&toplevel.destroy);
        xdg_toplevel.events.request_move.add(&toplevel.request_move);
        xdg_toplevel.events.request_resize.add(&toplevel.request_resize);
    }

    fn newXdgToplevelDecoration(
        _: *wl.Listener(*wlr.XdgToplevelDecorationV1),
        decoration: *wlr.XdgToplevelDecorationV1,
    ) void {
        const scene_tree = @as(?*wlr.SceneTree, @ptrCast(@alignCast(decoration.toplevel.base.data))) orelse return;
        const toplevel = @as(?*Toplevel, @ptrCast(@alignCast(scene_tree.node.data))) orelse return;

        toplevel.decoration.setXdgDecoration(decoration);
    }

    fn newXdgPopup(_: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
        const xdg_surface = xdg_popup.base;

        // These asserts are fine since tinywl.zig doesn't support anything else that can
        // make xdg popups (e.g. layer shell).
        const parent = wlr.XdgSurface.tryFromWlrSurface(xdg_popup.parent.?) orelse return;
        const parent_tree = @as(?*wlr.SceneTree, @ptrCast(@alignCast(parent.data))) orelse {
            // The xdg surface user data could be left null due to allocation failure.
            return;
        };
        const scene_tree = parent_tree.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate xdg popup node", .{});
            return;
        };
        xdg_surface.data = scene_tree;

        const popup = gpa.create(Popup) catch {
            std.log.err("failed to allocate new popup", .{});
            return;
        };
        popup.* = .{
            .xdg_popup = xdg_popup,
        };

        xdg_surface.surface.events.commit.add(&popup.commit);
        xdg_popup.events.destroy.add(&popup.destroy);
    }

    pub const ViewAtResult = struct {
        toplevel: *Toplevel,
        surface: *wlr.Surface,
        sx: f64,
        sy: f64,
    };

    pub fn viewAt(server: *Server, lx: f64, ly: f64) ?ViewAtResult {
        var sx: f64 = undefined;
        var sy: f64 = undefined;
        if (server.scene.tree.node.at(lx, ly, &sx, &sy)) |node| {
            if (node.type != .buffer) return null;
            const scene_buffer = wlr.SceneBuffer.fromNode(node);
            const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return null;

            var it: ?*wlr.SceneTree = node.parent;
            while (it) |n| : (it = n.node.parent) {
                if (@as(?*Toplevel, @ptrCast(@alignCast(n.node.data)))) |toplevel| {
                    return ViewAtResult{
                        .toplevel = toplevel,
                        .surface = scene_surface.surface,
                        .sx = sx,
                        .sy = sy,
                    };
                }
            }
        }
        return null;
    }

    fn newInput(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
        const server: *Server = @fieldParentPtr("new_input", listener);
        switch (device.type) {
            .keyboard => Keyboard.create(server, device) catch |err| {
                std.log.err("failed to create keyboard: {}", .{err});
                return;
            },
            .pointer => server.cursor.attachInputDevice(device),
            else => {},
        }

        server.seat.setCapabilities(.{
            .pointer = true,
            .keyboard = server.keyboards.length() > 0,
        });
    }

    fn requestSetSelection(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
        event: *wlr.Seat.event.RequestSetSelection,
    ) void {
        const server: *Server = @fieldParentPtr("request_set_selection", listener);
        server.seat.setSelection(event.source, event.serial);
    }
};
