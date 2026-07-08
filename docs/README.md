# MagixWM Internals

เอกสารชุดนี้อธิบายการทำงานของ compositor ตัวนี้จาก code ปัจจุบันใน `src/` โดยเน้น lifecycle, event flow, input handling, focus, drag/resize, scene graph, output render loop และ animation ของ title bar

ไฟล์เอกสาร:

- [01-overview.md](01-overview.md): ภาพรวม architecture และ object สำคัญ
- [02-startup-and-server-lifecycle.md](02-startup-and-server-lifecycle.md): startup, server init/deinit และ Wayland socket
- [03-scene-and-toplevel-lifecycle.md](03-scene-and-toplevel-lifecycle.md): lifecycle ของ xdg_toplevel, scene tree, map/unmap/destroy
- [04-input-focus-keyboard-pointer.md](04-input-focus-keyboard-pointer.md): keyboard, pointer, focus, keybind และ clipboard selection
- [05-drag-resize-and-hit-testing.md](05-drag-resize-and-hit-testing.md): title-bar hit test, drag-to-move และ resize mode
- [06-titlebar-decoration-animation.md](06-titlebar-decoration-animation.md): decoration, title bar, hide/show animation, clipping และ frame scheduling
- [07-output-render-loop.md](07-output-render-loop.md): output lifecycle, render frame และ animation tick
- [08-popups-build-tests-and-notes.md](08-popups-build-tests-and-notes.md): popup, build system, tests และข้อควรระวัง
- [09-handler-trigger-reference.md](09-handler-trigger-reference.md): reference ว่า handler แต่ละตัวถูก trigger เมื่อไร

คำศัพท์ในเอกสาร:

- `server`: instance ของ `Server` ใน `src/server.zig`
- `toplevel`: window หลักแบบ `xdg_toplevel`
- `scene_tree`: outer tree ของ window ทั้งก้อน
- `client_tree`: scene tree ของ XDG surface/client ภายใน window
- `Decoration`: compositor-owned title bar
- `seat`: wlroots seat ที่ถือ keyboard/pointer focus และส่ง event ให้ client
