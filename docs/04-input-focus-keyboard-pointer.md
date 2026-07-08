# Input, Focus, Keyboard และ Pointer

ไฟล์หลัก:

- `src/server.zig`
- `src/input/cursor.zig`
- `src/input/keyboard.zig`
- `src/input/keybind.zig`
- `src/input/focus.zig`

## Lifecycle ของ Input Device

เมื่อ backend เจอ input device ใหม่:

```text
backend.events.new_input -> Server.newInput
```

`Server.newInput()` switch ตามชนิด device:

```zig
switch (device.type) {
    .keyboard => Keyboard.create(server, device)
    .pointer => server.cursor.attachInputDevice(device)
    else => {}
}
```

หลังจากนั้น update seat capabilities:

```zig
server.seat.setCapabilities(.{
    .pointer = true,
    .keyboard = server.keyboards.length() > 0,
});
```

## Keyboard

`Keyboard.create()` ทำ:

1. allocate `Keyboard`
2. สร้าง xkb context
3. สร้าง keymap จาก default names
4. set keymap ให้ `wlr_keyboard`
5. set repeat info
6. register listeners:

```text
wlr_keyboard.modifiers -> Keyboard.handleModifiers
wlr_keyboard.key -> Keyboard.handleKey
device.destroy -> Keyboard.handleDestroy
```

7. set keyboard ให้ seat
8. append เข้า `server.keyboards`

## Keyboard Modifiers

เมื่อ modifiers เปลี่ยน:

```zig
Keyboard.handleModifiers
```

ทำ:

```zig
seat.setKeyboard(wlr_keyboard);
seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
```

นี่ส่ง modifier state เช่น Alt/Shift/Ctrl ให้ focused client

## Keyboard Key

เมื่อกด/ปล่อย key:

```zig
Keyboard.handleKey
```

ขั้นตอน:

1. เอา `wlr_keyboard`
2. แปลง libinput keycode เป็น xkb keycode:

```zig
const keycode = event.keycode + 8;
```

3. ถ้า Alt ถูกกดและ event เป็น pressed จะลอง compositor keybind:

```zig
if (wlr_keyboard.getModifiers().alt and event.state == .pressed) {
    for (wlr_keyboard.xkb_state.?.keyGetSyms(keycode)) |sym| {
        if (keybind.handle(server, sym)) {
            handled = true;
            break;
        }
    }
}
```

4. ถ้า compositor ไม่ handle จะ forward ให้ client:

```zig
seat.setKeyboard(wlr_keyboard);
seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
```

## Keybind

`src/input/keybind.zig`

ตอนนี้มี:

```text
Alt+Escape -> quit compositor
Alt+s -> focus_next
```

`actionForKey()` map keysym เป็น action

`handle()` execute action:

- `quit`: `server.wl_server.terminate()`
- `focus_next`: เอา toplevel ตัวถัดไปใน stack แล้ว `focus.activateToplevel(...)`

## Pointer และ Cursor

`Cursor.init()` สร้าง:

- `wlr.Cursor`
- `wlr.XcursorManager`

และ attach output layout:

```zig
wlr_cursor.attachOutputLayout(output_layout);
```

`Cursor.attach()` register:

```text
seat.request_set_cursor -> Cursor.handleRequestSetCursor
cursor.motion -> Cursor.handleMotion
cursor.motion_absolute -> Cursor.handleMotionAbsolute
cursor.button -> Cursor.handleButton
cursor.axis -> Cursor.handleAxis
cursor.frame -> Cursor.handleFrame
```

## Pointer Motion

motion relative:

```zig
wlr_cursor.move(event.device, event.delta_x, event.delta_y);
processMotion(event.time_msec);
```

motion absolute:

```zig
wlr_cursor.warpAbsolute(event.device, event.x, event.y);
processMotion(event.time_msec);
```

## Pointer Mode แบบ Passthrough

ใน mode `.passthrough`:

1. hit-test scene graph:

```zig
server.viewAt(cursor.x, cursor.y)
```

2. ถ้าเจอ client surface:

```zig
seat.pointerNotifyEnter(res.surface, res.sx, res.sy);
seat.pointerNotifyMotion(time_msec, res.sx, res.sy);
```

3. ถ้าไม่เจอ:

```zig
cursor.setXcursor(default);
seat.pointerClearFocus();
```

pointer focus ตอนนี้เกิดจาก hover/motion แต่ keyboard focus เกิดตอน click/focus action

## Request Set Cursor

client ขอเปลี่ยน cursor surface ผ่าน seat event:

```zig
Cursor.handleRequestSetCursor
```

compositor ยอมให้เปลี่ยน cursor เฉพาะ client ที่มี pointer focus:

```zig
if (event.seat_client == seat.pointer_state.focused_client)
    cursor.setSurface(...)
```

## Logic ของ Focus

`focus.activateToplevel(server, toplevel, surface)` ทำ:

1. ดู keyboard focused surface เดิม
2. ถ้าเดิมเป็น surface เดียวกัน return
3. ถ้าเดิมเป็น toplevel อื่น เรียก `previous_toplevel.notifyUnfocus()`
4. raise scene node:

```zig
toplevel.scene_tree.node.raiseToTop();
```

5. ย้าย linked-list order:

```zig
toplevel.link.remove();
server.toplevels.prepend(toplevel);
```

6. เรียก:

```zig
toplevel.notifyFocus();
```

`notifyFocus()` และ `notifyUnfocus()` เป็นจุดที่เริ่ม show/hide animation ของ title bar และ client clipping

7. ส่ง keyboard enter ให้ client:

```zig
seat.keyboardNotifyEnter(surface, keycodes, modifiers);
```

## Clipboard Selection

`requestSetSelection` รับ request จาก client ที่ต้องการตั้ง clipboard/data selection:

```zig
server.seat.setSelection(event.source, event.serial);
```

นี่คือ path พื้นฐานของ copy/paste ผ่าน Wayland data device
