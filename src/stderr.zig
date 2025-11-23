const std = @import("std");
const stderr = std.fs.File.stderr();
var writer: std.fs.File.Writer = undefined;

pub fn init(stderrBuf: *[4096]u8) void {

    writer = stderr.writer(stderrBuf);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    writer.interface.print(fmt, args) catch {};
    writer.interface.flush() catch {};
}
