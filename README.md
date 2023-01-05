## [zig](https://ziglang.org) docs on command line.

usage:

    zdoc [-s] <source> [identifier]

the program searches source code for matching public identifiers,
printing found types and their doc comments to stdout.
the search is case-insensitive and non-exhaustive. no semantic
analysis is run.

if -s option is specified, any identifier substring matches.
as a side effect, the -s with no identifier arg results in
printing out only top level doc comments.

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

zdoc outputs results in a basic colored format unless `NO_COLOR`
env variable is set or `--nocolor` flag is seen on command line.

### supported versions

zdoc `master` branch requires zig v0.11. however, zdoc can be built with zig v0.10
from the `0.10` branch.

### contributing

to contribute, create a pull request or send a patch with
[git send-mail](https://git-scm.com/docs/git-send-email) to alex-dot-cloudware.io.

before sending a change, please make sure tests pass:

    zig build test

and all code is formatted:

    zig fmt --check .

### license

same as zig license.
