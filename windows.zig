const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const Window = @import("Window.zig");

const WindowsWindow = @This();

width: u32 = 0,
height: u32 = 0,
mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: u8 = 0,
keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

pub fn init(_: shared.InitOptions) !WindowsWindow {
    return error.WindowsNotImplemented;
}

pub fn start(_: *WindowsWindow) !void {}
pub fn deinit(_: *WindowsWindow) void {}
pub fn show(_: *WindowsWindow) void {}

pub fn shouldClose(_: *WindowsWindow) bool {
    return true;
}

pub fn pollEvents(_: *WindowsWindow, _: *Window) void {}

pub fn getNativeHandles(_: *WindowsWindow) shared.NativeHandles {
    unreachable;
}

pub fn getSize(self: *WindowsWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(_: *WindowsWindow) bool {
    return false;
}

pub fn getNewSize(self: *WindowsWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn clearResize(_: *WindowsWindow) void {}

pub fn getMousePosition(self: *WindowsWindow) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *WindowsWindow) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *WindowsWindow, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *WindowsWindow) std.EnumSet(Key) {
    return self.keys_pressed;
}
