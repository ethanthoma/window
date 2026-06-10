// Cross-platform windowing library
// Supports Wayland, X11, Win32, and macOS

pub const Window = @import("Window.zig");
pub const Event = Window.Event;
pub const Action = Window.Action;
pub const Position = Window.Position;
pub const Scroll = Window.Scroll;
pub const Key = Window.Key;
pub const MouseButton = Window.MouseButton;
pub const InitOptions = Window.InitOptions;
pub const Size = Window.Size;
pub const NativeHandles = Window.NativeHandles;

test {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(Window);
}
