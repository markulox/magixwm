# Reference การ Trigger Handler

เอกสารนี้สรุปว่า handler สำคัญใน project ถูกเรียกเมื่อไร ใครเป็นคน trigger และโดยทั่วไปควรคาดหวัง state แบบไหนตอนเข้า handler

## ภาพรวม Event Sources

handler ใน project นี้มาจาก 4 แหล่งหลัก:

1. backend events: output/input device ถูกเพิ่มหรือหายไป
2. xdg-shell events: client สร้าง window, popup, map/unmap, commit, destroy
3. input events: keyboard, pointer, cursor motion/button/axis
4. output frame events: ถึงเวลาวาด frame ถัดไป

ทุก handler ที่เป็น `wl.Listener` จะถูกเรียกโดย Wayland/wlroots event loop หลังจาก `wl_server.run()` เริ่มทำงานแล้ว

## Handler ของ Server

### `Server.newOutput`

ถูก trigger เมื่อ backend เจอ output ใหม่

ตัวอย่างสถานการณ์:

- compositor start แล้ว backend สร้าง nested output
- เสียบ monitor ใหม่
- backend รายงาน output เพิ่ม

สิ่งที่ handler ทำ:

- init render สำหรับ output
- enable output
- set preferred mode ถ้ามี
- commit output state
- สร้าง `Output` wrapper
- attach output เข้า output layout และ scene output layout

### `Server.newInput`

ถูก trigger เมื่อ backend เจอ input device ใหม่

ตัวอย่างสถานการณ์:

- compositor start แล้วเจอ keyboard/pointer จาก host backend
- เสียบ mouse/keyboard ใหม่

สิ่งที่ handler ทำ:

- ถ้าเป็น keyboard จะสร้าง `Keyboard`
- ถ้าเป็น pointer จะ attach device เข้า `Cursor`
- update seat capabilities

### `Server.newXdgToplevel`

ถูก trigger เมื่อ client สร้าง `xdg_toplevel` ใหม่

จุดสำคัญ: ตอน handler นี้ถูกเรียก window ยังไม่จำเป็นต้อง mapped แล้ว handler นี้เป็นแค่ช่วงสร้าง object และ register listeners

สิ่งที่ handler ทำ:

- allocate `Toplevel`
- สร้าง outer `scene_tree`
- สร้าง `client_tree` จาก xdg surface
- set `node.data` และ `xdg_surface.data`
- สร้าง title bar scene node
- register commit/map/unmap/destroy/request_move/request_resize listeners

### `Server.newXdgPopup`

ถูก trigger เมื่อ client สร้าง `xdg_popup`

ตัวอย่าง:

- menu
- context menu
- tooltip-like popup

สิ่งที่ handler ทำ:

- หา parent xdg surface
- สร้าง popup scene tree ใต้ parent
- allocate `Popup`
- register commit/destroy listeners

### `Server.newXdgToplevelDecoration`

ถูก trigger เมื่อ client สร้าง xdg-decoration object สำหรับ toplevel

สิ่งที่ handler ทำ:

- หา `Toplevel` จาก `decoration.toplevel.base.data`
- เรียก `toplevel.decoration.setXdgDecoration(decoration)`

หลังจากนั้น `Decoration` จะพยายาม set mode เป็น server-side เมื่อ surface initialized แล้ว

### `Server.requestSetSelection`

ถูก trigger เมื่อ client ขอ set clipboard/data selection

ตัวอย่าง:

- client copy text
- client ตั้ง data source ใหม่ให้ seat

สิ่งที่ handler ทำ:

```zig
server.seat.setSelection(event.source, event.serial);
```

## Handler ของ Toplevel

### `Toplevel.handleCommit`

ถูก trigger ทุกครั้งที่ client commit surface state

ตัวอย่าง:

- initial commit
- client วาด buffer ใหม่
- client ตอบรับ configure size
- geometry เปลี่ยน

สิ่งที่ handler ทำ:

- ถ้าเป็น initial commit จะตั้ง position/size เริ่มต้น
- ให้ decoration update layout ตาม geometry ปัจจุบัน
- ถ้ามี pending hide animation และ client commit expanded height แล้ว จะเริ่ม hide animation

จุดสำคัญ: `xdg_toplevel.setSize()` ไม่ทำให้ geometry เปลี่ยนทันที ต้องรอ commit handler นี้เพื่อเห็น geometry ใหม่

### `Toplevel.handleMap`

ถูก trigger เมื่อ surface กลายเป็น mapped

mapped หมายถึง client พร้อมแสดงผลจริงแล้ว โดยทั่วไปมี buffer/role state พร้อม

สิ่งที่ handler ทำ:

- prepend เข้า `server.toplevels`
- focus window ผ่าน `focus.activateToplevel`

### `Toplevel.handleUnmap`

ถูก trigger เมื่อ surface หยุด mapped

ตัวอย่าง:

- window ถูก hide
- client unmap surface
- window กำลังจะปิดหรือ recreate

สิ่งที่ handler ทำ:

- remove จาก `server.toplevels`

### `Toplevel.handleDestroy`

ถูก trigger เมื่อ `xdg_toplevel` ถูก destroy

ตัวอย่าง:

- client ปิด window
- client disconnect
- xdg_toplevel resource ถูกทำลาย

สิ่งที่ handler ทำ:

- remove listeners
- deinit decoration
- destroy scene node
- free `Toplevel`

### `Toplevel.handleRequestMove`

ถูก trigger เมื่อ client ส่ง xdg_toplevel request move

ตัวอย่าง:

- client-side titlebar เรียก interactive move
- app ขอให้ compositor เริ่ม move operation

สิ่งที่ handler ทำ:

- เรียก `cursor.beginMove(toplevel)`

หมายเหตุ: code ปัจจุบันยังไม่ได้ validate serial

### `Toplevel.handleRequestResize`

ถูก trigger เมื่อ client ส่ง xdg_toplevel request resize

ตัวอย่าง:

- client ขอ interactive resize จาก edge/corner

สิ่งที่ handler ทำ:

- เรียก `cursor.beginResize(toplevel, event.edges)`

## Handler ของ Decoration

### `Decoration.handleCommit`

ถูกเรียกจาก `Toplevel.handleCommit` ไม่ได้ถูก wlroots trigger โดยตรง

จังหวะที่เกิด:

- ทุก surface commit ของ toplevel

สิ่งที่ทำ:

- configure xdg decoration เป็น server-side ถ้าพร้อม
- layout title bar width/height/position

### `Decoration.handleDestroy`

ถูก trigger เมื่อ xdg-decoration object ถูก destroy

ตัวอย่าง:

- client destroy decoration resource
- toplevel ปิด

สิ่งที่ handler ทำ:

- remove decoration destroy listener
- clear `xdg_decoration`

## Handler ของ Popup

### `Popup.handleCommit`

ถูก trigger ทุกครั้งที่ popup surface commit

ถ้าเป็น initial commit:

```zig
popup.xdg_popup.base.scheduleConfigure();
```

เหตุผลคือ xdg_popup ต้องได้รับ configure ก่อนจะ map/แสดงผลได้ถูกต้อง

### `Popup.handleDestroy`

ถูก trigger เมื่อ `xdg_popup` ถูก destroy

สิ่งที่ทำ:

- remove listeners
- free `Popup`

## Handler ของ Output

### `Output.handleFrame`

ถูก trigger เมื่อ output ต้องการ frame ใหม่

ตัวอย่าง:

- display refresh
- compositor เรียก `wlr_output.scheduleFrame()`
- scene/output มี damage หรือ animation ต้องวาดต่อ

สิ่งที่ handler ทำ:

1. อ่าน timestamp
2. update animation ของทุก toplevel
3. commit scene output
4. send frame done ให้ clients
5. ถ้ายังมี animation active ให้ schedule frame ต่อ

นี่เป็นจุดที่ title bar animation เดินจริง เพราะ animation ใช้ timestamp จาก frame handler

### `Output.handleRequestState`

ถูก trigger เมื่อ output backend/request ต้องการ commit state ใหม่

สิ่งที่ทำ:

```zig
output.wlr_output.commitState(event.state);
```

### `Output.handleDestroy`

ถูก trigger เมื่อ output ถูก destroy

ตัวอย่าง:

- unplug monitor
- nested backend output หาย
- backend shutdown

สิ่งที่ทำ:

- remove listeners
- remove from `server.outputs`
- free `Output`

## Handler ของ Cursor

### `Cursor.handleMotion`

ถูก trigger เมื่อ pointer ส่ง relative motion

ตัวอย่าง:

- mouse ขยับ
- touchpad relative motion

สิ่งที่ทำ:

- update `wlr_cursor` position ด้วย delta
- เรียก `processMotion`

### `Cursor.handleMotionAbsolute`

ถูก trigger เมื่อ pointer ส่ง absolute motion

ตัวอย่าง:

- tablet
- absolute pointer device

สิ่งที่ทำ:

- warp cursor ตาม absolute coordinate
- เรียก `processMotion`

### `Cursor.processMotion`

ไม่ใช่ wlroots handler โดยตรง แต่ถูกเรียกจาก motion handlers

ทำงานต่างกันตาม cursor mode:

- `.passthrough`: hit-test client แล้วส่ง pointer enter/motion
- `.move`: ย้าย toplevel ตาม cursor
- `.resize`: คำนวณ geometry ใหม่แล้ว set position/size

### `Cursor.handleButton`

ถูก trigger เมื่อ pointer button pressed/released

ตอน pressed:

- ถ้ากดบน title bar จะ focus window แล้วเข้า title-bar move mode
- ถ้าไม่ได้กด title bar จะ forward button ให้ client แล้ว focus client ใต้ cursor

ตอน released:

- reset mode เป็น passthrough
- ถ้าเป็น title-bar drag จะไม่ forward release ให้ client
- ถ้าไม่ใช่ title-bar drag จะ forward release ให้ client

### `Cursor.handleAxis`

ถูก trigger เมื่อมี scroll event

สิ่งที่ทำ:

```zig
seat.pointerNotifyAxis(...)
```

forward scroll ให้ focused pointer client

### `Cursor.handleFrame`

ถูก trigger เมื่อ cursor frame จบ

สิ่งที่ทำ:

```zig
seat.pointerNotifyFrame();
```

Wayland pointer events มักถูกส่งเป็นชุด แล้วปิดท้ายด้วย frame event

### `Cursor.handleRequestSetCursor`

ถูก trigger เมื่อ client ขอเปลี่ยน cursor image

สิ่งที่ทำ:

- อนุญาตเฉพาะ client ที่มี pointer focus
- set cursor surface/hotspot จาก request

## Handler ของ Keyboard

### `Keyboard.handleModifiers`

ถูก trigger เมื่อ modifier state เปลี่ยน

ตัวอย่าง:

- กดหรือปล่อย Alt
- กดหรือปล่อย Shift/Ctrl

สิ่งที่ทำ:

- set keyboard ให้ seat
- notify modifiers ให้ client

### `Keyboard.handleKey`

ถูก trigger เมื่อ key pressed/released

สิ่งที่ทำ:

1. แปลง keycode เป็น xkb keycode
2. ถ้า Alt + pressed จะลอง compositor keybind
3. ถ้า keybind handle แล้ว ไม่ส่งให้ client
4. ถ้าไม่ handle จะ notify key ให้ client

### `Keyboard.handleDestroy`

ถูก trigger เมื่อ keyboard input device ถูก destroy

สิ่งที่ทำ:

- remove keyboard จาก list
- remove listeners
- set keyboard ตัวถัดไปให้ seat ถ้ามี
- ถ้าไม่มี keyboard เหลือ set null
- update seat capabilities
- free `Keyboard`

## Handler ของ Keybind

### `keybind.handle`

ไม่ใช่ wlroots handler โดยตรง แต่ถูกเรียกจาก `Keyboard.handleKey` เฉพาะตอน Alt + key pressed

ตอนนี้รองรับ:

- `Alt+Escape`: terminate compositor
- `Alt+s`: focus next/previous window ตาม list order

## Function สำหรับ Focus

### `focus.activateToplevel`

ไม่ใช่ event handler โดยตรง แต่ถูกเรียกจากหลาย path:

- `Toplevel.handleMap` ตอน window map ใหม่
- `Cursor.handleButton` ตอน click client หรือ title bar
- `keybind.handle` ตอน switch focus

สิ่งที่ทำ:

- unfocus window เดิม
- raise scene node
- move toplevel ไปหัว list
- call `notifyFocus`
- send keyboard enter

## ตัวอย่าง Timeline ที่เจอบ่อย

### เปิด window ใหม่

```text
client creates xdg_toplevel
-> Server.newXdgToplevel
client commits initial state
-> Toplevel.handleCommit
client maps surface
-> Toplevel.handleMap
-> focus.activateToplevel
-> Toplevel.notifyFocus
```

### click title bar แล้วลาก

```text
pointer button pressed
-> Cursor.handleButton
-> Server.titleBarAt
-> focus.activateToplevel
-> Cursor.beginTitleBarMove
pointer motion
-> Cursor.handleMotion
-> Cursor.processMotion(.move)
pointer button released
-> Cursor.handleButton
-> reset mode
```

### unfocus window แล้ว hide title bar

```text
another window focused
-> focus.activateToplevel
-> previous_toplevel.notifyUnfocus
-> configure expanded client size
client commits expanded size
-> Toplevel.handleCommit
-> start hide animation
output frame
-> Output.handleFrame
-> Server.updateAnimations
-> Toplevel.updateAnimations
-> Decoration.updateTitleBarAnimation
```

### show title bar ตอน focus กลับ

```text
window focused
-> focus.activateToplevel
-> Toplevel.notifyFocus
-> start show animation
output frame
-> Output.handleFrame
-> Toplevel.updateAnimations
-> Decoration.updateTitleBarAnimation
animation ends
-> configure final normal client size
client commits final size
-> Toplevel.handleCommit
```
