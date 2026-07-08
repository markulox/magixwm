const std = @import("std");
const posix = std.posix;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const gpa = std.heap.c_allocator;

const Server = @import("../server.zig").Server;
const timestamp = @import("../utils/time.zig").timestamp;
pub const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,
    link: wl.list.Link = undefined,

    frame: wl.Listener(*wlr.Output) = .init(handleFrame),
    request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(handleRequestState),
    destroy: wl.Listener(*wlr.Output) = .init(handleDestroy),

    // The wlr.Output should be destroyed by the caller on failure to trigger cleanup.
    pub fn create(server: *Server, wlr_output: *wlr.Output) !void {
        const output = try gpa.create(Output);

        output.* = .{
            .server = server,
            .wlr_output = wlr_output,
        };
        wlr_output.events.frame.add(&output.frame);
        wlr_output.events.request_state.add(&output.request_state);
        wlr_output.events.destroy.add(&output.destroy);

        const layout_output = try server.output_layout.addAuto(wlr_output);

        const scene_output = try server.scene.createSceneOutput(wlr_output);
        server.scene_output_layout.addOutput(layout_output, scene_output);
        server.outputs.prepend(output);
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("frame", listener);

        const scene_output = output.server.scene.getSceneOutput(output.wlr_output).?;
        var now = timestamp();
        const now_msec = (@as(u64, @intCast(now.sec)) * std.time.ms_per_s) +
            @as(u64, @intCast(@divTrunc(now.nsec, std.time.ns_per_ms)));
        const animations_active = output.server.updateAnimations(now_msec);

        if (!scene_output.commit(null)) {
            std.log.err("failed to commit scene output {s}", .{output.wlr_output.name});
            return;
        }

        scene_output.sendFrameDone(&now);

        if (animations_active) {
            output.wlr_output.scheduleFrame();
        }
    }

    fn handleRequestState(
        listener: *wl.Listener(*wlr.Output.event.RequestState),
        event: *wlr.Output.event.RequestState,
    ) void {
        const output: *Output = @fieldParentPtr("request_state", listener);
        _ = output.wlr_output.commitState(event.state);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("destroy", listener);

        output.frame.link.remove();
        output.request_state.link.remove();
        output.destroy.link.remove();
        output.link.remove();

        gpa.destroy(output);
    }
};
