# Output And Render Loop

ไฟล์หลัก:

- `src/server.zig`
- `src/scene/output.zig`
- `src/utils/time.zig`

## New Output

เมื่อ backend เจอ output:

```text
backend.events.new_output -> Server.newOutput
```

`newOutput()`:

1. init render:

```zig
wlr_output.initRender(server.allocator, server.renderer)
```

2. สร้าง output state
3. enable output
4. ถ้ามี preferred mode ให้ set mode
5. commit state
6. สร้าง `Output` wrapper:

```zig
Output.create(server, wlr_output)
```

## Output.create

`Output.create()`:

1. allocate `Output`
2. register listeners:

```text
output.frame -> Output.handleFrame
output.request_state -> Output.handleRequestState
output.destroy -> Output.handleDestroy
```

3. add output เข้า output layout:

```zig
server.output_layout.addAuto(wlr_output)
```

4. create scene output:

```zig
server.scene.createSceneOutput(wlr_output)
```

5. add scene output เข้า scene output layout
6. prepend เข้า `server.outputs`

`server.outputs` ใช้สำหรับ schedule frame เมื่อ animation เริ่ม

## Frame Handler

ทุก output frame:

```zig
Output.handleFrame
```

ลำดับ:

1. หา scene output:

```zig
const scene_output = server.scene.getSceneOutput(wlr_output).?
```

2. อ่าน monotonic timestamp:

```zig
var now = timestamp()
```

3. แปลงเป็น milliseconds:

```zig
now_msec = now.sec * 1000 + now.nsec / 1_000_000
```

4. update animations:

```zig
const animations_active = server.updateAnimations(now_msec);
```

5. commit scene output:

```zig
scene_output.commit(null)
```

6. ส่ง frame done ให้ clients:

```zig
scene_output.sendFrameDone(&now)
```

7. ถ้ายังมี animation active:

```zig
wlr_output.scheduleFrame()
```

## Animation Tick

`Server.updateAnimations(now_msec)` เดินทุก mapped toplevel:

```zig
var it = server.toplevels.iterator(.forward);
while (it.next()) |toplevel| {
    active = toplevel.updateAnimations(now_msec) or active;
}
```

ถ้า toplevel ใด update animation แล้ว return true, output frame จะถูก schedule ต่อ

## Request State

ถ้า output request state:

```zig
Output.handleRequestState
```

ทำ:

```zig
wlr_output.commitState(event.state)
```

## Output Destroy

เมื่อ output destroy:

1. remove listeners
2. remove from `server.outputs`
3. free `Output`

## timestamp()

`src/utils/time.zig` ใช้:

```zig
clock_gettime(CLOCK_MONOTONIC)
```

เพราะ animation ควรใช้ monotonic clock ไม่ใช่ wall-clock time

