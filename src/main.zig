const std = @import("std");
const clap = @import("clap");
const git = @import("./libgit.zig");
const GitError = git.GitError;
const StrArray = @import("./strarray.zig").StrArray;
const libgit = @cImport({
    @cInclude("git2.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // const allocator = gpa.allocator();
    const repository_path = "./";

    errdefer print_error();

    var ret = libgit.git_libgit2_init();
    if (ret == 0) {
        return GitError.InitError;
    }
    if (ret > 1) {
        return GitError.AlreadyInitialized;
    }

    var repo: ?*libgit.struct_git_repository = null;
    ret = libgit.git_repository_open(&repo, repository_path.ptr);
    if (ret != 0) {
        return GitError.InitError;
    }

    var remotes: libgit.git_strarray = undefined;
    ret = libgit.git_remote_list(&remotes, repo);
    if (ret != 0) {
        return GitError.InitError;
    }

    std.debug.assert(remotes.count > 0);

    const remote_name = remotes.strings[0];
    var remote: ?*libgit.struct_git_remote = null;
    ret = libgit.git_remote_lookup(&remote, repo, remote_name);
    if (ret != 0) {
        return GitError.InitError;
    }
    defer libgit.git_remote_free(remote);

    var cbs: libgit.struct_git_remote_callbacks = undefined;
    ret = libgit.git_remote_init_callbacks(&cbs, libgit.GIT_REMOTE_CALLBACKS_VERSION);
    if (ret != 0) {
        return GitError.InitError;
    }

    ret = libgit.git_remote_connect(remote, libgit.GIT_DIRECTION_PUSH, &cbs, null, null);
    if (ret != 0) {
        return GitError.InitError;
    }

    var opts: libgit.git_push_options = undefined;
    ret = libgit.git_push_options_init(&opts, libgit.GIT_PUSH_OPTIONS_VERSION);
    if (ret != 0) {
        return GitError.InitError;
    }

    var iter: ?*libgit.git_branch_iterator = null;
    ret = libgit.git_branch_iterator_new(&iter, repo, libgit.GIT_BRANCH_LOCAL);
    if (ret != 0) {
        return GitError.InitError;
    }

    // const refs_arr = try StrArray.init(allocator, push_refs);
    // defer refs_arr.deinit();

    while(true) {
        var branch_ref: ?*libgit.git_reference = null;
        var branch_type: libgit.git_branch_t = 0;
        ret = libgit.git_branch_next(&branch_ref, &branch_type, iter);
        if (ret == libgit.GIT_ITEROVER) {
            break;
        }
        if (ret != 0) {
            return GitError.InitError;
        }
        defer libgit.git_reference_free(branch_ref);

        const branch_ref_name = libgit.git_reference_name(branch_ref);
        std.debug.print("{s} is a branch \n", .{branch_ref_name});
    }

    //
    // const as_lg_array = refs_arr.libgit_view();
    // ret = libgit.git_remote_push(remote, @ptrCast(&as_lg_array), &opts);
    // if (ret != 0) {
    //     return GitError.InitError;
    // }
}


fn print_error() void {
    const err = libgit.git_error_last();
    if (err != null) {
        std.debug.print("ERROR: {s}\n", .{err.*.message});
    }
}
