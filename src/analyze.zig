const std = @import("std");
const output = @import("output.zig");
const Ast = std.zig.Ast;

/// Query specifies the kind of identifier matching to look for when search'ing.
pub const Query = union(enum) {
    none, // never match
    all, // always match
    exact: []const u8, // exact match, case-insensitive
    sub: []const u8, // substring match, case-insensitive
};

/// search parses the source code into std.zig.Ast, walks over top level declarations
/// optionally matching against the query, and prints results using ais.
///
/// a .none query matches no identifier; what's left is top level doc comments.
pub fn search(alloc: std.mem.Allocator, ais: *output.Ais, source: [:0]const u8, query: Query) !void {
    var tree = try std.zig.parse(alloc, source);
    defer tree.deinit(alloc);

    // the assumption is top level doc comments are of litte to no interest
    // if an exact/sub query is specified.
    if (query == .none or query == .all) {
        try output.renderTopLevelDocComments(ais, tree);
    }

    var insert_newline = false;
    for (tree.rootDecls()) |decl| {
        if (!isPublic(tree, decl) or !identifierMatch(tree, decl, query)) {
            continue;
        }
        if (insert_newline) {
            try output.renderExtraNewline(ais, tree, decl);
        }
        try output.renderPubMember(alloc, ais, tree, decl, .newline);
        insert_newline = true;
    }
}

/// reports whether the declaration is visible to other modules.
pub fn isPublic(tree: Ast, decl: Ast.Node.Index) bool {
    const token_tags = tree.tokens.items(.tag);
    switch (tree.nodes.items(.tag)[decl]) {
        .fn_decl,
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            var i = tree.nodes.items(.main_token)[decl];
            while (i > 0) {
                i -= 1;
                switch (token_tags[i]) {
                    .keyword_export,
                    .keyword_pub,
                    => return true,
                    .keyword_extern,
                    .string_literal,
                    .keyword_inline,
                    .keyword_noinline,
                    => continue,
                    else => break,
                }
            }
        },
        .@"usingnamespace" => {
            const i = tree.nodes.items(.main_token)[decl];
            return i > 0 and token_tags[i - 1] == .keyword_pub;
        },
        .simple_var_decl => {
            var i = tree.nodes.items(.main_token)[decl];
            while (i > 0) {
                i -= 1;
                // from tree.fullVarDecl
                switch (token_tags[i]) {
                    .keyword_export,
                    .keyword_pub,
                    => return true,
                    .keyword_extern,
                    .keyword_comptime,
                    .keyword_threadlocal,
                    .string_literal,
                    => continue,
                    else => break,
                }
            }
        },
        // container fields are always public
        .container_field_init,
        .container_field_align,
        .container_field,
        => return true,
        else => return false,
    }
    return false;
}

/// reports whether the given name matches decl identifier, case-insensitive.
pub fn identifierMatch(tree: Ast, decl: Ast.Node.Index, q: Query) bool {
    return switch (q) {
        .none => false,
        .all => true,
        .exact => |qexact| exact: {
            const id = identifier(tree, decl);
            break :exact id != null and std.ascii.eqlIgnoreCase(id.?, qexact);
        },
        .sub => |qsub| sub: {
            const id = identifier(tree, decl);
            break :sub id != null and std.ascii.indexOfIgnoreCase(id.?, qsub) != null;
        },
    };
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

test "identifier exact match" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\pub const Baz = struct { z: u32 };
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
        const exact = Query{ .exact = tc.name };
        if (!identifierMatch(tree, decl, exact)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): false; identifier({d}): {?s}\n", .{ i, tc.name, decl, id });
            return error.NoExactMatch;
        }
    }
}

test "identifier sub match" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\pub const Baz = struct { z: u32 };
        \\fn quix() void { }
    ;
    const tt = [_]struct { name: []const u8 }{
        .{ .name = "fo" },
        .{ .name = "ar" },
        .{ .name = "baz" },
        .{ .name = "UI" },
    };
    var tree = try std.zig.parse(alloc, src);
    defer tree.deinit(alloc);
    for (tree.rootDecls()) |decl, i| {
        const tc = tt[i];
        const sub = Query{ .sub = tc.name };
        if (!identifierMatch(tree, decl, sub)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): false; identifier({d}): {?s}\n", .{ i, tc.name, decl, id });
            return error.NoSubMatch;
        }
    }
}

test "no identifier exact match" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\pub const baz = struct { z: u32 };
        \\fn quix() void { }
    ;
    var tree = try std.zig.parse(alloc, src);
    defer tree.deinit(alloc);

    const z = Query{ .exact = "z" };
    for (tree.rootDecls()) |decl, i| {
        if (identifierMatch(tree, decl, z)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): true; identifier({d}): {?s}\n", .{ i, z.exact, decl, id });
            return error.ExactMatch;
        }
    }
}

test "no identifier sub match" {
    const alloc = std.testing.allocator;
    const print = std.debug.print;

    const src =
        \\const foo: u32 = 1;
        \\pub const bar: i32 = 2;
        \\fn quix() void { }
    ;
    var tree = try std.zig.parse(alloc, src);
    defer tree.deinit(alloc);

    const z = Query{ .sub = "z" };
    for (tree.rootDecls()) |decl, i| {
        if (identifierMatch(tree, decl, z)) {
            const id = identifier(tree, decl);
            print("{d}: identifierMatch({s}): true; identifier({d}): {?s}\n", .{ i, z.sub, decl, id });
            return error.SubMatch;
        }
    }
}
