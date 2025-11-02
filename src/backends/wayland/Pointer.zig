const std = @import("std");

const Pointer = @This();

const Registry = @import("Registry.zig");
const wl_seat = Registry.wl_seat;

pub const wl_pointer = extern struct {};

const wl_pointer_listener = extern struct {
    enter: ?*const fn (?*anyopaque, ?*wl_pointer, u32, ?*anyopaque, i32, i32) callconv(.c) void,
    leave: ?*const fn (?*anyopaque, ?*wl_pointer, u32, ?*anyopaque) callconv(.c) void,
    motion: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32, i32) callconv(.c) void,
    button: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32, u32, u32) callconv(.c) void,
    axis: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32, i32) callconv(.c) void,
    frame: ?*const fn (?*anyopaque, ?*wl_pointer) callconv(.c) void,
    axis_source: ?*const fn (?*anyopaque, ?*wl_pointer, u32) callconv(.c) void,
    axis_stop: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32) callconv(.c) void,
    axis_discrete: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32) callconv(.c) void,
    axis_value120: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32) callconv(.c) void,
    axis_relative_direction: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32) callconv(.c) void,
};

extern "c" fn wl_seat_get_pointer_wrapper(*wl_seat) ?*wl_pointer;
extern "c" fn wl_pointer_add_listener_wrapper(*wl_pointer, *const wl_pointer_listener, ?*anyopaque) i32;
extern "c" fn wl_pointer_destroy_wrapper(*wl_pointer) void;

pub const MouseButton = enum(u32) {
    left = 0x110,
    right = 0x111,
    middle = 0x112,
    back = 0x113,
    forward = 0x114,
    _,

    pub fn fromLinuxCode(code: u32) MouseButton {
        return @enumFromInt(code);
    }
};

pointer: *wl_pointer,
x: f64 = 0,
y: f64 = 0,

pub fn init(seat: *wl_seat) !Pointer {
    const ptr = wl_seat_get_pointer_wrapper(seat) orelse return error.PointerCreationFailed;
    return .{ .pointer = ptr };
}

pub fn addListener(self: *Pointer, user_data: ?*anyopaque) !void {
    const listener = wl_pointer_listener{
        .enter = handleEnter,
        .leave = handleLeave,
        .motion = handleMotion,
        .button = handleButton,
        .axis = handleAxis,
        .frame = handleFrame,
        .axis_source = handleAxisSource,
        .axis_stop = handleAxisStop,
        .axis_discrete = handleAxisDiscrete,
        .axis_value120 = handleAxisValue120,
        .axis_relative_direction = handleAxisRelativeDirection,
    };

    const result = wl_pointer_add_listener_wrapper(self.pointer, &listener, user_data);
    if (result < 0) return error.ListenerFailed;
}

pub fn destroy(self: Pointer) void {
    wl_pointer_destroy_wrapper(self.pointer);
}

fn handleEnter(
    data: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: ?*anyopaque,
    surface_x: i32,
    surface_y: i32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    if (window.pointer) |*ptr| {
        ptr.x = wl_fixed_to_double(surface_x);
        ptr.y = wl_fixed_to_double(surface_y);
    }

    window.pushEvent(.{ .mouse_enter = .{
        .x = wl_fixed_to_double(surface_x),
        .y = wl_fixed_to_double(surface_y),
    } });
}

fn handleLeave(
    data: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: ?*anyopaque,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));
    window.pushEvent(.mouse_leave);
}

fn handleMotion(
    data: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    surface_x: i32,
    surface_y: i32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    const x = wl_fixed_to_double(surface_x);
    const y = wl_fixed_to_double(surface_y);

    if (window.pointer) |*ptr| {
        ptr.x = x;
        ptr.y = y;
    }

    window.pushEvent(.{ .mouse_motion = .{ .x = x, .y = y } });
}

fn handleButton(
    data: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: u32,
    button: u32,
    state: u32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    const mouse_button = MouseButton.fromLinuxCode(button);
    const pressed = state == 1;

    window.pushEvent(if (pressed)
        .{ .mouse_button_press = mouse_button }
    else
        .{ .mouse_button_release = mouse_button });
}

fn handleAxis(
    data: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    axis: u32,
    value: i32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    const delta = wl_fixed_to_double(value);

    if (axis == 0) {
        window.pushEvent(.{ .mouse_scroll = .{ .x = delta, .y = 0 } });
    } else if (axis == 1) {
        window.pushEvent(.{ .mouse_scroll = .{ .x = 0, .y = delta } });
    }
}

fn handleFrame(
    _: ?*anyopaque,
    _: ?*wl_pointer,
) callconv(.c) void {}

fn handleAxisSource(
    _: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
) callconv(.c) void {}

fn handleAxisStop(
    _: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: u32,
) callconv(.c) void {}

fn handleAxisDiscrete(
    _: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: i32,
) callconv(.c) void {}

fn handleAxisValue120(
    _: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: i32,
) callconv(.c) void {}

fn handleAxisRelativeDirection(
    _: ?*anyopaque,
    _: ?*wl_pointer,
    _: u32,
    _: u32,
) callconv(.c) void {}

fn wl_fixed_to_double(f: i32) f64 {
    return @as(f64, @floatFromInt(f)) / 256.0;
}
