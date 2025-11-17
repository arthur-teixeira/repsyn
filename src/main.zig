const std = @import("std");
const clap = @import("clap");
const git = @import("./libgit.zig");

pub fn main() !void {
    const repo: git.Repository = try .init("./");
    defer repo.deinit() catch { };
    const local_master = try repo.find_branch_tree("master", .Local);
    const remote_master = try repo.find_branch_tree("master", .Remote);

    try repo.diff_to_remote(local_master, remote_master);
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

}
