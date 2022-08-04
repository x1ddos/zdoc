//! zdoc searches source code according to the provided query and prints
//! the results to stdout. see usage for details.

const std = @import("std");

const analyze = @import("analyze.zig");
const output = @import("output.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // parse cmd line args
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    defer args.deinit();
    const progname = args.next().?;
    var zquery: ?[:0]const u8 = null;
    var zsource: [:0]const u8 = undefined;
    var nargs: u8 = 0;
    while (args.next()) |a| {
        switch (nargs) {
            0 => {
                zsource = a;
                nargs += 1;
            },
            1 => {
                zquery = a;
                nargs += 1;
            },
            else => fatal("too many args", .{}),
        }
    }
    if (nargs == 0) { // expected 1 or 2 args
        usage(progname) catch {};
        return;
    }

    // output all results to stdout
    var auto_indenting_stream = output.Ais{
        .indent_delta = 4,
        .underlying_writer = stdout,
    };
    const ais = &auto_indenting_stream;

    // run the search, one file at a time
    var query: ?[]const u8 = if (zquery) |q| q[0..] else null;
    const list = try expandSourcePath(alloc, zsource);
    for (list.items) |src| {
        // todo: consider replacing arena with something else to dealloc already
        // analyzed files early and possibly reduce memory footprint.
        const contents = try readFile(alloc, src);
        try analyze.search(alloc, ais, contents, query);
    }
}

fn usage(prog: []const u8) !void {
    try stderr.print(
        \\usage: {s} [source] <identifier>
        \\
        \\the program searches source code for matching public identifiers,
        \\printing found types and their doc comments to stdout.
        \\the search is case-insensitive and non-exhaustive.
        \\
        \\for example, look up format function in std lib:
        \\
        \\    zdoc std.fmt format
        \\
        \\print fmt's top level doc comments:
        \\
        \\    zdoc std.fmt
        \\
        \\look up "hello" identifier in a project file:
        \\
        \\    zdoc ./src/main.zig hello
        \\
        \\search across all .zig files starting from the src directory,
        \\recursively and following symlinks:
        \\
        \\    zdoc ./src hello
        \\
    , .{prog});
}

/// fatal prints an std.format-formatted message and terminates the program
/// with exit code 1.
fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    stderr.print(fmt, args) catch {};
    if (fmt[fmt.len - 1] != '\n') {
        stderr.writeByte('\n') catch {};
    }
    std.os.exit(1);
}

/// todo: caller must free ...
fn readFile(alloc: std.mem.Allocator, name: []const u8) ![:0]const u8 {
    var b: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(name, &b);
    const file = try std.fs.openFileAbsolute(realpath, .{ .mode = .read_only });
    defer file.close();
    const st = try file.stat();
    const contents = try alloc.allocSentinel(u8, st.size, '\x00');
    _ = try file.readAll(contents);
    return contents;
}

/// todo: caller must free ...
fn expandSourcePath(alloc: std.mem.Allocator, name: []const u8) !std.ArrayList([]const u8) {
    // check for special std case
    if (std.mem.startsWith(u8, name, "std.")) {
        const stdroot = try zigStdPath(alloc);
        // std.foo.bar -> std/foo/bar and append .zig extension
        const fspath = try std.mem.join(alloc, &.{}, &.{
            try std.mem.replaceOwned(u8, alloc, name[4..], ".", std.fs.path.sep_str),
            ".zig",
        });
        var list = try std.ArrayList([]const u8).initCapacity(alloc, 1);
        try list.append(try std.fs.path.join(alloc, &.{ stdroot, fspath }));
        return list;
    }

    // otherwise, try a fileystem path
    var b: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(name, &b);
    const stat = stat: {
        const file = try std.fs.openFileAbsolute(realpath, .{ .mode = .read_only });
        defer file.close();
        const info = try file.stat();
        break :stat info;
    };

    // simple case, a single file
    if (stat.kind == .File) {
        var list = try std.ArrayList([]const u8).initCapacity(alloc, 1);
        try list.append(name);
        return list;
    }

    // openIterableDir follows symlinks by default.
    var root = try std.fs.cwd().openIterableDir(realpath, .{});
    defer root.close();
    var walker = try root.walk(alloc);
    defer walker.deinit();
    var list = std.ArrayList([]const u8).init(alloc);
    // todo: this walks into zig-cache and .dot dirs; switch to raw root.iterate()
    while (try walker.next()) |entry| {
        if (entry.kind != .File or !std.mem.eql(u8, ".zig", std.fs.path.extension(entry.path))) {
            continue;
        }
        //std.debug.print("walker entry: {s}\n", .{entry.path});
        const srcfile = try std.fs.path.join(alloc, &.{ realpath, entry.path });
        try list.append(srcfile);
    }
    return list;
}

fn zigStdPath(alloc: std.mem.Allocator) ![]const u8 {
    const res = try std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "zig", "env" },
    });
    defer {
        alloc.free(res.stdout);
        alloc.free(res.stderr);
    }
    if (res.term.Exited != 0) {
        fatal("zig env: {s}", .{res.stderr});
    }

    const Env = struct { std_dir: []const u8 };
    const opt = .{ .allocator = alloc, .ignore_unknown_fields = true };
    var jenv = try std.json.parse(Env, &std.json.TokenStream.init(res.stdout), opt);
    defer std.json.parseFree(Env, jenv, opt);
    return alloc.dupe(u8, jenv.std_dir);
}

test {
    // run tests found in all @import'ed files.
    std.testing.refAllDecls(@This());
}
