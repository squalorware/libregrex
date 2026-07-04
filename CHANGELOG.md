# Change Log
All notable changes to this project will be documented in this file.

## [Unreleased] - yyyy-mm-dd

### Added

### Changed

### Fixed

## [0.1.0] - 2026-07-04

### Added
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
- Library root top-level one-off functions (the pattern is compiled on the fly and destroyed at the execution end):
    - `compile` to get a reusable compiled regex pattern
    - `search` to look for the first match anywhere in the input
    - `match` to look for the match at the beginning of the input
    - `findAll` to eagerly retrieve all of the matches 
    - `sub` which takes a string and returns a copy of the input where all of the matches have been replaced with said string
- `Pattern` type which represents the compiled regular expression. It provides the same four basic operations (`search`, `match`, `findAll` and `sub`), as well as introduces `findIter` function which returns an instance of `FindIterator` type, the latter allowing for lazy lookup doing one match at a time with its `next` function
- `Match` type which represents the lookup results. This type holds byte offsets into the input string representing matching and captured groups.
- `MatchArray` which is a convenience type to simplify managing dynamically growing list of  `Match` objects received from `findAll`function.
- C-compatible API/ABI declaration and implementation
