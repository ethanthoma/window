const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;

const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("X11/cursorfont.h");
});

const X11 = @This();

fn dispatchInputEvent(window_wrapper: ?*anyopaque, event: @import("Window.zig").InputEvent) void {
    if (window_wrapper) |wrapper| {
        const Window = @import("Window.zig");
        const win: *Window = @ptrCast(@alignCast(wrapper));
        win.pushEvent(event);
    }
}

display: *x11.Display,
window: x11.Window,

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

pub fn init(options: shared.InitOptions) !X11 {
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

    const arrow = x11.XCreateFontCursor(display, x11.XC_left_ptr);
    if (arrow != 0) _ = x11.XDefineCursor(display, window_handle, arrow);

    _ = x11.XSync(display, 0);

    std.debug.print("Using native X11 backend\n", .{});

    var self = X11{
        .display = display,
        .window = window_handle,
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

pub fn start(_: *X11) !void {}

pub fn deinit(self: *X11) void {
    _ = x11.XCloseDisplay(self.display);
}

pub fn show(self: *X11) void {
    _ = x11.XMapWindow(self.display, self.window);
    _ = x11.XFlush(self.display);

    var event: x11.XEvent = undefined;
    var mapped = false;
    while (!mapped) {
        _ = x11.XNextEvent(self.display, &event);
        if (event.type == x11.MapNotify) {
            mapped = true;
        }
    }

    var window_attrs: x11.XWindowAttributes = undefined;
    _ = x11.XGetWindowAttributes(self.display, self.window, &window_attrs);
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
        self.display,
        self.window,
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
}

pub fn shouldClose(self: *X11) bool {
    return self.should_close_flag;
}

pub fn pollEvents(self: *X11, window_wrapper: ?*anyopaque) void {
    var event: x11.XEvent = undefined;
    while (x11.XPending(self.display) > 0) {
        _ = x11.XNextEvent(self.display, &event);
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
    _ = x11.XGetWindowAttributes(self.display, self.window, &window_attrs);
    const actual_width: u32 = @intCast(window_attrs.width);
    const actual_height: u32 = @intCast(window_attrs.height);
    if (actual_width != self.width or actual_height != self.height) {
        self.new_width = actual_width;
        self.new_height = actual_height;
        self.needs_resize = true;
    }
}

pub fn getNativeHandles(self: *X11) shared.NativeHandles {
    return .{
        .x11 = .{
            .display = self.display,
            .window = @intCast(self.window),
        },
    };
}

pub fn getSize(self: *X11) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(self: *X11) bool {
    return self.needs_resize;
}

pub fn getNewSize(self: *X11) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *X11) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}

pub fn getMousePosition(self: *X11) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *X11) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *X11, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *X11) std.EnumSet(Key) {
    return self.keys_pressed;
}
