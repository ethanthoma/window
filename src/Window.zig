const std = @import("std");

pub const RGFW_Window = opaque {};
pub const wl_display = opaque {};
pub const wl_surface = opaque {};

pub const Rect = extern struct {
    x: c_int,
    y: c_int,
    width: c_uint,
    height: c_uint,
};

pub const Point = extern struct {
    x: c_int,
    y: c_int,
};

pub const WindowFlags = packed struct(c_ulonglong) {
    center: bool = false,
    _padding: u63 = 0,
};

pub const Event = extern struct {
    type: u8,
};

extern fn RGFW_createWindow(name: [*:0]const u8, rect: Rect, args: c_ulonglong) ?*RGFW_Window;
extern fn RGFW_window_close(win: *RGFW_Window) void;
extern fn RGFW_window_checkEvent(win: *RGFW_Window) ?*Event;
extern fn RGFW_getDisplay_Wayland() ?*wl_display;
extern fn RGFW_window_getWindow_Wayland(win: *RGFW_Window) ?*wl_surface;
extern fn RGFW_window_createSurface_WebGPU(win: *RGFW_Window, instance: ?*anyopaque) ?*anyopaque;

const Window = @This();

window: *RGFW_Window,

pub fn init(
    name: [*:0]const u8,
    pos: Point,
    size: Rect,
    flags: WindowFlags,
) !Window {
    const rect = Rect{
        .x = pos.x,
        .y = pos.y,
        .width = size.width,
        .height = size.height,
    };

    const window = RGFW_createWindow(name, rect, @bitCast(flags)) orelse return error.WindowCreationFailed;

    return .{ .window = window };
}

pub fn deinit(self: Window) void {
    RGFW_window_close(self.window);
}

pub fn getEvent(self: *Window) ?*Event {
    return RGFW_window_checkEvent(self.window);
}

pub fn getWaylandDisplay() ?*wl_display {
    return RGFW_getDisplay_Wayland();
}

pub fn getWaylandSurface(self: *Window) ?*wl_surface {
    return RGFW_window_getWindow_Wayland(self.window);
}

pub fn createSurfaceWebGPU(self: *Window, wgpu_instance: ?*anyopaque) ?*anyopaque {
    return RGFW_window_createSurface_WebGPU(self.window, wgpu_instance);
}
