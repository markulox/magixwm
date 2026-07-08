# Popup, Build, Test และ Notes

## Popup

Popup อยู่ใน `src/scene/popup.zig`

เมื่อมี `new_xdg_popup`, server:

1. หา parent XDG surface จาก `xdg_popup.parent`
2. อ่าน `parent.data` เป็น scene tree
3. สร้าง popup XDG surface tree ใต้ parent tree
4. allocate `Popup`
5. register commit/destroy listeners

ตอน initial commit:

```zig
_ = popup.xdg_popup.base.scheduleConfigure();
```

ตอน destroy:

- remove listeners
- free object

ข้อจำกัด: code ปัจจุบัน assume ว่า parent เป็น XDG surface เท่านั้น

## Build System

`build.zig` สร้าง:

- Wayland protocol scanner output
- module `magixwm`
- executable `magixwm`
- test steps สำหรับ module และ executable root

protocols ที่ scanner เพิ่ม:

- `xdg-shell`
- `xdg-decoration-unstable-v1`
- `tablet-v2`
- `color-management-v1`

libraries ที่ link:

- `wayland-server`
- `xkbcommon`
- `pixman-1`
- `wlroots-0.20`

## การ Run

ทั่วไป:

```sh
zig build run
```

ถ้าจะ spawn client:

```sh
zig build run -- foot
```

`main.zig` จะ set `WAYLAND_DISPLAY` ให้ child process

## Test

ใช้:

```sh
zig build test -Dcpu=baseline -Doptimize=Debug -Dllvm=true --summary all
```

test ที่มีตอนนี้ครอบคลุม:

- keybind mapping
- title bar geometry hit test
- title bar height visibility
- title bar animation interpolation

## ลำดับของ Linked List

`server.toplevels` ใช้เป็นทั้ง mapped windows list และ stacking/focus order

เมื่อ focus:

```zig
toplevel.link.remove();
server.toplevels.prepend(toplevel);
```

ดังนั้น front ของ list คือ window ที่ focus/raise ล่าสุด

`Alt+s` เลือก window จากท้าย list:

```zig
server.toplevels.link.prev
```

แล้ว activate window นั้น

## Data Pointers

มีการใช้ `node.data` และ `xdg_surface.data` สำคัญมาก:

```zig
toplevel.scene_tree.node.data = toplevel;
toplevel.client_tree.node.data = toplevel;
xdg_surface.data = toplevel.client_tree;
```

ผล:

- focus helper หา toplevel จาก surface ได้
- hit-test เดิน parent tree แล้วเจอ toplevel
- decoration lookup จาก xdg decoration ใช้ `base.data` เพื่อหา scene tree

ถ้าเปลี่ยน scene graph ต้องระวัง pointer เหล่านี้เสมอ

## Tradeoff ของ Design ที่ควรรู้

### Focus animation พึ่ง `isShown`

`Decoration.isShown` ถูกใช้ทั้งเป็น logical state และใช้แยก show/hide animation ใน `Toplevel.updateAnimations()`

สำหรับโปรเจกต์เล็กใช้ได้ แต่ถ้า animation ซับซ้อนขึ้นควรมี explicit direction:

```zig
enum { none, showing, hiding }
```

### Request move/resize ยังไม่ validate serial

Production compositor ควร validate ว่า request move/resize มาจาก grab/serial ที่ถูกต้อง ไม่ใช่รับทุก request ทันที

### Pointer focus กับ keyboard focus แยกกัน

pointer focus เกิดจาก hover/motion ผ่าน `pointerNotifyEnter`

keyboard focus เกิดจาก click/titlebar/keybind ผ่าน `focus.activateToplevel`

### Wayland configure เป็น async

ห้าม assume ว่า `xdg_toplevel.setSize()` แล้ว geometry เปลี่ยนทันที

project นี้จึงรอ commit ใน hide flow:

```zig
geometry.height >= pending_hide_height
```

### KWin Nested Backend

ถ้ารัน compositor nested ใน KWin บาง output mode/custom mode อาจทำให้ nested window หายหรือ commit fail ได้ ขึ้นกับ backend และ host compositor

## Tips สำหรับ Debug

- ถ้า window ไม่ขยับ: เช็คว่าแก้ outer `scene_tree` หรือ `client_tree`
- ถ้า content โผล่เกิน bottom edge: เช็ค `setClientClip`
- ถ้า title bar hit test ผิด: เช็ค `toplevel.x/y`, `Decoration.title_bar_y`, และ geometry width
- ถ้า focus animation ไม่เล่น: เช็ค `server.scheduleFrame()` และ `Output.handleFrame`
- ถ้า keyboard ไม่เข้า client: เช็ค `seat.keyboardNotifyEnter`
- ถ้า pointer event ไม่เข้า client: เช็ค `viewAt` และ `pointerNotifyEnter`
