# ภาพรวม

โปรเจกต์นี้เป็น Wayland compositor ขนาดเล็กที่ใช้ `wlroots` ผ่าน Zig bindings โครงสร้างคล้าย tinywl แต่มี logic เพิ่มสำหรับ focus, title bar decoration, drag-to-move, resize และ animation ของ title bar

## จุดเริ่มต้น

จุดเริ่มต้นอยู่ที่ `src/main.zig`

ลำดับหลัก:

1. init wlroots log
2. สร้าง `Server`
3. สร้าง Wayland socket ด้วย `wl_server.addSocketAuto`
4. ถ้ามี command argument จะ spawn process โดยใส่ `WAYLAND_DISPLAY` ให้ client
5. start backend
6. เข้า Wayland event loop ด้วย `wl_server.run()`

ภาพรวม:

```text
main.zig
  Server.init()
  wl_server.addSocketAuto()
  optional spawn client
  backend.start()
  wl_server.run()
```

เมื่อ `wl_server.run()` ทำงานแล้ว control flow จะมาจาก event callbacks ของ wlroots/Wayland เป็นหลัก เช่น new output, new input, new xdg_toplevel, pointer motion, keyboard key, output frame

## Object หลัก

`Server` ใน `src/server.zig` เป็น root object ที่ถือ state ของ compositor:

- `wl_server`: Wayland server
- `backend`: backend ที่ wlroots เลือกให้อัตโนมัติ เช่น nested Wayland backend ตอนรันบน KWin
- `renderer`: renderer สำหรับ render buffer
- `allocator`: allocator สำหรับ buffer/resource ของ wlroots
- `scene`: wlroots scene graph root
- `output_layout`: layout ของ outputs
- `scene_output_layout`: mapping ระหว่าง scene กับ outputs
- `xdg_shell`: รับ xdg_toplevel/xdg_popup
- `xdg_decoration_manager`: รับ xdg_toplevel decoration protocol
- `seat`: keyboard/pointer seat
- `cursor`: wrapper ของ `wlr.Cursor`
- `toplevels`: linked list ของ mapped toplevels ใช้เป็น stacking/focus order
- `outputs`: linked list ของ active outputs ใช้ schedule frame ตอน animation
- `keyboards`: linked list ของ keyboard devices

## Scene Graph ปัจจุบัน

ตอนสร้าง toplevel ตอนนี้ใช้ scene graph แบบแยก outer window กับ client:

```text
server.scene.tree
  toplevel.scene_tree          // outer window tree, ใช้เป็น position/stacking ของ window
    decoration.title_bar       // compositor-owned SceneRect สำหรับพื้นหลัง title bar
    toplevel.client_tree       // XDG surface tree ของ client
      client buffers/subsurfaces
```

เหตุผลที่แยกแบบนี้:

- outer `scene_tree` ขยับ window ทั้งก้อน
- `client_tree` ขยับเฉพาะ client content ได้
- title bar เป็น compositor-owned node และ animate ได้โดยไม่ต้องให้ client วาด
- ระหว่าง animation สามารถ clip `client_tree` เพื่อให้ bottom edge ไม่ขยับ

## รูปแบบ Event

โปรเจกต์ใช้ `wl.Listener` ตาม pattern ของ wlroots

ตัวอย่าง:

```zig
new_output: wl.Listener(*wlr.Output) = .init(newOutput)
```

ตอน init จะ register listener:

```zig
server.backend.events.new_output.add(&server.new_output);
```

เมื่อ wlroots emit event, callback `newOutput` จะถูกเรียก และใช้:

```zig
const server: *Server = @fieldParentPtr("new_output", listener);
```

เพื่อหา owner object กลับมา

pattern นี้ใช้ทั่ว project:

- output frame -> `Output.handleFrame`
- xdg_toplevel commit/map/unmap/destroy -> `Toplevel.handleCommit` ฯลฯ
- keyboard key/modifiers/destroy -> `Keyboard.handleKey` ฯลฯ
- cursor motion/button/axis/frame -> `Cursor.handleMotion` ฯลฯ

## รูปแบบ Memory และ Lifetime

หลาย object allocate ด้วย `std.heap.c_allocator`:

- `Toplevel`
- `Output`
- `Popup`
- `Keyboard`

destroy path ต้อง:

1. remove listeners
2. remove linked-list link ถ้ามี
3. destroy wlroots resource ถ้า object owner เป็นคนสร้าง
4. `gpa.destroy(...)`

ตัวอย่าง `Toplevel.handleDestroy`:

- remove commit/map/unmap/destroy/request listeners
- `decoration.deinit()`
- destroy outer scene node
- free `Toplevel`

## กฎสำคัญของ Design

Wayland `xdg_toplevel.setSize()` ไม่ใช่ immediate resize แต่เป็น protocol configure ที่ client จะตอบกลับภายหลังผ่าน commit

ดังนั้น animation ที่ต้องลื่นควร animate scene nodes ของ compositor เอง ไม่ควร spam `setSize()` ทุก frame

project นี้จึงทำ:

- resize client size เฉพาะจุด stable state
- animate title bar และ `client_tree` ใน compositor scene graph
- ใช้ output frame callback เป็น clock สำหรับ animation
