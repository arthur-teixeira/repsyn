const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});

const GitError = error {
    InitError,
    AlreadyInitialized,
    AlreadyShutdown,
    BranchNotFound,
    DiffError,
};

const Where = enum(c_uint) {
    None = 0,
    Local = libgit.GIT_BRANCH_LOCAL,
    Remote = libgit.GIT_BRANCH_REMOTE,
};

pub const Repository = struct {
    repo: ?*libgit.struct_git_repository,

    pub fn init(repository_path: []const u8) GitError!Repository {
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

        return Repository {
            .repo = repo,
        };
    }

    pub fn deinit(r: Repository) GitError!void {
        errdefer print_error();
        std.debug.assert(r.repo != null);
        libgit.git_repository_free(r.repo.?);

        const ret = libgit.git_libgit2_shutdown();
        if (ret != 0) {
            return GitError.AlreadyShutdown;
        }
    }

    pub fn diff_to_remote(r: Repository, tree1: Tree, tree2: Tree) !void {
        var diff: ?*libgit.struct_git_diff = null;
        if (libgit.git_diff_tree_to_tree(&diff, r.repo, tree1.tree, tree2.tree, null) != 0) {
            return GitError.DiffError;
        }

        libgit.git_diff_free(diff);

        std.debug.print("Got diff between remote and local \n", .{});
    }

    pub fn find_branch_tree(repo: Repository, branch_name: []const u8, where: Where) !Tree {
        errdefer print_error();
        var branch: ?*libgit.struct_git_reference = null;
        if (libgit.git_branch_lookup(&branch, repo.repo, branch_name.ptr, @intFromEnum(where)) != 0) {
            return GitError.BranchNotFound;
        }
        defer libgit.git_reference_free(branch);

        var obj: ?*libgit.struct_git_object = null;
        if (libgit.git_reference_peel(&obj, branch, libgit.GIT_OBJECT_COMMIT) != 0) {
            return GitError.BranchNotFound;
        }
        return Tree.from_commit_object(obj.?);
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

    pub fn deinit(tree: Tree) void {
        libgit.git_tree_free(tree.tree);
    }
};

fn print_error() void {
    const err = libgit.git_error_last();
    if (err != null) {
        std.debug.print("ERROR: {s}\n", .{err.*.message});
    }
}
