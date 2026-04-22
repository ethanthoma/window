const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const Window = @import("Window.zig");

const c = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

const MacOSWindow = @This();

const id = *anyopaque;
const SEL = *anyopaque;
const Class = *anyopaque;
const BOOL = i8;
const YES: BOOL = 1;
const NO: BOOL = 0;

const CGFloat = f64;
const CGPoint = extern struct { x: CGFloat, y: CGFloat };
const CGSize = extern struct { width: CGFloat, height: CGFloat };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

fn sel(name: [*:0]const u8) SEL {
    return c.sel_registerName(name);
}

fn cls(name: [*:0]const u8) Class {
    return c.objc_getClass(name).?;
}

fn msg(target: anytype, sel_name: [*:0]const u8, args: anytype) id {
    const func: *const fn (id, SEL, ...) callconv(.c) id = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgVoid(target: anytype, sel_name: [*:0]const u8, args: anytype) void {
    const func: *const fn (id, SEL, ...) callconv(.c) void = @ptrCast(&c.objc_msgSend);
    @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgBool(target: anytype, sel_name: [*:0]const u8, args: anytype) BOOL {
    const func: *const fn (id, SEL, ...) callconv(.c) BOOL = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgU16(target: anytype, sel_name: [*:0]const u8, args: anytype) u16 {
    const func: *const fn (id, SEL, ...) callconv(.c) u16 = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgU64(target: anytype, sel_name: [*:0]const u8, args: anytype) u64 {
    const func: *const fn (id, SEL, ...) callconv(.c) u64 = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgRect(target: anytype, sel_name: [*:0]const u8, args: anytype) CGRect {
    // On x86_64, stret is used for structs > 16 bytes. On ARM64, regular msgSend works.
    const func: *const fn (id, SEL, ...) callconv(.c) CGRect = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msgPoint(target: anytype, sel_name: [*:0]const u8, args: anytype) CGPoint {
    const func: *const fn (id, SEL, ...) callconv(.c) CGPoint = @ptrCast(&c.objc_msgSend);
    return @call(.auto, func, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

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

ns_app: id,
ns_window: id,
metal_layer: id,

pub fn init(options: shared.InitOptions) !MacOSWindow {
    const NSApplication = cls("NSApplication");
    const app = msg(NSApplication, "sharedApplication", .{});

    // NSApplicationActivationPolicyRegular = 0
    msgVoid(app, "setActivationPolicy:", .{@as(i64, 0)});

    const NSWindow = cls("NSWindow");
    const alloc = msg(NSWindow, "alloc", .{});

    const style_mask: u64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3);
    const rect = CGRect{
        .origin = .{ .x = 100, .y = 100 },
        .size = .{ .width = @floatFromInt(options.width), .height = @floatFromInt(options.height) },
    };

    const window = msg(alloc, "initWithContentRect:styleMask:backing:defer:", .{
        rect,
        style_mask,
        @as(u64, 2), // NSBackingStoreBuffered
        NO,
    });

    const title_str = msg(cls("NSString"), "stringWithUTF8String:", .{options.title});
    msgVoid(window, "setTitle:", .{title_str});

    const content_view = msg(window, "contentView", .{});
    msgVoid(content_view, "setWantsLayer:", .{YES});

    const layer = msg(cls("CAMetalLayer"), "layer", .{});
    msgVoid(content_view, "setLayer:", .{layer});

    msgVoid(window, "setAcceptsMouseMovedEvents:", .{YES});

    return .{
        .width = options.width,
        .height = options.height,
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
        .ns_app = app,
        .ns_window = window,
        .metal_layer = layer,
    };
}

pub fn start(_: *MacOSWindow) !void {}

pub fn deinit(self: *MacOSWindow) void {
    msgVoid(self.ns_window, "close", .{});
}

pub fn show(self: *MacOSWindow) void {
    msgVoid(self.ns_window, "makeKeyAndOrderFront:", .{@as(?id, null)});
    msgVoid(self.ns_app, "activateIgnoringOtherApps:", .{YES});
}

pub fn shouldClose(self: *MacOSWindow) bool {
    return self.should_close_flag;
}

pub fn pollEvents(self: *MacOSWindow, window: *Window) void {
    const run_loop_mode = msg(cls("NSString"), "stringWithUTF8String:", .{@as([*:0]const u8, "kCFRunLoopDefaultMode")});

    while (true) {
        const event_or_null = msg(self.ns_app, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
            @as(u64, 0xFFFFFFFFFFFFFFFF),
            @as(?id, null),
            run_loop_mode,
            YES,
        });

        // Check if event is nil (null pointer).
        if (@intFromPtr(event_or_null) == 0) break;

        const event_type = msgU64(event_or_null, "type", .{});

        switch (event_type) {
            1 => { // NSEventTypeLeftMouseDown
                self.mouse_buttons |= @intFromEnum(Window.MouseButton.left);
                updateMouseFromEvent(self, event_or_null);
                window.pushEvent(.{ .mouse_click = .{ .x = self.mouse_x, .y = self.mouse_y, .button = @intFromEnum(Window.MouseButton.left) } });
            },
            2 => self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.left),
            3 => { // NSEventTypeRightMouseDown
                self.mouse_buttons |= @intFromEnum(Window.MouseButton.right);
                updateMouseFromEvent(self, event_or_null);
                window.pushEvent(.{ .mouse_click = .{ .x = self.mouse_x, .y = self.mouse_y, .button = @intFromEnum(Window.MouseButton.right) } });
            },
            4 => self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.right),
            5, 6, 27 => updateMouseFromEvent(self, event_or_null),
            10 => { // NSEventTypeKeyDown
                const keycode = msgU16(event_or_null, "keyCode", .{});
                const key = Key.fromMacKeyCode(keycode);
                if (key != .unknown and !self.keys_pressed.contains(key)) {
                    self.keys_pressed.insert(key);
                    window.pushEvent(.{ .key_press = key });
                }
            },
            11 => { // NSEventTypeKeyUp
                const keycode = msgU16(event_or_null, "keyCode", .{});
                const key = Key.fromMacKeyCode(keycode);
                if (key != .unknown) {
                    self.keys_pressed.remove(key);
                    window.pushEvent(.{ .key_release = key });
                }
            },
            12 => handleModifierFlags(self, event_or_null, window),
            else => {},
        }

        msgVoid(self.ns_app, "sendEvent:", .{event_or_null});
    }

    // Check window visibility (close detection).
    if (msgBool(self.ns_window, "isVisible", .{}) == NO) {
        self.should_close_flag = true;
    }

    // Check resize.
    const frame = msgRect(self.ns_window, "frame", .{});
    const content = msgRect(self.ns_window, "contentRectForFrameRect:", .{frame});
    const new_w: u32 = @intFromFloat(@max(1.0, content.size.width));
    const new_h: u32 = @intFromFloat(@max(1.0, content.size.height));
    if (new_w != self.width or new_h != self.height) {
        self.new_width = new_w;
        self.new_height = new_h;
        self.needs_resize = true;
    }
}

fn updateMouseFromEvent(self: *MacOSWindow, event: id) void {
    const loc = msgPoint(event, "locationInWindow", .{});
    self.mouse_x = @floatCast(loc.x);
    self.mouse_y = @as(f32, @floatFromInt(self.height)) - @as(f32, @floatCast(loc.y));
}

fn handleModifierFlags(self: *MacOSWindow, event: id, window: *Window) void {
    const flags = msgU64(event, "modifierFlags", .{});
    const pairs = [_]struct { mask: u64, key: Key }{
        .{ .mask = 1 << 17, .key = .left_shift },
        .{ .mask = 1 << 18, .key = .left_control },
        .{ .mask = 1 << 19, .key = .left_alt },
        .{ .mask = 1 << 20, .key = .left_super },
    };
    for (pairs) |p| {
        const pressed = (flags & p.mask) != 0;
        const was_pressed = self.keys_pressed.contains(p.key);
        if (pressed and !was_pressed) {
            self.keys_pressed.insert(p.key);
            window.pushEvent(.{ .key_press = p.key });
        } else if (!pressed and was_pressed) {
            self.keys_pressed.remove(p.key);
            window.pushEvent(.{ .key_release = p.key });
        }
    }
}

pub fn getNativeHandles(self: *MacOSWindow) shared.NativeHandles {
    return .{ .metal = self.metal_layer };
}

pub fn getSize(self: *MacOSWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(self: *MacOSWindow) bool {
    return self.needs_resize;
}

pub fn getNewSize(self: *MacOSWindow) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *MacOSWindow) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}

pub fn getMousePosition(self: *MacOSWindow) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *MacOSWindow) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *MacOSWindow, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *MacOSWindow) std.EnumSet(Key) {
    return self.keys_pressed;
}
