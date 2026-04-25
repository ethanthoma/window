const std = @import("std");
const shared = @import("shared.zig");
const Wayland = @import("wayland.zig");
const X11 = @import("x11.zig");
const Key = @import("key.zig").Key;

const LinuxWindow = @This();

backend: union(enum) {
    wayland: Wayland,
    x11: X11,
},

pub fn init(options: shared.InitOptions) !LinuxWindow {
    if (std.posix.getenv("WAYLAND_DISPLAY")) |val| if (val.len != 0) {
        return .{ .backend = .{ .wayland = try Wayland.init(options) } };
    };
    if (std.posix.getenv("DISPLAY")) |_| {
        return .{ .backend = .{ .x11 = try X11.init(options) } };
    }
    return error.NoDisplayServerFound;
}

pub fn start(self: *LinuxWindow) !void {
    switch (self.backend) {
        inline else => |*b| try b.start(),
    }
}

pub fn deinit(self: *LinuxWindow) void {
    switch (self.backend) {
        inline else => |*b| b.deinit(),
    }
}

pub fn show(self: *LinuxWindow) void {
    switch (self.backend) {
        inline else => |*b| b.show(),
    }
}

pub fn shouldClose(self: *LinuxWindow) bool {
    return switch (self.backend) {
        inline else => |*b| b.shouldClose(),
    };
}

pub fn pollEvents(self: *LinuxWindow, window: anytype) void {
    switch (self.backend) {
        inline else => |*b| b.pollEvents(window),
    }
}

pub fn getNativeHandles(self: *LinuxWindow) shared.NativeHandles {
    return switch (self.backend) {
        inline else => |*b| b.getNativeHandles(),
    };
}

pub fn getSize(self: *LinuxWindow) shared.Size {
    return switch (self.backend) {
        inline else => |*b| b.getSize(),
    };
}

pub fn needsResize(self: *LinuxWindow) bool {
    return switch (self.backend) {
        inline else => |*b| b.needsResize(),
    };
}

pub fn getNewSize(self: *LinuxWindow) shared.Size {
    return switch (self.backend) {
        inline else => |*b| b.getNewSize(),
    };
}

pub fn clearResize(self: *LinuxWindow) void {
    switch (self.backend) {
        inline else => |*b| b.clearResize(),
    }
}

pub fn getMousePosition(self: *LinuxWindow) shared.MousePosition {
    return switch (self.backend) {
        inline else => |*b| b.getMousePosition(),
    };
}

pub fn getMouseButtons(self: *LinuxWindow) u8 {
    return switch (self.backend) {
        inline else => |*b| b.getMouseButtons(),
    };
}

pub fn isKeyPressed(self: *LinuxWindow, key: Key) bool {
    return switch (self.backend) {
        inline else => |*b| b.isKeyPressed(key),
    };
}

pub fn getKeysPressed(self: *LinuxWindow) std.EnumSet(Key) {
    return switch (self.backend) {
        inline else => |*b| b.getKeysPressed(),
    };
}
