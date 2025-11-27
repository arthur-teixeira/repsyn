const std = @import("std");
const clap = @import("clap");
const git = @import("./libgit.zig");
const GitError = git.GitError;
const StrArray = @import("./strarray.zig").StrArrayBuilder;
const libgit = @cImport({
    @cInclude("git2.h");
});
const stderr = @import("./stderr.zig");

const Args = struct {
    allocator: std.mem.Allocator,
    repository_paths: std.BufSet,
    remotes: std.StringArrayHashMap([]const u8),
    ignores: std.BufSet,

    fn deinit(self: *Args) void {
        self.repository_paths.deinit();
        self.remotes.deinit();
        self.ignores.deinit();
    }

    fn init(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !?Args {
        var self = Args{
            .allocator = allocator,
            .repository_paths = undefined,
            .remotes = undefined,
            .ignores = undefined,
        };
        const mode = args.next() orelse return null;
        const param = args.next() orelse return null;

        if (!try parse_lists(allocator, args, &self)) {
            return null;
        }

        const repositories = resolve_repositories_from_mode(allocator, mode, param, &self.ignores) orelse return null;
        self.repository_paths = repositories;
        
        return self;
    }
};

const underlineStart = "\x1b[4m";
const underlineEnd = "\x1b[0m";

fn usage(program: []const u8) void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("{s} {s}mode{s} {s}mode-value{s} ", .{program, underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("{{[{s}-o{s} {s}origin-name{s} {s}origin-url{s}]}}\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("Available modes:\n", .{});
    std.debug.print("\t{s}--file{s} {s}filename{s}: specify a file containing a list of repository paths.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("\t\tFile must be a text file with newline-separated repository paths.\n", .{});
    std.debug.print("\t{s}--dir{s} {s}path{s}: specify a folder containing a list of repositories.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("\t{s}--repo{s} {s}path{s}: specify a single repository path.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("\t {{[{s}-e{s} {s}subfolder{s}]}} - Subfolder to ignore.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
}

fn resolve_file(allocator: std.mem.Allocator, file_path: []const u8, ignores: *const std.BufSet) !std.BufSet {
    const cwd = std.fs.cwd();
    const f = cwd.openFile(file_path, .{}) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            std.log.err("Could not open file {s}: File not found\n", .{file_path});
            std.process.exit(1);
        }
        return err;
    };
    defer f.close();

    var read_buf: [4096]u8 = undefined;
    var rdr = f.reader(&read_buf);

    var strings: std.BufSet = .init(allocator);
    while (rdr.interface.takeDelimiter('\n')) |line| {
        if (line == null) {
            break;
        }
        if (ignores.contains(line.?)) {
            stderr.print("Ignoring {s}\n", .{line.?});
            continue;
        }

        try strings.insert(line.?);
    } else |err| return err;

    if (strings.count() == 0) {
        std.log.err("source file is empty\n", .{});
        std.process.exit(1);
    }

    return strings;
}

fn resolve_folder(allocator: std.mem.Allocator, folder_path: []const u8, ignores: *const std.BufSet) !?std.BufSet {
    const cwd = std.fs.cwd();
    var folder = try cwd.openDir(folder_path, .{ .iterate = true });
    defer folder.close();

    var repositories: std.BufSet = .init(allocator);

    var it = folder.iterateAssumeFirstIteration();
    while (try it.next()) |f| {
        if (f.kind != .directory) {
            continue;
        }
        if (ignores.contains(f.name)) {
            stderr.print("Ignoring folder {s}\n", .{f.name});
            continue;
        }

        const sub_path = try std.fs.path.join(allocator, &[_][]const u8 {
            folder_path,
            f.name
        });
        defer allocator.free(sub_path);

        var sub_folder = try cwd.openDir(sub_path, .{ .iterate = true, .access_sub_paths = true });
        sub_folder.access(".git", .{}) catch |err| {
            if (err == std.fs.Dir.OpenError.FileNotFound) {
                stderr.print("Subfolder {s} is not a git repository, ignoring.\n", .{sub_path});
                continue;
            }
            return err;
        };

        try repositories.insert(sub_path);
    }

    if (repositories.count() == 0) {
        std.log.err("Specified folder does not contain any repositories.\n", .{});
        std.process.exit(1);
    }

    return repositories;
}

fn resolve_single_repository(allocator: std.mem.Allocator, repository: []const u8) !std.BufSet {
    var a: std.BufSet = .init(allocator);
    try a.insert(repository);
    return a;
}

fn resolve_repositories_from_mode(allocator: std.mem.Allocator, mode: [:0]const u8, param: [:0]const u8, ignores: *const std.BufSet) ?std.BufSet {
    if (std.mem.eql(u8, mode, "--file")) {
        return resolve_file(allocator, param, ignores) catch return null;
    }

    if (std.mem.eql(u8, mode, "--dir")) {
        return resolve_folder(allocator, param, ignores) catch return null;
    }

    if (std.mem.eql(u8, mode, "--repo")) {
        return resolve_single_repository(allocator, param) catch return null;
    }

    return null;
}

fn parse_lists(allocator: std.mem.Allocator, args: *std.process.ArgIterator, parsed_args: *Args) !bool {
    var remotes: std.StringArrayHashMap([]const u8) = .init(allocator);
    var ignores: std.BufSet = .init(allocator);
    while (args.next()) |arg| {
        const is_o = std.mem.eql(u8, arg, "-o");
        const is_e = std.mem.eql(u8, arg, "-e");
        if (!is_o and !is_e) {
            break;
        }

        if (is_o) {
            const remote_name = args.next() orelse return false;
            const remote_url = args.next() orelse return false;
            try remotes.put(remote_name, remote_url);
            continue;
        }

        const folder_name = args.next() orelse return false;
        try ignores.insert(folder_name);
    }

    parsed_args.ignores = ignores;
    parsed_args.remotes = remotes;
    return true;
}

pub fn main() !void {
    var stderrBuf: [4096]u8 = undefined;
    stderr.init(&stderrBuf);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    defer args.deinit();
    const program_name = args.next().?;

    var parsed = try Args.init(allocator, &args) orelse {
        usage(program_name);
        return;
    };
    defer parsed.deinit();

    const ret = libgit.git_libgit2_init();
    if (ret == 0) {
        return GitError.InitError;
    }
    if (ret > 1) {
        return GitError.AlreadyInitialized;
    }
    defer _ = libgit.git_libgit2_shutdown();

    var it = parsed.repository_paths.iterator();
    while (it.next()) |repo_path| {
        std.log.info("handling repository {s}\n", .{repo_path.*});
        var repo = try git.Repository.init(allocator, repo_path.*);
        defer repo.deinit();
        try repo.push_to_remotes();
    }

    errdefer print_error();
}

fn print_error() void {
    const err = libgit.git_error_last();
    if (err != null) {
        std.log.err("{s}\n", .{err.*.message});
    }
}
