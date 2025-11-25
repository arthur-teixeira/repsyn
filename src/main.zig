const std = @import("std");
const clap = @import("clap");
const git = @import("./libgit.zig");
const GitError = git.GitError;
const StrArray = @import("./strarray.zig").StrArrayBuilder;
const libgit = @cImport({
    @cInclude("git2.h");
});
const stderr = @import("./stderr.zig");


const Remote = struct {
    name: []const u8,
    url: []const u8,
};

const Args = struct {
    allocator: std.mem.Allocator,
    repository_paths: std.BufSet,
    remotes: std.ArrayList(Remote),

    fn deinit(self: *Args) void {
        for (self.repository_paths.items) |r| {
            self.allocator.free(r);
        }
        self.repository_paths.deinit(self.allocator);
        self.remotes.deinit(self.allocator);
    }

    fn init(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !?Args {
        const repositories = resolve_repositories_from_mode(allocator, args) orelse return null;
        std.debug.print("REPOSITORIES {any}\n", .{repositories});

        _ = try parse_remotes(allocator, args) orelse return null;

        return null;
    }
};

const underlineStart = "\x1b[4m";
const underlineEnd = "\x1b[0m";

fn usage(program: []const u8) void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("{s} {s}mode{s} {s}mode-value{s} {{[{s}-o{s} {s}origin-name{s} {s}origin-url{s}]}}\n", .{program, underlineStart, underlineEnd, underlineStart, underlineEnd, underlineStart, underlineEnd, underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("Available modes:\n", .{});
    std.debug.print("\t{s}--file{s} {s}filename{s}: specify a file containing a list of repository paths.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("\t\tFile must be a text file with newline-separated repository paths.\n", .{});
    std.debug.print("\t{s}--root{s} {s}path{s}: specify a folder containing a list of repositories.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
    std.debug.print("\t{s}--repo{s} {s}path{s}: specify a single repository path.\n", .{underlineStart, underlineEnd, underlineStart, underlineEnd});
}

fn resolve_file(allocator: std.mem.Allocator, file_path: []const u8) !std.BufSet {
    const cwd = std.fs.cwd();
    const f = cwd.openFile(file_path, .{}) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            stderr.print("ERROR: Could not open file {s}: File not found\n", .{file_path});
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

        try strings.insert(allocator, line.?);
    } else |err| return err;

    if (strings.count() == 0) {
        stderr.print("ERROR: source file is empty\n", .{});
        std.process.exit(1);
    }

    return strings;
}

fn resolve_folder(_: std.mem.Allocator, folder_path: []const u8) !?std.ArrayList([]u8) {
    const cwd = std.fs.cwd();
    var folder = try cwd.openDir(folder_path, .{});
    defer folder.close();

    return null;
}

fn resolve_single_repository(allocator: std.mem.Allocator, repository: []const u8) !std.BufSet {
    var a: std.BufSet = try .init(allocator);
    try a.insert(repository);
    return a;
}

fn resolve_repositories_from_mode(allocator: std.mem.Allocator, args: *std.process.ArgIterator) ?std.BufSet {
    const mode = args.next() orelse return null;
    const param = args.next() orelse return null;
    std.debug.print("MODE {s} PARAM {s}\n", .{mode, param});

    if (std.mem.eql(u8, mode, "--file")) {
        return resolve_file(allocator, param) catch return null;
    }

    if (std.mem.eql(u8, mode, "--root")) {
        return resolve_folder(allocator, param) catch return null;
    }

    if (std.mem.eql(u8, mode, "--repo")) {
        return resolve_single_repository(allocator, param) catch return null;
    }

    return null;
}

fn parse_remotes(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !?std.ArrayList(Remote) {
    var remotes: std.ArrayList(Remote) = try .initCapacity(allocator, 10);
    while (args.next()) |arg| {
        if (!std.mem.eql(u8, arg, "-o")) {
            break;
        }

        const remote_name = args.next() orelse return null;
        const remote_url = args.next() orelse return null;
        const remote = Remote {
            .name = remote_name,
            .url = remote_url,
        };

        try remotes.append(allocator, remote);
    }

    return remotes;
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

    try repo.push_to_remotes();
}

fn print_error() void {
    const err = libgit.git_error_last();
    if (err != null) {
        std.debug.print("ERROR: {s}\n", .{err.*.message});
    }
}
