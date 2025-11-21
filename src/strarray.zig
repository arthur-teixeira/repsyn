const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});

pub const StrArrayBuilder = struct{
    allocator: std.mem.Allocator,
    strings: std.ArrayList([]u8),
    finished: bool,
    refs: ?[][]u8,
    cref: ?[][*c]u8,

    pub fn init(allocator: std.mem.Allocator) !StrArrayBuilder {
        return StrArrayBuilder {
            .allocator = allocator,
            .strings = try std.ArrayList([]u8).initCapacity(allocator, 10),
            .finished = false,
            .refs = null,
            .cref = null,
        };
    }

    pub fn deinit(self: *StrArrayBuilder) void {
        if (self.refs != null) {
            for (self.refs.?) |ref| {
                self.allocator.free(ref);
            }
            self.allocator.free(self.refs.?);
        }

        if (self.cref != null) {
            self.allocator.free(self.cref.?);
        }

        for (self.strings.items) |item| {
            self.allocator.free(item);
        }

        self.strings.deinit(self.allocator);
    }

    pub fn append(self: *StrArrayBuilder, str: []const u8) !void {
        const n = try self.allocator.alloc(u8, str.len);
        @memcpy(n, str);
        return self.strings.append(self.allocator, n);
    }

    pub fn finish(self: *StrArrayBuilder) !void {
        if (self.finished) {
            return;
        }

        self.cref = try self.allocator.alloc([*c]u8, self.strings.items.len);
        self.refs = try self.allocator.alloc([]u8, self.strings.items.len);
        for (self.strings.items, 0..) |item, i| {
            const cstring = try self.allocator.alloc(u8, item.len + 1);
            @memcpy(cstring[0..item.len], item);
            cstring[item.len] = 0;

            self.refs.?[i] = cstring;
        }

        self.finished = true;
    }

    pub fn libgit_view(self: *StrArrayBuilder) libgit.git_strarray {
        std.debug.assert(self.finished);

        var out = libgit.git_strarray{
            .strings = self.cref.?.ptr,
            .count = self.strings.items.len,
        };

        for (self.refs.?, 0..) |item, i| {
            out.strings[i] = item.ptr;
        }


        return out;
    }
};
