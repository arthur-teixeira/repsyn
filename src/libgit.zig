const std = @import("std");
const libgit = @cImport({
    @cInclude("git2.h");
});
const StrArrayBuilder = @import("./strarray.zig").StrArrayBuilder;

pub const GitError = error {
    InitError,
    AlreadyInitialized,
    AlreadyShutdown,
    BranchNotFound,
    DiffError,
    FetchError,
};

pub const Repository = struct {
    allocator: std.mem.Allocator,
    repo: *libgit.struct_git_repository,
    branches: StrArrayBuilder,
    remotes: libgit.git_strarray,
    push_opts: libgit.git_push_options,
    callbacks: libgit.git_remote_callbacks,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Repository {
        var out: Repository = undefined;
        out.allocator = allocator;

        var repo: ?*libgit.struct_git_repository = null;
        const ret = libgit.git_repository_open(&repo, path.ptr);
        if (ret != 0) {
            return GitError.InitError;
        }

        out.repo = repo.?;
        try out.set_branch_list();
        try out.set_remote_list();
        try out.set_callbacks();
        try out.set_push_opts();

        return out;
    }

    pub fn deinit(self: *Repository) void {
        libgit.git_repository_free(self.repo);
        libgit.git_strarray_free(&self.remotes);
        self.branches.deinit();
    }

    fn set_callbacks(self: *Repository) !void {
        const ret = libgit.git_remote_init_callbacks(&self.callbacks, libgit.GIT_REMOTE_CALLBACKS_VERSION);
        if (ret != 0) {
            return GitError.InitError;
        }
    }

    fn set_push_opts(self: *Repository) !void {
        const ret = libgit.git_push_options_init(&self.push_opts, libgit.GIT_PUSH_OPTIONS_VERSION);
        if (ret != 0) {
            return GitError.InitError;
        }
        self.push_opts.callbacks = self.callbacks;
    }

    fn set_remote_list(self: *Repository) !void {
        const ret = libgit.git_remote_list(&self.remotes, self.repo);
        if (ret != 0) {
            return GitError.InitError;
        }
    }

    fn set_branch_list(self: *Repository) !void {
        var iter: ?*libgit.git_branch_iterator = null;
        var ret = libgit.git_branch_iterator_new(&iter, self.repo, libgit.GIT_BRANCH_LOCAL);
        if (ret != 0) {
            return GitError.InitError;
        }
        defer libgit.git_branch_iterator_free(iter);

        var branches = try StrArrayBuilder.init(self.allocator);

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
            try branches.append(std.mem.span(branch_ref_name));
        }

        try branches.finish();
        self.branches = branches;
    }

    pub fn push_to_remotes(self: *Repository) !void {
        for (0..self.remotes.count) |i| {
            const remote = self.remotes.strings[i];
            try self.push_to_remote(remote);
        }
    }

    fn push_to_remote(self: *Repository, remote_name: [*c]const u8) !void {
        var remote: ?*libgit.struct_git_remote = null;
        var ret = libgit.git_remote_lookup(&remote, self.repo, remote_name);
        if (ret != 0) {
            return GitError.InitError;
        }
        defer libgit.git_remote_free(remote);
        const as_lg_array = self.branches.libgit_view();
        ret = libgit.git_remote_push(remote, @ptrCast(&as_lg_array), &self.push_opts);
        if (ret != 0) {
            return GitError.InitError;
        }
    }
};
