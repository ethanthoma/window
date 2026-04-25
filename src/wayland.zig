const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;

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

pub const Event = union(enum) {
    close,
    configure: struct { width: i32, height: i32 },
    key_press: Key,
    key_release: Key,
    mouse_enter: struct { x: f64, y: f64 },
    mouse_leave,
    mouse_motion: struct { x: f64, y: f64 },
    mouse_button_press: PointerButton,
    mouse_button_release: PointerButton,
    mouse_scroll: struct { x: f64, y: f64 },
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

display: *wl.Display,
registry: *wl.Registry,
compositor: *wl.Compositor,
seat: *wl.Seat,
wm_base: *xdg.WmBase,
surface: *wl.Surface,
xdg_surface: *xdg.Surface,
xdg_toplevel: *xdg.Toplevel,
keyboard: ?*wl.Keyboard = null,
pointer: ?*wl.Pointer = null,

xkb_context: ?*CXkbContext = null,
xkb_keymap: ?*CXkbKeymap = null,
xkb_state: ?*CXkbState = null,

event_queue: EventQueue = .{},
event_index: usize = 0,

configured: bool = false,
last_configure_serial: u32 = 0,
should_close: bool = false,

width: u32,
height: u32,
needs_resize: bool = false,
new_width: u32 = 0,
new_height: u32 = 0,

mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: u8 = 0,
pointer_x: f64 = 0,
pointer_y: f64 = 0,

keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    seat: ?*wl.Seat = null,
    wm_base: ?*xdg.WmBase = null,
};

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

    var self = Wayland{
        .display = display,
        .registry = registry,
        .compositor = compositor,
        .seat = seat,
        .wm_base = wm_base,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .xdg_toplevel = xdg_toplevel,
        .keyboard = keyboard,
        .pointer = pointer,
        .xkb_context = xkb_context,
        .width = options.width,
        .height = options.height,
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
    };

    pollEventsInternal(&self, null);
    if (self.needs_resize) {
        self.width = self.new_width;
        self.height = self.new_height;
        self.needs_resize = false;
    }

    std.debug.print("Using native Wayland backend\n", .{});
    return self;
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
}

pub fn deinit(self: *Wayland) void {
    if (self.xkb_state) |s| xkb_state_unref(s);
    if (self.xkb_keymap) |k| xkb_keymap_unref(k);
    if (self.xkb_context) |c| xkb_context_unref(c);
    if (self.keyboard) |kb| kb.destroy();
    if (self.pointer) |p| p.destroy();
    self.xdg_toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.destroy();
    self.wm_base.destroy();
    self.seat.destroy();
    self.compositor.destroy();
    self.registry.destroy();
    self.display.disconnect();
}

pub fn show(_: *Wayland) void {}

pub fn shouldClose(self: *Wayland) bool {
    return self.should_close;
}

pub fn pushEvent(self: *Wayland, event: Event) void {
    self.event_queue.append(event) catch {
        std.debug.print("Event queue full, dropping event\n", .{});
    };
}

fn pollEvent(self: *Wayland) !?Event {
    if (self.event_index >= self.event_queue.len) {
        self.event_queue.clear();
        self.event_index = 0;

        if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
        if (self.display.flush() != .SUCCESS) return error.FlushFailed;

        if (self.event_queue.len == 0) {
            if (!self.display.prepareRead()) {
                if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
                if (self.event_queue.len == 0) return null;
            } else {
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
                    if (self.display.readEvents() != .SUCCESS) return error.ReadEventsFailed;
                    if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
                } else {
                    self.display.cancelRead();
                }
            }
        }

        if (self.event_queue.len == 0) return null;
    }

    const event = self.event_queue.get(self.event_index);
    self.event_index += 1;
    return event;
}

pub fn pollEvents(self: *Wayland, window_wrapper: ?*anyopaque) void {
    pollEventsInternal(self, window_wrapper);
}

fn pollEventsInternal(self: *Wayland, window_wrapper: ?*anyopaque) void {
    var events_polled: u32 = 0;
    const max_events_per_frame: u32 = 10;

    while (events_polled < max_events_per_frame) {
        const event = self.pollEvent() catch null orelse break;
        events_polled += 1;

        if (event == .key_press) {
            if (self.keys_pressed.contains(event.key_press)) continue;
        }
        switch (event) {
            .configure => |config| {
                if (config.width > 0 and config.height > 0) {
                    const new_w: u32 = @intCast(config.width);
                    const new_h: u32 = @intCast(config.height);
                    if (new_w != self.width or new_h != self.height) {
                        self.new_width = new_w;
                        self.new_height = new_h;
                        self.needs_resize = true;
                    }
                }
            },
            .mouse_motion => |motion| {
                self.mouse_x = @floatCast(motion.x);
                self.mouse_y = @floatCast(motion.y);
            },
            .mouse_button_press => |button| {
                const button_bit: u8 = switch (button) {
                    .left => @intFromEnum(MouseButton.left),
                    .right => @intFromEnum(MouseButton.right),
                    .middle => @intFromEnum(MouseButton.middle),
                    else => 0x00,
                };
                self.mouse_buttons |= button_bit;

                const click_x: f32 = @floatCast(self.pointer_x);
                const click_y: f32 = @floatCast(self.pointer_y);
                self.mouse_x = click_x;
                self.mouse_y = click_y;

                dispatchInputEvent(window_wrapper, .{ .mouse_click = .{
                    .x = click_x,
                    .y = click_y,
                    .button = button_bit,
                } });
            },
            .mouse_button_release => |button| {
                const button_bit: u8 = switch (button) {
                    .left => @intFromEnum(MouseButton.left),
                    .right => @intFromEnum(MouseButton.right),
                    .middle => @intFromEnum(MouseButton.middle),
                    else => 0x00,
                };
                self.mouse_buttons &= ~button_bit;
            },
            .key_press => |key| {
                self.keys_pressed.insert(key);
                dispatchInputEvent(window_wrapper, .{ .key_press = key });
            },
            .key_release => |key| {
                self.keys_pressed.remove(key);
                dispatchInputEvent(window_wrapper, .{ .key_release = key });
            },
            else => {},
        }
    }
}

fn dispatchInputEvent(window_wrapper: ?*anyopaque, event: @import("Window.zig").InputEvent) void {
    if (window_wrapper) |wrapper| {
        const Window = @import("Window.zig");
        const win: *Window = @ptrCast(@alignCast(wrapper));
        win.pushEvent(event);
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

pub fn needsResize(self: *Wayland) bool {
    return self.needs_resize;
}

pub fn getNewSize(self: *Wayland) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *Wayland) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}

pub fn getMousePosition(self: *Wayland) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *Wayland) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *Wayland, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *Wayland) std.EnumSet(Key) {
    return self.keys_pressed;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |g| {
            if (std.mem.orderZ(u8, g.interface, wl.Compositor.interface.name) == .eq) {
                globals.compositor = registry.bind(g.name, wl.Compositor, @min(g.version, 4)) catch return;
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
            if (c.width > 0 or c.height > 0) {
                const new_width = if (c.width > 0) c.width else @as(i32, @intCast(self.width));
                const new_height = if (c.height > 0) c.height else @as(i32, @intCast(self.height));
                self.pushEvent(.{ .configure = .{ .width = new_width, .height = new_height } });
            }
        },
        .close => {
            self.should_close = true;
            self.pushEvent(.close);
        },
        .configure_bounds => {},
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, self: *Wayland) void {
    switch (event) {
        .keymap => |k| {
            defer std.posix.close(k.fd);
            if (k.format != .xkb_v1) return;

            const map_shm = std.posix.mmap(
                null,
                k.size,
                std.posix.PROT.READ,
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
            const xkb_st = self.xkb_state orelse return;
            const keycode = k.key + 8;
            const keysym = xkb_state_key_get_one_sym(xkb_st, keycode);
            const key_enum = Key.fromKeysym(keysym);
            const pressed = k.state == .pressed;
            self.pushEvent(if (pressed) .{ .key_press = key_enum } else .{ .key_release = key_enum });
        },
        .modifiers => |m| {
            if (self.xkb_state) |state| {
                _ = xkb_state_update_mask(state, m.mods_depressed, m.mods_latched, m.mods_locked, 0, 0, m.group);
            }
        },
        .enter, .leave, .repeat_info => {},
    }
}

fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, self: *Wayland) void {
    switch (event) {
        .enter => |e| {
            const x = e.surface_x.toDouble();
            const y = e.surface_y.toDouble();
            self.pointer_x = x;
            self.pointer_y = y;
            self.pushEvent(.{ .mouse_enter = .{ .x = x, .y = y } });
        },
        .leave => self.pushEvent(.mouse_leave),
        .motion => |m| {
            const x = m.surface_x.toDouble();
            const y = m.surface_y.toDouble();
            self.pointer_x = x;
            self.pointer_y = y;
            self.pushEvent(.{ .mouse_motion = .{ .x = x, .y = y } });
        },
        .button => |b| {
            const mouse_button: PointerButton = @enumFromInt(b.button);
            const pressed = b.state == .pressed;
            self.pushEvent(if (pressed)
                .{ .mouse_button_press = mouse_button }
            else
                .{ .mouse_button_release = mouse_button });
        },
        .axis => |a| {
            const delta = a.value.toDouble();
            switch (a.axis) {
                .horizontal_scroll => self.pushEvent(.{ .mouse_scroll = .{ .x = delta, .y = 0 } }),
                .vertical_scroll => self.pushEvent(.{ .mouse_scroll = .{ .x = 0, .y = delta } }),
                _ => {},
            }
        },
        .frame, .axis_source, .axis_stop, .axis_discrete => {},
    }
}
