//! paramux FR-3: enumerate the TCP ports a pane's process tree is LISTENing on.
//! Given the pane's child process id, walk its descendant process tree and
//! intersect it with the system's listening-socket table (IPv4 + IPv6). Pure
//! Win32; no dependency on the apprt so it can be unit-tested in isolation.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;

const DWORD = windows.DWORD;
const HANDLE = windows.HANDLE;
const BOOL = windows.BOOL;

const TH32CS_SNAPPROCESS: DWORD = 0x00000002;
const AF_INET: DWORD = 2;
const AF_INET6: DWORD = 23;
// TCP_TABLE_OWNER_PID_LISTENER
const TCP_TABLE_OWNER_PID_LISTENER: DWORD = 3;

const PROCESSENTRY32W = extern struct {
    dwSize: DWORD,
    cntUsage: DWORD,
    th32ProcessID: DWORD,
    th32DefaultHeapID: usize,
    th32ModuleID: DWORD,
    cntThreads: DWORD,
    th32ParentProcessID: DWORD,
    pcPriClassBase: i32,
    dwFlags: DWORD,
    szExeFile: [260]u16,
};

const MIB_TCPROW_OWNER_PID = extern struct {
    dwState: DWORD,
    dwLocalAddr: DWORD,
    dwLocalPort: DWORD,
    dwRemoteAddr: DWORD,
    dwRemotePort: DWORD,
    dwOwningPid: DWORD,
};

const MIB_TCP6ROW_OWNER_PID = extern struct {
    ucLocalAddr: [16]u8,
    dwLocalScopeId: DWORD,
    dwLocalPort: DWORD,
    ucRemoteAddr: [16]u8,
    dwRemoteScopeId: DWORD,
    dwRemotePort: DWORD,
    dwState: DWORD,
    dwOwningPid: DWORD,
};

extern "kernel32" fn GetProcessId(Process: HANDLE) callconv(.winapi) DWORD;
extern "kernel32" fn CreateToolhelp32Snapshot(dwFlags: DWORD, th32ProcessID: DWORD) callconv(.winapi) HANDLE;
extern "kernel32" fn Process32FirstW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) BOOL;
extern "kernel32" fn Process32NextW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) BOOL;
extern "iphlpapi" fn GetExtendedTcpTable(
    pTcpTable: ?*anyopaque,
    pdwSize: *DWORD,
    bOrder: BOOL,
    ulAf: DWORD,
    TableClass: DWORD,
    Reserved: DWORD,
) callconv(.winapi) DWORD;

/// Convert a MIB `dwLocalPort` (port in network byte order in the low 2 bytes)
/// to a host-order port number.
fn mibPort(dw: DWORD) u16 {
    const raw: u16 = @truncate(dw);
    return (raw >> 8) | (raw << 8);
}

/// Return the sorted, de-duplicated set of TCP ports that the process tree
/// rooted at `child_handle` is listening on. Caller owns the slice. Best-effort:
/// any failure yields an empty list.
pub fn listeningPorts(alloc: Allocator, child_handle: HANDLE) []u16 {
    const root_pid = GetProcessId(child_handle);
    if (root_pid == 0) return &.{};
    return listeningPortsForPid(alloc, root_pid);
}

pub fn listeningPortsForPid(alloc: Allocator, root_pid: DWORD) []u16 {
    var tree = std.AutoArrayHashMapUnmanaged(DWORD, void){};
    defer tree.deinit(alloc);
    collectTree(alloc, root_pid, &tree) catch return &.{};
    if (tree.count() == 0) return &.{};

    var ports = std.AutoArrayHashMapUnmanaged(u16, void){};
    defer ports.deinit(alloc);
    collectPorts(alloc, AF_INET, &tree, &ports) catch {};
    collectPorts(alloc, AF_INET6, &tree, &ports) catch {};

    const out = alloc.dupe(u16, ports.keys()) catch return &.{};
    std.mem.sort(u16, out, {}, std.sort.asc(u16));
    return out;
}

/// Build the set of PIDs in the process tree rooted at `root_pid` (inclusive)
/// from a single process snapshot.
fn collectTree(alloc: Allocator, root_pid: DWORD, tree: *std.AutoArrayHashMapUnmanaged(DWORD, void)) !void {
    const snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == windows.INVALID_HANDLE_VALUE) return error.SnapshotFailed;
    defer windows.CloseHandle(snap);

    // Read all (pid, parent) pairs once.
    var pairs = std.ArrayListUnmanaged(struct { pid: DWORD, parent: DWORD }){};
    defer pairs.deinit(alloc);

    var entry: PROCESSENTRY32W = undefined;
    entry.dwSize = @sizeOf(PROCESSENTRY32W);
    if (Process32FirstW(snap, &entry) == 0) return error.SnapshotEmpty;
    while (true) {
        try pairs.append(alloc, .{ .pid = entry.th32ProcessID, .parent = entry.th32ParentProcessID });
        entry.dwSize = @sizeOf(PROCESSENTRY32W);
        if (Process32NextW(snap, &entry) == 0) break;
    }

    // BFS from root_pid over the parent links.
    try tree.put(alloc, root_pid, {});
    var frontier = std.ArrayListUnmanaged(DWORD){};
    defer frontier.deinit(alloc);
    try frontier.append(alloc, root_pid);
    while (frontier.pop()) |parent| {
        for (pairs.items) |pair| {
            if (pair.parent == parent and !tree.contains(pair.pid) and pair.pid != 0) {
                try tree.put(alloc, pair.pid, {});
                try frontier.append(alloc, pair.pid);
            }
        }
    }
}

/// Query the listener table for `af` and add any port owned by a PID in `tree`.
fn collectPorts(
    alloc: Allocator,
    af: DWORD,
    tree: *const std.AutoArrayHashMapUnmanaged(DWORD, void),
    ports: *std.AutoArrayHashMapUnmanaged(u16, void),
) !void {
    var size: DWORD = 0;
    _ = GetExtendedTcpTable(null, &size, 0, af, TCP_TABLE_OWNER_PID_LISTENER, 0);
    if (size == 0) return;

    const buf = try alloc.alignedAlloc(u8, .of(DWORD), size);
    defer alloc.free(buf);
    if (GetExtendedTcpTable(buf.ptr, &size, 0, af, TCP_TABLE_OWNER_PID_LISTENER, 0) != 0) return;

    const count = @as(*const DWORD, @ptrCast(@alignCast(buf.ptr))).*;
    if (af == AF_INET) {
        const rows: [*]const MIB_TCPROW_OWNER_PID = @ptrCast(@alignCast(buf.ptr + 4));
        for (0..count) |i| {
            const row = rows[i];
            if (tree.contains(row.dwOwningPid)) try ports.put(alloc, mibPort(row.dwLocalPort), {});
        }
    } else {
        const rows: [*]const MIB_TCP6ROW_OWNER_PID = @ptrCast(@alignCast(buf.ptr + 4));
        for (0..count) |i| {
            const row = rows[i];
            if (tree.contains(row.dwOwningPid)) try ports.put(alloc, mibPort(row.dwLocalPort), {});
        }
    }
}

test "mibPort byte-swaps the network-order port" {
    // 3000 = 0x0BB8; network order bytes 0x0B 0xB8 -> DWORD low word 0xB80B.
    try std.testing.expectEqual(@as(u16, 3000), mibPort(0x0000B80B));
    try std.testing.expectEqual(@as(u16, 80), mibPort(0x00005000));
}

test "listeningPortsForPid finds a port this test process is listening on" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const testing = std.testing;

    // Bind a listening socket in THIS process, then confirm it shows up for our
    // own PID (a single-process "tree").
    const posix = std.posix;
    const sock = posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0) catch return error.SkipZigTest;
    defer posix.close(sock);
    var addr = std.net.Address.parseIp4("127.0.0.1", 0) catch unreachable;
    posix.bind(sock, &addr.any, addr.getOsSockLen()) catch return error.SkipZigTest;
    try posix.listen(sock, 1);
    var slen: posix.socklen_t = addr.getOsSockLen();
    posix.getsockname(sock, &addr.any, &slen) catch return error.SkipZigTest;
    const bound_port = addr.getPort();

    const pid = windows.GetCurrentProcessId();
    const ports = listeningPortsForPid(testing.allocator, pid);
    defer testing.allocator.free(ports);
    try testing.expect(std.mem.indexOfScalar(u16, ports, bound_port) != null);
}
