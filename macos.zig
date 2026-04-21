const std = @import("std");
const shared = @import("shared.zig");

const MacOSWindow = @This();

// TODO: Implement native macOS backend using Cocoa/AppKit
// For now, macOS builds are not supported
// GLFW has been removed - need to implement Cocoa/AppKit backend

width: u32 = 0,
height: u32 = 0,

pub fn init(options: shared.InitOptions) !MacOSWindow {
    _ = options;
    return error.MacOSNotImplemented;
}

pub fn deinit(self: *MacOSWindow) void {
    _ = self;
}

pub fn shouldClose(self: *MacOSWindow) bool {
    _ = self;
    return true;
}

pub fn pollEvents(self: *MacOSWindow) void {
    _ = self;
}

pub fn getNativeHandles(self: *MacOSWindow) shared.NativeHandles {
    _ = self;
    unreachable;
}

pub fn getSize(self: *MacOSWindow) shared.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

pub fn needsResize(self: *MacOSWindow) bool {
    _ = self;
    return false;
}

pub fn getNewSize(self: *MacOSWindow) shared.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

pub fn clearResize(self: *MacOSWindow) void {
    _ = self;
}
