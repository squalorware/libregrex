# regrex

**regrex** = Regret + RegEx

> A programmable regret - inevitable. Inexorable. The Crime and the Punishment.

![REGRET](assets/readme.jpg)

## What is this?

`regrex` is a simple PCRE/Python inspired regular expression engine implemented in the Zig programming language, built as a hobby in spare time. It was conceived as an exercise for both learning Zig and the theoretical fundamentals of building a compiler and/or interpreter. Thus, it follows the classical pipeline: 
1. The string containing a regular expression pattern is lexically analyzed and broken into a stream of lexical tokens
2. The token array is then parsed, generating the abstract syntax tree of the expression
3. Then the generated AST is compiled into the intermediate code representation (bytecode) instructions
4. Finally, the instructions are executed by a virtual machine

One of the key goals was to make it as much Unicode-friendly as possible. For this reason, while internally `regrex` operates with the byte offsets into an input string as it would be expected, at the same time the core entity consumed by all of the steps above is a custom `Rune` type, defined as an **unsigned 21-bit integer**, which represents a single UTF-8 scalar value, providing an abstraction that allows to treat any valid Unicode character as if it were a simple `char` (unsigned 8-bit integer).

Features `regrex` currently supports:
- Literal character matching;
- Escaped literal characters, such as `\.`, `\*`, `\(`, and `\\`;
- Wildcard matching with `.`;
- Start and end anchors with `^` and `$`;
- Greedy quantifiers: `*`, `+`, and `?`;
- Character classes, such as `[a-z]`, `[A-Z]`, `[0-9]`, and `[a-zA-Z0-9_]`;
- Negated character classes, such as `[^0-9]`;
- Unicode-aware literals and explicit Unicode ranges;
- Capturing groups with `(...)`;
- Non-capturing groups with `(?:...)`;
- Branching (alternation) with `|`;

The exposed API consists of 
- library root level functions (the pattern is compiled on the fly and destroyed at the execution end):
    - `compile` to get a reusable compiled regex pattern
    - `search` to look for the first match anywhere in the input
    - `match` to look for the match at the beginning of the input
    - `findAll` to eagerly retrieve all of the matches 
    - `sub` which takes a string and returns a copy of the input where all of the matches have been replaced with said string
- `Pattern` type which represents the compiled regular expression. It provides the same four basic operations (`search`, `match`, `findAll` and `sub`), as well as introduces `findIter` function which returns an instance of `FindIterator` type, the latter allowing for lazy lookup doing one match at a time with its `next` function
- `Match` type which represents the lookup results. This type holds byte offsets into the input string representing matching and captured groups.
- `MatchArray` which is a convenience type to simplify managing dynamically growing list of  `Match` objects received from `findAll`function.

Apart from this functionality, `regrex` also exposes C-compatible API/ABI, taking advantage of amazing Zig-to-C interoperability capabilities. Look at the `include/regrex.h` and `src/clib.zig` files for declaration and implementation respectively and to learn more about it.

### Nota Bene!
This project does not aim to be a proper and serious production-grade implementation of regular expressions like PCRE or Python `re` - treat it as a learning project or a proof of concept at best. Advanced features such as lookarounds, backreferences, lazy quantifiers, counted repetitions, Unicode properties like `\p{L}`, and full regex flag handling are well outside of scope of this project for foreseeable future.

## HOWTO

### Install
Fetch and save to `build.zig.zon` in one step
```bash
zig fetch --save https://github.com/squalorware/libregrex/archive/refs/tags/v0.1.0.tar.gz
```

Alternatively, you can fetch it via `git ref`

```bash
zig fetch --save git+https://github.com/squalorware/libregrex#v0.1.0
```

This will automatically add the dependency and its hash to your `build.zig.zon`.

After fetching the package, add the following to `build.zig`
```zig
// A typical build function

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Include the library here!
    const regrex = b.dependency("regrex", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("regrex", regrex.module("regrex"));

    // The rest of your build configuration
    b.installArtifact(exe);
}
```

### Use (in Zig)
For one-off operations, import `regrex` and pass an allocator explicitly. Returned `Match` values own internal subgroup storage, so they must be released with `Match.deinit()`

```zig
const std = @import("std");
const regrex = @import("regrex");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // If no match was found, search() returns null;
    var result = (try regrex.search(
        allocator,
        "[0-9]+",
        "foo 123 bar",
    )) orelse {
        std.debug.print("no match found\n", .{});
        return;
    };
    defer result.deinit(allocator);

    std.debug.print("matched: {s}\n", .{result.full()});
}
```
If you need to use the same pattern more than once, it's better to compile it once to keep a reusable `Pattern` handle until you release it:
```zig
// Other code...
const allocator = std.heap.page_allocator;

const pattern = try regrex.compile(allocator, "[a-zA-Z]+=[0-9]+");
defer pattern.deinit();

var first = (try pattern.search("foo=123 bar=456")) orelse {
    std.debug.print("no match found\n", .{});
    return;
};
defer first.deinit(allocator);
std.debug.print("first match: {s}\n", .{first.full()});
```
`Pattern` provides all the same functionality as the one-off functions - in fact, what, for example, the `regrex.match` is doing is basically compiling a temporary `Pattern` and calling its methods; the `Pattern` is released at the end of the function's execution. 

If you need to retrieve all matches you can use `findAll` function to get them at once
```zig
var matches: regrex.MatchArray = try pattern.findAll("foo=123 bar=456 baz=789");
defer matches.deinit();

for (matches) |m| {
    std.debug.print("match: {s}\n", .{m.full()});
}
```

Alternatively, you can use the lazy iterator which `Pattern` provides, allowing for more versatile control
```zig
var iter = try pattern.findIter("foo=123 bar=456 baz=789");
defer iter.deinit();

// for example you can retrieve just one next match
var match = (try iter.next()) orelse {
    std.debug.print("no match found\n", .{});
    return;
};
std.debug.print("{s}\n", .{match});

// ...or going over matches in a loop
while(iter.next()) |m| {
    std.debug.print("{s}\n", .{m});
}
```
And of course, you can replace the matches (the original input is never mutated - `sub` copies the non-matching bits and inserts the string stored inside `repl_buf` parameter at the byte offsets of the matches)
```
const replaced = try pattern.sub("<pair>", "foo=123 bar=456", .{ .count = 0 });
defer allocator.free(replaced);

std.debug.print("replaced: {s}\n", .{replaced});
```

### ... and in C

The provided C-compatible API is expected to expose all the same functionality as the Zig library, keeping in mind the inevitable limitations and possible pitfalls. The C ABI operates with opaque handler types wrapping over the Zig implementation and explicit destructors for every type to ensure as much maximum memory safety as it is possible due to the nature of C.

- `regx_errcode_t` is an enum type containing execution status codes.
- `regx_pattern_t` and `regx_match_t` are opaque types wrapping the underlying Zig `Pattern`and `Match` types.
- `regx_match_arr_t` respectively encapsulates the `MatchArray` type
- `regx_buffer_t` represents a convenience type that holds the string (byte buffer) and its length. 
- `REGX_BUF` is a helper macro that allows converting string literals and C strings to `regx_buffer_t`
```c
#include <stdio.h>
#include "regrex.h"

int main(void) 
{
    regx_errcode_t rc; // As per tradition 0 is OK; trouble - everything else.
    regx_pattern_t *pattern = NULL;
    regx_match_t *match = NULL;

    rc = regrex_compile(REGX_BUFFER("[0-9]+"), &pattern);
    if (rc != REGREX_OK) {
        fprintf(stderr, "regrex_compile failed: %s\n", regrex_error(rc));
        return 1;
    }

    rc = regx_pattern_search(pattern, REGX_BUFFER("foo 123 bar"), &match);
    if (rc == REGREX_OK) {
        regx_group_t span;

        rc = regx_match_span(match, 0, &span);
        if (rc == REGREX_OK) {
            const char *input = "foo 123 bar";
            printf("matched: %.*s\n", (int)(span.end - span.start), input + span.start);
        }

        regx_match_destroy(match);
    } else if (rc == REGREX_ENOMATCH) {
        puts("no match found");
    } else {
        fprintf(stderr, "search failed: %s\n", regrex_error(rc));
    }
    // Don't forget about the destructors!
    regx_pattern_destroy(pattern);
    return (int) rc;
}
```
## Building

Minimal required version for a successful build is 0.16.0

### Testing

Run `zig build test --summary all --verbose`
