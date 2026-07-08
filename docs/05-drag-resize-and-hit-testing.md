# Drag, Resize And Hit Testing

ไฟล์หลัก:

- `src/server.zig`
- `src/input/cursor.zig`
- `src/scene/toplevel.zig`

## Hit Test Client Surface

`Server.viewAt(lx, ly)` ใช้ wlroots scene graph:

```zig
server.scene.tree.node.at(lx, ly, &sx, &sy)
```

ถ้า node ที่เจอเป็น `.buffer` จะหา `SceneSurface`:

```zig
const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer)
```

จากนั้นเดิน parent tree:

```zig
var it: ?*wlr.SceneTree = node.parent;
while (it) |n| : (it = n.node.parent) {
    if (@as(?*Toplevel, @ptrCast(@alignCast(n.node.data)))) |toplevel| {
        return ViewAtResult{ ... };
    }
}
```

เพราะทั้ง `client_tree.node.data` และ outer `scene_tree.node.data` ชี้ไปที่ `Toplevel` จึงหา owner window ได้

ผลลัพธ์ `ViewAtResult` มี:

- `toplevel`
- `surface`
- `sx`, `sy`: coordinate ภายใน surface

## Hit Test Title Bar

title bar ไม่ใช่ client buffer แต่เป็น compositor-owned `SceneRect` ดังนั้นใช้ function แยก:

```zig
Server.titleBarAt(lx, ly)
```

เดิน `server.toplevels` จากบนลงล่าง:

```zig
var it = server.toplevels.iterator(.forward);
while (it.next()) |toplevel| {
    if (toplevel.titleBarContains(lx, ly)) return toplevel;
}
```

`Toplevel.titleBarContains()` ใช้ geometry:

```text
left = toplevel.x
top = toplevel.y + Decoration.title_bar_y
right = left + xdg_toplevel.base.geometry.width
bottom = top + title_bar_height
```

เงื่อนไข:

```text
lx >= left
lx < right
ly >= top
ly < bottom
```

ถ้า title bar hidden หรือ width <= 0 จะ return false

## Pointer Button Flow

`Cursor.handleButton()`:

### Pressed

ก่อนส่ง event ให้ client จะเช็ค title bar:

```zig
if (event.state == .pressed) {
    if (server.titleBarAt(cursor.x, cursor.y)) |toplevel| {
        focus.activateToplevel(...);
        cursor.beginTitleBarMove(toplevel);
        return;
    }
}
```

ถ้ากดบน title bar:

1. focus window
2. เข้า move mode
3. return เลย ไม่ forward button event ให้ client

ถ้าไม่ได้กด title bar:

1. forward button press ให้ client
2. ถ้า pointer อยู่บน client surface จะ focus window นั้น

### Released

ถ้า release:

```zig
cursor.mode = .passthrough;
cursor.grabbed_view = null;
cursor.title_bar_grab = false;
```

ถ้า release มาจาก title-bar drag (`title_bar_grab == true`) จะไม่ forward release ให้ client เพราะ press ก็ไม่ได้ส่งให้ client เช่นกัน

## Move Mode

เริ่มด้วย:

```zig
Cursor.beginMove(toplevel)
```

บันทึก:

```zig
grab_x = cursor.x - toplevel.x
grab_y = cursor.y - toplevel.y
```

ระหว่าง motion ใน mode `.move`:

```zig
toplevel.x = cursor.x - grab_x;
toplevel.y = cursor.y - grab_y;
toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);
```

หลักคือรักษาระยะระหว่าง cursor กับมุมซ้ายบนของ window เอาไว้ ทำให้ลากแล้ว window ไม่กระโดด

## Title Bar Move

`beginTitleBarMove()` เรียก `beginMove()` แล้ว set:

```zig
title_bar_grab = true
```

flag นี้ใช้ตอน release เพื่อไม่ส่ง mouse release ให้ client

## Resize Mode

client สามารถ request resize ผ่าน xdg_toplevel request:

```zig
Toplevel.handleRequestResize
```

แล้ว compositor เรียก:

```zig
cursor.beginResize(toplevel, event.edges);
```

`beginResize()` เก็บ:

- `grabbed_view`
- `resize_edges`
- `grab_box`: geometry ตอนเริ่ม resize
- `grab_x`, `grab_y`: offset ระหว่าง cursor กับ edge ที่ถูกจับ

ระหว่าง motion ใน mode `.resize`:

1. คำนวณ border position ใหม่จาก cursor
2. คำนวณ `new_left`, `new_right`, `new_top`, `new_bottom`
3. กันไม่ให้ width/height <= 0
4. update position:

```zig
toplevel.setPosition(
    new_left - geometry.x,
    new_top - geometry.y,
);
```

5. update size:

```zig
toplevel.setSize(new_width, new_height);
```

`setSize()` จะ update cached size และส่ง configure ให้ client

## Request Move

client สามารถส่ง xdg_toplevel request move:

```zig
Toplevel.handleRequestMove
```

ตอนนี้ compositor ตอบโดย:

```zig
toplevel.server.cursor.beginMove(toplevel);
```

ยังไม่ได้ validate serial/request origin แบบ compositor ที่ production-ready ควรทำ

