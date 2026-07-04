This project is a small wlroots-based Wayland compositor written in Zig.

  At a high level:

  1. main.zig starts the compositor.
  2. Server owns the Wayland server, wlroots backend, renderer, scene graph, outputs, input devices, cursor, seat, and xdg-shell.
  3. wlroots emits events when monitors, keyboards, pointers, windows, and popups appear.
  4. Your event handlers create small Zig structs like Output, Keyboard, Toplevel, and Popup.
  5. Those structs attach listeners to wlroots objects and clean themselves up when the wlroots object is destroyed.

  Startup Flow
  src/main.zig:8 initializes logging, creates a Server, adds a Wayland socket, optionally starts a command under that socket, starts the backend, then enters the Wayland event loop:

  try server.init();
  defer server.deinit();

  const socket = try server.wl_server.addSocketAuto(&buf);
  try server.backend.start();
  server.wl_server.run();

  The socket becomes WAYLAND_DISPLAY, so clients know where to connect.

  Server Core
  src/server.zig:16 is the compositor’s central state object. It creates:

  - wl.Server: Wayland display server
  - wlr.Backend: talks to real or nested display/input backend
  - wlr.Renderer: renders buffers
  - wlr.Scene: wlroots scene graph
  - wlr.OutputLayout: monitor arrangement
  - wlr.XdgShell: receives normal application windows
  - wlr.Seat: represents keyboard/pointer capabilities to clients
  - wlr.Cursor: tracks pointer movement

  Then it registers listeners like:

  server.backend.events.new_output.add(&server.new_output);
  server.xdg_shell.events.new_toplevel.add(&server.new_xdg_toplevel);
  server.backend.events.new_input.add(&server.new_input);

  That is the core pattern: wlroots owns the low-level objects, your Zig structs subscribe to events.

  Outputs
  When a monitor appears, newOutput runs in src/server.zig:128.

  It initializes rendering for that output, enables the preferred mode, then creates an Output wrapper from src/scence/output.zig:13.

  Output listens for frame events. On each frame:

  _ = scene_output.commit(null);
  scene_output.sendFrameDone(&now);

  So rendering is scene-graph driven: windows and other scene nodes are committed to each output.

  Windows
  When an app creates an xdg toplevel window, newXdgToplevel runs in src/server.zig:149.

  It creates a Toplevel struct, creates a scene tree for the xdg surface, and attaches listeners for:

  - commit
  - map
  - unmap
  - destroy
  - request_move
  - request_resize

  When the window maps, src/scence/toplevel.zig:45 adds it to the compositor’s toplevel list and focuses it.

  Input
  When input devices appear, newInput in src/server.zig:271 handles them.

  - Keyboard devices become Keyboard wrappers.
  - Pointer devices get attached to the cursor.
  - Seat capabilities are updated.

  Keyboard handling in src/input/keyboard.zig:50 checks for Alt keybindings. For example, Alt+Escape terminates the compositor, and Alt+F1 cycles focus.

  If a key is not handled by the compositor, it is forwarded to the focused client.

  Cursor And Focus
  Pointer motion goes through processCursorMotion in src/server.zig:323.

  There are three cursor modes:

  .passthrough
  .move
  .resize

  In passthrough mode, the compositor finds the surface under the cursor and forwards pointer enter/motion events to the client.

  In move mode, cursor movement changes the toplevel scene node position.

  In resize mode, cursor movement computes a new window box and sends setSize to the client.

  Mental Model
  The project is basically:

  main.zig
    creates Server
    starts backend
    runs Wayland loop

  Server
    owns global compositor state
    listens for wlroots events
    routes events to Output / Keyboard / Toplevel / Popup

  Output
    renders scene frames

  Toplevel
    represents one application window

  Popup
    represents one xdg popup

  Keyboard
    handles compositor keybindings or forwards keys to clients

  The strongest design idea here is good: small wrapper structs around wlroots objects, each owning its listeners. The main thing to keep improving is lifecycle safety: every listener added should have a clear removal path, and
  every allocated wrapper should be cleaned up on both normal destroy and partial initialization failure.
