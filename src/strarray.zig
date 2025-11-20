const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});

pub const StrArray = struct{
    allocator: std.mem.Allocator,
    count: usize,
    strings: [][*c]u8,
    refs: [][]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        list: []const []const u8,
    ) !StrArray {
        var out = StrArray {
            .allocator = allocator,
            .count = list.len,
            .strings = try allocator.alloc([*c]u8, list.len),
            .refs = try allocator.alloc([]u8, list.len),
        };

        for (list, 0..) |item, i| {
            const cstring = try allocator.alloc(u8, item.len + 1);
            @memcpy(cstring[0..item.len], item);
            cstring[item.len] = 0;
            out.refs[i] = cstring;
        }

        return out;
    }

    pub fn deinit(
        self: StrArray
    ) void {
        for (self.refs) |ref| {
            self.allocator.free(ref);
        }
        self.allocator.free(self.strings);
        self.allocator.free(self.refs);
    }

    pub fn libgit_view(
        self: StrArray
    ) libgit.git_strarray {
        var out = libgit.git_strarray{
            .strings = null,
            .count = self.strings.len,
        };

        out.strings = self.strings.ptr;

        for (self.refs, 0..) |item, i| {
            out.strings[i] = item.ptr;
        }

        return out;
    }
};


pub fn free_strarray(allocator: std.mem.Allocator, s: libgit.git_strarray) void {
    for (0..s.count) |i| {
        if (s.strings[i] != null) {
            allocator.free(@as([*]u8, @ptrCast(s.strings[i])));
            // allocator.free(s.strings[i]);
        }
    }

    // allocator.free(s.strings);
}
