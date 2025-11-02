const std = @import("std");

const Keyboard = @This();

const Registry = @import("Registry.zig");
const wl_seat = Registry.wl_seat;

pub const wl_keyboard = extern struct {};

const wl_keyboard_listener = extern struct {
    keymap: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, i32, u32) callconv(.c) void,
    enter: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, ?*anyopaque, ?*anyopaque) callconv(.c) void,
    leave: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, ?*anyopaque) callconv(.c) void,
    key: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, u32, u32, u32) callconv(.c) void,
    modifiers: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, u32, u32, u32, u32) callconv(.c) void,
    repeat_info: ?*const fn (?*anyopaque, ?*wl_keyboard, i32, i32) callconv(.c) void,
};

const CXkbContext = extern struct {};
const CXkbKeymap = extern struct {};
const CXkbState = extern struct {};

extern "c" fn wl_seat_get_keyboard_wrapper(*wl_seat) ?*wl_keyboard;
extern "c" fn wl_keyboard_add_listener_wrapper(*wl_keyboard, *const wl_keyboard_listener, ?*anyopaque) i32;
extern "c" fn wl_keyboard_destroy_wrapper(*wl_keyboard) void;

extern "c" fn xkb_context_new(flags: u32) ?*CXkbContext;
extern "c" fn xkb_context_unref(*CXkbContext) void;
extern "c" fn xkb_keymap_new_from_string(*CXkbContext, [*:0]const u8, format: u32, flags: u32) ?*CXkbKeymap;
extern "c" fn xkb_keymap_unref(*CXkbKeymap) void;
extern "c" fn xkb_state_new(*CXkbKeymap) ?*CXkbState;
extern "c" fn xkb_state_unref(*CXkbState) void;
extern "c" fn xkb_state_key_get_one_sym(*CXkbState, u32) u32;
extern "c" fn xkb_state_update_mask(*CXkbState, u32, u32, u32, u32, u32, u32) u32;
extern "c" fn xkb_keysym_get_name(u32, [*]u8, usize) i32;

const XKB_KEYMAP_FORMAT_TEXT_V1: u32 = 1;

keyboard: *wl_keyboard,
xkb_context: ?*CXkbContext = null,
xkb_keymap: ?*CXkbKeymap = null,
xkb_state: ?*CXkbState = null,

pub fn init(seat: *wl_seat) !Keyboard {
    const kb = wl_seat_get_keyboard_wrapper(seat) orelse return error.KeyboardCreationFailed;

    const ctx = xkb_context_new(0) orelse return error.XkbContextCreationFailed;

    return .{
        .keyboard = kb,
        .xkb_context = ctx,
    };
}

pub fn addListener(self: *Keyboard, user_data: ?*anyopaque) !void {
    const listener = wl_keyboard_listener{
        .keymap = handleKeymap,
        .enter = handleEnter,
        .leave = handleLeave,
        .key = handleKey,
        .modifiers = handleModifiers,
        .repeat_info = handleRepeatInfo,
    };

    const result = wl_keyboard_add_listener_wrapper(self.keyboard, &listener, user_data);
    if (result < 0) return error.ListenerFailed;
}

pub fn destroy(self: Keyboard) void {
    if (self.xkb_state) |state| xkb_state_unref(state);
    if (self.xkb_keymap) |keymap| xkb_keymap_unref(keymap);
    if (self.xkb_context) |ctx| xkb_context_unref(ctx);
    wl_keyboard_destroy_wrapper(self.keyboard);
}

fn handleKeymap(
    data: ?*anyopaque,
    _: ?*wl_keyboard,
    format: u32,
    fd: i32,
    size: u32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    if (format != XKB_KEYMAP_FORMAT_TEXT_V1) {
        std.posix.close(fd);
        return;
    }

    const map_shm = std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        fd,
        0,
    ) catch {
        std.posix.close(fd);
        return;
    };
    defer std.posix.munmap(map_shm);
    std.posix.close(fd);

    const keymap_str: [*:0]const u8 = @ptrCast(map_shm.ptr);

    if (window.keyboard) |*kb| {
        if (kb.xkb_context) |ctx| {
            const keymap = xkb_keymap_new_from_string(ctx, keymap_str, XKB_KEYMAP_FORMAT_TEXT_V1, 0) orelse return;

            if (kb.xkb_keymap) |old_keymap| xkb_keymap_unref(old_keymap);
            kb.xkb_keymap = keymap;

            const state = xkb_state_new(keymap) orelse return;

            if (kb.xkb_state) |old_state| xkb_state_unref(old_state);
            kb.xkb_state = state;
        }
    }
}

fn handleEnter(
    _: ?*anyopaque,
    _: ?*wl_keyboard,
    _: u32,
    _: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {}

fn handleLeave(
    _: ?*anyopaque,
    _: ?*wl_keyboard,
    _: u32,
    _: ?*anyopaque,
) callconv(.c) void {}

fn handleKey(
    data: ?*anyopaque,
    _: ?*wl_keyboard,
    _: u32,
    _: u32,
    key: u32,
    state: u32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    if (window.keyboard) |*kb| {
        if (kb.xkb_state) |xkb_st| {
            const keycode = key + 8;
            const keysym = xkb_state_key_get_one_sym(xkb_st, keycode);

            const pressed = state == 1;
            const key_enum = Window.Key.fromKeysym(keysym);
            window.pushEvent(if (pressed)
                .{ .key_press = key_enum }
            else
                .{ .key_release = key_enum });
        }
    }
}

fn handleModifiers(
    data: ?*anyopaque,
    _: ?*wl_keyboard,
    _: u32,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32,
) callconv(.c) void {
    const Window = @import("../../Window.zig");
    const window: *Window = @ptrCast(@alignCast(data));

    if (window.keyboard) |*kb| {
        if (kb.xkb_state) |state| {
            _ = xkb_state_update_mask(state, mods_depressed, mods_latched, mods_locked, 0, 0, group);
        }
    }
}

fn handleRepeatInfo(
    _: ?*anyopaque,
    _: ?*wl_keyboard,
    _: i32,
    _: i32,
) callconv(.c) void {}
