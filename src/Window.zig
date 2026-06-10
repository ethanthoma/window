const std = @import("std");
const builtin = @import("builtin");
const shared = @import("shared.zig");

const Window = @This();

pub const Action = enum { press, release };
pub const Position = struct { x: f32, y: f32 };
// positive dy scrolls content down, positive dx scrolls content right
pub const Scroll = struct { dx: f32, dy: f32 };

pub const Event = union(enum) {
    close,
    resize: Size,
    key: struct { key: Key, action: Action },
    mouse_button: struct { button: MouseButton, action: Action, x: f32, y: f32 },
    mouse_move: Position,
    mouse_scroll: Scroll,
    mouse_enter: Position,
    mouse_leave,
};

const MAX_EVENTS = 256;

backend: Backend,

event_queue: [MAX_EVENTS]Event = undefined,
event_len: usize = 0,
event_read: usize = 0,

should_close: bool = false,
mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: std.EnumSet(MouseButton) = std.EnumSet(MouseButton).initEmpty(),
keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

const Backend = switch (builtin.target.os.tag) {
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    .macos => @import("macos.zig"),
    else => @compileError("Unsupported OS"),
};

pub const InitOptions = shared.InitOptions;
pub const Size = shared.Size;
pub const NativeHandles = shared.NativeHandles;
pub const Key = @import("key.zig").Key;
pub const MouseButton = @import("mouse_button.zig").MouseButton;

pub fn init(options: InitOptions) !Window {
    return .{
        .backend = try Backend.init(options),
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
    };
}

pub fn start(self: *Window) !void {
    try self.backend.start();
}

pub fn deinit(self: *Window) void {
    self.backend.deinit();
}

pub fn show(self: *Window) void {
    self.backend.show();
}

pub fn shouldClose(self: *Window) bool {
    return self.should_close;
}

pub fn pollEvents(self: *Window) void {
    self.event_len = 0;
    self.event_read = 0;
    self.backend.pollEvents(self);
}

pub fn nextEvent(self: *Window) ?Event {
    if (self.event_read >= self.event_len) return null;
    const event = self.event_queue[self.event_read];
    self.event_read += 1;
    return event;
}

pub fn pushEvent(self: *Window, event: Event) void {
    switch (event) {
        .close => self.should_close = true,
        .key => |k| switch (k.action) {
            .press => {
                if (k.key == .unknown or self.keys_pressed.contains(k.key)) return;
                self.keys_pressed.insert(k.key);
            },
            .release => {
                if (k.key == .unknown) return;
                self.keys_pressed.remove(k.key);
            },
        },
        .mouse_button => |b| {
            self.mouse_x = b.x;
            self.mouse_y = b.y;
            switch (b.action) {
                .press => self.mouse_buttons.insert(b.button),
                .release => self.mouse_buttons.remove(b.button),
            }
        },
        .mouse_move, .mouse_enter => |p| {
            self.mouse_x = p.x;
            self.mouse_y = p.y;
        },
        .resize, .mouse_scroll, .mouse_leave => {},
    }
    if (self.event_len >= MAX_EVENTS) return;
    self.event_queue[self.event_len] = event;
    self.event_len += 1;
}

pub fn getNativeHandles(self: *Window) NativeHandles {
    return self.backend.getNativeHandles();
}

pub fn getSize(self: *Window) Size {
    return self.backend.getSize();
}

pub fn getMousePosition(self: *Window) Position {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *Window) std.EnumSet(MouseButton) {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *Window, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *Window) std.EnumSet(Key) {
    return self.keys_pressed;
}
