const std = @import("std");
const shared = @import("shared.zig");
const Wayland = @import("wayland.zig");
const X11 = @import("x11.zig");
const Window = @import("Window.zig");

const LinuxWindow = @This();

backend: union(enum) {
    wayland: Wayland,
    x11: X11,
},

pub fn init(options: shared.InitOptions) !LinuxWindow {
    if (std.c.getenv("WAYLAND_DISPLAY")) |val| if (val[0] != 0) {
        return .{ .backend = .{ .wayland = try Wayland.init(options) } };
    };
    if (std.c.getenv("DISPLAY")) |_| {
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

pub fn pollEvents(self: *LinuxWindow, window: *Window) void {
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
