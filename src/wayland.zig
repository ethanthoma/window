const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;
const Window = @import("Window.zig");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const Wayland = @This();

const XKB_KEYMAP_FORMAT_TEXT_V1: u32 = 1;

const CXkbContext = opaque {};
const CXkbKeymap = opaque {};
const CXkbState = opaque {};

extern "c" fn xkb_context_new(flags: u32) ?*CXkbContext;
extern "c" fn xkb_context_unref(*CXkbContext) void;
extern "c" fn xkb_keymap_new_from_string(*CXkbContext, [*:0]const u8, format: u32, flags: u32) ?*CXkbKeymap;
extern "c" fn xkb_keymap_unref(*CXkbKeymap) void;
extern "c" fn xkb_state_new(*CXkbKeymap) ?*CXkbState;
extern "c" fn xkb_state_unref(*CXkbState) void;
extern "c" fn xkb_state_key_get_one_sym(*CXkbState, u32) u32;
extern "c" fn xkb_state_update_mask(*CXkbState, u32, u32, u32, u32, u32, u32) u32;

pub const PointerButton = enum(u32) {
    left = 0x110,
    right = 0x111,
    middle = 0x112,
    back = 0x113,
    forward = 0x114,
    _,
};

display: *wl.Display,
registry: *wl.Registry,
compositor: *wl.Compositor,
shm: *wl.Shm,
seat: *wl.Seat,
wm_base: *xdg.WmBase,
surface: *wl.Surface,
xdg_surface: *xdg.Surface,
xdg_toplevel: *xdg.Toplevel,
keyboard: ?*wl.Keyboard = null,
pointer: ?*wl.Pointer = null,

cursor_theme: ?*wl.CursorTheme = null,
cursor_surface: ?*wl.Surface = null,
cursor_image: ?*wl.CursorImage = null,

xkb_context: ?*CXkbContext = null,
xkb_keymap: ?*CXkbKeymap = null,
xkb_state: ?*CXkbState = null,

window: ?*Window = null,

configured: bool = false,
last_configure_serial: u32 = 0,

width: u32,
height: u32,
pending_width: u32 = 0,
pending_height: u32 = 0,
pending_resize: bool = false,

pointer_x: f64 = 0,
pointer_y: f64 = 0,

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    seat: ?*wl.Seat = null,
    wm_base: ?*xdg.WmBase = null,
};

const CURSOR_SIZE: i32 = 24;

pub fn init(options: shared.InitOptions) !Wayland {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();

    const registry = try display.getRegistry();
    errdefer registry.destroy();

    var globals: Globals = .{};
    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const compositor = globals.compositor orelse return error.CompositorNotFound;
    errdefer compositor.destroy();
    const shm = globals.shm orelse return error.ShmNotFound;
    errdefer shm.destroy();
    const seat = globals.seat orelse return error.SeatNotFound;
    errdefer seat.destroy();
    const wm_base = globals.wm_base orelse return error.XdgWmBaseNotFound;
    errdefer wm_base.destroy();

    const keyboard = seat.getKeyboard() catch null;
    errdefer if (keyboard) |kb| kb.destroy();
    const pointer = seat.getPointer() catch null;
    errdefer if (pointer) |p| p.destroy();

    const xkb_context = xkb_context_new(0);
    errdefer if (xkb_context) |c| xkb_context_unref(c);

    const surface = try compositor.createSurface();
    errdefer surface.destroy();

    if (compositor.createRegion()) |region| {
        defer region.destroy();
        region.add(0, 0, @intCast(options.width), @intCast(options.height));
        surface.setOpaqueRegion(region);
    } else |_| {}

    const xdg_surface = try wm_base.getXdgSurface(surface);
    errdefer xdg_surface.destroy();

    const xdg_toplevel = try xdg_surface.getToplevel();
    errdefer xdg_toplevel.destroy();

    xdg_toplevel.setTitle(options.title);
    xdg_toplevel.setAppId("zig-wayland-window");

    var cursor_theme: ?*wl.CursorTheme = null;
    var cursor_surface: ?*wl.Surface = null;
    var cursor_image: ?*wl.CursorImage = null;
    if (wl.CursorTheme.load(null, CURSOR_SIZE, shm)) |theme| {
        if (theme.getCursor("left_ptr")) |cursor| {
            if (cursor.image_count > 0) {
                cursor_theme = theme;
                cursor_image = cursor.images[0];
                cursor_surface = compositor.createSurface() catch null;
            } else {
                theme.destroy();
            }
        } else {
            theme.destroy();
        }
    } else |_| {}
    errdefer if (cursor_theme) |t| t.destroy();
    errdefer if (cursor_surface) |s| s.destroy();

    std.debug.print("Using native Wayland backend\n", .{});

    return .{
        .display = display,
        .registry = registry,
        .compositor = compositor,
        .shm = shm,
        .seat = seat,
        .wm_base = wm_base,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .xdg_toplevel = xdg_toplevel,
        .keyboard = keyboard,
        .pointer = pointer,
        .xkb_context = xkb_context,
        .cursor_theme = cursor_theme,
        .cursor_surface = cursor_surface,
        .cursor_image = cursor_image,
        .width = options.width,
        .height = options.height,
    };
}

pub fn start(self: *Wayland) !void {
    self.wm_base.setListener(*Wayland, wmBaseListener, self);
    self.xdg_surface.setListener(*Wayland, xdgSurfaceListener, self);
    self.xdg_toplevel.setListener(*Wayland, xdgToplevelListener, self);
    if (self.keyboard) |kb| kb.setListener(*Wayland, keyboardListener, self);
    if (self.pointer) |p| p.setListener(*Wayland, pointerListener, self);

    self.surface.commit();

    while (!self.configured) {
        if (self.display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }

    self.surface.commit();
    if (self.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    if (self.pending_resize) {
        self.pending_resize = false;
        self.width = self.pending_width;
        self.height = self.pending_height;
    }
}

pub fn deinit(self: *Wayland) void {
    if (self.xkb_state) |s| xkb_state_unref(s);
    if (self.xkb_keymap) |k| xkb_keymap_unref(k);
    if (self.xkb_context) |c| xkb_context_unref(c);
    if (self.cursor_surface) |s| s.destroy();
    if (self.cursor_theme) |t| t.destroy();
    if (self.keyboard) |kb| kb.destroy();
    if (self.pointer) |p| p.destroy();
    self.xdg_toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.destroy();
    self.wm_base.destroy();
    self.seat.destroy();
    self.shm.destroy();
    self.compositor.destroy();
    self.registry.destroy();
    self.display.disconnect();
}

pub fn show(_: *Wayland) void {}

pub fn pollEvents(self: *Wayland, window: *Window) void {
    self.window = window;
    defer self.window = null;

    if (self.display.dispatchPending() != .SUCCESS) return;
    if (self.display.flush() != .SUCCESS) return;

    if (self.display.prepareRead()) {
        var pfd = [_]std.posix.pollfd{.{
            .fd = self.display.getFd(),
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&pfd, 0) catch 0;
        if (ready > 0) {
            _ = self.display.readEvents();
        } else {
            self.display.cancelRead();
        }
        if (self.display.dispatchPending() != .SUCCESS) return;
    }

    if (self.pending_resize) {
        self.pending_resize = false;
        if (self.pending_width != self.width or self.pending_height != self.height) {
            self.width = self.pending_width;
            self.height = self.pending_height;
            window.pushEvent(.{ .resize = .{ .width = self.width, .height = self.height } });
        }
    }
}

pub fn getNativeHandles(self: *Wayland) shared.NativeHandles {
    return .{
        .wayland = .{
            .display = @ptrCast(self.display),
            .surface = @ptrCast(self.surface),
        },
    };
}

pub fn getSize(self: *Wayland) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |g| {
            if (std.mem.orderZ(u8, g.interface, wl.Compositor.interface.name) == .eq) {
                globals.compositor = registry.bind(g.name, wl.Compositor, @min(g.version, 4)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, wl.Shm.interface.name) == .eq) {
                globals.shm = registry.bind(g.name, wl.Shm, @min(g.version, 1)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, wl.Seat.interface.name) == .eq) {
                globals.seat = registry.bind(g.name, wl.Seat, @min(g.version, 7)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, xdg.WmBase.interface.name) == .eq) {
                globals.wm_base = registry.bind(g.name, xdg.WmBase, @min(g.version, 4)) catch return;
            }
        },
        .global_remove => {},
    }
}

fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: *Wayland) void {
    switch (event) {
        .ping => |p| wm_base.pong(p.serial),
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, self: *Wayland) void {
    switch (event) {
        .configure => |c| {
            self.last_configure_serial = c.serial;
            self.configured = true;
            xdg_surface.ackConfigure(c.serial);
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *Wayland) void {
    switch (event) {
        .configure => |c| {
            if (c.width <= 0 and c.height <= 0) return;
            self.pending_width = if (c.width > 0) @intCast(c.width) else self.width;
            self.pending_height = if (c.height > 0) @intCast(c.height) else self.height;
            self.pending_resize = true;
        },
        .close => if (self.window) |w| w.pushEvent(.close),
        .configure_bounds => {},
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, self: *Wayland) void {
    switch (event) {
        .keymap => |k| {
            defer _ = std.c.close(k.fd);
            if (k.format != .xkb_v1) return;

            const map_shm = std.posix.mmap(
                null,
                k.size,
                .{ .READ = true },
                .{ .TYPE = .PRIVATE },
                k.fd,
                0,
            ) catch return;
            defer std.posix.munmap(map_shm);

            const keymap_str: [*:0]const u8 = @ptrCast(map_shm.ptr);
            const ctx = self.xkb_context orelse return;
            const keymap = xkb_keymap_new_from_string(ctx, keymap_str, XKB_KEYMAP_FORMAT_TEXT_V1, 0) orelse return;

            if (self.xkb_keymap) |old| xkb_keymap_unref(old);
            self.xkb_keymap = keymap;

            const state = xkb_state_new(keymap) orelse return;
            if (self.xkb_state) |old| xkb_state_unref(old);
            self.xkb_state = state;
        },
        .key => |k| {
            const win = self.window orelse return;
            const xkb_st = self.xkb_state orelse return;
            const keysym = xkb_state_key_get_one_sym(xkb_st, k.key + 8);
            win.pushEvent(.{ .key = .{
                .key = Key.fromKeysym(keysym),
                .action = if (k.state == .pressed) .press else .release,
            } });
        },
        .modifiers => |m| {
            if (self.xkb_state) |state| {
                _ = xkb_state_update_mask(state, m.mods_depressed, m.mods_latched, m.mods_locked, 0, 0, m.group);
            }
        },
        .enter, .leave, .repeat_info => {},
    }
}

fn applyCursor(self: *Wayland, pointer: *wl.Pointer, serial: u32) void {
    const surface = self.cursor_surface orelse return;
    const image = self.cursor_image orelse return;
    const buffer = image.getBuffer() catch return;
    pointer.setCursor(serial, surface, @intCast(image.hotspot_x), @intCast(image.hotspot_y));
    surface.attach(buffer, 0, 0);
    surface.damageBuffer(0, 0, @intCast(image.width), @intCast(image.height));
    surface.commit();
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, self: *Wayland) void {
    switch (event) {
        .enter => |e| {
            self.pointer_x = e.surface_x.toDouble();
            self.pointer_y = e.surface_y.toDouble();
            applyCursor(self, pointer, e.serial);
            if (self.window) |w| w.pushEvent(.{ .mouse_enter = .{
                .x = @floatCast(self.pointer_x),
                .y = @floatCast(self.pointer_y),
            } });
        },
        .leave => if (self.window) |w| w.pushEvent(.mouse_leave),
        .motion => |m| {
            self.pointer_x = m.surface_x.toDouble();
            self.pointer_y = m.surface_y.toDouble();
            if (self.window) |w| w.pushEvent(.{ .mouse_move = .{
                .x = @floatCast(self.pointer_x),
                .y = @floatCast(self.pointer_y),
            } });
        },
        .button => |b| {
            const win = self.window orelse return;
            const button: MouseButton = switch (@as(PointerButton, @enumFromInt(b.button))) {
                .left => .left,
                .right => .right,
                .middle => .middle,
                else => return,
            };
            win.pushEvent(.{ .mouse_button = .{
                .button = button,
                .action = if (b.state == .pressed) .press else .release,
                .x = @floatCast(self.pointer_x),
                .y = @floatCast(self.pointer_y),
            } });
        },
        .axis => |a| {
            const win = self.window orelse return;
            const delta: f32 = @floatCast(a.value.toDouble());
            switch (a.axis) {
                .horizontal_scroll => win.pushEvent(.{ .mouse_scroll = .{ .dx = delta, .dy = 0 } }),
                .vertical_scroll => win.pushEvent(.{ .mouse_scroll = .{ .dx = 0, .dy = delta } }),
                _ => {},
            }
        },
        .frame, .axis_source, .axis_stop, .axis_discrete => {},
    }
}
