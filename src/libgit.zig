const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});

pub const GitError = error {
    InitError,
    AlreadyInitialized,
    AlreadyShutdown,
    BranchNotFound,
    DiffError,
    FetchError,
};

const Where = enum(c_uint) {
    Local = libgit.GIT_BRANCH_LOCAL,
    Remote = libgit.GIT_BRANCH_REMOTE,
};

pub const Repository = struct {
    allocator: std.mem.Allocator,
    repo: ?*libgit.struct_git_repository,
    remotes: libgit.git_strarray,
    remote_conns: std.StringHashMap(*libgit.struct_git_remote),

    pub fn init(allocator: std.mem.Allocator, repository_path: []const u8) GitError!Repository {
        // errdefer print_error();

        const ret = libgit.git_libgit2_init();
        if (ret == 0) {
            return GitError.InitError;
        }
        if (ret > 1) {
            return GitError.AlreadyInitialized;
        }

        var repo: ?*libgit.struct_git_repository = null;
        if (libgit.git_repository_open(&repo, repository_path.ptr) != 0) {
            return GitError.InitError;
        }

        var remotes: libgit.git_strarray = undefined;
        if (libgit.git_remote_list(&remotes, repo) != 0) {
            return GitError.InitError;
        }

        var r = Repository {
            .allocator = allocator,
            .repo = repo,
            .remotes = remotes,
            .remote_conns = .init(allocator),
        };

        for (0..remotes.count) |i| {
            const remote_name = remotes.strings[i];
            const remote_name_str = std.mem.span(remote_name);
            var remote: ?*libgit.struct_git_remote = null;
            if (libgit.git_remote_lookup(&remote, repo, remote_name) != 0) {
                return GitError.InitError;
            }
            r.remote_conns.put(remote_name_str, remote.?) catch {
                return GitError.InitError;
            };
        }

        return r;
    }

    // pub fn fetch(repo: Repository, remote_name: []const u8) !void {
    //     errdefer print_error();
    //     const remote = repo.remote_conns.get(remote_name);
    //     if (remote == null) {
    //         return GitError.BranchNotFound;
    //     }
    //
    //     libgit.git_remote_connect(remote, libgit.GIT_DIRECTION_FETCH, callbacks: [*c]const struct_git_remote_callbacks, null, null);
    //
    //     if (libgit.git_remote_fetch(remote, null, null, null) != 0) {
    //         return GitError.FetchError;
    //     }
    // }

    pub fn find_branch_tree(repo: Repository, branch_name: []const u8, remote_name: []const u8) !Tree {
        if (remote_name.len == 0) {
            return git_find_branch_tree(repo.repo, branch_name, .Local);
        }

        const remote = repo.remote_conns.get(remote_name);
        if (remote == null) {
            return GitError.BranchNotFound;
        }

        return git_find_branch_tree(remote, branch_name, .Remote);
    }

    pub fn deinit(r: *Repository) GitError!void {
        // errdefer print_error();
        std.debug.assert(r.repo != null);
        libgit.git_repository_free(r.repo.?);
        libgit.git_strarray_free(&r.remotes);

        // var it = r.remote_conns.valueIterator();
        // while (it.next()) |remote| {
            // libgit.git_repository_free(remote.*);
        // }

        r.remote_conns.deinit();

        const ret = libgit.git_libgit2_shutdown();
        if (ret != 0) {
            return GitError.AlreadyShutdown;
        }
    }
};

pub const Tree = struct {
    tree: *libgit.struct_git_tree,
    fn from_commit_object(obj: *libgit.struct_git_object) !Tree {
        defer libgit.git_object_free(obj);
        const as_commit: *libgit.struct_git_commit = @ptrCast(obj);

        var tree: ?*libgit.struct_git_tree = null;
        if (libgit.git_commit_tree(&tree, as_commit) != 0) {
            return GitError.BranchNotFound;
        }
        return Tree {
            .tree = tree.?,
        };
    }
 };

pub fn deinit(tree: Tree) void {
    libgit.git_tree_free(tree.tree);
}


fn git_find_branch_tree(repo: ?*libgit.struct_git_repository, branch_name: []const u8, where: Where) !Tree {
    // errdefer print_error();
    var branch: ?*libgit.struct_git_reference = null;
    if (libgit.git_branch_lookup(&branch, repo, branch_name.ptr, @intFromEnum(where)) != 0) {
        return GitError.BranchNotFound;
    }
    defer libgit.git_reference_free(branch);

    var obj: ?*libgit.struct_git_object = null;
    if (libgit.git_reference_peel(&obj, branch, libgit.GIT_OBJECT_COMMIT) != 0) {
        return GitError.BranchNotFound;
    }

    return Tree.from_commit_object(obj.?);
}
