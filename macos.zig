const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const Window = @import("Window.zig");
const objc = @import("objc");

const MacOSWindow = @This();

const Object = objc.Object;
const Class = objc.Class;
const sel = objc.sel;

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

ns_app: Object,
ns_window: Object,
metal_layer: Object,

pub fn init(options: shared.InitOptions) !MacOSWindow {
    // [NSApplication sharedApplication]
    const NSApplication = Class.getClass("NSApplication") orelse return error.CocoaInitFailed;
    const app = NSApplication.msgSend(Object, sel("sharedApplication"), .{});

    // [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]
    app.msgSend(void, sel("setActivationPolicy:"), .{@as(i64, 0)});

    // Create window: [[NSWindow alloc] initWithContentRect:styleMask:backing:defer:]
    const NSWindow = Class.getClass("NSWindow") orelse return error.CocoaInitFailed;
    const alloc = NSWindow.msgSend(Object, sel("alloc"), .{});

    const style_mask: u64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3); // titled | closable | miniaturizable | resizable
    const backing: u64 = 2; // NSBackingStoreBuffered

    const rect = CGRect{
        .origin = .{ .x = 100, .y = 100 },
        .size = .{ .width = @floatFromInt(options.width), .height = @floatFromInt(options.height) },
    };

    const window = alloc.msgSend(Object, sel("initWithContentRect:styleMask:backing:defer:"), .{
        rect,
        style_mask,
        backing,
        @as(i8, 0), // defer: NO
    });

    // Set title
    const NSString = Class.getClass("NSString") orelse return error.CocoaInitFailed;
    const title = NSString.msgSend(Object, sel("stringWithUTF8String:"), .{options.title});
    window.msgSend(void, sel("setTitle:"), .{title});

    // Set up metal layer on the content view
    const content_view = window.msgSend(Object, sel("contentView"), .{});
    content_view.msgSend(void, sel("setWantsLayer:"), .{@as(i8, 1)});

    const CAMetalLayer = Class.getClass("CAMetalLayer") orelse return error.CocoaInitFailed;
    const layer = CAMetalLayer.msgSend(Object, sel("layer"), .{});
    content_view.msgSend(void, sel("setLayer:"), .{layer});

    // Accept mouse events
    window.msgSend(void, sel("setAcceptsMouseMovedEvents:"), .{@as(i8, 1)});

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
    self.ns_window.msgSend(void, sel("close"), .{});
}

pub fn show(self: *MacOSWindow) void {
    self.ns_window.msgSend(void, sel("makeKeyAndOrderFront:"), .{@as(?Object, null)});
    self.ns_app.msgSend(void, sel("activateIgnoringOtherApps:"), .{@as(i8, 1)});
}

pub fn shouldClose(self: *MacOSWindow) bool {
    return self.should_close_flag;
}

pub fn pollEvents(self: *MacOSWindow, window: *Window) void {
    while (true) {
        // [NSApp nextEventMatchingMask:untilDate:inMode:dequeue:]
        const NSDefaultRunLoopMode = objc.getClass("NSString").?.msgSend(
            Object,
            sel("stringWithUTF8String:"),
            .{@as([*:0]const u8, "kCFRunLoopDefaultMode")},
        );

        const event = self.ns_app.msgSend(?Object, sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), .{
            @as(u64, 0xFFFFFFFFFFFFFFFF), // NSEventMaskAny
            @as(?Object, null), // untilDate: nil (don't wait)
            NSDefaultRunLoopMode,
            @as(i8, 1), // dequeue: YES
        }) orelse break;

        const event_type: u64 = event.msgSend(u64, sel("type"), .{});

        switch (event_type) {
            1 => { // NSEventTypeLeftMouseDown
                self.mouse_buttons |= @intFromEnum(Window.MouseButton.left);
                const loc = getMouseLocation(event, self);
                window.pushEvent(.{ .mouse_click = .{ .x = loc.x, .y = loc.y, .button = @intFromEnum(Window.MouseButton.left) } });
            },
            2 => { // NSEventTypeLeftMouseUp
                self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.left);
            },
            3 => { // NSEventTypeRightMouseDown
                self.mouse_buttons |= @intFromEnum(Window.MouseButton.right);
                const loc = getMouseLocation(event, self);
                window.pushEvent(.{ .mouse_click = .{ .x = loc.x, .y = loc.y, .button = @intFromEnum(Window.MouseButton.right) } });
            },
            4 => { // NSEventTypeRightMouseUp
                self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.right);
            },
            5, 6, 27 => { // MouseMoved, LeftMouseDragged, OtherMouseDragged
                const loc = getMouseLocation(event, self);
                self.mouse_x = loc.x;
                self.mouse_y = loc.y;
            },
            7 => { // NSEventTypeMouseEntered
            },
            10 => { // NSEventTypeKeyDown
                const keycode: u16 = event.msgSend(u16, sel("keyCode"), .{});
                const key = Key.fromMacKeyCode(keycode);
                if (key != .unknown and !self.keys_pressed.contains(key)) {
                    self.keys_pressed.insert(key);
                    window.pushEvent(.{ .key_press = key });
                }
            },
            11 => { // NSEventTypeKeyUp
                const keycode: u16 = event.msgSend(u16, sel("keyCode"), .{});
                const key = Key.fromMacKeyCode(keycode);
                if (key != .unknown) {
                    self.keys_pressed.remove(key);
                    window.pushEvent(.{ .key_release = key });
                }
            },
            12 => { // NSEventTypeFlagsChanged (modifier keys)
                handleModifierFlags(self, event, window);
            },
            else => {},
        }

        // [NSApp sendEvent:event] — forward to normal Cocoa handling
        self.ns_app.msgSend(void, sel("sendEvent:"), .{event});
    }

    // Check window close
    if (self.ns_window.msgSend(i8, sel("isVisible"), .{}) == 0) {
        self.should_close_flag = true;
    }

    // Check resize
    const frame = self.ns_window.msgSend(CGRect, sel("contentRectForFrameRect:"), .{
        self.ns_window.msgSend(CGRect, sel("frame"), .{}),
    });
    const new_w: u32 = @intFromFloat(@max(1.0, frame.size.width));
    const new_h: u32 = @intFromFloat(@max(1.0, frame.size.height));
    if (new_w != self.width or new_h != self.height) {
        self.new_width = new_w;
        self.new_height = new_h;
        self.needs_resize = true;
    }
}

fn getMouseLocation(event: Object, self: *MacOSWindow) shared.MousePosition {
    const loc = event.msgSend(CGPoint, sel("locationInWindow"), .{});
    return .{
        .x = @floatCast(loc.x),
        .y = @as(f32, @floatFromInt(self.height)) - @as(f32, @floatCast(loc.y)),
    };
}

fn handleModifierFlags(self: *MacOSWindow, event: Object, window: *Window) void {
    const flags: u64 = event.msgSend(u64, sel("modifierFlags"), .{});
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
    return .{ .metal = self.metal_layer.value };
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

const CGFloat = f64;
const CGPoint = extern struct { x: CGFloat, y: CGFloat };
const CGSize = extern struct { width: CGFloat, height: CGFloat };
const CGRect = extern struct { origin: CGPoint, size: CGSize };
