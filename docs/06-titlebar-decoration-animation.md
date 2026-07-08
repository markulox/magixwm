# Title Bar, Decoration And Animation

ไฟล์หลัก:

- `src/scene/decoration.zig`
- `src/scene/toplevel.zig`
- `src/scene/output.zig`
- `src/server.zig`

## Decoration คืออะไร

`Decoration` เป็น compositor-side object ที่ถือ title bar:

```zig
title_bar: ?*wlr.SceneRect
```

title bar เป็น `SceneRect` สีเทา ไม่ใช่ surface ของ client

ค่าคงที่:

```zig
title_bar_height = 30
title_bar_y = -title_bar_height
title_bar_animation_duration_ms = 75
```

## Server-side Decoration Protocol

ถ้า client ใช้ xdg-decoration protocol, `Server.newXdgToplevelDecoration()` จะเรียก:

```zig
toplevel.decoration.setXdgDecoration(decoration);
```

`Decoration.configureXdg()` ตั้ง mode เป็น:

```zig
server_side
```

แปลว่า compositor เป็นคนวาด decoration

## Title Bar Layout

ทุก commit:

```zig
Decoration.handleCommit(xdg_toplevel)
```

จะ layout title bar ตาม `xdg_toplevel.base.geometry.width`

height ที่ใช้:

- ถ้า animation active: ใช้ height ปัจจุบันของ rect
- ถ้าไม่ active: ใช้ `titleBarHeight(isShown)`

position ใช้ `positionTitleBar()`

## Positioning Modes

`Decoration` มี enum:

```zig
const TitleBarPosition = enum {
    above_client,
    fixed_top,
};
```

### above_client

ใช้ตอน normal/show:

```text
y = offset - height
```

ถ้า height = 30 และ offset = 0:

```text
y = -30
```

title bar อยู่เหนือ client

### fixed_top

ใช้ตอน hide animation ปัจจุบัน:

```text
y = offset
```

ตอน hide เรียกด้วย offset = 0 ดังนั้น title bar อยู่ local y = 0 และลด height จาก 30 -> 0 ทำให้หดจากล่างขึ้นบน

## Animation State

`TitleBarAnimation`:

```zig
active: bool
started_msec: u64
duration_msec: u32
from_height: c_int
to_height: c_int
```

height คำนวณด้วย linear interpolation:

```zig
from + (to - from) * elapsed / duration
```

ถ้า elapsed >= duration จะ clamp เป็น `to_height`

## Hide Flow

เมื่อ window ถูก unfocus:

```zig
Toplevel.notifyUnfocus()
```

ถ้า title bar ยัง shown:

1. ตั้ง pending:

```zig
pending_hide_animation = true
pending_hide_height = size_height + title_bar_height
hide_animation_start_y = y
```

2. ส่ง configure ให้ client ขยาย height:

```zig
configureSize(size_width, pending_hide_height)
```

นี่ทำให้ client มีพื้นที่เพิ่มแทน title bar ที่จะหายไป

### รอ client commit

ใน `handleCommit()`:

```zig
if pending_hide_animation and geometry.height >= pending_hide_height
```

เมื่อ client commit size ที่ขยายแล้ว:

1. clear pending
2. move outer window ขึ้นครั้งเดียว:

```zig
setPosition(x, hide_animation_start_y - title_bar_height)
```

3. ตั้ง client offset:

```zig
setClientOffset(title_bar_height)
```

ทำให้ client ที่ขยายแล้วเริ่มจากตำแหน่งเดิมด้านล่าง title bar

4. clip client:

```zig
setClientClip(pending_hide_height - title_bar_height)
```

5. start title bar hide animation:

```zig
decoration.startHideAnimation(nowMsec(), 0)
```

6. schedule frame

### ระหว่าง hide animation

`Toplevel.updateAnimations()`:

```zig
height = decoration.currentTitleBarHeight()
setClientOffset(height)
setClientClip(pending_hide_height - height)
```

เมื่อ height ลดจาก 30 -> 0:

- client offset ลดจาก 30 -> 0
- client จึง slide ขึ้น
- clip height เพิ่มจาก normal height -> expanded height
- bottom edge ไม่ควรขยับ เพราะ outer tree อยู่ final position แล้ว และ client ถูก clip

เมื่อ animation จบ:

```zig
setClientOffset(0)
clearClientClip()
```

ไม่ต้อง configure size อีก เพราะ configure expanded size ถูกส่งก่อน animation แล้ว

## Show Flow

เมื่อ window ถูก focus และ title bar hidden:

```zig
Toplevel.notifyFocus()
```

ทำ:

1. clear pending hide
2. clear client offset/clip
3. activate xdg_toplevel
4. start show animation
5. move outer window ลงเพื่อเตรียมพื้นที่ title bar:

```zig
show_animation_start_y = y
startShowAnimation(nowMsec())
setPosition(x, y + title_bar_height)
scheduleFrame()
```

สำคัญ: ตอน show animation เริ่ม จะยังไม่ส่ง final client size ทันที

```zig
configure_now = false
```

เพราะ requirement ปัจจุบันคือให้ animation จบก่อน แล้วค่อย apply final client size

### ระหว่าง show animation

`updateAnimations()`:

```zig
height = decoration.currentTitleBarHeight()
setScenePosition(x, show_animation_start_y + height)
setClientClip((size_height + title_bar_height) - height)
```

เมื่อ height เพิ่มจาก 0 -> 30:

- outer window y ขยับจาก hidden y -> focused y
- client ยังเป็น expanded size เดิมระหว่าง animation
- clip ลดจาก expanded height -> normal height
- ทำให้ bottom edge stable ระหว่าง animation

### เมื่อ show จบ

```zig
setPosition(x, show_animation_start_y + title_bar_height)
clearClientClip()
configureSize(size_width, size_height)
```

หลัง animation จบแล้วค่อยบอก client ให้กลับไป normal focused size

## Frame Scheduling

animation ไม่เดินเอง ต้องมี output frame events

เมื่อเริ่ม animation:

```zig
server.scheduleFrame()
```

`Server.scheduleFrame()` เรียก `scheduleFrame()` ของทุก output

ใน `Output.handleFrame()`:

1. timestamp
2. `server.updateAnimations(now_msec)`
3. commit scene output
4. send frame done
5. ถ้ายังมี animation active ให้ schedule frame ต่อ

## Why Not Use setSize Every Frame

`xdg_toplevel.setSize()` เป็น Wayland configure negotiation ไม่ใช่ immediate command

ถ้าส่งทุก frame:

- client อาจตอบช้า
- animation jitter
- frame timing ไม่ตรง compositor
- protocol semantics ผิด เพราะ compositor ควรส่ง configure ตอน layout state เปลี่ยน ไม่ใช่ใช้เป็น animation primitive

ดังนั้น project นี้ animate scene nodes:

- title bar rect size/position
- client_tree local position
- client_tree clip
- outer scene tree position เฉพาะ transition boundary

