const std = @import("std");

const XdgSurface = @This();

const Registry = @import("Registry.zig");
const Surface = @import("Surface.zig");
const xdg_wm_base = Registry.xdg_wm_base;
const wl_surface = Surface.wl_surface;

pub const xdg_surface = extern struct {};

const xdg_surface_listener = extern struct {
    configure: ?*const fn (?*anyopaque, ?*xdg_surface, u32) callconv(.c) void,
};

extern "c" fn xdg_wm_base_get_xdg_surface_wrapper(*xdg_wm_base, *wl_surface) ?*xdg_surface;
extern "c" fn xdg_surface_add_listener_wrapper(*xdg_surface, *const xdg_surface_listener, ?*anyopaque) i32;
extern "c" fn xdg_surface_destroy_wrapper(*xdg_surface) void;
extern "c" fn xdg_surface_ack_configure_wrapper(*xdg_surface, u32) void;

handle: *xdg_surface,
configured: bool = false,
last_serial: u32 = 0,

pub fn init(wm_base: *xdg_wm_base, surface: *wl_surface) !XdgSurface {
    const xdg_surf = xdg_wm_base_get_xdg_surface_wrapper(wm_base, surface) orelse return error.XdgSurfaceCreationFailed;
    return .{ .handle = xdg_surf };
}

pub fn addListener(self: *XdgSurface, user_data: ?*anyopaque) !void {
    const listener = xdg_surface_listener{
        .configure = handleConfigure,
    };

    const result = xdg_surface_add_listener_wrapper(self.handle, &listener, user_data);
    if (result < 0) return error.ListenerFailed;
}

pub fn ackConfigure(self: *XdgSurface) void {
    xdg_surface_ack_configure_wrapper(self.handle, self.last_serial);
}

pub fn destroy(self: XdgSurface) void {
    xdg_surface_destroy_wrapper(self.handle);
}

fn handleConfigure(
    data: ?*anyopaque,
    _: ?*xdg_surface,
    serial: u32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));
    window.xdg_surface.last_serial = serial;
    window.xdg_surface.configured = true;
    window.xdg_surface.ackConfigure();
}
