const std = @import("std");

const Surface = @This();

const Registry = @import("Registry.zig");
const wl_compositor = Registry.wl_compositor;

const wl_callback = extern struct {};
pub const wl_surface = extern struct {};

surface: *wl_surface,
frame_callback: ?*wl_callback = null,

extern "c" fn wl_compositor_create_surface_wrapper(*wl_compositor) ?*wl_surface;
pub fn init(compositor: *wl_compositor) !Surface {
    const surface = wl_compositor_create_surface_wrapper(compositor) orelse return error.SurfaceCreationFailed;
    return .{ .surface = surface };
}

const wl_callback_listener = extern struct {
    done: ?*const fn (?*anyopaque, ?*wl_callback, u32) callconv(.c) void,
};
extern "c" fn wl_callback_destroy_wrapper(*wl_callback) void;
extern "c" fn wl_surface_destroy_wrapper(*wl_surface) void;
pub fn deinit(self: *Surface) void {
    if (self.frame_callback) |cb| wl_callback_destroy_wrapper(cb);
    wl_surface_destroy_wrapper(self.surface);
}

extern "c" fn wl_surface_commit_wrapper(*wl_surface) void;
pub fn commit(self: Surface) void {
    wl_surface_commit_wrapper(self.surface);
}

extern "c" fn wl_surface_damage_wrapper(*wl_surface, i32, i32, i32, i32) void;
pub fn damage(self: Surface, x: i32, y: i32, width: i32, height: i32) void {
    wl_surface_damage_wrapper(self.surface, x, y, width, height);
}

extern "c" fn wl_surface_frame_wrapper(*wl_surface) ?*wl_callback;
extern "c" fn wl_callback_add_listener_wrapper(*wl_callback, *const wl_callback_listener, ?*anyopaque) i32;
pub fn requestFrame(self: *Surface, listener: *const wl_callback_listener, data: ?*anyopaque) !void {
    if (self.frame_callback) |cb| wl_callback_destroy_wrapper(cb);

    self.frame_callback = wl_surface_frame_wrapper(self.surface) orelse return error.FrameCallbackFailed;
    const result = wl_callback_add_listener_wrapper(self.frame_callback.?, listener, data);
    if (result < 0) return error.ListenerFailed;
}

test "surface creation and destruction" {
    const Display = @import("Display.zig");

    const display = Display.connect(null) catch return error.SkipZigTest;
    defer display.disconnect();

    const wl_registry = try display.getRegistry();
    var registry = Registry.init(wl_registry);
    defer registry.destroy();

    try registry.addListener();
    try display.roundtrip();

    const compositor = registry.globals.compositor orelse return error.CompositorNotFound;
    var surface = try Surface.init(compositor);
    defer surface.deinit();

    surface.damage(0, 0, 100, 100);
    surface.commit();

    try display.roundtrip();
}

test "surface frame callback" {
    const Display = @import("Display.zig");

    const display = Display.connect(null) catch return error.SkipZigTest;
    defer display.disconnect();

    const wl_registry = try display.getRegistry();
    var registry = Registry.init(wl_registry);
    defer registry.destroy();

    try registry.addListener();
    try display.roundtrip();

    const compositor = registry.globals.compositor orelse return error.CompositorNotFound;
    var surface = try Surface.init(compositor);
    defer surface.deinit();

    var frame_done = false;
    const listener = wl_callback_listener{
        .done = struct {
            fn callback(data: ?*anyopaque, _: ?*wl_callback, _: u32) callconv(.c) void {
                const done_ptr: *bool = @ptrCast(@alignCast(data));
                done_ptr.* = true;
            }
        }.callback,
    };

    try surface.requestFrame(&listener, &frame_done);
    surface.commit();

    try display.dispatch();
}
