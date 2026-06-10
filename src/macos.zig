const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;
const Window = @import("Window.zig");

const c = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

extern fn MTLCreateSystemDefaultDevice() ?*anyopaque;

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
    return c.sel_registerName(name) orelse unreachable;
}

fn cls(name: [*:0]const u8) Class {
    return c.objc_getClass(name) orelse unreachable;
}

// Casting objc_msgSend to a variadic fn pointer breaks on Apple ARM64:
// variadic args are passed on the stack, but objc_msgSend's resolved IMP
// expects them in registers (x2-x7 for ints/pointers, d0-d7 for floats,
// HFA layout for NSRect). Build a non-variadic fn type per call from the
// args tuple so the regular AAPCS64 register convention is used.
inline fn objcCall(comptime Ret: type, target: anytype, sel_name: [*:0]const u8, args: anytype) Ret {
    const args_info = @typeInfo(@TypeOf(args)).@"struct";
    const FnType = comptime fn_ty: {
        var param_types: [2 + args_info.fields.len]type = undefined;
        param_types[0] = id;
        param_types[1] = SEL;
        for (args_info.fields, 0..) |f, i| {
            param_types[2 + i] = f.type;
        }
        const param_attrs = [_]std.builtin.Type.Fn.Param.Attributes{.{}} ** param_types.len;
        break :fn_ty @Fn(&param_types, &param_attrs, Ret, .{ .@"callconv" = .c });
    };

    const f: *const FnType = @ptrCast(&c.objc_msgSend);
    return @call(.auto, f, .{ @as(id, @ptrCast(target)), sel(sel_name) } ++ args);
}

fn msg(target: anytype, sel_name: [*:0]const u8, args: anytype) id {
    return objcCall(id, target, sel_name, args);
}

fn msgVoid(target: anytype, sel_name: [*:0]const u8, args: anytype) void {
    return objcCall(void, target, sel_name, args);
}

fn msgBool(target: anytype, sel_name: [*:0]const u8, args: anytype) BOOL {
    return objcCall(BOOL, target, sel_name, args);
}

fn msgU16(target: anytype, sel_name: [*:0]const u8, args: anytype) u16 {
    return objcCall(u16, target, sel_name, args);
}

fn msgU64(target: anytype, sel_name: [*:0]const u8, args: anytype) u64 {
    return objcCall(u64, target, sel_name, args);
}

fn msgF64(target: anytype, sel_name: [*:0]const u8, args: anytype) f64 {
    return objcCall(f64, target, sel_name, args);
}

// Struct args/returns must use non-variadic typed signatures. On ARM64 Darwin,
// objc_msgSend's variadic ABI puts struct args on the stack but the method
// expects them in float registers (d0-d3 for NSRect). Variadic returns
// have similar issues. Use typed wrappers for any selector touching CGRect/CGPoint.

fn msgFrame(target: id) CGRect {
    const Fn = *const fn (id, SEL) callconv(.c) CGRect;
    const f: Fn = @ptrCast(&c.objc_msgSend);
    return f(target, sel("frame"));
}

fn msgContentRectForFrameRect(target: id, frame: CGRect) CGRect {
    const Fn = *const fn (id, SEL, CGRect) callconv(.c) CGRect;
    const f: Fn = @ptrCast(&c.objc_msgSend);
    return f(target, sel("contentRectForFrameRect:"), frame);
}

fn msgLocationInWindow(event: id) CGPoint {
    const Fn = *const fn (id, SEL) callconv(.c) CGPoint;
    const f: Fn = @ptrCast(&c.objc_msgSend);
    return f(event, sel("locationInWindow"));
}

fn msgInitWindow(alloc: id, rect: CGRect, style: u64, backing: u64, defer_flag: BOOL) id {
    const Fn = *const fn (id, SEL, CGRect, u64, u64, BOOL) callconv(.c) id;
    const f: Fn = @ptrCast(&c.objc_msgSend);
    return f(alloc, sel("initWithContentRect:styleMask:backing:defer:"), rect, style, backing, defer_flag);
}

width: u32,
height: u32,
close_pushed: bool = false,
modifier_keys: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

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

    const window = msgInitWindow(alloc, rect, style_mask, 2, NO);

    const title_str = msg(cls("NSString"), "stringWithUTF8String:", .{options.title});
    msgVoid(window, "setTitle:", .{title_str});

    const content_view = msg(window, "contentView", .{});

    // Layer-hosting NSView: set layer BEFORE wantsLayer (Apple docs).
    // Reverse order makes it layer-backed with an AppKit-owned plain
    // CALayer, which wgpu rejects when initializing the Metal surface.
    // Use alloc/init (not +[CAMetalLayer layer]) — the latter is
    // autoreleased and can disappear before wgpu's surface holds it.
    const layer_alloc = msg(cls("CAMetalLayer"), "alloc", .{});
    const layer = msg(layer_alloc, "init", .{});

    // Set Metal device on the layer. Some wgpu-native versions reject
    // surfaces from a CAMetalLayer that has no device assigned yet.
    if (MTLCreateSystemDefaultDevice()) |metal_device| {
        msgVoid(layer, "setDevice:", .{@as(id, @ptrCast(metal_device))});
    }

    msgVoid(content_view, "setLayer:", .{layer});
    msgVoid(content_view, "setWantsLayer:", .{YES});

    msgVoid(window, "setAcceptsMouseMovedEvents:", .{YES});

    return .{
        .width = options.width,
        .height = options.height,
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

fn mouseLocation(self: *MacOSWindow, event: id) Window.Position {
    const loc = msgLocationInWindow(event);
    return .{
        .x = @floatCast(loc.x),
        .y = @as(f32, @floatFromInt(self.height)) - @as(f32, @floatCast(loc.y)),
    };
}

fn pushButton(self: *MacOSWindow, window: *Window, event: id, button: MouseButton, action: Window.Action) void {
    const pos = self.mouseLocation(event);
    window.pushEvent(.{ .mouse_button = .{ .button = button, .action = action, .x = pos.x, .y = pos.y } });
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
            1 => self.pushButton(window, event_or_null, .left, .press), // NSEventTypeLeftMouseDown
            2 => self.pushButton(window, event_or_null, .left, .release),
            3 => self.pushButton(window, event_or_null, .right, .press), // NSEventTypeRightMouseDown
            4 => self.pushButton(window, event_or_null, .right, .release),
            25, 26 => { // NSEventTypeOtherMouseDown/Up
                if (msgU64(event_or_null, "buttonNumber", .{}) == 2) {
                    self.pushButton(window, event_or_null, .middle, if (event_type == 25) .press else .release);
                }
            },
            5, 6, 7, 27 => { // moved + left/right/other dragged
                const pos = self.mouseLocation(event_or_null);
                window.pushEvent(.{ .mouse_move = pos });
            },
            10 => { // NSEventTypeKeyDown
                const keycode = msgU16(event_or_null, "keyCode", .{});
                window.pushEvent(.{ .key = .{ .key = Key.fromMacKeyCode(keycode), .action = .press } });
            },
            11 => { // NSEventTypeKeyUp
                const keycode = msgU16(event_or_null, "keyCode", .{});
                window.pushEvent(.{ .key = .{ .key = Key.fromMacKeyCode(keycode), .action = .release } });
            },
            12 => handleModifierFlags(self, event_or_null, window),
            22 => { // NSEventTypeScrollWheel
                const dx = msgF64(event_or_null, "scrollingDeltaX", .{});
                const dy = msgF64(event_or_null, "scrollingDeltaY", .{});
                window.pushEvent(.{ .mouse_scroll = .{
                    .dx = -@as(f32, @floatCast(dx)),
                    .dy = -@as(f32, @floatCast(dy)),
                } });
            },
            else => {},
        }

        msgVoid(self.ns_app, "sendEvent:", .{event_or_null});
    }

    // Check window visibility (close detection).
    if (msgBool(self.ns_window, "isVisible", .{}) == NO and !self.close_pushed) {
        self.close_pushed = true;
        window.pushEvent(.close);
    }

    // Check resize.
    const frame = msgFrame(self.ns_window);
    const content = msgContentRectForFrameRect(self.ns_window, frame);
    const new_w: u32 = @intFromFloat(@max(1.0, content.size.width));
    const new_h: u32 = @intFromFloat(@max(1.0, content.size.height));
    if (new_w != self.width or new_h != self.height) {
        self.width = new_w;
        self.height = new_h;
        window.pushEvent(.{ .resize = .{ .width = new_w, .height = new_h } });
    }
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
        const was_pressed = self.modifier_keys.contains(p.key);
        if (pressed and !was_pressed) {
            self.modifier_keys.insert(p.key);
            window.pushEvent(.{ .key = .{ .key = p.key, .action = .press } });
        } else if (!pressed and was_pressed) {
            self.modifier_keys.remove(p.key);
            window.pushEvent(.{ .key = .{ .key = p.key, .action = .release } });
        }
    }
}

pub fn getNativeHandles(self: *MacOSWindow) shared.NativeHandles {
    return .{ .metal = self.metal_layer };
}

pub fn getSize(self: *MacOSWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}
