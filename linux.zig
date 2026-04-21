const std = @import("std");
const shared = @import("shared.zig");
const WaylandWindow = @import("wayland/WaylandWindow.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;

const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
});

const LinuxWindow = @This();

const Backend = enum { wayland, x11 };

fn dispatchInputEvent(window_wrapper: ?*anyopaque, event: @import("Window.zig").InputEvent) void {
    if (window_wrapper) |wrapper| {
        const Window = @import("Window.zig");
        const win: *Window = @ptrCast(@alignCast(wrapper));
        win.pushEvent(event);
    }
}

backend: Backend,
wayland_window: ?WaylandWindow = null,
x11_display: ?*x11.Display = null,
x11_window: ?x11.Window = null,

width: u32,
height: u32,
needs_resize: bool = false,
new_width: u32 = 0,
new_height: u32 = 0,
should_close_flag: bool = false,

mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: u8 = 0,

keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

fn detectDisplayServer() ?Backend {
    if (std.posix.getenv("WAYLAND_DISPLAY")) |val| if (val.len != 0) {
        return .wayland;
    };

    if (std.posix.getenv("DISPLAY")) |_| {
        return .x11;
    }

    return null;
}

pub fn init(options: shared.InitOptions) !LinuxWindow {
    const backend = detectDisplayServer() orelse return error.NoDisplayServerFound;
    return switch (backend) {
        .wayland => initWayland(options),
        .x11 => initX11(options),
    };
}

fn initWayland(options: shared.InitOptions) !LinuxWindow {
    const window = try WaylandWindow.initWithOptions(
        options.title,
        @intCast(options.width),
        @intCast(options.height),
        .{
            .use_shm_buffer = false,
            .enable_input = true,
            .create_egl_window = false,
        },
    );

    var self = LinuxWindow{
        .backend = .wayland,
        .wayland_window = window,
        .width = options.width,
        .height = options.height,
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
    };

    pollEventsWayland(&self, null);
    if (self.needs_resize) {
        self.width = self.new_width;
        self.height = self.new_height;
        self.needs_resize = false;
    }

    std.debug.print("Using native Wayland backend\n", .{});
    return self;
}

fn initX11(options: shared.InitOptions) !LinuxWindow {
    const display = x11.XOpenDisplay(null) orelse return error.FailedToOpenDisplay;
    errdefer _ = x11.XCloseDisplay(display);

    const screen = x11.XDefaultScreen(display);
    const root_window = x11.XRootWindow(display, screen);

    const window_handle = x11.XCreateSimpleWindow(
        display,
        root_window,
        0,
        0,
        options.width,
        options.height,
        0,
        0,
        0,
    );

    _ = x11.XSelectInput(
        display,
        window_handle,
        x11.ExposureMask | x11.KeyPressMask | x11.KeyReleaseMask | x11.ButtonPressMask | x11.ButtonReleaseMask | x11.PointerMotionMask | x11.StructureNotifyMask,
    );

    _ = x11.XSync(display, 0);

    std.debug.print("Using native X11 backend\n", .{});

    var self = LinuxWindow{
        .backend = .x11,
        .x11_display = display,
        .x11_window = window_handle,
        .width = options.width,
        .height = options.height,
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
    };

    var root_return: x11.Window = undefined;
    var child_return: x11.Window = undefined;
    var root_x: c_int = undefined;
    var root_y: c_int = undefined;
    var win_x: c_int = undefined;
    var win_y: c_int = undefined;
    var mask_return: c_uint = undefined;

    if (x11.XQueryPointer(
        display,
        window_handle,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &mask_return,
    ) != 0) {
        self.mouse_x = @floatFromInt(win_x);
        self.mouse_y = @floatFromInt(win_y);
    }

    return self;
}

pub fn show(self: *LinuxWindow) void {
    switch (self.backend) {
        .wayland => {},
        .x11 => {
            const display = self.x11_display.?;
            const window_handle = self.x11_window.?;
            _ = x11.XMapWindow(display, window_handle);
            _ = x11.XFlush(display);

            var event: x11.XEvent = undefined;
            var mapped = false;
            while (!mapped) {
                _ = x11.XNextEvent(display, &event);
                if (event.type == x11.MapNotify) {
                    mapped = true;
                }
            }

            var window_attrs: x11.XWindowAttributes = undefined;
            _ = x11.XGetWindowAttributes(display, window_handle, &window_attrs);
            self.width = @intCast(window_attrs.width);
            self.height = @intCast(window_attrs.height);

            var root_return: x11.Window = undefined;
            var child_return: x11.Window = undefined;
            var root_x: c_int = undefined;
            var root_y: c_int = undefined;
            var win_x: c_int = undefined;
            var win_y: c_int = undefined;
            var mask_return: c_uint = undefined;

            if (x11.XQueryPointer(
                display,
                window_handle,
                &root_return,
                &child_return,
                &root_x,
                &root_y,
                &win_x,
                &win_y,
                &mask_return,
            ) != 0) {
                self.mouse_x = @floatFromInt(win_x);
                self.mouse_y = @floatFromInt(win_y);
            }
        },
    }
}

pub fn start(self: *LinuxWindow) !void {
    switch (self.backend) {
        .wayland => {
            if (self.wayland_window) |*w| {
                try w.registerListeners();
            }
        },
        .x11 => {},
    }
}

pub fn deinit(self: *LinuxWindow) void {
    switch (self.backend) {
        .wayland => if (self.wayland_window) |*w| w.deinit(),
        .x11 => if (self.x11_display) |d| {
            _ = x11.XCloseDisplay(d);
        },
    }
}

pub fn shouldClose(self: *LinuxWindow) bool {
    return switch (self.backend) {
        .wayland => shouldCloseWayland(self),
        .x11 => self.should_close_flag,
    };
}

fn shouldCloseWayland(self: *LinuxWindow) bool {
    return self.wayland_window.?.xdg_toplevel.should_close;
}

pub fn pollEvents(self: *LinuxWindow, window: anytype) void {
    switch (self.backend) {
        .wayland => pollEventsWayland(self, window),
        .x11 => pollEventsX11(self, window),
    }
}

fn pollEventsWayland(self: *LinuxWindow, window_wrapper: ?*anyopaque) void {
    const window = &self.wayland_window.?;

    var events_polled: u32 = 0;
    const max_events_per_frame: u32 = 10;

    while (events_polled < max_events_per_frame) {
        const event = window.pollEvent() catch null orelse break;
        events_polled += 1;

        // Skip key repeats
        if (event == .key_press) {
            if (self.keys_pressed.contains(event.key_press)) {
                continue;
            }
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

                var click_x = self.mouse_x;
                var click_y = self.mouse_y;
                if (self.wayland_window) |*ww| {
                    if (ww.pointer) |ptr| {
                        click_x = @floatCast(ptr.x);
                        click_y = @floatCast(ptr.y);
                        self.mouse_x = click_x;
                        self.mouse_y = click_y;
                    }
                }

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

fn pollEventsX11(self: *LinuxWindow, window_wrapper: ?*anyopaque) void {
    const display = self.x11_display.?;
    const window_handle = self.x11_window.?;
    var event: x11.XEvent = undefined;
    while (x11.XPending(display) > 0) {
        _ = x11.XNextEvent(display, &event);
        switch (event.type) {
            x11.ClientMessage => self.should_close_flag = true,
            x11.ConfigureNotify => {
                const new_w: u32 = @intCast(event.xconfigure.width);
                const new_h: u32 = @intCast(event.xconfigure.height);
                if (new_w != self.width or new_h != self.height) {
                    self.new_width = new_w;
                    self.new_height = new_h;
                    self.needs_resize = true;
                }
            },
            x11.KeyPress => {
                const keysym = x11.XLookupKeysym(&event.xkey, 0);
                const key = Key.fromKeysym(@intCast(keysym));
                if (key != .unknown) {
                    self.keys_pressed.insert(key);
                    dispatchInputEvent(window_wrapper, .{ .key_press = key });
                }
            },
            x11.KeyRelease => {
                const keysym = x11.XLookupKeysym(&event.xkey, 0);
                const key = Key.fromKeysym(@intCast(keysym));
                if (key != .unknown) {
                    self.keys_pressed.remove(key);
                    dispatchInputEvent(window_wrapper, .{ .key_release = key });
                }
            },
            x11.ButtonPress => {
                const button_bit: u8 = switch (event.xbutton.button) {
                    1 => @intFromEnum(MouseButton.left),
                    2 => @intFromEnum(MouseButton.middle),
                    3 => @intFromEnum(MouseButton.right),
                    else => 0x00,
                };
                self.mouse_buttons |= button_bit;

                const click_x = @as(f32, @floatFromInt(event.xbutton.x));
                const click_y = @as(f32, @floatFromInt(event.xbutton.y));
                self.mouse_x = click_x;
                self.mouse_y = click_y;

                dispatchInputEvent(window_wrapper, .{ .mouse_click = .{
                    .x = click_x,
                    .y = click_y,
                    .button = button_bit,
                } });
            },
            x11.ButtonRelease => {
                const button_bit: u8 = switch (event.xbutton.button) {
                    1 => @intFromEnum(MouseButton.left),
                    2 => @intFromEnum(MouseButton.middle),
                    3 => @intFromEnum(MouseButton.right),
                    else => 0x00,
                };
                self.mouse_buttons &= ~button_bit;
            },
            x11.MotionNotify => {
                self.mouse_x = @floatFromInt(event.xmotion.x);
                self.mouse_y = @floatFromInt(event.xmotion.y);
            },
            else => {},
        }
    }

    var window_attrs: x11.XWindowAttributes = undefined;
    _ = x11.XGetWindowAttributes(display, window_handle, &window_attrs);
    const actual_width: u32 = @intCast(window_attrs.width);
    const actual_height: u32 = @intCast(window_attrs.height);
    if (actual_width != self.width or actual_height != self.height) {
        self.new_width = actual_width;
        self.new_height = actual_height;
        self.needs_resize = true;
    }
}

pub fn getNativeHandles(self: *LinuxWindow) shared.NativeHandles {
    return switch (self.backend) {
        .wayland => getNativeHandlesWayland(self),
        .x11 => getNativeHandlesX11(self),
    };
}

fn getNativeHandlesWayland(self: *LinuxWindow) shared.NativeHandles {
    const window = &self.wayland_window.?;
    return .{
        .wayland = .{
            .display = window.getWaylandDisplay(),
            .surface = window.getWaylandSurface(),
        },
    };
}

fn getNativeHandlesX11(self: *LinuxWindow) shared.NativeHandles {
    return .{
        .x11 = .{
            .display = self.x11_display.?,
            .window = @intCast(self.x11_window.?),
        },
    };
}

pub fn getSize(self: *LinuxWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(self: *LinuxWindow) bool {
    return switch (self.backend) {
        .wayland => self.needs_resize,
        .x11 => self.needs_resize,
    };
}

pub fn getNewSize(self: *LinuxWindow) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *LinuxWindow) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}
