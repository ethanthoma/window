pub const InitOptions = struct {
    width: u32 = 800,
    height: u32 = 600,
    title: [*:0]const u8 = "Game Window",
};

pub const WaylandHandles = struct {
    display: *anyopaque,
    surface: *anyopaque,
};

pub const X11Handles = struct {
    display: *anyopaque,
    window: u64,
};

pub const Win32Handles = struct {
    hinstance: *anyopaque,
    hwnd: *anyopaque,
};

pub const MetalLayer = *anyopaque;

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const NativeHandles = union(enum) {
    wayland: WaylandHandles,
    x11: X11Handles,
    win32: Win32Handles,
    metal: MetalLayer,
};

pub const ClickEvent = struct {
    x: f32,
    y: f32,
    button: u8,
};

pub const MousePosition = struct {
    x: f32,
    y: f32,
};
