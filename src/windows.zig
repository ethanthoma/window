const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const Window = @import("Window.zig");

const WindowsWindow = @This();

const HANDLE = *anyopaque;
const HINSTANCE = HANDLE;
const HWND = HANDLE;
const HICON = HANDLE;
const HCURSOR = HANDLE;
const HBRUSH = HANDLE;
const HMENU = HANDLE;
const HMODULE = HANDLE;
const BOOL = i32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const UINT = u32;
const ATOM = u16;
const LPCSTR = [*:0]const u8;
const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const WNDCLASSEXA = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?LPCSTR,
    lpszClassName: LPCSTR,
    hIconSm: ?HICON,
};

const POINT = extern struct { x: i32, y: i32 };
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
    lPrivate: u32,
};

const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const CS_OWNDC: u32 = 0x0020;
const SW_SHOW: i32 = 5;
const PM_REMOVE: u32 = 1;

const WM_DESTROY: UINT = 0x0002;
const WM_SIZE: UINT = 0x0005;
const WM_CLOSE: UINT = 0x0010;
const WM_KEYDOWN: UINT = 0x0100;
const WM_KEYUP: UINT = 0x0101;
const WM_SYSKEYDOWN: UINT = 0x0104;
const WM_SYSKEYUP: UINT = 0x0105;
const WM_MOUSEMOVE: UINT = 0x0200;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_RBUTTONUP: UINT = 0x0205;

const IDC_ARROW: LPCSTR = @ptrFromInt(32512);
const CLASS_NAME: LPCSTR = "ZigGameWindow";

extern "user32" fn RegisterClassExA(wcx: *const WNDCLASSEXA) callconv(.winapi) ATOM;
extern "user32" fn CreateWindowExA(
    dwExStyle: u32,
    lpClassName: LPCSTR,
    lpWindowName: LPCSTR,
    dwStyle: u32,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
extern "user32" fn DefWindowProcA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn PeekMessageA(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
extern "user32" fn LoadCursorA(hInstance: ?HINSTANCE, lpCursorName: LPCSTR) callconv(.winapi) ?HCURSOR;
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?LPCSTR) callconv(.winapi) ?HMODULE;

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

hinstance: HINSTANCE,
hwnd: HWND,

threadlocal var current_backend: ?*WindowsWindow = null;
threadlocal var current_window: ?*Window = null;
var class_registered: bool = false;

pub fn init(options: shared.InitOptions) !WindowsWindow {
    const hinstance = GetModuleHandleA(null) orelse return error.GetModuleHandleFailed;

    if (!class_registered) {
        const wc = WNDCLASSEXA{
            .cbSize = @sizeOf(WNDCLASSEXA),
            .style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC,
            .lpfnWndProc = &wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hinstance,
            .hIcon = null,
            .hCursor = LoadCursorA(null, IDC_ARROW),
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = CLASS_NAME,
            .hIconSm = null,
        };
        if (RegisterClassExA(&wc) == 0) return error.RegisterClassFailed;
        class_registered = true;
    }

    const hwnd = CreateWindowExA(
        0,
        CLASS_NAME,
        options.title,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        @intCast(options.width),
        @intCast(options.height),
        null,
        null,
        hinstance,
        null,
    ) orelse return error.CreateWindowFailed;

    var rect: RECT = undefined;
    _ = GetClientRect(hwnd, &rect);
    const client_w: u32 = @intCast(rect.right - rect.left);
    const client_h: u32 = @intCast(rect.bottom - rect.top);

    return .{
        .width = client_w,
        .height = client_h,
        .mouse_x = @as(f32, @floatFromInt(client_w)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(client_h)) / 2.0,
        .hinstance = hinstance,
        .hwnd = hwnd,
    };
}

pub fn start(_: *WindowsWindow) !void {}

pub fn deinit(self: *WindowsWindow) void {
    _ = DestroyWindow(self.hwnd);
}

pub fn show(self: *WindowsWindow) void {
    _ = ShowWindow(self.hwnd, SW_SHOW);
}

pub fn shouldClose(self: *WindowsWindow) bool {
    return self.should_close_flag;
}

pub fn pollEvents(self: *WindowsWindow, window: *Window) void {
    current_backend = self;
    current_window = window;
    defer {
        current_backend = null;
        current_window = null;
    }

    var msg: MSG = undefined;
    while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
    }
}

fn wndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    const self = current_backend orelse return DefWindowProcA(hwnd, msg, wparam, lparam);
    const win = current_window orelse return DefWindowProcA(hwnd, msg, wparam, lparam);

    switch (msg) {
        WM_CLOSE, WM_DESTROY => {
            self.should_close_flag = true;
            return 0;
        },
        WM_SIZE => {
            const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
            const new_w: u32 = @max(1, lp32 & 0xFFFF);
            const new_h: u32 = @max(1, (lp32 >> 16) & 0xFFFF);
            if (new_w != self.width or new_h != self.height) {
                self.new_width = new_w;
                self.new_height = new_h;
                self.needs_resize = true;
            }
            return 0;
        },
        WM_MOUSEMOVE => {
            const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
            const x: i16 = @bitCast(@as(u16, @intCast(lp32 & 0xFFFF)));
            const y: i16 = @bitCast(@as(u16, @intCast((lp32 >> 16) & 0xFFFF)));
            self.mouse_x = @floatFromInt(x);
            self.mouse_y = @floatFromInt(y);
            return 0;
        },
        WM_LBUTTONDOWN => {
            self.mouse_buttons |= @intFromEnum(Window.MouseButton.left);
            win.pushEvent(.{ .mouse_click = .{ .x = self.mouse_x, .y = self.mouse_y, .button = @intFromEnum(Window.MouseButton.left) } });
            return 0;
        },
        WM_LBUTTONUP => {
            self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.left);
            return 0;
        },
        WM_RBUTTONDOWN => {
            self.mouse_buttons |= @intFromEnum(Window.MouseButton.right);
            win.pushEvent(.{ .mouse_click = .{ .x = self.mouse_x, .y = self.mouse_y, .button = @intFromEnum(Window.MouseButton.right) } });
            return 0;
        },
        WM_RBUTTONUP => {
            self.mouse_buttons &= ~@intFromEnum(Window.MouseButton.right);
            return 0;
        },
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            const key = decodeKey(@intCast(wparam), lparam);
            if (key != .unknown and !self.keys_pressed.contains(key)) {
                self.keys_pressed.insert(key);
                win.pushEvent(.{ .key_press = key });
            }
            return 0;
        },
        WM_KEYUP, WM_SYSKEYUP => {
            const key = decodeKey(@intCast(wparam), lparam);
            if (key != .unknown) {
                self.keys_pressed.remove(key);
                win.pushEvent(.{ .key_release = key });
            }
            return 0;
        },
        else => return DefWindowProcA(hwnd, msg, wparam, lparam),
    }
}

fn decodeKey(vk: u32, lparam: LPARAM) Key {
    const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
    const scan_code: u8 = @intCast((lp32 >> 16) & 0xFF);
    const extended: bool = (lp32 & (1 << 24)) != 0;

    return switch (vk) {
        0x10 => if (scan_code == 0x36) Key.right_shift else Key.left_shift,
        0x11 => if (extended) Key.right_control else Key.left_control,
        0x12 => if (extended) Key.right_alt else Key.left_alt,
        else => Key.fromWindowsVKey(vk),
    };
}

pub fn getNativeHandles(self: *WindowsWindow) shared.NativeHandles {
    return .{ .win32 = .{ .hinstance = self.hinstance, .hwnd = self.hwnd } };
}

pub fn getSize(self: *WindowsWindow) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(self: *WindowsWindow) bool {
    return self.needs_resize;
}

pub fn getNewSize(self: *WindowsWindow) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *WindowsWindow) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}

pub fn getMousePosition(self: *WindowsWindow) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *WindowsWindow) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *WindowsWindow, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *WindowsWindow) std.EnumSet(Key) {
    return self.keys_pressed;
}
