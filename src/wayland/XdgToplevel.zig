const std = @import("std");

const XdgToplevel = @This();

const XdgSurface = @import("XdgSurface.zig");
const xdg_surface = XdgSurface.xdg_surface;

const xdg_toplevel = extern struct {};
const wl_array = extern struct {};

const xdg_toplevel_listener = extern struct {
    configure: ?*const fn (?*anyopaque, ?*xdg_toplevel, i32, i32, ?*wl_array) callconv(.c) void,
    close: ?*const fn (?*anyopaque, ?*xdg_toplevel) callconv(.c) void,
    configure_bounds: ?*const fn (?*anyopaque, ?*xdg_toplevel, i32, i32) callconv(.c) void,
    wm_capabilities: ?*const fn (?*anyopaque, ?*xdg_toplevel, ?*wl_array) callconv(.c) void,
};

extern "c" fn xdg_surface_get_toplevel_wrapper(*xdg_surface) ?*xdg_toplevel;
extern "c" fn xdg_toplevel_add_listener_wrapper(*xdg_toplevel, *const xdg_toplevel_listener, ?*anyopaque) i32;
extern "c" fn xdg_toplevel_destroy_wrapper(*xdg_toplevel) void;
extern "c" fn xdg_toplevel_set_title_wrapper(*xdg_toplevel, [*:0]const u8) void;
extern "c" fn xdg_toplevel_set_app_id_wrapper(*xdg_toplevel, [*:0]const u8) void;

toplevel: *xdg_toplevel,
width: i32 = 0,
height: i32 = 0,
should_close: bool = false,

pub fn init(xdg_surf: *xdg_surface) !XdgToplevel {
    const toplevel = xdg_surface_get_toplevel_wrapper(xdg_surf) orelse return error.ToplevelCreationFailed;
    return .{ .toplevel = toplevel };
}

pub fn addListener(self: *XdgToplevel, user_data: ?*anyopaque) !void {
    const listener = xdg_toplevel_listener{
        .configure = handleConfigure,
        .close = handleClose,
        .configure_bounds = handleConfigureBounds,
        .wm_capabilities = handleWmCapabilities,
    };

    const result = xdg_toplevel_add_listener_wrapper(self.toplevel, &listener, user_data);
    if (result < 0) return error.ListenerFailed;
}

pub fn setTitle(self: XdgToplevel, title: [*:0]const u8) void {
    xdg_toplevel_set_title_wrapper(self.toplevel, title);
}

pub fn setAppId(self: XdgToplevel, app_id: [*:0]const u8) void {
    xdg_toplevel_set_app_id_wrapper(self.toplevel, app_id);
}

pub fn destroy(self: XdgToplevel) void {
    xdg_toplevel_destroy_wrapper(self.toplevel);
}

fn handleConfigure(
    data: ?*anyopaque,
    _: ?*xdg_toplevel,
    width: i32,
    height: i32,
    _: ?*wl_array,
) callconv(.c) void {
    const Window = @import("../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    if (width > 0) window.xdg_toplevel.width = width;
    if (height > 0) window.xdg_toplevel.height = height;

    if (width > 0 or height > 0) {
        window.pushEvent(.{
            .configure = .{
                .width = if (width > 0) width else window.xdg_toplevel.width,
                .height = if (height > 0) height else window.xdg_toplevel.height,
            },
        });
    }
}

fn handleClose(
    data: ?*anyopaque,
    _: ?*xdg_toplevel,
) callconv(.c) void {
    const Window = @import("../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));
    window.xdg_toplevel.should_close = true;
    window.pushEvent(.close);
}

fn handleConfigureBounds(
    _: ?*anyopaque,
    _: ?*xdg_toplevel,
    _: i32,
    _: i32,
) callconv(.c) void {}

fn handleWmCapabilities(
    _: ?*anyopaque,
    _: ?*xdg_toplevel,
    _: ?*wl_array,
) callconv(.c) void {}
