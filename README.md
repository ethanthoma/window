# window

Minimal cross-platform windowing for Zig (0.16.0+). Single-file backend per
platform.

## Platforms

| Platform        | Backend                                                             | File              |
| --------------- | ------------------------------------------------------------------- | ----------------- |
| Linux (Wayland) | [zig-wayland](https://codeberg.org/ifreund/zig-wayland) + xkbcommon | `src/wayland.zig` |
| Linux (X11)     | raw Xlib                                                            | `src/x11.zig`     |
| Windows         | raw Win32                                                           | `src/windows.zig` |
| macOS           | raw objc runtime + AppKit                                           | `src/macos.zig`   |

On Linux the dispatcher in `src/linux.zig` selects Wayland or X11 at runtime
based on `WAYLAND_DISPLAY` / `DISPLAY`.

## C API

`zig build c-api` produces `zig-out/lib/libwindow.a`, a static library exposing
the library over a C ABI (one window per process) for non-Zig consumers:

```c
int  window_init(uint32_t width, uint32_t height, const char *title); // 0 on success
void window_deinit(void);
uint32_t window_should_close(void);
void window_poll_events(void);
uint32_t window_next_event(CEvent *out);             // 0 when drained
uint32_t window_native_handles(CNativeHandles *out); // for wgpu/vulkan surfaces
void window_size(uint32_t *w, uint32_t *h);
void window_mouse_position(float *x, float *y);
```

Struct layouts live in `src/c_api.zig`. Event, key, and button enums cross the
boundary as integers in declaration order — bindings must mirror `src/key.zig`
and `src/mouse_button.zig`. Ready-made Odin bindings live in `bindings/odin/`.

## Usage

`build.zig.zon`:

```zig
.dependencies = .{
    .window = .{
        .url = "https://github.com/ethanthoma/window/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

`build.zig`:

```zig
const window_dep = b.dependency("window", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("window", window_dep.module("window"));
```

Minimal program:

```zig
const std = @import("std");
const window = @import("window");

pub fn main() !void {
    var win = try window.Window.init(.{
        .width = 800,
        .height = 600,
        .title = "Hello",
    });
    defer win.deinit();
    try win.start();
    win.show();

    while (!win.shouldClose()) {
        win.pollEvents();
        while (win.nextEvent()) |event| switch (event) {
            .key => |k| if (k.key == .escape and k.action == .press) return,
            else => {},
        };
    }
}
```

## Events

Everything arrives through one queue, drained with `nextEvent()` after each
`pollEvents()`:

`close`, `resize`, `key`, `mouse_button`, `mouse_move`, `mouse_scroll`,
`mouse_enter`, `mouse_leave`

Key and mouse button events carry an `action` (`.press`/`.release`). Held keys
do not repeat. Scroll deltas are positive scrolling down/right.

Polled state derived from the same events: `shouldClose()`,
`getMousePosition()`, `getMouseButtons()`, `isKeyPressed()`, `getKeysPressed()`,
plus `getSize()` from the backend.

## Build dependencies

### Linux

System libraries (resolved via `pkg-config`):

- `wayland-client`, `xkbcommon`, `x11`

Build tools:

- `wayland-scanner` on `PATH`
- `WAYLAND_XML` — path to `wayland.xml` (e.g. `/usr/share/wayland/wayland.xml`)
- `WAYLAND_PROTOCOLS_DIR` — path to `wayland-protocols` share dir (e.g.
  `/usr/share/wayland-protocols`)

### Windows

Links `user32`, `kernel32`, `gdi32` from the system. No extra config.

### macOS

Links `AppKit`, `QuartzCore`, `Metal` from the SDK.
