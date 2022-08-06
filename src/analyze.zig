const std = @import("std");
const output = @import("output.zig");
const Ast = std.zig.Ast;

/// search parses the source code into std.zig.Ast and walks over top level declarations,
/// optionally matching against the query.
///
/// results are printed using ais.
pub fn search(alloc: std.mem.Allocator, ais: *output.Ais, source: [:0]const u8, query: ?[]const u8) !void {
    var tree = try std.zig.parse(alloc, source);
    defer tree.deinit(alloc);
    var insert_newline = false;
    for (tree.rootDecls()) |decl| {
        if (!isPublic(tree, decl)) {
            continue;
        }
        if (query != null and !identifierMatch(tree, decl, query.?)) {
            continue;
        }
        if (insert_newline) {
            try ais.insertNewline();
        }
        try output.renderPubMember(alloc, ais, tree, decl, .newline);
        insert_newline = true;
    }
}

/// reports whether the declaration is visible to other modules.
pub fn isPublic(tree: Ast, decl: Ast.Node.Index) bool {
    const token_tags = tree.tokens.items(.tag);
    var i = tree.nodes.items(.main_token)[decl];
    while (i > 0) {
        i -= 1;
        switch (token_tags[i]) {
            .keyword_export,
            .keyword_pub,
            => return true,

            .keyword_extern,
            .keyword_comptime,
            .keyword_threadlocal,
            .keyword_inline,
            .keyword_noinline,
            .string_literal,
            => continue,

            else => break,
        }
    }
    return false;
}

/// reports whether the given name matches decl identifier, case-insensitive.
pub fn identifierMatch(tree: Ast, decl: Ast.Node.Index, name: []const u8) bool {
    return if (identifier(tree, decl)) |ident| std.ascii.eqlIgnoreCase(name, ident) else false;
}

/// identifier returns node's identifier, if any.
fn identifier(tree: Ast, node: Ast.Node.Index) ?[]const u8 {
    switch (tree.nodes.items(.tag)[node]) {
        .fn_decl => return identifier(tree, tree.nodes.items(.data)[node].lhs),

        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => |tag| {
            const proto = switch (tag) {
                .fn_proto_simple => simple: {
                    var params: [1]Ast.Node.Index = undefined;
                    const proto = tree.fnProtoSimple(&params, node);
                    break :simple proto;
                },
                .fn_proto_one => one: {
                    var params: [1]Ast.Node.Index = undefined;
                    const proto = tree.fnProtoOne(&params, node);
                    break :one proto;
                },
                .fn_proto_multi => tree.fnProtoMulti(node),
                .fn_proto => tree.fnProto(node),
                else => unreachable,
            };
            const idx = proto.ast.fn_token + 1;
            if (tree.tokens.items(.tag)[idx] == .identifier) {
                return tree.tokenSlice(idx);
            }
        },

        .simple_var_decl => {
            const decl = tree.simpleVarDecl(node);
            return tree.tokenSlice(decl.ast.mut_token + 1);
        },

        else => return null,
    }
    return null;
}

test "identifier matches" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\pub const baz = struct { z: u32 };
        \\fn quix() void { }
    ;
    const tt = [_]struct { name: []const u8 }{
        .{ .name = "foo" },
        .{ .name = "bar" },
        .{ .name = "baz" },
        .{ .name = "quix" },
    };
    var tree = try std.zig.parse(alloc, src);
    defer tree.deinit(alloc);
    for (tree.rootDecls()) |decl, i| {
        const tc = tt[i];
        if (!identifierMatch(tree, decl, tc.name)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): false; identifier({d}): {?s}\n", .{ i, tc.name, decl, id });
            return error.NoMatch;
        }
    }
}

test "no identifier match" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\pub const baz = struct { z: u32 };
        \\fn quix() void { }
    ;
    const z = "z";
    var tree = try std.zig.parse(alloc, src);
    defer tree.deinit(alloc);
    for (tree.rootDecls()) |decl, i| {
        if (identifierMatch(tree, decl, z)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): true; identifier({d}): {?s}\n", .{ i, z, decl, id });
            return error.Match;
        }
    }
}
