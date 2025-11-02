const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_webgpu = b.option(bool, "webgpu", "Enable WebGPU support") orelse false;

    const wayland_protocols_dir = std.posix.getenv("WAYLAND_PROTOCOLS_DIR") orelse "/usr/share/wayland-protocols";
    const wayland_scanner = std.posix.getenv("WAYLAND_SCANNER") orelse "wayland-scanner";

    const protocols = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "stable/xdg-shell/xdg-shell.xml", .name = "xdg-shell" },
    };

    const write_files = b.addWriteFiles();

    for (protocols) |protocol| {
        const xml_path = b.fmt("{s}/{s}", .{ wayland_protocols_dir, protocol.path });
        const header_name = b.fmt("{s}.h", .{protocol.name});
        const code_name = b.fmt("{s}.c", .{protocol.name});

        const gen_header = b.addSystemCommand(&.{ wayland_scanner, "client-header", xml_path });
        const header = gen_header.addOutputFileArg(header_name);

        const gen_code = b.addSystemCommand(&.{ wayland_scanner, "public-code", xml_path });
        const code = gen_code.addOutputFileArg(code_name);

        _ = write_files.addCopyFile(header, header_name);
        _ = write_files.addCopyFile(code, code_name);
    }

    const wayland_protocols_dir_path = write_files.getDirectory();

    const wl_mod = b.addModule("window", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    wl_mod.addIncludePath(wayland_protocols_dir_path);
    wl_mod.linkSystemLibrary("wayland-client", .{});
    wl_mod.linkSystemLibrary("xkbcommon", .{});

    if (enable_webgpu) {
        const wgpu_dep = b.lazyDependency("wgpu_linux_x86_64_debug", .{}) orelse @panic("wgpu dependency not found");
        wl_mod.addIncludePath(wgpu_dep.path("include"));
    }

    for (protocols) |protocol| {
        const c_file = wayland_protocols_dir_path.path(b, b.fmt("{s}.c", .{protocol.name}));
        wl_mod.addCSourceFile(.{
            .file = c_file,
            .flags = &.{
                "-std=c99",
                "-D_POSIX_C_SOURCE=200809L",
            },
        });
    }

    wl_mod.addCSourceFile(.{
        .file = b.path("src/wayland/wayland_wrapper.c"),
        .flags = &.{
            "-std=c99",
            "-D_POSIX_C_SOURCE=200809L",
        },
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = wl_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const basic_example_mod = b.createModule(.{
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    basic_example_mod.addImport("window", wl_mod);

    const basic_example = b.addExecutable(.{
        .name = "basic",
        .root_module = basic_example_mod,
    });

    b.installArtifact(basic_example);

    const run_basic = b.addRunArtifact(basic_example);
    run_basic.step.dependOn(b.getInstallStep());

    const run_basic_step = b.step("run-basic", "Run the basic example");
    run_basic_step.dependOn(&run_basic.step);
}
