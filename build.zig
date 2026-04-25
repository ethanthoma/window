const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const window_module = b.addModule("window", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("main.zig"),
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
    module.addCSourceFile(.{
        .file = b.path("wayland/wayland_wrapper.c"),
        .flags = &.{"-std=c11"},
    });
    module.addCSourceFile(.{
        .file = b.path("wayland/xdg-shell-protocol.c"),
        .flags = &.{"-std=c11"},
    });

    module.addIncludePath(b.path("wayland"));
    module.link_libc = true;

    module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .force });
    module.linkSystemLibrary("wayland-egl", .{ .use_pkg_config = .force });
    module.linkSystemLibrary("xkbcommon", .{ .use_pkg_config = .force });
    module.linkSystemLibrary("x11", .{ .use_pkg_config = .force });
}
