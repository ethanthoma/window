const std = @import("std");
const shared = @import("shared.zig");

const WindowsWindow = @This();

// TODO: Implement native Windows backend
// For now, Windows builds are not supported
// GLFW has been removed - need to implement Win32 API backend

width: u32 = 0,
height: u32 = 0,

pub fn init(options: shared.InitOptions) !WindowsWindow {
    _ = options;
    return error.WindowsNotImplemented;
}

pub fn deinit(self: *WindowsWindow) void {
    _ = self;
}

pub fn shouldClose(self: *WindowsWindow) bool {
    _ = self;
    return true;
}

pub fn pollEvents(self: *WindowsWindow) void {
    _ = self;
}

pub fn getNativeHandles(self: *WindowsWindow) shared.NativeHandles {
    _ = self;
    unreachable;
}

pub fn getSize(self: *WindowsWindow) shared.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

pub fn needsResize(self: *WindowsWindow) bool {
    _ = self;
    return false;
}

pub fn getNewSize(self: *WindowsWindow) shared.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

pub fn clearResize(self: *WindowsWindow) void {
    _ = self;
}
