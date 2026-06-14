# regrex

> A programmable regret - inevitable. Inexorable. The Crime and the Punishment.

## What is this?

**regrex** = Regret + RegEx

![REGRET](assets/readme.jpg)

An amateurish implementation of regular expressions in Zig. It implements a small PCRE/Python-inspired grammar using a traditional compiler-style pipeline: 
1. Lexical analysis and tokenization (Lexer)
2. Parsing tokens into an abstract syntax tree
3. Compiling AST nodes to an intermediate code representation (bytecode)
4. Executing bytecode instructions by a backtracking virtual machine.

Currently available features:
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
- Compiled reusable Pattern objects;
- search, match, and findall style APIs.

**Nota bene**: this project does not aim to be a proper PCRE-like implementation of regular expressions - treat it as a learning project or a proof of concept at best. Advanced features such as lookarounds, backreferences, lazy quantifiers, counted repetitions, Unicode properties like `\p{L}`, and full regex flag handling are well outside of scope of this project for foreseeable future.

## Usage

## Building

Minimal required version for a successful build is 0.16.0

### Testing

Run `zig build test --summary all --verbose`
