const std = @import("std");
const window_lib = @import("window");

pub fn main() !void {
    const window = try window_lib.Window.init("Basic Window Example", 800, 600);
    defer window.deinit();

    std.debug.print("Window created successfully!\n", .{});
    std.debug.print("Close the window to exit...\n", .{});

    while (!window.shouldClose()) {
        try window.pollEvents();
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }

    std.debug.print("Window closed, exiting...\n", .{});
}
