/* 
    regrex.h - Public C ABI declarations for the regrex library.
    regrex is a simple PCRE/Python inspired regular expression engine 
    implemented in the Zig programming language.
    Copyright (C) 2026 oniko94

    This file is part of regrex

    regrex is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    regrex is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
    Lesser General Public License for more details.
*/

#ifndef REGREX_H
#define REGREX_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
    Stable return code type used by the C ABI.
*/
typedef unsigned int regx_errcode_t;
enum {
    REGREX_OK = 0u,              /* Success */
    REGREX_EARG = 1u,            /* Invalid argument */
    REGREX_ENOMATCH = 2u,        /* No matching group */
    REGREX_ENOSPACE = 3u,        /* Memory allocation error */
    REGREX_EBADGRP = 4u,         /* Group index is out of range */
    REGREX_EMAXGRP = 5u,         /* Exceeded maximum group count limit */
    REGREX_EBADUTF8 = 6u,        /* Invalid or malformed UTF-8  */
    REGREX_ETOKEN = 7u,          /* Unexpected Token */
    REGREX_EEND = 7u,            /* Unexpected end of pattern */
    REGREX_EEXPR = 9u,           /* Expected expression */
    REGREX_EBADESC = 10u,        /* Trailing backslash */
    REGREX_EBADREP = 11u,        /* Invalid repetition operator */
    REGREX_ERPAREN = 12u,        /* Closing parenthesis missing */
    REGREX_ERBRACK = 13u,        /* Closing bracket missing */
    REGREX_EINTERNAL = 255u,     /* Generic error (unknown) */
};

/*
    Byte span of a match inside the original input.

    `start` is inclusive. `end` is exclusive. 
    Both values are byte offsets, not UTF-8 scalar indices.
*/
typedef struct 
{
    size_t start;
    size_t end;
} regx_group_t;

/*
    A convenience type to wrap a string as a byte buffer with a known length.

    Can be a borrowed read-only buffer which doesn't own the memory
    or owned (i.e. allocated) in which case it must be released.

    A buffer with `NULL` pointer `ptr` and zero length is an empty buffer.
    A buffer with `NULL` `ptr` and non-zero length is invalid
*/
typedef struct
{
    const unsigned char *ptr;
    size_t len;
} regx_buffer_t;

/*
    Opaque handler for result type produced by matching operations.

    It is allocated on the heap and must be released.
*/
typedef struct regx_match_t regx_match_t;

/*
    Opaque handler for a list of matches.

    It is allocated on the heap and must be released.
*/
typedef struct regx_match_list_t regx_match_list_t;

/*
    Opaque handler for compiled reusable regex pattern.

    It is allocated on the heap and must be released
*/
typedef struct regx_pattern_t regx_pattern_t;

/*
    Opaque handler for a lazy iterator created by the compiled pattern.

    The parent pattern and input buffer must outlive the iterator.

    It is allocated on the heap and must be released
*/
typedef struct regx_iter_t regx_iter_t;

/*
    `regx_match_t` destructor.

    Passing `NULL` is valid and has no effect.
*/
void regx_match_destroy(regx_match_t *match);

/*
    Writes the number of captured groups in match to `out_i`.

    Excludes group 0, which is the full match.
*/
regx_errcode_t regx_match_groups_len(
    const regx_match_t *match,
    size_t *out_i
);

/*
    Write the byte span of group `i` to `out_obj`.

    Group 0 is the full match. Capturing groups start at index 1.
*/
regx_errcode_t regx_match_span(
    const regx_match_t *match,
    size_t i,
    regx_group_t *out_obj
);

/*
    Copies substring of input at byte span `i` 
    to a `out_obj` buffer wrapper.

    The buffer should be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regx_match_group(
    const regx_match_t *match,
    size_t i,
    regx_buffer_t *out_obj
);

/* 
    Copies the full matching string (group 0) 
    to a `out_obj` buffer wrapper.

    The buffer should be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regx_match_full(
    const regx_match_t *match,
    regx_buffer_t *out_obj
);

/*
    `regx_match_list_t` destructor.

    Passing `NULL` is valid and has no effect.
*/
void regx_match_list_destroy(regx_match_list_t *list);

/* Writes the number of matches in list to `out_i`. */
regx_errcode_t regx_match_list_len(
    const regx_match_list_t *list,
    size_t *out_i
);

/*
    Retrieves a byte span of group `group_idx` 
    found in match located at `match_idx` in `list`.

    Group 0 is the full match.
*/
regx_errcode_t regx_match_list_span(
    const regx_match_list_t *list,
    size_t match_idx,
    size_t group_idx,
    regx_group_t *out_obj
);

/* 
    Copies substring of input at byte span `group_idx`
    found in match located at `match_idx` in `list`
    to the `out_obj` buffer wrapper.

    The buffer should be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regx_match_list_group(
    const regx_match_list_t *list,
    size_t match_idx,
    size_t group_idx,
    regx_buffer_t *out_obj
);

/*
    Copies the full matching string (group 0)
    of a match located at `match_idx` in `list`
    to the `out_obj` buffer wrapper.

    The buffer should be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regx_match_list_full(
    const regx_match_list_t *list,
    size_t match_idx,
    regx_buffer_t *out_obj
);

/* 
    `regx_pattern_t` compiled pattern handler's destructor.

    Passing `NULL` is valid and has no effect.
*/
void regx_pattern_destroy(regx_pattern_t *pattern);

/*
    Searches input with the compiled pattern.

    The returned match is stored to the `out_obj` 
    and must be released with `regx_match_destroy()`.

    Returns .REGX_ENOMATCH if no match found; 
    `out_obj` is set to `NULL`
*/
regx_errcode_t regx_pattern_search(
    const regx_pattern_t *pattern,
    regx_buffer_t input_buf,
    regx_match_t **out_obj
);

/*
    Matches input against the compiled pattern 
    starting from the beginning of the input.

    The returned match is stored to the `out_obj` 
    and must be released with `regx_match_destroy()`.

    Returns .REGX_ENOMATCH if no match found; 
    `out_obj` is set to `NULL`
*/
regx_errcode_t regx_pattern_match(
    const regx_pattern_t *pattern,
    regx_buffer_t input_buf,
    regx_match_t **out_obj
);

/*
    Creates a lazy iterator over non-overlapping matches
    from the compiled pattern.

    Stores the iterator to `out_obj`. The iterator must be released
    with `regx_iter_destroy()`. The pattern and the input must outlive it.
*/
regx_errcode_t regx_pattern_find_iter(
    const regx_pattern_t *pattern,
    regx_buffer_t input_buf,
    regx_iter_t **out_obj
);

/*
    Finds all non-overlapping matches for a compiled pattern.

    Stores resulting `regx_match_list_t` to `out_obj`.
    It must be released with `regx_match_list_destroy()`.
*/
regx_errcode_t regx_pattern_find_all(
    const regx_pattern_t *pattern,
    regx_buffer_t input_buf,
    regx_match_list_t **out_obj
);

/*
    Replaces all matches found by the compiled pattern.

    Stores a new string buffer to `out_buf` where matches
    are replaced with `repl_buf`. Does NOT modify the original input. 
    Controls number of replacements with `count` 
    (`count == 0` means replacing all matches).

    Output buffer must be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regx_pattern_sub(
    const regx_pattern_t *pattern,
    regx_buffer_t repl_buf,
    regx_buffer_t input_buf,
    size_t count,
    regx_buffer_t *out_buf
);

/*
    Calls the lazy iterator to produce the next match.

    Stores produced match to `out_obj`. It must be released
    with `regx_match_destroy()`. Returns .REGX_ENOMATCH and sets
    `out_obj` to `NULL` when the iterator is exhausted.
*/
regx_errcode_t regx_iter_next(
    regx_iter_t *iter,
    regx_match_t **out_obj
);

/*
    `regx_iter_t` destructor.

    Passing `NULL` is valid and has no effect.

    Matches already produced by the iterator are not destroyed
    and must be released separately.
*/
void regx_iter_destroy(regx_iter_t *iter);

/*
    Creates a borrowed buffer of the `str`

    Points directly to `str` without allocating, copying or taking ownership.
    Returned length excludes the trailing `\0` byte.

    If `str` is `NULL`, returns an empty buffer.
*/
regx_buffer_t regx_buffer_from_cstr(const unsigned char *str);

#define REGX_BUF(s) regx_buffer_from_cstr((s))

/*
    Releases memory held by an owned buffer.

    Should only be used for `buffer` which was allocated,
    e.g. by `regrex_sub()` or `regx_pattern_sub()`.

    Passing an empty buffer or a buffer with a `NULL` pointer is allowed
    and has no effect.
*/
void regx_buffer_destroy(regx_buffer_t buffer);

/* 
    Maps return code to a static string message.

    The returned pointer has static storage duration and must not be freed.
*/
const char *regrex_error(regx_errcode_t code);

/*
    Compiles a regex pattern.

    Stores the result to `out_obj` as a reusable pattern type
    which does not require to be recompiled for each operation.
    Must be released with `regx_pattern_destroy()`
*/
regx_errcode_t regrex_compile(
    regx_buffer_t pattern_buf,
    regx_pattern_t **out_obj
);

/*
    Compiles the string pattern and searches for the first match.
    Compiled pattern is automatically destroyed at the end of the execution.

    The returned match is stored to the `out_obj` 
    and must be released with `regx_match_destroy()`.

    Returns .REGX_ENOMATCH if no match found; 
    `out_obj` is set to `NULL`
*/
regx_errcode_t regrex_search(
    regx_buffer_t pattern_buf,
    regx_buffer_t input_buf,
    regx_match_t **out_obj
);

/*
    Compiles the string pattern and looks for matches
    at the beginning of the input.
    Compiled pattern is automatically destroyed at the end of the execution.

    The returned match is stored to the `out_obj` 
    and must be released with `regx_match_destroy()`.

    Returns .REGX_ENOMATCH if no match found; 
    `out_obj` is set to `NULL`
*/
regx_errcode_t regrex_match(
    regx_buffer_t pattern_buf,
    regx_buffer_t input_buf,
    regx_match_t **out_obj
);

/*
    Compiles the string pattern and collects all non-overlapping matches.
    Compiled pattern is automatically destroyed at the end of the execution.

    The returned match list is stored to the `out_obj` 
    and must be released with `regx_match_list_destroy()`.

    Returns .REGX_ENOMATCH if no match found; 
    `out_obj` is set to `NULL`
*/
regx_errcode_t regrex_find_all(
    regx_buffer_t pattern_buf,
    regx_buffer_t input_buf,
    regx_match_list_t **out_obj
);

/*
    Compiles the string pattern and replaces all matches.
    Compiled pattern is automatically destroyed at the end of the execution.

    Stores a new string buffer to `out_buf` where matches
    are replaced with `repl_buf`. Does NOT modify the original input. 
    Controls number of replacements with `count` 
    (`count == 0` means replacing all matches).

    Output buffer must be released with `regx_buffer_destroy()`.
*/
regx_errcode_t regrex_sub(
    regx_buffer_t pattern_buf,
    regx_buffer_t repl_buf,
    regx_buffer_t input_buf,
    size_t count,
    regx_buffer_t *out_buf
);

#ifdef __cplusplus
}
#endif

#endif /* REGREX_H */
