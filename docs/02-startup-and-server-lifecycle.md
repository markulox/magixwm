# การเริ่มต้นระบบและ Lifecycle ของ Server

ไฟล์หลัก:

- `src/main.zig`
- `src/server.zig`
- `src/root.zig`

## main.zig

`main()` ทำงานแบบนี้:

```text
wlr.log.init
Server.init
wl_server.addSocketAuto
optional spawn child process
backend.start
wl_server.run
defer Server.deinit
```

## สร้าง Server

`Server.init()` สร้าง resource หลักตามลำดับ:

1. `wl.Server.create()`
2. `wl_server.getEventLoop()`
3. `wlr.Backend.autocreate(loop, null)`
4. `wlr.Renderer.autocreate(backend)`
5. `wlr.OutputLayout.create(wl_server)`
6. `wlr.Scene.create()`
7. `wlr.Allocator.autocreate(backend, renderer)`
8. `scene.attachOutputLayout(output_layout)`
9. `wlr.XdgShell.create(wl_server, 2)`
10. `wlr.XdgDecorationManagerV1.create(wl_server)`
11. `wlr.Seat.create(wl_server, "default")`
12. `Cursor.init(server, output_layout)`

หลังจากนั้น init protocol globals:

```zig
_ = try wlr.Compositor.create(server.wl_server, 6, server.renderer);
_ = try wlr.Subcompositor.create(server.wl_server);
_ = try wlr.DataDeviceManager.create(server.wl_server);
```

protocol globals คือสิ่งที่ client เห็นผ่าน Wayland registry เช่น `wl_compositor`, `wl_subcompositor`, data device

## การ Register Event

หลัง resource พร้อมแล้ว `Server.init()` register listener:

```text
backend.new_output -> Server.newOutput
xdg_shell.new_toplevel -> Server.newXdgToplevel
xdg_shell.new_popup -> Server.newXdgPopup
xdg_decoration_manager.new_toplevel_decoration -> Server.newXdgToplevelDecoration
backend.new_input -> Server.newInput
seat.request_set_selection -> Server.requestSetSelection
cursor events -> Cursor.attach()
```

linked lists ถูก init:

```text
server.outputs.init()
server.toplevels.init()
server.keyboards.init()
```

## Wayland Socket

ใน `main.zig`:

```zig
const socket = try server.wl_server.addSocketAuto(&buf);
```

wlroots จะเลือกชื่อ socket เช่น `wayland-1` แล้ว return string นั้น

ถ้า user run command ต่อท้าย:

```sh
zig build run -- foot
```

โปรแกรมจะ spawn `/bin/sh -c foot` และ set:

```text
WAYLAND_DISPLAY=<socket>
```

ทำให้ client ที่ spawn มา connect เข้า compositor นี้

## เริ่ม Backend

```zig
try server.backend.start();
```

เมื่อ backend start แล้ว wlroots จะเริ่ม emit event เช่น:

- new output
- new input device
- client connection
- frame events

## Event Loop

```zig
server.wl_server.run();
```

หลังบรรทัดนี้ program จะรอ event จาก Wayland/wlroots จนกว่าจะ terminate

`Alt+Escape` ผ่าน keybind จะเรียก:

```zig
server.wl_server.terminate();
```

ทำให้ event loop จบ แล้ว `defer server.deinit()` ทำงาน

## Deinit

`Server.deinit()`:

1. `destroyClients()`
2. remove listeners หลัก
3. `cursor.deinit()`
4. `backend.destroy()`
5. `wl_server.destroy()`

ข้อควรระวัง: object หลายตัวผูก lifetime กับ wlroots event destroy ของ resource นั้น ๆ เช่น `Output`, `Keyboard`, `Toplevel`, `Popup`
