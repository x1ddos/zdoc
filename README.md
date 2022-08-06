## [zig](https://ziglang.org) docs on command line.

usage:

    zdoc [-s] <source> [identifier]

the program searches source code for matching public identifiers,
printing found types and their doc comments to stdout.
the search is case-insensitive and non-exhaustive.
if -s option is specified, any identifier substring matches.

for example, look up "hello" identifier in a project file:

    zdoc ./src/main.zig hello

search across all .zig files starting from the src directory,
recursively and following symlinks:

    zdoc ./src hello

if the source starts with `std.`, the dot delimiters are replaced
with filesystem path separator and "std." with the `std_dir` value
from `zig env` command output.

for example, look up format function in std lib:

    zdoc std.fmt format

list all expectXxx functions from the testing module:

    zdoc -s std.testing expect

as a special case, if the source is exactly `std` and no such file
or directory exists, zdoc searches across the whole zig std lib.
---

that's about all it can do for now. a future version may include search
syntax for public struct fields, enum tags and other constructs, like so:

    zdoc std.foo.bar .somefield

for some types, zig may log an error reading something like,
"renderingExpression for ... unimplemented". that's because i commented out
a big chunk of rendering cases in src/output.zig which was adapted from
std/zig/render.zig, to suppress definitions output.

if you see an error like this, please create an issue or send a code change.

---

to contribute, create a pull request or send a patch with
[git send-mail](https://git-scm.com/docs/git-send-email) to alex-dot-cloudware.io.

before sending a change, please make sure tests pass:

    zig build test

and all code is formatted:

    zig fmt --check .

### license

same as zig license.
