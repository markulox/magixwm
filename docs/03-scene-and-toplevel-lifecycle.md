# Scene และ Lifecycle ของ Toplevel

ไฟล์หลัก:

- `src/server.zig`
- `src/scene/toplevel.zig`
- `src/scene/decoration.zig`
- `src/scene/popup.zig`

## เมื่อมี xdg_toplevel ใหม่

เมื่อ client สร้าง window ใหม่ wlroots emit:

```text
xdg_shell.events.new_toplevel
```

callback:

```zig
Server.newXdgToplevel
```

ทำงาน:

1. allocate `Toplevel`
2. สร้าง outer scene tree:

```zig
const scene_tree = server.scene.tree.createSceneTree()
```

3. สร้าง XDG surface tree เป็น child ของ outer tree:

```zig
const client_tree = scene_tree.createSceneXdgSurface(xdg_surface)
```

4. init `Toplevel`:

```zig
toplevel.* = .{
    .server = server,
    .xdg_toplevel = xdg_toplevel,
    .scene_tree = scene_tree,
    .client_tree = client_tree,
};
```

5. set back pointers:

```zig
toplevel.scene_tree.node.data = toplevel;
toplevel.client_tree.node.data = toplevel;
xdg_surface.data = toplevel.client_tree;
```

`xdg_surface.data` ชี้ไปที่ `client_tree` เพราะ XDG surface scene tree เป็นตัวที่เกี่ยวกับ client surface โดยตรง แต่ทั้ง client tree และ outer tree ใส่ `node.data = toplevel` เพื่อให้ hit-test เดิน parent tree แล้วเจอ `Toplevel`

6. สร้าง title bar:

```zig
toplevel.decoration.createTitleBar(toplevel.scene_tree);
```

ขั้นตอนนี้สร้าง `decoration.title_bar` แบบ `SceneRect`

7. register listeners:

```text
surface.commit -> Toplevel.handleCommit
surface.map -> Toplevel.handleMap
surface.unmap -> Toplevel.handleUnmap
xdg_toplevel.destroy -> Toplevel.handleDestroy
xdg_toplevel.request_move -> Toplevel.handleRequestMove
xdg_toplevel.request_resize -> Toplevel.handleRequestResize
```

## Layout ของ Scene

หลังสร้าง window:

```text
server.scene.tree
  toplevel.scene_tree
    decoration.title_bar       // SceneRect พื้นหลัง title bar
    toplevel.client_tree
      xdg surface buffers
```

`toplevel.scene_tree` คือ outer window position และ stacking node

`toplevel.client_tree` คือ client content ที่สามารถถูก offset/clip ระหว่าง animation

## Commit แรก

เมื่อ surface commit ครั้งแรก:

```zig
Toplevel.handleCommit
```

ถ้า:

```zig
toplevel.xdg_toplevel.base.initial_commit
```

code ตั้งค่าเริ่มต้น:

```zig
toplevel.x = 100;
toplevel.y = 70;
_ = toplevel.setSize(860, 640);
toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);
```

`setSize()` จะ update cached normal size:

```zig
self.size_width = width;
self.size_height = height;
self.configureSize(width, height);
```

`configureSize()` เรียก:

```zig
xdg_toplevel.setSize(width, height)
```

นี่เป็น Wayland configure request ไม่ใช่ resize ทันที

## การจัดการ Decoration ตอน Commit

ทุก commit เรียก:

```zig
toplevel.decoration.handleCommit(toplevel.xdg_toplevel);
```

Decoration จะ:

1. configure xdg decoration เป็น server-side ถ้า initialized แล้ว
2. layout title bar ด้วย geometry width ของ xdg_toplevel

```zig
decoration.layoutTitleBar(xdg_toplevel.base.geometry.width);
```

## ตอน Map

เมื่อ client map surface:

```zig
Toplevel.handleMap
```

ทำ:

```zig
server.toplevels.prepend(toplevel);
focus.activateToplevel(server, toplevel, toplevel.xdg_toplevel.base.surface);
```

แปลว่า window ใหม่จะถูกใส่ไว้บนสุดของ focus/stack list แล้ว focus ทันที

## ตอน Unmap

เมื่อ surface unmap:

```zig
Toplevel.handleUnmap
```

ทำ:

```zig
toplevel.link.remove();
```

เอา window ออกจาก mapped toplevel list

## ตอน Destroy

เมื่อ xdg_toplevel ถูก destroy:

```zig
Toplevel.handleDestroy
```

ทำ:

1. remove listeners ทั้งหมด
2. `decoration.deinit()`
3. destroy outer scene node:

```zig
toplevel.scene_tree.node.destroy();
```

เพราะ `client_tree` และ title bar เป็น child ของ outer tree จึงถูก destroy ตาม scene graph

4. free `Toplevel`

```zig
gpa.destroy(toplevel);
```

## Lifecycle ของ Popup

เมื่อ client สร้าง `xdg_popup`:

```zig
Server.newXdgPopup
```

ทำ:

1. หา parent XDG surface
2. เอา `parent.data` มาเป็น parent scene tree
3. สร้าง popup scene XDG surface เป็น child ของ parent tree
4. allocate `Popup`
5. register commit/destroy listeners

ตอน popup initial commit:

```zig
_ = popup.xdg_popup.base.scheduleConfigure();
```

ตอน destroy:

- remove listeners
- free `Popup`

ข้อจำกัด: popup code ตอนนี้รองรับ parent ที่เป็น XDG surface เท่านั้น ยังไม่ได้รองรับ layer-shell หรือ parent ชนิดอื่น
