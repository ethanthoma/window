const std = @import("std");

const Registry = @This();

const Display = @import("Display.zig");
const wl_registry = Display.wl_registry;

pub const wl_compositor = extern struct {};
pub const wl_seat = extern struct {};
pub const wl_shm = extern struct {};
pub const xdg_wm_base = extern struct {};
const wl_proxy = extern struct {};

const wl_interface = extern struct {
    name: [*:0]const u8,
    version: i32,
    method_count: i32,
    methods: ?*const wl_message,
    event_count: i32,
    events: ?*const wl_message,
};

const wl_message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: ?*const ?*const wl_interface,
};

const wl_registry_listener = extern struct {
    global: ?*const fn (?*anyopaque, ?*wl_registry, u32, [*c]const u8, u32) callconv(.c) void,
    global_remove: ?*const fn (?*anyopaque, ?*wl_registry, u32) callconv(.c) void,
};

const xdg_wm_base_listener = extern struct {
    ping: ?*const fn (?*anyopaque, ?*xdg_wm_base, u32) callconv(.c) void,
};

extern "c" fn wl_registry_add_listener_wrapper(*wl_registry, *const wl_registry_listener, ?*anyopaque) i32;
extern "c" fn wl_registry_bind_wrapper(*wl_registry, u32, *const wl_interface, u32) ?*anyopaque;
extern "c" fn xdg_wm_base_add_listener_wrapper(*xdg_wm_base, *const xdg_wm_base_listener, ?*anyopaque) i32;
extern "c" fn xdg_wm_base_pong_wrapper(*xdg_wm_base, u32) void;
extern "c" fn wl_proxy_destroy(*wl_proxy) void;

extern "c" var wl_compositor_interface: wl_interface;
extern "c" var wl_seat_interface: wl_interface;
extern "c" var wl_shm_interface: wl_interface;
extern "c" var xdg_wm_base_interface: wl_interface;

pub const Globals = struct {
    compositor: ?*wl_compositor = null,
    seat: ?*wl_seat = null,
    shm: ?*wl_shm = null,
    xdg_wm_base: ?*xdg_wm_base = null,
};

registry: *wl_registry,
globals: Globals = .{},

const registry_listener = wl_registry_listener{
    .global = handleGlobal,
    .global_remove = handleGlobalRemove,
};

const xdg_wm_base_listener_impl = xdg_wm_base_listener{
    .ping = handleXdgWmBasePing,
};

pub fn init(registry: *wl_registry) Registry {
    return .{ .registry = registry };
}

pub fn addListener(self: *Registry) !void {
    const result = wl_registry_add_listener_wrapper(self.registry, &registry_listener, self);
    if (result < 0) return error.ListenerFailed;
}

pub fn setupXdgWmBase(self: *Registry) !void {
    const xdg_wm_base_obj = self.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound;

    const result = xdg_wm_base_add_listener_wrapper(xdg_wm_base_obj, &xdg_wm_base_listener_impl, xdg_wm_base_obj);
    if (result < 0) return error.ListenerFailed;
}

fn handleGlobal(
    data: ?*anyopaque,
    registry: ?*wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self: *Registry = @ptrCast(@alignCast(data.?));
    const iface = std.mem.span(interface);

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        const desired_version = if (version < 4) version else 4;
        const proxy = wl_registry_bind_wrapper(
            registry.?,
            name,
            &wl_compositor_interface,
            desired_version,
        ) orelse return;
        self.globals.compositor = @ptrCast(proxy);
    } else if (std.mem.eql(u8, iface, "wl_seat")) {
        const iface_version: u32 = @as(u32, @intCast(wl_seat_interface.version));
        const desired_version = if (version < iface_version) version else iface_version;
        const proxy = wl_registry_bind_wrapper(
            registry.?,
            name,
            &wl_seat_interface,
            desired_version,
        ) orelse return;
        self.globals.seat = @ptrCast(proxy);
    } else if (std.mem.eql(u8, iface, "wl_shm")) {
        const iface_version: u32 = @as(u32, @intCast(wl_shm_interface.version));
        const desired_version = if (version < iface_version) version else iface_version;
        const proxy = wl_registry_bind_wrapper(
            registry.?,
            name,
            &wl_shm_interface,
            desired_version,
        ) orelse return;
        self.globals.shm = @ptrCast(proxy);
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        const desired_version = if (version < 1) version else 1;
        const proxy = wl_registry_bind_wrapper(
            registry.?,
            name,
            &xdg_wm_base_interface,
            desired_version,
        ) orelse return;
        self.globals.xdg_wm_base = @ptrCast(proxy);
    }
}

fn handleGlobalRemove(
    _: ?*anyopaque,
    _: ?*wl_registry,
    _: u32,
) callconv(.c) void {}

fn handleXdgWmBasePing(
    data: ?*anyopaque,
    xdg_wm_base_obj: ?*xdg_wm_base,
    serial: u32,
) callconv(.c) void {
    _ = data;
    if (xdg_wm_base_obj) |wm_base| {
        xdg_wm_base_pong_wrapper(wm_base, serial);
    }
}

pub fn destroy(self: Registry) void {
    if (self.globals.compositor) |comp| wl_proxy_destroy(@ptrCast(comp));
    if (self.globals.seat) |seat| wl_proxy_destroy(@ptrCast(seat));
    if (self.globals.shm) |shm| wl_proxy_destroy(@ptrCast(shm));
    if (self.globals.xdg_wm_base) |xdg| wl_proxy_destroy(@ptrCast(xdg));
    wl_proxy_destroy(@ptrCast(self.registry));
}

test "registry init and bind globals" {
    const display = Display.connect(null) catch return error.SkipZigTest;
    defer display.disconnect();

    const reg = try display.getRegistry();
    var registry = Registry.init(reg);
    defer registry.destroy();

    try registry.addListener();
    try display.roundtrip();

    try std.testing.expect(registry.globals.compositor != null);
}
