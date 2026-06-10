const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;
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
const WM_MBUTTONDOWN: UINT = 0x0207;
const WM_MBUTTONUP: UINT = 0x0208;
const WM_MOUSEWHEEL: UINT = 0x020A;
const WM_MOUSEHWHEEL: UINT = 0x020E;

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

    return .{
        .width = @intCast(rect.right - rect.left),
        .height = @intCast(rect.bottom - rect.top),
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

fn mouseX(lparam: LPARAM) f32 {
    const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
    const x: i16 = @bitCast(@as(u16, @intCast(lp32 & 0xFFFF)));
    return @floatFromInt(x);
}

fn mouseY(lparam: LPARAM) f32 {
    const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
    const y: i16 = @bitCast(@as(u16, @intCast((lp32 >> 16) & 0xFFFF)));
    return @floatFromInt(y);
}

fn wheelDelta(wparam: WPARAM) f32 {
    const delta: i16 = @bitCast(@as(u16, @intCast((wparam >> 16) & 0xFFFF)));
    return @as(f32, @floatFromInt(delta)) / 120.0;
}

fn wndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    const self = current_backend orelse return DefWindowProcA(hwnd, msg, wparam, lparam);
    const win = current_window orelse return DefWindowProcA(hwnd, msg, wparam, lparam);

    switch (msg) {
        WM_CLOSE, WM_DESTROY => {
            win.pushEvent(.close);
            return 0;
        },
        WM_SIZE => {
            const lp32: u32 = @truncate(@as(usize, @bitCast(lparam)));
            const new_w: u32 = @max(1, lp32 & 0xFFFF);
            const new_h: u32 = @max(1, (lp32 >> 16) & 0xFFFF);
            if (new_w != self.width or new_h != self.height) {
                self.width = new_w;
                self.height = new_h;
                win.pushEvent(.{ .resize = .{ .width = new_w, .height = new_h } });
            }
            return 0;
        },
        WM_MOUSEMOVE => {
            win.pushEvent(.{ .mouse_move = .{ .x = mouseX(lparam), .y = mouseY(lparam) } });
            return 0;
        },
        WM_LBUTTONDOWN, WM_LBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP => {
            const button: MouseButton = switch (msg) {
                WM_LBUTTONDOWN, WM_LBUTTONUP => .left,
                WM_RBUTTONDOWN, WM_RBUTTONUP => .right,
                else => .middle,
            };
            const action: Window.Action = switch (msg) {
                WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN => .press,
                else => .release,
            };
            win.pushEvent(.{ .mouse_button = .{
                .button = button,
                .action = action,
                .x = mouseX(lparam),
                .y = mouseY(lparam),
            } });
            return 0;
        },
        WM_MOUSEWHEEL => {
            win.pushEvent(.{ .mouse_scroll = .{ .dx = 0, .dy = -wheelDelta(wparam) } });
            return 0;
        },
        WM_MOUSEHWHEEL => {
            win.pushEvent(.{ .mouse_scroll = .{ .dx = wheelDelta(wparam), .dy = 0 } });
            return 0;
        },
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            win.pushEvent(.{ .key = .{ .key = decodeKey(@intCast(wparam), lparam), .action = .press } });
            return 0;
        },
        WM_KEYUP, WM_SYSKEYUP => {
            win.pushEvent(.{ .key = .{ .key = decodeKey(@intCast(wparam), lparam), .action = .release } });
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
