const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const Window = @import("Window.zig");

const MacOSWindow = @This();

width: u32 = 0,
height: u32 = 0,
mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: u8 = 0,
keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

pub fn init(_: shared.InitOptions) !MacOSWindow {
    return error.MacOSNotImplemented;
}

pub fn start(_: *MacOSWindow) !void {}
pub fn deinit(_: *MacOSWindow) void {}
pub fn show(_: *MacOSWindow) void {}

pub fn shouldClose(_: *MacOSWindow) bool {
    return true;
}

pub fn pollEvents(_: *MacOSWindow, _: *Window) void {}

pub fn getNativeHandles(_: *MacOSWindow) shared.NativeHandles {
    unreachable;
}

pub fn getSize(self: *MacOSWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(_: *MacOSWindow) bool {
    return false;
}

pub fn getNewSize(self: *MacOSWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn clearResize(_: *MacOSWindow) void {}

pub fn getMousePosition(self: *MacOSWindow) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *MacOSWindow) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *MacOSWindow, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *MacOSWindow) std.EnumSet(Key) {
    return self.keys_pressed;
}
