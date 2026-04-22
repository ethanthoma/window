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
        setupLinux(b, window_module, target);
    }

    if (target.result.os.tag == .macos) {
        setupMacOS(b, window_module);
    }
}

fn setupMacOS(b: *std.Build, module: *std.Build.Module) void {
    const objc_dep = b.dependency("zig_objc", .{});
    module.addImport("objc", objc_dep.module("objc"));

    module.linkFramework("AppKit", .{});
    module.linkFramework("QuartzCore", .{});
    module.linkFramework("Metal", .{});
}

fn setupLinux(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    _ = target;
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

    // Resolve include paths from LD_LIBRARY_PATH (Nix environments).
    if (std.posix.getenv("LD_LIBRARY_PATH")) |ld_path| {
        var it = std.mem.splitScalar(u8, ld_path, ':');
        while (it.next()) |lib_path| {
            module.addLibraryPath(.{ .cwd_relative = lib_path });

            if (std.mem.endsWith(u8, lib_path, "/lib")) {
                const base_path = lib_path[0 .. lib_path.len - 4];
                const include_path = b.fmt("{s}/include", .{base_path});
                std.fs.accessAbsolute(include_path, .{}) catch continue;
                module.addSystemIncludePath(.{ .cwd_relative = include_path });
            }

            if (std.mem.indexOf(u8, lib_path, "/nix/store/") != null and
                std.mem.endsWith(u8, lib_path, "/lib"))
            {
                const maybe_dev_path = b.fmt("{s}-dev/include", .{lib_path[0 .. lib_path.len - 4]});
                std.fs.accessAbsolute(maybe_dev_path, .{}) catch continue;
                module.addSystemIncludePath(.{ .cwd_relative = maybe_dev_path });
            }
        }
    }

    // Hardcoded Nix store fallbacks.
    const nix_include_paths = [_][]const u8{
        "/nix/store/465lj8xn3vp4xfand16iqlwx1kqgc4id-wayland-1.24.0-dev/include",
        "/nix/store/anzq0yqha04vzs47v32nisyqf9dqak9j-libxkbcommon-1.11.0-dev/include",
    };
    for (nix_include_paths) |path| {
        std.fs.accessAbsolute(path, .{}) catch continue;
        module.addIncludePath(.{ .cwd_relative = path });
    }

    if (b.graph.env_map.get("XORGPROTO_INCLUDE_PATH")) |xorgproto_path| {
        module.addSystemIncludePath(.{ .cwd_relative = xorgproto_path });
    } else {
        const xorgproto_paths = [_][]const u8{
            "/nix/store/6kqqglmwhrqjd4i8z4fycyming0r7v2z-xorgproto-2024.1/include",
            "/nix/store/h6xil473xysi4lp6xr3mnwcfdd9nsr1b-xorgproto-2024.1/include",
        };
        for (xorgproto_paths) |path| {
            std.fs.accessAbsolute(path, .{}) catch continue;
            module.addSystemIncludePath(.{ .cwd_relative = path });
            break;
        }
    }

    module.linkSystemLibrary("wayland-client", .{});
    module.linkSystemLibrary("wayland-egl", .{});
    module.linkSystemLibrary("xkbcommon", .{});
    module.linkSystemLibrary("X11", .{});
}
