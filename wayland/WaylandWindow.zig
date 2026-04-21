const std = @import("std");
const builtin = @import("builtin");

const Window = @This();

pub const InitOptions = struct {
    /// When true, create and manage a wl_shm buffer for CPU rendering.
    /// Set to false when an external API (e.g. WebGPU/Vulkan) will manage buffers.
    use_shm_buffer: bool = true,
    enable_input: bool = true,
    create_egl_window: bool = false,
};

pub const Key = @import("../key.zig").Key;
pub const MouseButton = @import("Pointer.zig").MouseButton;

const backend = switch (builtin.os.tag) {
    .linux => struct {
        pub const Display = @import("Display.zig");
        pub const Registry = @import("Registry.zig");
        pub const Surface = @import("Surface.zig");
        pub const XdgSurface = @import("XdgSurface.zig");
        pub const XdgToplevel = @import("XdgToplevel.zig");
        pub const Keyboard = @import("Keyboard.zig");
        pub const Pointer = @import("Pointer.zig");
    },
    else => @compileError("Unsupported platform: only Wayland (Linux) is currently supported"),
};

const Display = backend.Display;
const Registry = backend.Registry;
const Surface = backend.Surface;
const XdgSurface = backend.XdgSurface;
const XdgToplevel = backend.XdgToplevel;
const Keyboard = backend.Keyboard;
const Pointer = backend.Pointer;

const wl_shm = Registry.wl_shm;
const wl_shm_pool = extern struct {};
const wl_buffer = extern struct {};
const wl_egl_window = extern struct {};

extern "c" fn wl_shm_create_pool_wrapper(*wl_shm, i32, i32) ?*wl_shm_pool;
extern "c" fn wl_shm_pool_create_buffer_wrapper(*wl_shm_pool, i32, i32, i32, i32, u32) ?*wl_buffer;
extern "c" fn wl_shm_pool_destroy_wrapper(*wl_shm_pool) void;
extern "c" fn wl_surface_attach_wrapper(*Surface.wl_surface, *wl_buffer, i32, i32) void;
extern "c" fn wl_buffer_destroy_wrapper(*wl_buffer) void;
extern "c" fn wl_egl_window_create_wrapper(*Surface.wl_surface, i32, i32) ?*wl_egl_window;
extern "c" fn wl_egl_window_destroy_wrapper(*wl_egl_window) void;
extern "c" fn wl_egl_window_resize_wrapper(*wl_egl_window, i32, i32, i32, i32) void;

pub const Event = union(enum) {
    close,
    configure: struct {
        width: i32,
        height: i32,
    },
    key_press: Key,
    key_release: Key,
    mouse_enter: struct {
        x: f64,
        y: f64,
    },
    mouse_leave,
    mouse_motion: struct {
        x: f64,
        y: f64,
    },
    mouse_button_press: MouseButton,
    mouse_button_release: MouseButton,
    mouse_scroll: struct {
        x: f64,
        y: f64,
    },
};

const EventQueue = struct {
    events: [128]Event = undefined,
    len: usize = 0,

    fn append(self: *EventQueue, event: Event) !void {
        if (self.len >= self.events.len) return error.QueueFull;
        self.events[self.len] = event;
        self.len += 1;
    }

    fn get(self: EventQueue, index: usize) Event {
        return self.events[index];
    }

    fn clear(self: *EventQueue) void {
        self.len = 0;
    }
};

display: Display,
registry: Registry,
surface: Surface,
xdg_surface: XdgSurface,
xdg_toplevel: XdgToplevel,
keyboard: ?Keyboard = null,
pointer: ?Pointer = null,
width: i32,
height: i32,
buffer: ?*wl_buffer = null,
shm_pool: ?*wl_shm_pool = null,
shm_fd: i32 = -1,
use_shm_buffer: bool = true,
egl_window: ?*wl_egl_window = null,
event_queue: EventQueue,
event_index: usize = 0,

pub fn getWaylandDisplay(self: *Window) *anyopaque {
    return @ptrCast(self.display.display);
}

pub fn getWaylandSurface(self: *Window) *anyopaque {
    return @ptrCast(self.surface.surface);
}

pub fn getWaylandCompositor(self: *Window) ?*Registry.wl_compositor {
    return self.registry.globals.compositor;
}

pub fn getXdgWmBase(self: *Window) ?*Registry.xdg_wm_base {
    return self.registry.globals.xdg_wm_base;
}

pub fn init(
    title: [*:0]const u8,
    width: i32,
    height: i32,
) !Window {
    return initWithOptions(title, width, height, .{});
}

pub fn initWithOptions(
    title: [*:0]const u8,
    width: i32,
    height: i32,
    options: InitOptions,
) !Window {
    const display = try Display.connect(null);
    errdefer display.disconnect();

    const reg = try display.getRegistry();

    var window = Window{
        .display = display,
        .registry = Registry.init(reg),
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .keyboard = null,
        .pointer = null,
        .width = width,
        .height = height,
        .buffer = null,
        .shm_pool = null,
        .shm_fd = -1,
        .use_shm_buffer = options.use_shm_buffer,
        .event_queue = .{},
        .event_index = 0,
    };

    errdefer window.registry.destroy();

    try window.registry.addListener();
    try window.display.roundtrip();
    try window.registry.setupXdgWmBase();

    const compositor = window.registry.globals.compositor orelse return error.CompositorNotFound;
    const xdg_wm_base = window.registry.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound;

    if (options.enable_input) {
        const seat = window.registry.globals.seat orelse return error.SeatNotFound;
        window.keyboard = try Keyboard.init(seat);
        errdefer if (window.keyboard) |*kb| kb.destroy();
        window.pointer = try Pointer.init(seat);
        errdefer if (window.pointer) |*ptr| ptr.destroy();
    }

    window.surface = try Surface.init(compositor);
    errdefer window.surface.deinit();
    window.surface.setOpaqueRegion(compositor, width, height);

    window.xdg_surface = try XdgSurface.init(xdg_wm_base, window.surface.surface);
    errdefer window.xdg_surface.destroy();

    window.xdg_toplevel = try XdgToplevel.init(window.xdg_surface.handle);
    errdefer window.xdg_toplevel.destroy();

    if (!window.use_shm_buffer and options.create_egl_window) {
        window.egl_window = wl_egl_window_create_wrapper(window.surface.surface, width, height) orelse return error.EglWindowCreationFailed;
    }

    if (window.use_shm_buffer) {
        const stride = width * 4;
        const size = stride * height;

        window.shm_fd = try std.posix.memfd_create("wl_shm", 0);
        errdefer if (window.shm_fd >= 0) std.posix.close(window.shm_fd);

        try std.posix.ftruncate(window.shm_fd, @intCast(size));

        const shm = window.registry.globals.shm orelse return error.ShmNotFound;
        window.shm_pool = wl_shm_create_pool_wrapper(shm, window.shm_fd, size) orelse return error.ShmPoolCreationFailed;
        errdefer if (window.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);

        window.buffer = wl_shm_pool_create_buffer_wrapper(window.shm_pool.?, 0, width, height, stride, 0) orelse return error.BufferCreationFailed;
        errdefer if (window.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    }

    window.xdg_toplevel.setTitle(title);
    window.xdg_toplevel.setAppId("zig-wayland-window");

    return window;
}

pub fn registerListeners(self: *Window) !void {
    try self.xdg_surface.addListener(self);
    try self.xdg_toplevel.addListener(self);
    if (self.keyboard) |*kb| try kb.addListener(self);
    if (self.pointer) |*ptr| try ptr.addListener(self);

    self.surface.commit();

    while (!self.xdg_surface.configured) {
        try self.display.dispatch();
    }

    if (self.use_shm_buffer) {
        if (self.buffer) |buf| {
            wl_surface_attach_wrapper(self.surface.surface, buf, 0, 0);
            self.surface.damage(0, 0, self.width, self.height);
            self.surface.commit();
            try self.display.roundtrip();
        } else if (self.registry.globals.shm) |shm| {
            const stride = @max(1, self.width) * 4;
            const height = @max(1, self.height);
            const size = stride * height;

            const fd = std.posix.memfd_create("wl_tmp", 0) catch null;
            if (fd) |tmp_fd| {
                if (std.posix.ftruncate(tmp_fd, @intCast(size))) |_| {
                    if (wl_shm_create_pool_wrapper(shm, tmp_fd, size)) |pool| {
                        if (wl_shm_pool_create_buffer_wrapper(pool, 0, self.width, self.height, stride, 0)) |buffer| {
                            self.shm_fd = tmp_fd;
                            self.shm_pool = pool;
                            self.buffer = buffer;
                            wl_surface_attach_wrapper(self.surface.surface, buffer, 0, 0);
                            self.surface.damage(0, 0, self.width, self.height);
                            self.surface.commit();
                            try self.display.roundtrip();
                            return;
                        } else {
                            wl_shm_pool_destroy_wrapper(pool);
                            std.posix.close(tmp_fd);
                        }
                    } else {
                        std.posix.close(tmp_fd);
                    }
                } else |_| {
                    std.posix.close(tmp_fd);
                }
            }

            self.surface.commit();
            try self.display.roundtrip();
        } else {
            self.surface.commit();
            try self.display.roundtrip();
        }
    } else {
        self.surface.commit();
        try self.display.roundtrip();
    }
}

pub fn deinit(self: *Window) void {
    if (self.keyboard) |kb| kb.destroy();
    if (self.pointer) |ptr| ptr.destroy();
    if (self.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    if (self.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);
    if (self.shm_fd >= 0) std.posix.close(self.shm_fd);
    if (self.egl_window) |egl| wl_egl_window_destroy_wrapper(egl);
    self.xdg_toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.deinit();
    self.registry.destroy();
    self.display.disconnect();
}

pub fn flush(self: *Window) !void {
    try self.display.flush();
}

pub fn resize(self: *Window, new_width: i32, new_height: i32) !void {
    if (new_width == self.width and new_height == self.height) return;
    if (new_width <= 0 or new_height <= 0) return;

    self.width = new_width;
    self.height = new_height;

    if (!self.use_shm_buffer) {
        if (self.egl_window) |egl| {
            wl_egl_window_resize_wrapper(egl, new_width, new_height, 0, 0);
        }
        return;
    }

    if (self.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    if (self.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);
    if (self.shm_fd >= 0) std.posix.close(self.shm_fd);

    const stride = new_width * 4;
    const size = stride * new_height;

    const shm_fd = try std.posix.memfd_create("wl_shm", 0);
    errdefer std.posix.close(shm_fd);

    try std.posix.ftruncate(shm_fd, @intCast(size));

    const shm = self.registry.globals.shm orelse return error.ShmNotFound;
    const pool = wl_shm_create_pool_wrapper(shm, shm_fd, size) orelse return error.ShmPoolCreationFailed;
    errdefer wl_shm_pool_destroy_wrapper(pool);

    const buffer = wl_shm_pool_create_buffer_wrapper(pool, 0, new_width, new_height, stride, 0) orelse return error.BufferCreationFailed;

    self.buffer = buffer;
    self.shm_pool = pool;
    self.shm_fd = shm_fd;

    wl_surface_attach_wrapper(self.surface.surface, buffer, 0, 0);
    self.surface.damage(0, 0, new_width, new_height);
    self.surface.commit();
}

pub fn pushEvent(self: *Window, event: Event) void {
    self.event_queue.append(event) catch {
        std.debug.print("Event queue full, dropping event\n", .{});
    };
}

pub fn pollEvent(self: *Window) !?Event {
    if (self.event_index >= self.event_queue.len) {
        self.event_queue.clear();
        self.event_index = 0;

        try self.display.dispatchPending();
        try self.display.flush();

        if (self.event_queue.len == 0) {
            self.display.prepareRead() catch {
                return null;
            };

            const fd = self.display.getFd();
            var pfd = [_]std.posix.pollfd{.{
                .fd = fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};

            const result = std.posix.poll(&pfd, 0) catch |err| {
                self.display.cancelRead();
                return err;
            };

            if (result > 0) {
                try self.display.readEvents();
                try self.display.dispatchPending();
            } else {
                self.display.cancelRead();
            }
        }

        if (self.event_queue.len == 0) return null;
    }

    const event = self.event_queue.get(self.event_index);
    self.event_index += 1;
    return event;
}
