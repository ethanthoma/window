// C ABI over a single static Window, for consumption from non-Zig languages.
// Event/key/button enums cross the boundary as @intFromEnum of the Zig enums:
// bindings must mirror the declaration order in key.zig and mouse_button.zig.
const std = @import("std");
const window = @import("main.zig");

var win: window.Window = undefined;
var initialized = false;

pub const CEvent = extern struct {
    kind: u32,
    key: u32,
    action: u32,
    button: u32,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    width: u32,
    height: u32,
};

pub const CNativeHandles = extern struct {
    kind: u32,
    display: ?*anyopaque,
    surface: ?*anyopaque,
    window: u64,
};

export fn window_init(width: u32, height: u32, title: [*:0]const u8) i32 {
    std.debug.assert(!initialized);
    win = window.Window.init(.{ .width = width, .height = height, .title = title }) catch return -1;
    win.start() catch return -2;
    win.show();
    initialized = true;
    return 0;
}

export fn window_deinit() void {
    std.debug.assert(initialized);
    win.deinit();
    initialized = false;
}

export fn window_should_close() u32 {
    std.debug.assert(initialized);
    return if (win.shouldClose()) 1 else 0;
}

export fn window_poll_events() void {
    std.debug.assert(initialized);
    win.pollEvents();
}

export fn window_next_event(out: *CEvent) u32 {
    std.debug.assert(initialized);
    const event = win.nextEvent() orelse return 0;
    out.* = std.mem.zeroes(CEvent);
    switch (event) {
        .close => out.kind = 1,
        .resize => |s| {
            out.kind = 2;
            out.width = s.width;
            out.height = s.height;
        },
        .key => |k| {
            out.kind = 3;
            out.key = @intFromEnum(k.key);
            out.action = @intFromEnum(k.action);
        },
        .mouse_button => |b| {
            out.kind = 4;
            out.button = @intFromEnum(b.button);
            out.action = @intFromEnum(b.action);
            out.x = b.x;
            out.y = b.y;
        },
        .mouse_move => |p| {
            out.kind = 5;
            out.x = p.x;
            out.y = p.y;
        },
        .mouse_scroll => |s| {
            out.kind = 6;
            out.dx = s.dx;
            out.dy = s.dy;
        },
        .mouse_enter => |p| {
            out.kind = 7;
            out.x = p.x;
            out.y = p.y;
        },
        .mouse_leave => out.kind = 8,
    }
    return 1;
}

export fn window_native_handles(out: *CNativeHandles) u32 {
    std.debug.assert(initialized);
    out.* = std.mem.zeroes(CNativeHandles);
    switch (win.getNativeHandles()) {
        .wayland => |h| {
            out.kind = 0;
            out.display = h.display;
            out.surface = h.surface;
        },
        .x11 => |h| {
            out.kind = 1;
            out.display = h.display;
            out.window = h.window;
        },
        .win32 => |h| {
            out.kind = 2;
            out.display = h.hinstance;
            out.surface = h.hwnd;
        },
        .metal => |l| {
            out.kind = 3;
            out.surface = l;
        },
    }
    return 1;
}

export fn window_size(w: *u32, h: *u32) void {
    std.debug.assert(initialized);
    const s = win.getSize();
    w.* = s.width;
    h.* = s.height;
}

export fn window_mouse_position(x: *f32, y: *f32) void {
    std.debug.assert(initialized);
    const p = win.getMousePosition();
    x.* = p.x;
    y.* = p.y;
}
