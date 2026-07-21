const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const apprt = @import("../apprt.zig");
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,
    class: ?[:0]const u8 = null,

    /// Port on 127.0.0.1 (default 7877).
    port: u16 = 7877,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Serve the running instance's fleet structure as JSON over
/// localhost HTTP: `GET /status` returns exactly what
/// `paramux list-windows` prints (structure, attention states, token
/// totals — never pane text). Binds 127.0.0.1 only; this is a
/// separate bridge process, so the GUI's attack surface is unchanged.
/// Stop with Ctrl+C.
///
///   * `paramux serve` then `curl http://127.0.0.1:7877/status`
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const result = runArgs(alloc, &iter, &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    return result;
}

fn runArgs(
    alloc: Allocator,
    args_iter: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var opts: Options = .{ ._arena = ArenaAllocator.init(alloc) };
    defer opts.deinit();
    const a = opts._arena.?.allocator();

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--class=")) |class| {
            opts.class = try a.dupeZ(u8, class);
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--port=")) |rest| {
            opts.port = std.fmt.parseInt(u16, rest, 10) catch {
                try stderr.print("bad --port value: {s}\n", .{rest});
                return 1;
            };
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;

    const address = std.net.Address.parseIp4("127.0.0.1", opts.port) catch unreachable;
    // No reuse_address: on Windows SO_REUSEADDR lets a second serve
    // bind an actively listening port and silently steal its traffic.
    // Listening sockets don't linger in TIME_WAIT, so quick restarts
    // don't need it.
    var listener = address.listen(.{}) catch |err| {
        try stderr.print("could not bind 127.0.0.1:{d} (err={})\n", .{ opts.port, err });
        return 1;
    };
    defer listener.deinit();
    try stdout.print("Serving fleet status on http://127.0.0.1:{d}/status (Ctrl+C stops).\n", .{opts.port});
    try stdout.flush();

    while (true) {
        const conn = listener.accept() catch continue;
        defer conn.stream.close();

        var recv_buf: [4096]u8 = undefined;
        var send_buf: [4096]u8 = undefined;
        var reader = conn.stream.reader(&recv_buf);
        var writer = conn.stream.writer(&send_buf);
        var server: std.http.Server = .init(reader.interface(), &writer.interface);
        var request = server.receiveHead() catch continue;

        const path = request.head.target;
        // One operability line per request; the defer covers every
        // route's `continue`. recv_buf (and so `path`) is still live
        // at iteration-scope exit.
        const started_ms = std.time.milliTimestamp();
        defer {
            stdout.print("{d}ms {s}\n", .{ std.time.milliTimestamp() - started_ms, path }) catch {};
            stdout.flush() catch {};
        }
        if (lib.cutPrefix(u8, path, "/panes/")) |rest| {
            // /panes/<id>/text — pane CONTENT, so it requires the
            // instance token as `Authorization: Bearer <token>`.
            pane_route: {
                const slash = std.mem.indexOfScalar(u8, rest, '/') orelse break :pane_route;
                if (!std.mem.eql(u8, rest[slash..], "/text")) break :pane_route;
                const id = std.fmt.parseInt(u64, rest[0..slash], 10) catch break :pane_route;

                const token = apprt.App.readClientIpcTokenFromFile(alloc) orelse {
                    request.respond("{\"error\":\"no instance token on this machine\"}", .{
                        .status = .service_unavailable,
                        .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                    }) catch {};
                    continue;
                };
                defer alloc.free(token);
                var authed = false;
                var head_it = request.iterateHeaders();
                while (head_it.next()) |h| {
                    if (!std.ascii.eqlIgnoreCase(h.name, "authorization")) continue;
                    const prefix = "Bearer ";
                    if (h.value.len != prefix.len + token.len) continue;
                    if (!std.ascii.startsWithIgnoreCase(h.value, prefix)) continue;
                    var diff: u8 = 0;
                    for (h.value[prefix.len..], token) |ca, cb| diff |= ca ^ cb;
                    if (diff == 0) authed = true;
                }
                if (!authed) {
                    request.respond("{\"error\":\"missing or wrong bearer token\"}", .{
                        .status = .unauthorized,
                        .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                    }) catch {};
                    continue;
                }

                const text = (apprt.App.performReadPane(alloc, target, .{ .surface_id = id }) catch null) orelse {
                    request.respond("{\"error\":\"pane not found or instance gone\"}", .{
                        .status = .not_found,
                        .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                    }) catch {};
                    continue;
                };
                defer alloc.free(text);

                // ETag = content hash: pollers send If-None-Match and
                // get a 304 instead of the full scrollback each cycle.
                var etag_buf: [20]u8 = undefined;
                const etag = std.fmt.bufPrint(
                    &etag_buf,
                    "\"{x:0>16}\"",
                    .{std.hash.Wyhash.hash(0, text)},
                ) catch unreachable;
                var inm_matches = false;
                var etag_it = request.iterateHeaders();
                while (etag_it.next()) |h| {
                    if (std.ascii.eqlIgnoreCase(h.name, "if-none-match") and
                        std.mem.eql(u8, std.mem.trim(u8, h.value, " "), etag))
                    {
                        inm_matches = true;
                    }
                }
                if (inm_matches) {
                    request.respond("", .{
                        .status = .not_modified,
                        .extra_headers = &.{.{ .name = "etag", .value = etag }},
                    }) catch {};
                    continue;
                }
                request.respond(text, .{
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                        .{ .name = "etag", .value = etag },
                    },
                }) catch {};
                continue;
            }
            request.respond("not found\n", .{ .status = .not_found }) catch {};
            continue;
        }
        if (std.mem.eql(u8, path, "/attention")) {
            // Timelines carry notify message text — same bearer gate
            // as pane content.
            const token = apprt.App.readClientIpcTokenFromFile(alloc) orelse {
                request.respond("{\"error\":\"no instance token on this machine\"}", .{
                    .status = .service_unavailable,
                    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                }) catch {};
                continue;
            };
            defer alloc.free(token);
            var authed = false;
            var head_it = request.iterateHeaders();
            while (head_it.next()) |h| {
                if (!std.ascii.eqlIgnoreCase(h.name, "authorization")) continue;
                const prefix = "Bearer ";
                if (h.value.len != prefix.len + token.len) continue;
                if (!std.ascii.startsWithIgnoreCase(h.value, prefix)) continue;
                var diff: u8 = 0;
                for (h.value[prefix.len..], token) |ca, cb| diff |= ca ^ cb;
                if (diff == 0) authed = true;
            }
            if (!authed) {
                request.respond("{\"error\":\"missing or wrong bearer token\"}", .{
                    .status = .unauthorized,
                    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                }) catch {};
                continue;
            }
            const json = (apprt.App.performReadAttention(alloc, target) catch null) orelse {
                request.respond("{\"error\":\"no running paramux instance\"}", .{
                    .status = .service_unavailable,
                    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                }) catch {};
                continue;
            };
            defer alloc.free(json);
            // Hash from the panes key on: the exported_at_ms prefix
            // changes every call and would defeat If-None-Match.
            const att_stable = if (std.mem.indexOf(u8, json, "\"panes\":")) |at|
                json[at..]
            else
                json;
            var att_etag_buf: [20]u8 = undefined;
            const att_etag = std.fmt.bufPrint(
                &att_etag_buf,
                "{c}{x:0>16}{c}",
                .{ '"', std.hash.Wyhash.hash(0, att_stable), '"' },
            ) catch unreachable;
            var att_inm = false;
            var att_it = request.iterateHeaders();
            while (att_it.next()) |h| {
                if (std.ascii.eqlIgnoreCase(h.name, "if-none-match") and
                    std.mem.eql(u8, std.mem.trim(u8, h.value, " "), att_etag))
                {
                    att_inm = true;
                }
            }
            if (att_inm) {
                request.respond("", .{
                    .status = .not_modified,
                    .extra_headers = &.{.{ .name = "etag", .value = att_etag }},
                }) catch {};
                continue;
            }
            request.respond(json, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                    .{ .name = "etag", .value = att_etag },
                },
            }) catch {};
            continue;
        }
        if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/")) {
            const payload = (apprt.App.queryAutomationWindowList(alloc, target) catch null) orelse {
                request.respond("{\"error\":\"no running paramux instance\"}", .{
                    .status = .service_unavailable,
                    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                }) catch {};
                continue;
            };
            defer alloc.free(payload);
            var etag_buf: [20]u8 = undefined;
            const etag = std.fmt.bufPrint(
                &etag_buf,
                "\"{x:0>16}\"",
                .{std.hash.Wyhash.hash(0, payload)},
            ) catch unreachable;
            var inm_matches = false;
            var etag_it = request.iterateHeaders();
            while (etag_it.next()) |h| {
                if (std.ascii.eqlIgnoreCase(h.name, "if-none-match") and
                    std.mem.eql(u8, std.mem.trim(u8, h.value, " "), etag))
                {
                    inm_matches = true;
                }
            }
            if (inm_matches) {
                request.respond("", .{
                    .status = .not_modified,
                    .extra_headers = &.{.{ .name = "etag", .value = etag }},
                }) catch {};
                continue;
            }
            request.respond(payload, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                    .{ .name = "etag", .value = etag },
                },
            }) catch {};
        } else {
            request.respond("not found\n", .{ .status = .not_found }) catch {};
        }
    }
}
