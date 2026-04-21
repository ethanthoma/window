const std = @import("std");
const builtin = @import("builtin");
const shared = @import("shared.zig");

const Window = @This();

pub const InputEvent = union(enum) {
    mouse_click: ClickEvent,
    key_press: Key,
    key_release: Key,
};

const MAX_EVENTS = 64;

backend: Backend,

event_queue: [MAX_EVENTS]InputEvent = undefined,
event_read: usize = 0,
event_write: usize = 0,

const Backend = switch (builtin.target.os.tag) {
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    .macos => @import("macos.zig"),
    else => @compileError("Unsupported OS"),
};

pub const InitOptions = shared.InitOptions;
pub const Size = shared.Size;
pub const NativeHandles = shared.NativeHandles;
pub const ClickEvent = shared.ClickEvent;
pub const Key = @import("key.zig").Key;
pub const MouseButton = @import("mouse_button.zig").MouseButton;

pub fn init(options: InitOptions) !Window {
    return .{ .backend = try Backend.init(options) };
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
    return self.backend.shouldClose();
}

pub fn pollEvents(self: *Window) void {
    self.event_read = 0;
    self.event_write = 0;
    self.backend.pollEvents(self);
}

pub fn nextEvent(self: *Window) ?InputEvent {
    if (self.event_read >= self.event_write) return null;
    const event = self.event_queue[self.event_read % MAX_EVENTS];
    self.event_read += 1;
    return event;
}

pub fn pushEvent(self: *Window, event: InputEvent) void {
    if (self.event_write - self.event_read >= MAX_EVENTS) return;
    self.event_queue[self.event_write % MAX_EVENTS] = event;
    self.event_write += 1;
}

pub fn getNativeHandles(self: *Window) NativeHandles {
    return self.backend.getNativeHandles();
}

pub fn getSize(self: *Window) Size {
    return self.backend.getSize();
}

pub fn needsResize(self: *Window) bool {
    return self.backend.needsResize();
}

pub fn getNewSize(self: *Window) Size {
    return self.backend.getNewSize();
}

pub fn clearResize(self: *Window) void {
    self.backend.clearResize();
}

pub fn getMousePosition(self: *Window) shared.MousePosition {
    return self.backend.getMousePosition();
}

pub fn getMouseButtons(self: *Window) u8 {
    return self.backend.getMouseButtons();
}

pub fn isKeyPressed(self: *Window, key: Key) bool {
    return self.backend.isKeyPressed(key);
}

pub fn getKeysPressed(self: *Window) std.EnumSet(Key) {
    return self.backend.getKeysPressed();
}
