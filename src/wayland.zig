const std = @import("std");
const shared = @import("shared.zig");
const Key = @import("key.zig").Key;
const MouseButton = @import("mouse_button.zig").MouseButton;

const Wayland = @This();

const wl_proxy = extern struct {};

const wl_interface = extern struct {
    name: [*:0]const u8,
    version: i32,
    method_count: i32,
    methods: ?*const wl_message,
    event_count: i32,
    events: ?*const wl_message,
};

const wl_message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: ?*const ?*const wl_interface,
};

extern "c" fn wl_proxy_destroy(*wl_proxy) void;

const Display = struct {
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

    pub fn getFd(self: Display) i32 {
        return wl_display_get_fd(self.display);
    }

    pub fn prepareRead(self: Display) !void {
        const result = wl_display_prepare_read(self.display);
        if (result < 0) return error.PrepareReadFailed;
    }

    pub fn readEvents(self: Display) !void {
        const result = wl_display_read_events(self.display);
        if (result < 0) return error.ReadEventsFailed;
    }

    pub fn cancelRead(self: Display) void {
        wl_display_cancel_read(self.display);
    }
};

const Registry = struct {
    const wl_registry = Display.wl_registry;

    pub const wl_compositor = extern struct {};
    pub const wl_seat = extern struct {};
    pub const wl_shm = extern struct {};
    pub const xdg_wm_base = extern struct {};

    const wl_registry_listener = extern struct {
        global: ?*const fn (?*anyopaque, ?*wl_registry, u32, [*c]const u8, u32) callconv(.c) void,
        global_remove: ?*const fn (?*anyopaque, ?*wl_registry, u32) callconv(.c) void,
    };

    const xdg_wm_base_listener = extern struct {
        ping: ?*const fn (?*anyopaque, ?*xdg_wm_base, u32) callconv(.c) void,
    };

    extern "c" fn wl_registry_add_listener_wrapper(*wl_registry, *const wl_registry_listener, ?*anyopaque) i32;
    extern "c" fn wl_registry_bind_wrapper(*wl_registry, u32, *const wl_interface, u32) ?*anyopaque;
    extern "c" fn xdg_wm_base_add_listener_wrapper(*xdg_wm_base, *const xdg_wm_base_listener, ?*anyopaque) i32;
    extern "c" fn xdg_wm_base_pong_wrapper(*xdg_wm_base, u32) void;

    extern "c" var wl_compositor_interface: wl_interface;
    extern "c" var wl_seat_interface: wl_interface;
    extern "c" var wl_shm_interface: wl_interface;
    extern "c" var xdg_wm_base_interface: wl_interface;

    pub const Globals = struct {
        compositor: ?*wl_compositor = null,
        seat: ?*wl_seat = null,
        shm: ?*wl_shm = null,
        xdg_wm_base: ?*xdg_wm_base = null,
    };

    registry: *wl_registry,
    globals: Globals = .{},

    const registry_listener = wl_registry_listener{
        .global = handleGlobal,
        .global_remove = handleGlobalRemove,
    };

    const xdg_wm_base_listener_impl = xdg_wm_base_listener{
        .ping = handleXdgWmBasePing,
    };

    pub fn init(registry: *wl_registry) Registry {
        return .{ .registry = registry };
    }

    pub fn addListener(self: *Registry) !void {
        const result = wl_registry_add_listener_wrapper(self.registry, &registry_listener, self);
        if (result < 0) return error.ListenerFailed;
    }

    pub fn setupXdgWmBase(self: *Registry) !void {
        const xdg_wm_base_obj = self.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound;

        const result = xdg_wm_base_add_listener_wrapper(xdg_wm_base_obj, &xdg_wm_base_listener_impl, xdg_wm_base_obj);
        if (result < 0) return error.ListenerFailed;
    }

    fn handleGlobal(
        data: ?*anyopaque,
        registry: ?*wl_registry,
        name: u32,
        interface: [*c]const u8,
        version: u32,
    ) callconv(.c) void {
        const self: *Registry = @ptrCast(@alignCast(data.?));
        const iface = std.mem.span(interface);

        if (std.mem.eql(u8, iface, "wl_compositor")) {
            const desired_version = if (version < 4) version else 4;
            const proxy = wl_registry_bind_wrapper(
                registry.?,
                name,
                &wl_compositor_interface,
                desired_version,
            ) orelse return;
            self.globals.compositor = @ptrCast(proxy);
        } else if (std.mem.eql(u8, iface, "wl_seat")) {
            const iface_version: u32 = @as(u32, @intCast(wl_seat_interface.version));
            const desired_version = if (version < iface_version) version else iface_version;
            const proxy = wl_registry_bind_wrapper(
                registry.?,
                name,
                &wl_seat_interface,
                desired_version,
            ) orelse return;
            self.globals.seat = @ptrCast(proxy);
        } else if (std.mem.eql(u8, iface, "wl_shm")) {
            const iface_version: u32 = @as(u32, @intCast(wl_shm_interface.version));
            const desired_version = if (version < iface_version) version else iface_version;
            const proxy = wl_registry_bind_wrapper(
                registry.?,
                name,
                &wl_shm_interface,
                desired_version,
            ) orelse return;
            self.globals.shm = @ptrCast(proxy);
        } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
            const desired_version = if (version < 1) version else 1;
            const proxy = wl_registry_bind_wrapper(
                registry.?,
                name,
                &xdg_wm_base_interface,
                desired_version,
            ) orelse return;
            self.globals.xdg_wm_base = @ptrCast(proxy);
        }
    }

    fn handleGlobalRemove(
        _: ?*anyopaque,
        _: ?*wl_registry,
        _: u32,
    ) callconv(.c) void {}

    fn handleXdgWmBasePing(
        data: ?*anyopaque,
        xdg_wm_base_obj: ?*xdg_wm_base,
        serial: u32,
    ) callconv(.c) void {
        _ = data;
        if (xdg_wm_base_obj) |wm_base| {
            xdg_wm_base_pong_wrapper(wm_base, serial);
        }
    }

    pub fn destroy(self: Registry) void {
        if (self.globals.compositor) |comp| wl_proxy_destroy(@ptrCast(comp));
        if (self.globals.seat) |seat| wl_proxy_destroy(@ptrCast(seat));
        if (self.globals.shm) |shm| wl_proxy_destroy(@ptrCast(shm));
        if (self.globals.xdg_wm_base) |xdg| wl_proxy_destroy(@ptrCast(xdg));
        wl_proxy_destroy(@ptrCast(self.registry));
    }
};

const Surface = struct {
    const wl_compositor = Registry.wl_compositor;

    const wl_callback = extern struct {};
    pub const wl_surface = extern struct {};
    const wl_region = extern struct {};

    surface: *wl_surface,
    frame_callback: ?*wl_callback = null,

    extern "c" fn wl_compositor_create_surface_wrapper(*wl_compositor) ?*wl_surface;
    extern "c" fn wl_compositor_create_region_wrapper(*wl_compositor) ?*wl_region;
    extern "c" fn wl_region_add_wrapper(*wl_region, i32, i32, i32, i32) void;
    extern "c" fn wl_surface_set_opaque_region_wrapper(*wl_surface, ?*wl_region) void;
    extern "c" fn wl_region_destroy_wrapper(*wl_region) void;

    pub fn init(compositor: *wl_compositor) !Surface {
        const surface = wl_compositor_create_surface_wrapper(compositor) orelse return error.SurfaceCreationFailed;
        return .{ .surface = surface };
    }

    const wl_callback_listener = extern struct {
        done: ?*const fn (?*anyopaque, ?*wl_callback, u32) callconv(.c) void,
    };
    extern "c" fn wl_callback_destroy_wrapper(*wl_callback) void;
    extern "c" fn wl_surface_destroy_wrapper(*wl_surface) void;

    pub fn deinit(self: *Surface) void {
        if (self.frame_callback) |cb| wl_callback_destroy_wrapper(cb);
        wl_surface_destroy_wrapper(self.surface);
    }

    extern "c" fn wl_surface_commit_wrapper(*wl_surface) void;
    pub fn commit(self: Surface) void {
        wl_surface_commit_wrapper(self.surface);
    }

    extern "c" fn wl_surface_damage_wrapper(*wl_surface, i32, i32, i32, i32) void;
    pub fn damage(self: Surface, x: i32, y: i32, width: i32, height: i32) void {
        wl_surface_damage_wrapper(self.surface, x, y, width, height);
    }

    pub fn setOpaqueRegion(self: Surface, compositor: *wl_compositor, width: i32, height: i32) void {
        const region = wl_compositor_create_region_wrapper(compositor) orelse return;
        defer wl_region_destroy_wrapper(region);
        wl_region_add_wrapper(region, 0, 0, width, height);
        wl_surface_set_opaque_region_wrapper(self.surface, region);
    }

    extern "c" fn wl_surface_frame_wrapper(*wl_surface) ?*wl_callback;
    extern "c" fn wl_callback_add_listener_wrapper(*wl_callback, *const wl_callback_listener, ?*anyopaque) i32;
    pub fn requestFrame(self: *Surface, listener: *const wl_callback_listener, data: ?*anyopaque) !void {
        if (self.frame_callback) |cb| wl_callback_destroy_wrapper(cb);

        self.frame_callback = wl_surface_frame_wrapper(self.surface) orelse return error.FrameCallbackFailed;
        const result = wl_callback_add_listener_wrapper(self.frame_callback.?, listener, data);
        if (result < 0) return error.ListenerFailed;
    }
};

const XdgSurface = struct {
    const xdg_wm_base = Registry.xdg_wm_base;
    const wl_surface = Surface.wl_surface;

    pub const xdg_surface = extern struct {};

    const xdg_surface_listener = extern struct {
        configure: ?*const fn (?*anyopaque, ?*xdg_surface, u32) callconv(.c) void,
    };

    extern "c" fn xdg_wm_base_get_xdg_surface_wrapper(*xdg_wm_base, *wl_surface) ?*xdg_surface;
    extern "c" fn xdg_surface_add_listener_wrapper(*xdg_surface, *const xdg_surface_listener, ?*anyopaque) i32;
    extern "c" fn xdg_surface_destroy_wrapper(*xdg_surface) void;
    extern "c" fn xdg_surface_ack_configure_wrapper(*xdg_surface, u32) void;

    handle: *xdg_surface,
    configured: bool = false,
    last_serial: u32 = 0,

    const xdg_surface_listener_impl = xdg_surface_listener{
        .configure = handleConfigure,
    };

    pub fn init(wm_base: *xdg_wm_base, surface: *wl_surface) !XdgSurface {
        const xdg_surf = xdg_wm_base_get_xdg_surface_wrapper(wm_base, surface) orelse return error.XdgSurfaceCreationFailed;
        return .{ .handle = xdg_surf };
    }

    pub fn addListener(self: *XdgSurface, user_data: ?*anyopaque) !void {
        const result = xdg_surface_add_listener_wrapper(self.handle, &xdg_surface_listener_impl, user_data);
        if (result < 0) return error.ListenerFailed;
    }

    pub fn ackConfigure(self: *XdgSurface) void {
        xdg_surface_ack_configure_wrapper(self.handle, self.last_serial);
    }

    pub fn destroy(self: XdgSurface) void {
        xdg_surface_destroy_wrapper(self.handle);
    }

    fn handleConfigure(
        data: ?*anyopaque,
        _: ?*xdg_surface,
        serial: u32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));
        window.xdg_surface.last_serial = serial;
        window.xdg_surface.configured = true;
        window.xdg_surface.ackConfigure();
    }
};

const XdgToplevel = struct {
    const xdg_surface = XdgSurface.xdg_surface;

    const xdg_toplevel = extern struct {};
    const wl_array = extern struct {};

    const xdg_toplevel_listener = extern struct {
        configure: ?*const fn (?*anyopaque, ?*xdg_toplevel, i32, i32, ?*wl_array) callconv(.c) void,
        close: ?*const fn (?*anyopaque, ?*xdg_toplevel) callconv(.c) void,
        configure_bounds: ?*const fn (?*anyopaque, ?*xdg_toplevel, i32, i32) callconv(.c) void,
        wm_capabilities: ?*const fn (?*anyopaque, ?*xdg_toplevel, ?*wl_array) callconv(.c) void,
    };

    extern "c" fn xdg_surface_get_toplevel_wrapper(*xdg_surface) ?*xdg_toplevel;
    extern "c" fn xdg_toplevel_add_listener_wrapper(*xdg_toplevel, *const xdg_toplevel_listener, ?*anyopaque) i32;
    extern "c" fn xdg_toplevel_destroy_wrapper(*xdg_toplevel) void;
    extern "c" fn xdg_toplevel_set_title_wrapper(*xdg_toplevel, [*:0]const u8) void;
    extern "c" fn xdg_toplevel_set_app_id_wrapper(*xdg_toplevel, [*:0]const u8) void;

    toplevel: *xdg_toplevel,
    width: i32 = 0,
    height: i32 = 0,
    should_close: bool = false,

    const xdg_toplevel_listener_impl = xdg_toplevel_listener{
        .configure = handleConfigure,
        .close = handleClose,
        .configure_bounds = handleConfigureBounds,
        .wm_capabilities = handleWmCapabilities,
    };

    pub fn init(xdg_surf: *xdg_surface) !XdgToplevel {
        const toplevel = xdg_surface_get_toplevel_wrapper(xdg_surf) orelse return error.ToplevelCreationFailed;
        return .{ .toplevel = toplevel };
    }

    pub fn addListener(self: *XdgToplevel, user_data: ?*anyopaque) !void {
        const result = xdg_toplevel_add_listener_wrapper(self.toplevel, &xdg_toplevel_listener_impl, user_data);
        if (result < 0) return error.ListenerFailed;
    }

    pub fn setTitle(self: XdgToplevel, title: [*:0]const u8) void {
        xdg_toplevel_set_title_wrapper(self.toplevel, title);
    }

    pub fn setAppId(self: XdgToplevel, app_id: [*:0]const u8) void {
        xdg_toplevel_set_app_id_wrapper(self.toplevel, app_id);
    }

    pub fn destroy(self: XdgToplevel) void {
        xdg_toplevel_destroy_wrapper(self.toplevel);
    }

    fn handleConfigure(
        data: ?*anyopaque,
        _: ?*xdg_toplevel,
        width: i32,
        height: i32,
        _: ?*wl_array,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        if (width > 0) window.xdg_toplevel.width = width;
        if (height > 0) window.xdg_toplevel.height = height;

        if (width > 0 or height > 0) {
            const new_width = if (width > 0) width else window.xdg_toplevel.width;
            const new_height = if (height > 0) height else window.xdg_toplevel.height;

            if (window.xdg_surface.configured) {
                window.resize(new_width, new_height) catch |err| {
                    std.debug.print("Failed to resize window: {}\n", .{err});
                    return;
                };
            }

            window.pushEvent(.{
                .configure = .{
                    .width = new_width,
                    .height = new_height,
                },
            });
        }
    }

    fn handleClose(
        data: ?*anyopaque,
        _: ?*xdg_toplevel,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));
        window.xdg_toplevel.should_close = true;
        window.pushEvent(.close);
    }

    fn handleConfigureBounds(
        _: ?*anyopaque,
        _: ?*xdg_toplevel,
        _: i32,
        _: i32,
    ) callconv(.c) void {}

    fn handleWmCapabilities(
        _: ?*anyopaque,
        _: ?*xdg_toplevel,
        _: ?*wl_array,
    ) callconv(.c) void {}
};

const Keyboard = struct {
    const wl_seat = Registry.wl_seat;

    pub const wl_keyboard = extern struct {};

    const wl_keyboard_listener = extern struct {
        keymap: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, i32, u32) callconv(.c) void,
        enter: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, ?*anyopaque, ?*anyopaque) callconv(.c) void,
        leave: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, ?*anyopaque) callconv(.c) void,
        key: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, u32, u32, u32) callconv(.c) void,
        modifiers: ?*const fn (?*anyopaque, ?*wl_keyboard, u32, u32, u32, u32, u32) callconv(.c) void,
        repeat_info: ?*const fn (?*anyopaque, ?*wl_keyboard, i32, i32) callconv(.c) void,
    };

    const CXkbContext = extern struct {};
    const CXkbKeymap = extern struct {};
    const CXkbState = extern struct {};

    extern "c" fn wl_seat_get_keyboard_wrapper(*wl_seat) ?*wl_keyboard;
    extern "c" fn wl_keyboard_add_listener_wrapper(*wl_keyboard, *const wl_keyboard_listener, ?*anyopaque) i32;
    extern "c" fn wl_keyboard_destroy_wrapper(*wl_keyboard) void;

    extern "c" fn xkb_context_new(flags: u32) ?*CXkbContext;
    extern "c" fn xkb_context_unref(*CXkbContext) void;
    extern "c" fn xkb_keymap_new_from_string(*CXkbContext, [*:0]const u8, format: u32, flags: u32) ?*CXkbKeymap;
    extern "c" fn xkb_keymap_unref(*CXkbKeymap) void;
    extern "c" fn xkb_state_new(*CXkbKeymap) ?*CXkbState;
    extern "c" fn xkb_state_unref(*CXkbState) void;
    extern "c" fn xkb_state_key_get_one_sym(*CXkbState, u32) u32;
    extern "c" fn xkb_state_update_mask(*CXkbState, u32, u32, u32, u32, u32, u32) u32;
    extern "c" fn xkb_keysym_get_name(u32, [*]u8, usize) i32;

    const XKB_KEYMAP_FORMAT_TEXT_V1: u32 = 1;

    keyboard: *wl_keyboard,
    xkb_context: ?*CXkbContext = null,
    xkb_keymap: ?*CXkbKeymap = null,
    xkb_state: ?*CXkbState = null,

    const keyboard_listener = wl_keyboard_listener{
        .keymap = handleKeymap,
        .enter = handleEnter,
        .leave = handleLeave,
        .key = handleKey,
        .modifiers = handleModifiers,
        .repeat_info = handleRepeatInfo,
    };

    pub fn init(seat: *wl_seat) !Keyboard {
        const kb = wl_seat_get_keyboard_wrapper(seat) orelse return error.KeyboardCreationFailed;

        const ctx = xkb_context_new(0) orelse return error.XkbContextCreationFailed;

        return .{
            .keyboard = kb,
            .xkb_context = ctx,
        };
    }

    pub fn addListener(self: *Keyboard, user_data: ?*anyopaque) !void {
        const result = wl_keyboard_add_listener_wrapper(self.keyboard, &keyboard_listener, user_data);
        if (result < 0) return error.ListenerFailed;
    }

    pub fn destroy(self: Keyboard) void {
        if (self.xkb_state) |state| xkb_state_unref(state);
        if (self.xkb_keymap) |keymap| xkb_keymap_unref(keymap);
        if (self.xkb_context) |ctx| xkb_context_unref(ctx);
        wl_keyboard_destroy_wrapper(self.keyboard);
    }

    fn handleKeymap(
        data: ?*anyopaque,
        _: ?*wl_keyboard,
        format: u32,
        fd: i32,
        size: u32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        if (format != XKB_KEYMAP_FORMAT_TEXT_V1) {
            std.posix.close(fd);
            return;
        }

        const map_shm = std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ,
            .{ .TYPE = .SHARED },
            fd,
            0,
        ) catch {
            std.posix.close(fd);
            return;
        };
        defer std.posix.munmap(map_shm);
        std.posix.close(fd);

        const keymap_str: [*:0]const u8 = @ptrCast(map_shm.ptr);

        if (window.keyboard) |*kb| {
            if (kb.xkb_context) |ctx| {
                const keymap = xkb_keymap_new_from_string(ctx, keymap_str, XKB_KEYMAP_FORMAT_TEXT_V1, 0) orelse return;

                if (kb.xkb_keymap) |old_keymap| xkb_keymap_unref(old_keymap);
                kb.xkb_keymap = keymap;

                const state = xkb_state_new(keymap) orelse return;

                if (kb.xkb_state) |old_state| xkb_state_unref(old_state);
                kb.xkb_state = state;
            }
        }
    }

    fn handleEnter(
        _: ?*anyopaque,
        _: ?*wl_keyboard,
        _: u32,
        _: ?*anyopaque,
        _: ?*anyopaque,
    ) callconv(.c) void {}

    fn handleLeave(
        _: ?*anyopaque,
        _: ?*wl_keyboard,
        _: u32,
        _: ?*anyopaque,
    ) callconv(.c) void {}

    fn handleKey(
        data: ?*anyopaque,
        _: ?*wl_keyboard,
        _: u32,
        _: u32,
        key: u32,
        state: u32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        if (window.keyboard) |*kb| {
            if (kb.xkb_state) |xkb_st| {
                const keycode = key + 8;
                const keysym = xkb_state_key_get_one_sym(xkb_st, keycode);

                const pressed = state == 1;
                const key_enum = Key.fromKeysym(keysym);
                window.pushEvent(if (pressed)
                    .{ .key_press = key_enum }
                else
                    .{ .key_release = key_enum });
            }
        }
    }

    fn handleModifiers(
        data: ?*anyopaque,
        _: ?*wl_keyboard,
        _: u32,
        mods_depressed: u32,
        mods_latched: u32,
        mods_locked: u32,
        group: u32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        if (window.keyboard) |*kb| {
            if (kb.xkb_state) |state| {
                _ = xkb_state_update_mask(state, mods_depressed, mods_latched, mods_locked, 0, 0, group);
            }
        }
    }

    fn handleRepeatInfo(
        _: ?*anyopaque,
        _: ?*wl_keyboard,
        _: i32,
        _: i32,
    ) callconv(.c) void {}
};

const Pointer = struct {
    const wl_seat = Registry.wl_seat;

    pub const wl_pointer = extern struct {};

    const wl_pointer_listener = extern struct {
        enter: ?*const fn (?*anyopaque, ?*wl_pointer, u32, ?*anyopaque, i32, i32) callconv(.c) void,
        leave: ?*const fn (?*anyopaque, ?*wl_pointer, u32, ?*anyopaque) callconv(.c) void,
        motion: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32, i32) callconv(.c) void,
        button: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32, u32, u32) callconv(.c) void,
        axis: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32, i32) callconv(.c) void,
        frame: ?*const fn (?*anyopaque, ?*wl_pointer) callconv(.c) void,
        axis_source: ?*const fn (?*anyopaque, ?*wl_pointer, u32) callconv(.c) void,
        axis_stop: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32) callconv(.c) void,
        axis_discrete: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32) callconv(.c) void,
        axis_value120: ?*const fn (?*anyopaque, ?*wl_pointer, u32, i32) callconv(.c) void,
        axis_relative_direction: ?*const fn (?*anyopaque, ?*wl_pointer, u32, u32) callconv(.c) void,
    };

    extern "c" fn wl_seat_get_pointer_wrapper(*wl_seat) ?*wl_pointer;
    extern "c" fn wl_pointer_add_listener_wrapper(*wl_pointer, *const wl_pointer_listener, ?*anyopaque) i32;
    extern "c" fn wl_pointer_destroy_wrapper(*wl_pointer) void;

    pub const PointerButton = enum(u32) {
        left = 0x110,
        right = 0x111,
        middle = 0x112,
        back = 0x113,
        forward = 0x114,
        _,

        pub fn fromLinuxCode(code: u32) PointerButton {
            return @enumFromInt(code);
        }
    };

    pointer: *wl_pointer,
    x: f64 = 0,
    y: f64 = 0,

    const pointer_listener = wl_pointer_listener{
        .enter = handleEnter,
        .leave = handleLeave,
        .motion = handleMotion,
        .button = handleButton,
        .axis = handleAxis,
        .frame = handleFrame,
        .axis_source = handleAxisSource,
        .axis_stop = handleAxisStop,
        .axis_discrete = handleAxisDiscrete,
        .axis_value120 = handleAxisValue120,
        .axis_relative_direction = handleAxisRelativeDirection,
    };

    pub fn init(seat: *wl_seat) !Pointer {
        const ptr = wl_seat_get_pointer_wrapper(seat) orelse return error.PointerCreationFailed;
        return .{ .pointer = ptr };
    }

    pub fn addListener(self: *Pointer, user_data: ?*anyopaque) !void {
        const result = wl_pointer_add_listener_wrapper(self.pointer, &pointer_listener, user_data);
        if (result < 0) return error.ListenerFailed;
    }

    pub fn destroy(self: Pointer) void {
        wl_pointer_destroy_wrapper(self.pointer);
    }

    fn handleEnter(
        data: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: ?*anyopaque,
        surface_x: i32,
        surface_y: i32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        if (window.pointer) |*ptr| {
            ptr.x = wl_fixed_to_double(surface_x);
            ptr.y = wl_fixed_to_double(surface_y);
        }

        window.pushEvent(.{ .mouse_enter = .{
            .x = wl_fixed_to_double(surface_x),
            .y = wl_fixed_to_double(surface_y),
        } });
    }

    fn handleLeave(
        data: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: ?*anyopaque,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));
        window.pushEvent(.mouse_leave);
    }

    fn handleMotion(
        data: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        surface_x: i32,
        surface_y: i32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        const x = wl_fixed_to_double(surface_x);
        const y = wl_fixed_to_double(surface_y);

        if (window.pointer) |*ptr| {
            ptr.x = x;
            ptr.y = y;
        }

        window.pushEvent(.{ .mouse_motion = .{ .x = x, .y = y } });
    }

    fn handleButton(
        data: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: u32,
        button: u32,
        state: u32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        const mouse_button = PointerButton.fromLinuxCode(button);
        const pressed = state == 1;

        window.pushEvent(if (pressed)
            .{ .mouse_button_press = mouse_button }
        else
            .{ .mouse_button_release = mouse_button });
    }

    fn handleAxis(
        data: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        axis: u32,
        value: i32,
    ) callconv(.c) void {
        const window: *Wayland = @ptrCast(@alignCast(data));

        const delta = wl_fixed_to_double(value);

        if (axis == 0) {
            window.pushEvent(.{ .mouse_scroll = .{ .x = delta, .y = 0 } });
        } else if (axis == 1) {
            window.pushEvent(.{ .mouse_scroll = .{ .x = 0, .y = delta } });
        }
    }

    fn handleFrame(
        _: ?*anyopaque,
        _: ?*wl_pointer,
    ) callconv(.c) void {}

    fn handleAxisSource(
        _: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
    ) callconv(.c) void {}

    fn handleAxisStop(
        _: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: u32,
    ) callconv(.c) void {}

    fn handleAxisDiscrete(
        _: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: i32,
    ) callconv(.c) void {}

    fn handleAxisValue120(
        _: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: i32,
    ) callconv(.c) void {}

    fn handleAxisRelativeDirection(
        _: ?*anyopaque,
        _: ?*wl_pointer,
        _: u32,
        _: u32,
    ) callconv(.c) void {}

    fn wl_fixed_to_double(f: i32) f64 {
        return @as(f64, @floatFromInt(f)) / 256.0;
    }
};

const wl_shm_pool = extern struct {};
const wl_buffer = extern struct {};
const wl_egl_window = extern struct {};

extern "c" fn wl_shm_create_pool_wrapper(*Registry.wl_shm, i32, i32) ?*wl_shm_pool;
extern "c" fn wl_shm_pool_create_buffer_wrapper(*wl_shm_pool, i32, i32, i32, i32, u32) ?*wl_buffer;
extern "c" fn wl_shm_pool_destroy_wrapper(*wl_shm_pool) void;
extern "c" fn wl_surface_attach_wrapper(*Surface.wl_surface, *wl_buffer, i32, i32) void;
extern "c" fn wl_buffer_destroy_wrapper(*wl_buffer) void;
extern "c" fn wl_egl_window_create_wrapper(*Surface.wl_surface, i32, i32) ?*wl_egl_window;
extern "c" fn wl_egl_window_destroy_wrapper(*wl_egl_window) void;
extern "c" fn wl_egl_window_resize_wrapper(*wl_egl_window, i32, i32, i32, i32) void;

pub const Event = union(enum) {
    close,
    configure: struct {
        width: i32,
        height: i32,
    },
    key_press: Key,
    key_release: Key,
    mouse_enter: struct {
        x: f64,
        y: f64,
    },
    mouse_leave,
    mouse_motion: struct {
        x: f64,
        y: f64,
    },
    mouse_button_press: Pointer.PointerButton,
    mouse_button_release: Pointer.PointerButton,
    mouse_scroll: struct {
        x: f64,
        y: f64,
    },
};

const EventQueue = struct {
    events: [128]Event = undefined,
    len: usize = 0,

    fn append(self: *EventQueue, event: Event) !void {
        if (self.len >= self.events.len) return error.QueueFull;
        self.events[self.len] = event;
        self.len += 1;
    }

    fn get(self: EventQueue, index: usize) Event {
        return self.events[index];
    }

    fn clear(self: *EventQueue) void {
        self.len = 0;
    }
};

fn dispatchInputEvent(window_wrapper: ?*anyopaque, event: @import("Window.zig").InputEvent) void {
    if (window_wrapper) |wrapper| {
        const Window = @import("Window.zig");
        const win: *Window = @ptrCast(@alignCast(wrapper));
        win.pushEvent(event);
    }
}

display: Display,
registry: Registry,
surface: Surface,
xdg_surface: XdgSurface,
xdg_toplevel: XdgToplevel,
keyboard: ?Keyboard = null,
pointer: ?Pointer = null,
buffer: ?*wl_buffer = null,
shm_pool: ?*wl_shm_pool = null,
shm_fd: i32 = -1,
use_shm_buffer: bool = true,
egl_window: ?*wl_egl_window = null,
event_queue: EventQueue,
event_index: usize = 0,

width: u32,
height: u32,
needs_resize: bool = false,
new_width: u32 = 0,
new_height: u32 = 0,

mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_buttons: u8 = 0,

keys_pressed: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),

pub fn init(options: shared.InitOptions) !Wayland {
    const display = try Display.connect(null);
    errdefer display.disconnect();

    const reg = try display.getRegistry();

    var self = Wayland{
        .display = display,
        .registry = Registry.init(reg),
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .keyboard = null,
        .pointer = null,
        .buffer = null,
        .shm_pool = null,
        .shm_fd = -1,
        .use_shm_buffer = false,
        .event_queue = .{},
        .event_index = 0,
        .width = options.width,
        .height = options.height,
        .mouse_x = @as(f32, @floatFromInt(options.width)) / 2.0,
        .mouse_y = @as(f32, @floatFromInt(options.height)) / 2.0,
    };

    errdefer self.registry.destroy();

    try self.registry.addListener();
    try self.display.roundtrip();
    try self.registry.setupXdgWmBase();

    const compositor = self.registry.globals.compositor orelse return error.CompositorNotFound;
    const xdg_wm_base = self.registry.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound;

    const seat = self.registry.globals.seat orelse return error.SeatNotFound;
    self.keyboard = try Keyboard.init(seat);
    errdefer if (self.keyboard) |*kb| kb.destroy();
    self.pointer = try Pointer.init(seat);
    errdefer if (self.pointer) |*ptr| ptr.destroy();

    self.surface = try Surface.init(compositor);
    errdefer self.surface.deinit();
    self.surface.setOpaqueRegion(compositor, @intCast(options.width), @intCast(options.height));

    self.xdg_surface = try XdgSurface.init(xdg_wm_base, self.surface.surface);
    errdefer self.xdg_surface.destroy();

    self.xdg_toplevel = try XdgToplevel.init(self.xdg_surface.handle);
    errdefer self.xdg_toplevel.destroy();

    self.xdg_toplevel.setTitle(options.title);
    self.xdg_toplevel.setAppId("zig-wayland-window");

    pollEventsInternal(&self, null);
    if (self.needs_resize) {
        self.width = self.new_width;
        self.height = self.new_height;
        self.needs_resize = false;
    }

    std.debug.print("Using native Wayland backend\n", .{});
    return self;
}

pub fn start(self: *Wayland) !void {
    try self.xdg_surface.addListener(self);
    try self.xdg_toplevel.addListener(self);
    if (self.keyboard) |*kb| try kb.addListener(self);
    if (self.pointer) |*ptr| try ptr.addListener(self);

    self.surface.commit();

    while (!self.xdg_surface.configured) {
        try self.display.dispatch();
    }

    self.surface.commit();
    try self.display.roundtrip();
}

pub fn deinit(self: *Wayland) void {
    if (self.keyboard) |kb| kb.destroy();
    if (self.pointer) |ptr| ptr.destroy();
    if (self.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    if (self.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);
    if (self.shm_fd >= 0) std.posix.close(self.shm_fd);
    if (self.egl_window) |egl| wl_egl_window_destroy_wrapper(egl);
    self.xdg_toplevel.destroy();
    self.xdg_surface.destroy();
    self.surface.deinit();
    self.registry.destroy();
    self.display.disconnect();
}

pub fn show(_: *Wayland) void {}

pub fn shouldClose(self: *Wayland) bool {
    return self.xdg_toplevel.should_close;
}

fn resize(self: *Wayland, new_width: i32, new_height: i32) !void {
    if (new_width == @as(i32, @intCast(self.width)) and new_height == @as(i32, @intCast(self.height))) return;
    if (new_width <= 0 or new_height <= 0) return;

    if (!self.use_shm_buffer) {
        if (self.egl_window) |egl| {
            wl_egl_window_resize_wrapper(egl, new_width, new_height, 0, 0);
        }
        return;
    }

    if (self.buffer) |buf| wl_buffer_destroy_wrapper(buf);
    if (self.shm_pool) |pool| wl_shm_pool_destroy_wrapper(pool);
    if (self.shm_fd >= 0) std.posix.close(self.shm_fd);

    const stride = new_width * 4;
    const size = stride * new_height;

    const shm_fd = try std.posix.memfd_create("wl_shm", 0);
    errdefer std.posix.close(shm_fd);

    try std.posix.ftruncate(shm_fd, @intCast(size));

    const shm = self.registry.globals.shm orelse return error.ShmNotFound;
    const pool = wl_shm_create_pool_wrapper(shm, shm_fd, size) orelse return error.ShmPoolCreationFailed;
    errdefer wl_shm_pool_destroy_wrapper(pool);

    const buffer = wl_shm_pool_create_buffer_wrapper(pool, 0, new_width, new_height, stride, 0) orelse return error.BufferCreationFailed;

    self.buffer = buffer;
    self.shm_pool = pool;
    self.shm_fd = shm_fd;

    wl_surface_attach_wrapper(self.surface.surface, buffer, 0, 0);
    self.surface.damage(0, 0, new_width, new_height);
    self.surface.commit();
}

pub fn pushEvent(self: *Wayland, event: Event) void {
    self.event_queue.append(event) catch {
        std.debug.print("Event queue full, dropping event\n", .{});
    };
}

fn pollEvent(self: *Wayland) !?Event {
    if (self.event_index >= self.event_queue.len) {
        self.event_queue.clear();
        self.event_index = 0;

        try self.display.dispatchPending();
        try self.display.flush();

        if (self.event_queue.len == 0) {
            self.display.prepareRead() catch {
                return null;
            };

            const fd = self.display.getFd();
            var pfd = [_]std.posix.pollfd{.{
                .fd = fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};

            const result = std.posix.poll(&pfd, 0) catch |err| {
                self.display.cancelRead();
                return err;
            };

            if (result > 0) {
                try self.display.readEvents();
                try self.display.dispatchPending();
            } else {
                self.display.cancelRead();
            }
        }

        if (self.event_queue.len == 0) return null;
    }

    const event = self.event_queue.get(self.event_index);
    self.event_index += 1;
    return event;
}

pub fn pollEvents(self: *Wayland, window_wrapper: ?*anyopaque) void {
    pollEventsInternal(self, window_wrapper);
}

fn pollEventsInternal(self: *Wayland, window_wrapper: ?*anyopaque) void {
    var events_polled: u32 = 0;
    const max_events_per_frame: u32 = 10;

    while (events_polled < max_events_per_frame) {
        const event = self.pollEvent() catch null orelse break;
        events_polled += 1;

        if (event == .key_press) {
            if (self.keys_pressed.contains(event.key_press)) {
                continue;
            }
        }
        switch (event) {
            .configure => |config| {
                if (config.width > 0 and config.height > 0) {
                    const new_w: u32 = @intCast(config.width);
                    const new_h: u32 = @intCast(config.height);
                    if (new_w != self.width or new_h != self.height) {
                        self.new_width = new_w;
                        self.new_height = new_h;
                        self.needs_resize = true;
                    }
                }
            },
            .mouse_motion => |motion| {
                self.mouse_x = @floatCast(motion.x);
                self.mouse_y = @floatCast(motion.y);
            },
            .mouse_button_press => |button| {
                const button_bit: u8 = switch (button) {
                    .left => @intFromEnum(MouseButton.left),
                    .right => @intFromEnum(MouseButton.right),
                    .middle => @intFromEnum(MouseButton.middle),
                    else => 0x00,
                };
                self.mouse_buttons |= button_bit;

                var click_x = self.mouse_x;
                var click_y = self.mouse_y;
                if (self.pointer) |ptr| {
                    click_x = @floatCast(ptr.x);
                    click_y = @floatCast(ptr.y);
                    self.mouse_x = click_x;
                    self.mouse_y = click_y;
                }

                dispatchInputEvent(window_wrapper, .{ .mouse_click = .{
                    .x = click_x,
                    .y = click_y,
                    .button = button_bit,
                } });
            },
            .mouse_button_release => |button| {
                const button_bit: u8 = switch (button) {
                    .left => @intFromEnum(MouseButton.left),
                    .right => @intFromEnum(MouseButton.right),
                    .middle => @intFromEnum(MouseButton.middle),
                    else => 0x00,
                };
                self.mouse_buttons &= ~button_bit;
            },
            .key_press => |key| {
                self.keys_pressed.insert(key);
                dispatchInputEvent(window_wrapper, .{ .key_press = key });
            },
            .key_release => |key| {
                self.keys_pressed.remove(key);
                dispatchInputEvent(window_wrapper, .{ .key_release = key });
            },
            else => {},
        }
    }
}

pub fn getNativeHandles(self: *Wayland) shared.NativeHandles {
    return .{
        .wayland = .{
            .display = @ptrCast(self.display.display),
            .surface = @ptrCast(self.surface.surface),
        },
    };
}

pub fn getSize(self: *Wayland) shared.Size {
    return .{ .width = self.width, .height = self.height };
}

pub fn needsResize(self: *Wayland) bool {
    return self.needs_resize;
}

pub fn getNewSize(self: *Wayland) shared.Size {
    return .{ .width = self.new_width, .height = self.new_height };
}

pub fn clearResize(self: *Wayland) void {
    self.needs_resize = false;
    self.width = self.new_width;
    self.height = self.new_height;
}

pub fn getMousePosition(self: *Wayland) shared.MousePosition {
    return .{ .x = self.mouse_x, .y = self.mouse_y };
}

pub fn getMouseButtons(self: *Wayland) u8 {
    return self.mouse_buttons;
}

pub fn isKeyPressed(self: *Wayland, key: Key) bool {
    return self.keys_pressed.contains(key);
}

pub fn getKeysPressed(self: *Wayland) std.EnumSet(Key) {
    return self.keys_pressed;
}
