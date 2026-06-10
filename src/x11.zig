const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;
const Window = @import("Window.zig");

const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/XKBlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("X11/cursorfont.h");
});

const X11 = @This();

display: *x11.Display,
window: x11.Window,
wm_delete_window: x11.Atom,

width: u32,
height: u32,

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
        x11.ExposureMask | x11.KeyPressMask | x11.KeyReleaseMask | x11.ButtonPressMask | x11.ButtonReleaseMask | x11.PointerMotionMask | x11.StructureNotifyMask | x11.EnterWindowMask | x11.LeaveWindowMask,
    );

    var wm_delete_window = x11.XInternAtom(display, "WM_DELETE_WINDOW", 0);
    _ = x11.XSetWMProtocols(display, window_handle, &wm_delete_window, 1);

    _ = x11.XkbSetDetectableAutoRepeat(display, 1, null);

    const arrow = x11.XCreateFontCursor(display, x11.XC_left_ptr);
    if (arrow != 0) _ = x11.XDefineCursor(display, window_handle, arrow);

    _ = x11.XSync(display, 0);

    std.debug.print("Using native X11 backend\n", .{});

    return .{
        .display = display,
        .window = window_handle,
        .wm_delete_window = wm_delete_window,
        .width = options.width,
        .height = options.height,
    };
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
}

fn mouseButtonFromX11(button: c_uint) ?MouseButton {
    return switch (button) {
        1 => .left,
        2 => .middle,
        3 => .right,
        else => null,
    };
}

pub fn pollEvents(self: *X11, window: *Window) void {
    var event: x11.XEvent = undefined;
    while (x11.XPending(self.display) > 0) {
        _ = x11.XNextEvent(self.display, &event);
        switch (event.type) {
            x11.ClientMessage => {
                if (event.xclient.data.l[0] == @as(c_long, @intCast(self.wm_delete_window))) {
                    window.pushEvent(.close);
                }
            },
            x11.ConfigureNotify => {
                const new_w: u32 = @intCast(event.xconfigure.width);
                const new_h: u32 = @intCast(event.xconfigure.height);
                if (new_w != self.width or new_h != self.height) {
                    self.width = new_w;
                    self.height = new_h;
                    window.pushEvent(.{ .resize = .{ .width = new_w, .height = new_h } });
                }
            },
            x11.KeyPress, x11.KeyRelease => {
                const keysym = x11.XLookupKeysym(&event.xkey, 0);
                window.pushEvent(.{ .key = .{
                    .key = Key.fromKeysym(@intCast(keysym)),
                    .action = if (event.type == x11.KeyPress) .press else .release,
                } });
            },
            x11.ButtonPress, x11.ButtonRelease => {
                if (mouseButtonFromX11(event.xbutton.button)) |button| {
                    window.pushEvent(.{ .mouse_button = .{
                        .button = button,
                        .action = if (event.type == x11.ButtonPress) .press else .release,
                        .x = @floatFromInt(event.xbutton.x),
                        .y = @floatFromInt(event.xbutton.y),
                    } });
                } else if (event.type == x11.ButtonPress) {
                    switch (event.xbutton.button) {
                        4 => window.pushEvent(.{ .mouse_scroll = .{ .dx = 0, .dy = -1 } }),
                        5 => window.pushEvent(.{ .mouse_scroll = .{ .dx = 0, .dy = 1 } }),
                        6 => window.pushEvent(.{ .mouse_scroll = .{ .dx = -1, .dy = 0 } }),
                        7 => window.pushEvent(.{ .mouse_scroll = .{ .dx = 1, .dy = 0 } }),
                        else => {},
                    }
                }
            },
            x11.MotionNotify => window.pushEvent(.{ .mouse_move = .{
                .x = @floatFromInt(event.xmotion.x),
                .y = @floatFromInt(event.xmotion.y),
            } }),
            x11.EnterNotify => window.pushEvent(.{ .mouse_enter = .{
                .x = @floatFromInt(event.xcrossing.x),
                .y = @floatFromInt(event.xcrossing.y),
            } }),
            x11.LeaveNotify => window.pushEvent(.mouse_leave),
            else => {},
        }
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
