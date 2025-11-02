const std = @import("std");
const window_lib = @import("window");

pub fn main() !void {
    const window = try window_lib.Window.init("Basic Window Example", 800, 600);
    defer window.deinit();

    std.debug.print("Window created successfully!\n", .{});
    std.debug.print("Close the window to exit...\n", .{});

    var should_close = false;
    while (!should_close) {
        while (try window.pollEvent()) |event| switch (event) {
            .close => should_close = true,
            .configure => |config| {
                std.debug.print("Configure event: {}x{}\n", .{ config.width, config.height });
            },
            .key_press => |key| {
                std.debug.print("Key pressed: {s}\n", .{@tagName(key)});
                if (key == .q) should_close = true;
            },
            .key_release => |key| {
                std.debug.print("Key released: {s}\n", .{@tagName(key)});
            },
            .mouse_enter => |pos| {
                std.debug.print("Mouse entered at ({d:.1}, {d:.1})\n", .{ pos.x, pos.y });
            },
            .mouse_leave => {
                std.debug.print("Mouse left window\n", .{});
            },
            .mouse_button_press => |button| {
                std.debug.print("Mouse button pressed: {s}\n", .{@tagName(button)});
            },
            .mouse_button_release => |button| {
                std.debug.print("Mouse button released: {s}\n", .{@tagName(button)});
            },
            .mouse_scroll => |delta| {
                std.debug.print("Mouse scroll: ({d:.1}, {d:.1})\n", .{ delta.x, delta.y });
            },
            else => {},
        };

        std.Thread.sleep(16 * std.time.ns_per_ms);
    }

    std.debug.print("Window closed, exiting...\n", .{});
}
