const std = @import("std");

pub const Window = @import("Window.zig");
pub const Key = @import("Key.zig").Key;
pub const MouseButton = @import("backends/wayland/Pointer.zig").MouseButton;

const Display = @import("backends/wayland/Display.zig");
const Registry = @import("backends/wayland/Registry.zig");
const Surface = @import("backends/wayland/Surface.zig");
const XdgSurface = @import("backends/wayland/XdgSurface.zig");
const XdgToplevel = @import("backends/wayland/XdgToplevel.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Window);
    std.testing.refAllDecls(Display);
    std.testing.refAllDecls(Registry);
    std.testing.refAllDecls(Surface);
    std.testing.refAllDecls(XdgSurface);
    std.testing.refAllDecls(XdgToplevel);
}
