const Ghostty = @This();

const std = @import("std");
const Config = @import("Config.zig");
const SharedDeps = @import("SharedDeps.zig");

/// The primary paramux executable.
exe: *std.Build.Step.Compile,

/// The install step for the executable.
install_step: *std.Build.Step.InstallArtifact,

/// Console launcher that shells resolve before paramux.exe.
command_exe: ?*std.Build.Step.Compile = null,
command_install_step: ?*std.Build.Step.InstallFile = null,

pub fn init(b: *std.Build, cfg: *const Config, deps: *const SharedDeps) !Ghostty {
    const exe: *std.Build.Step.Compile = b.addExecutable(.{
        .name = "paramux",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = cfg.target,
            .optimize = cfg.optimize,
            .strip = cfg.strip,
            .omit_frame_pointer = cfg.strip,
            .unwind_tables = if (cfg.strip) .none else .sync,
        }),
        // Crashes on x86_64 self-hosted on 0.15.1
        .use_llvm = true,
    });
    const install_step = b.addInstallArtifact(exe, .{});
    var command_exe: ?*std.Build.Step.Compile = null;
    var command_install_step: ?*std.Build.Step.InstallFile = null;

    // Set PIE if requested
    if (cfg.pie) exe.pie = true;

    // The app executable always needs the shared dependency wiring,
    // including build_options and generated imports.
    _ = try deps.add(exe);

    // OS-specific
    switch (cfg.target.result.os.tag) {
        .windows => {
            const version_major = b.fmt("/DPARAMUX_VERSION_MAJOR={d}", .{cfg.version.major});
            const version_minor = b.fmt("/DPARAMUX_VERSION_MINOR={d}", .{cfg.version.minor});
            const version_patch = b.fmt("/DPARAMUX_VERSION_PATCH={d}", .{cfg.version.patch});
            const version_revision = b.fmt(
                "/DPARAMUX_VERSION_REVISION={d}",
                .{win32VersionRevision(cfg.version)},
            );
            const version_string = b.fmt(
                "/DPARAMUX_VERSION_STRING=\"{f}\"",
                .{cfg.version},
            );

            exe.subsystem = .Windows;
            exe.addWin32ResourceFile(.{
                .file = b.path("dist/windows/paramux.rc"),
                .flags = &.{
                    try win32IconResourceStamp(b),
                    version_major,
                    version_minor,
                    version_patch,
                    version_revision,
                    version_string,
                },
            });

            const command = b.addExecutable(.{
                .name = "paramux-command",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main_paramux_command.zig"),
                    .target = cfg.target,
                    .optimize = cfg.optimize,
                    .strip = cfg.strip,
                    .omit_frame_pointer = cfg.strip,
                    .unwind_tables = if (cfg.strip) .none else .sync,
                }),
                .use_llvm = true,
            });
            command.subsystem = .Console;
            command.addWin32ResourceFile(.{
                .file = b.path("dist/windows/paramux.rc"),
                .flags = &.{
                    "/DPARAMUX_COMMAND_LAUNCHER",
                    version_major,
                    version_minor,
                    version_patch,
                    version_revision,
                    version_string,
                },
            });
            _ = try deps.add(command);
            command_exe = command;
            command_install_step = b.addInstallBinFile(command.getEmittedBin(), "paramux.com");
        },

        else => {},
    }

    return .{
        .exe = exe,
        .install_step = install_step,
        .command_exe = command_exe,
        .command_install_step = command_install_step,
    };
}

fn win32VersionRevision(version: std.SemanticVersion) u32 {
    const prerelease = version.pre orelse return 0;
    const prefix = "paramux.";
    if (!std.mem.startsWith(u8, prerelease, prefix)) return 0;
    return std.fmt.parseInt(u32, prerelease[prefix.len..], 10) catch 0;
}

/// Add the paramux exe to the install target.
pub fn install(self: *const Ghostty) void {
    const b = self.install_step.step.owner;
    b.getInstallStep().dependOn(&self.install_step.step);
    if (self.command_install_step) |step| b.getInstallStep().dependOn(&step.step);
}

fn win32IconResourceStamp(b: *std.Build) ![]const u8 {
    const icon_bytes = try std.fs.cwd().readFileAlloc(
        b.allocator,
        "dist/windows/paramux.ico",
        1024 * 1024,
    );
    defer b.allocator.free(icon_bytes);

    return try std.fmt.allocPrint(
        b.allocator,
        "/DPARAMUX_ICON_HASH_{x}",
        .{std.hash.Wyhash.hash(0, icon_bytes)},
    );
}
