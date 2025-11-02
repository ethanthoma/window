const std = @import("std");

const Display = @This();

pub const wl_display = extern struct {};
pub const wl_registry = extern struct {};

extern "c" fn wl_display_connect(?[*:0]const u8) ?*wl_display;
extern "c" fn wl_display_disconnect(*wl_display) void;
extern "c" fn wl_display_dispatch(*wl_display) i32;
extern "c" fn wl_display_dispatch_pending(*wl_display) i32;
extern "c" fn wl_display_roundtrip(*wl_display) i32;
extern "c" fn wl_display_get_error(*wl_display) i32;
extern "c" fn wl_display_flush(*wl_display) i32;
extern "c" fn wl_display_get_fd(*wl_display) i32;
extern "c" fn wl_display_prepare_read(*wl_display) i32;
extern "c" fn wl_display_read_events(*wl_display) i32;
extern "c" fn wl_display_cancel_read(*wl_display) void;
extern "c" fn wl_display_get_registry_wrapper(*wl_display) ?*wl_registry;

display: *wl_display,

pub fn connect(name: ?[*:0]const u8) !Display {
    const display = wl_display_connect(name) orelse return error.ConnectionFailed;
    return .{ .display = display };
}

pub fn disconnect(self: Display) void {
    wl_display_disconnect(self.display);
}

pub fn dispatch(self: Display) !void {
    const result = wl_display_dispatch(self.display);
    if (result < 0) return error.DispatchFailed;
}

pub fn dispatchPending(self: Display) !void {
    const result = wl_display_dispatch_pending(self.display);
    if (result < 0) return error.DispatchFailed;
}

pub fn roundtrip(self: Display) !void {
    const result = wl_display_roundtrip(self.display);
    if (result < 0) return error.RoundtripFailed;
}

pub fn flush(self: Display) !void {
    const result = wl_display_flush(self.display);
    if (result < 0) return error.FlushFailed;
}

pub fn getError(self: Display) ?i32 {
    const err = wl_display_get_error(self.display);
    return if (err == 0) null else err;
}

pub fn getRegistry(self: Display) !*wl_registry {
    return wl_display_get_registry_wrapper(self.display) orelse error.RegistryFailed;
}

test "display connect and disconnect" {
    const display = connect(null) catch |err| {
        if (err == error.ConnectionFailed) {
            std.debug.print("Wayland compositor not available, skipping test\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer display.disconnect();

    try std.testing.expect(display.getError() == null);
}

test "display roundtrip" {
    const display = connect(null) catch return error.SkipZigTest;
    defer display.disconnect();

    try display.roundtrip();
    try std.testing.expect(display.getError() == null);
}
