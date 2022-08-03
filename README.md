## [zig](https://ziglang.org) docs on command line.

usage:

    zdoc [source] <identifier>

the program searches source code for matching public identifiers,
printing found types and their doc comments to stdout.
the search is case-insensitive and non-exhaustive.

for example, look up format function in std lib:

    zdoc std.fmt format

print fmt's top level doc comments:

    zdoc std.fmt

look up "hello" identifier in a project file:

    zdoc ./src/main.zig hello

search across all .zig files starting from the src directory,
recursively and following symlinks:

    zdoc ./src hello

---

that's about all it can do for now. a future version may include search
syntax for public struct fields, enum tags and other constructs, like so:

    zdoc std.foo.bar .somefield

---

to contribute, create a pull request or send a patch with
[git send-mail](https://git-scm.com/docs/git-send-email) to alex-dot-cloudware.io.

before sending a change, please make sure all code is formatted. check with:

    zig fmt --check .

### license

same as zig license.
