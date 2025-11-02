const std = @import("std");

pub const Window = @import("Window.zig");

const Display = @import("wayland/Display.zig");
const Registry = @import("wayland/Registry.zig");
const Surface = @import("wayland/Surface.zig");
const XdgSurface = @import("wayland/XdgSurface.zig");
const XdgToplevel = @import("wayland/XdgToplevel.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Window);
    std.testing.refAllDecls(Display);
    std.testing.refAllDecls(Registry);
    std.testing.refAllDecls(Surface);
    std.testing.refAllDecls(XdgSurface);
    std.testing.refAllDecls(XdgToplevel);
}
