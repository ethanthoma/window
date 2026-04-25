const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const window_module = b.addModule("window", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    if (target.result.os.tag == .linux) {
        setupLinux(b, window_module);
    }

    if (target.result.os.tag == .macos) {
        setupMacOS(b, window_module);
    }

    if (target.result.os.tag == .windows) {
        setupWindows(window_module);
    }
}

fn setupWindows(module: *std.Build.Module) void {
    module.linkSystemLibrary("user32", .{});
    module.linkSystemLibrary("kernel32", .{});
    module.linkSystemLibrary("gdi32", .{});
}

fn setupMacOS(b: *std.Build, module: *std.Build.Module) void {
    if (b.graph.env_map.get("MACOS_SDK_PATH")) |sdk_path| {
        module.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdk_path}) });
        module.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sdk_path}) });
        module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk_path}) });
    }

    module.linkSystemLibrary("objc", .{});
    module.linkFramework("AppKit", .{});
    module.linkFramework("QuartzCore", .{});
    module.linkFramework("Metal", .{});
}

fn setupLinux(b: *std.Build, module: *std.Build.Module) void {
    const wayland_xml: ?std.Build.LazyPath = if (b.graph.env_map.get("WAYLAND_XML")) |p|
        .{ .cwd_relative = p }
    else
        null;
    const wayland_protocols: ?std.Build.LazyPath = if (b.graph.env_map.get("WAYLAND_PROTOCOLS_DIR")) |p|
        .{ .cwd_relative = p }
    else
        null;

    const scanner = Scanner.create(b, .{
        .wayland_xml = wayland_xml,
        .wayland_protocols = wayland_protocols,
    });
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("xdg_wm_base", 4);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    module.addImport("wayland", wayland);

    module.link_libc = true;
    module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .force });
    module.linkSystemLibrary("xkbcommon", .{ .use_pkg_config = .force });
    module.linkSystemLibrary("x11", .{ .use_pkg_config = .force });
}
