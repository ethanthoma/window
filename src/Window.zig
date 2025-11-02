const std = @import("std");

const Window = @This();

const Display = @import("wayland/Display.zig");
const Registry = @import("wayland/Registry.zig");
const Surface = @import("wayland/Surface.zig");
const XdgSurface = @import("wayland/XdgSurface.zig");
const XdgToplevel = @import("wayland/XdgToplevel.zig");

const wl_shm = Registry.wl_shm;
const wl_shm_pool = extern struct {};
const wl_buffer = extern struct {};

extern "c" fn wl_shm_create_pool_wrapper(*wl_shm, i32, i32) ?*wl_shm_pool;
extern "c" fn wl_shm_pool_create_buffer_wrapper(*wl_shm_pool, i32, i32, i32, i32, u32) ?*wl_buffer;
extern "c" fn wl_shm_pool_destroy_wrapper(*wl_shm_pool) void;
extern "c" fn wl_surface_attach_wrapper(*Surface.wl_surface, *wl_buffer, i32, i32) void;
extern "c" fn wl_buffer_destroy_wrapper(*wl_buffer) void;

display: Display,
registry: Registry,
surface: Surface,
xdg_surface: XdgSurface,
xdg_toplevel: XdgToplevel,
buffer: ?*wl_buffer = null,
shm_pool: ?*wl_shm_pool = null,
shm_fd: i32 = -1,

pub fn init(title: [*:0]const u8, width: i32, height: i32) !*Window {
    const allocator = std.heap.c_allocator;
    const display = try Display.connect(null);
    errdefer display.disconnect();

    const reg = try display.getRegistry();
    var registry = Registry.init(reg);
    errdefer registry.destroy();

    try registry.addListener();
    try display.roundtrip();

    try registry.setupXdgWmBase();

    const compositor = registry.globals.compositor orelse return error.CompositorNotFound;
    const xdg_wm_base = registry.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound;
    const shm = registry.globals.shm orelse return error.ShmNotFound;

    var surface = try Surface.init(compositor);
    errdefer surface.deinit();

    const xdg_surface = try XdgSurface.init(xdg_wm_base, surface.surface);
    const xdg_toplevel = try XdgToplevel.init(xdg_surface.handle);

    const stride = width * 4;
    const size = stride * height;

    const shm_fd = try std.posix.memfd_create("wl_shm", 0);
    errdefer std.posix.close(shm_fd);

    try std.posix.ftruncate(shm_fd, @intCast(size));

    const pool = wl_shm_create_pool_wrapper(shm, shm_fd, size) orelse return error.ShmPoolCreationFailed;
    errdefer wl_shm_pool_destroy_wrapper(pool);

    const buffer = wl_shm_pool_create_buffer_wrapper(pool, 0, width, height, stride, 0) orelse return error.BufferCreationFailed;
    errdefer wl_buffer_destroy_wrapper(buffer);

    const window = try allocator.create(Window);
    window.* = Window{
        .display = display,
        .registry = registry,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .xdg_toplevel = xdg_toplevel,
        .buffer = buffer,
        .shm_pool = pool,
        .shm_fd = shm_fd,
    };

    try window.xdg_surface.addListener(window);
    try window.xdg_toplevel.addListener(window);

    window.xdg_toplevel.setTitle(title);
    window.xdg_toplevel.setAppId("zig-wayland-window");

    window.surface.commit();

    while (!window.xdg_surface.configured) {
        try window.display.dispatch();
    }

    wl_surface_attach_wrapper(window.surface.surface, buffer, 0, 0);
    window.surface.damage(0, 0, width, height);
    window.surface.commit();
    try window.display.roundtrip();

    return window;
}

pub fn deinit(self: *Window) void {
    if (self.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    if (self.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);
    if (self.shm_fd >= 0) std.posix.close(self.shm_fd);
    self.xdg_toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.deinit();
    self.registry.destroy();
    self.display.disconnect();

    const allocator = std.heap.c_allocator;
    allocator.destroy(self);
}

pub fn shouldClose(self: Window) bool {
    return self.xdg_toplevel.should_close;
}

pub fn pollEvents(self: *Window) !void {
    try self.display.roundtrip();
}

test "window creation and basic lifecycle" {
    const window = Window.init("Test Window", 800, 600) catch return error.SkipZigTest;
    defer window.deinit();

    try std.testing.expect(!window.shouldClose());
    try std.testing.expect(window.xdg_surface.configured);
}
