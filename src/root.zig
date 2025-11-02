const std = @import("std");

const Display = @import("wayland/Display.zig");
const Registry = @import("wayland/Registry.zig");
const Surface = @import("wayland/Surface.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Display);
    std.testing.refAllDecls(Registry);
    std.testing.refAllDecls(Surface);
}
