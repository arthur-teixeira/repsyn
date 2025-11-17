const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});

const LibGitError = error {
    InitError
};

pub fn init() LibGitError!void {
    const ret = libgit.git_libgit2_init();
    std.debug.print("Called libgit {d}\n", .{ret});
    if (ret != 1) {
        return LibGitError.InitError;
    }
}
