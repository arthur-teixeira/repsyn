const std = @import("std");
const time = @import("zig-time");
const stderr = std.fs.File.stderr();
var writer: std.fs.File.Writer = undefined;
var writer_lock: std.Thread.Mutex = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator, stderrBuf: *[4096]u8) void {
    writer = stderr.writer(stderrBuf);
    allocator = alloc;
}

const BRT = time.Location.create(-180, "UTC-3");

pub fn print(comptime fmt: []const u8, args: anytype) void {
    writer_lock.lock();

    const dateFmt: []const u8 = "YYYY-MM-DD HH:mm:ss";
    const instant = time.now().setLoc(BRT);
    const fmtRes = instant.formatAlloc(allocator, dateFmt) catch return;
    defer allocator.free(fmtRes);

    writer.interface.print("[{s}] ", .{fmtRes}) catch return;
    writer.interface.print(fmt, args) catch return;
    writer.interface.flush() catch return;
    writer_lock.unlock();
}
