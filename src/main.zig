const std = @import("std");
const clap = @import("clap");
const git = @import("./libgit.zig");
const GitError = git.GitError;
const StrArray = @import("./strarray.zig").StrArrayBuilder;
const libgit = @cImport({
    @cInclude("git2.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const repository_path = "./";
    errdefer print_error();

    const ret = libgit.git_libgit2_init();
    if (ret == 0) {
        return GitError.InitError;
    }
    if (ret > 1) {
        return GitError.AlreadyInitialized;
    }
    defer _ = libgit.git_libgit2_shutdown();

    var repo = try git.Repository.init(allocator, repository_path);
    defer repo.deinit();

    std.debug.print("Remotes: {s}\n", .{repo.remotes.strings[0]});

    try repo.push_to_remotes();
}

fn print_error() void {
    const err = libgit.git_error_last();
    if (err != null) {
        std.debug.print("ERROR: {s}\n", .{err.*.message});
    }
}
