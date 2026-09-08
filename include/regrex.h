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
#define REGREX_H 1

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
    Stable return code type used by the C ABI.
*/
typedef int8_t regx_rcode_t;
enum
{
    ENOSYS = -1,             /* Shouldn't ever return; invalid syscall or not implemented */
    OK = 0,                  /* Success */
    ERR = 1,                 /* Non-specific generic error */
    REGREX_EARG,             /* Invalid argument */
    REGREX_ENOMATCH,         /* No matching group */
    REGREX_EMALLOC,          /* Memory allocation error */
    REGREX_ERANGE,           /* Index is out of range */
    REGREX_EMAXGRP,          /* Exceeded maximum group count limit */
    REGREX_EBADUTF8,         /* Invalid or malformed UTF-8  */
    REGREX_ETOKEN,           /* Unexpected Token */
    REGREX_EEND,             /* Unexpected end of pattern */
    REGREX_EEXPR,            /* Expected expression */
    REGREX_EBADESC,          /* Malformed escape sequence */
    REGREX_ETRAILESC,        /* Trailing backslash */
    REGREX_EBADREP,          /* Invalid repetition operator */
    REGREX_ERPAREN,          /* Closing parenthesis missing */
    REGREX_ERBRACK,          /* Closing bracket missing */
    REGREX_EINSTERR          /* Unexpected bytecode instruction */
};

/*
    Start and end indices of a capture group inside the input string

    `start` is inclusive. `end` is exclusive.
    Both values are byte offsets, not UTF-8 scalar indices.
*/
typedef struct
{
    size_t start;
    size_t end;
} regx_span_t;
/*
    Opaque handler for result type produced by matching operations.

    It is allocated on the heap and must be released.
*/
typedef struct regx_match_t regx_match_t;

void regx_match_destroy(regx_match_t* match);

/* */
regx_rcode_t regx_match_span(const regx_match_t* match, size_t i, regx_span_t* out_obj);
/* Allocates and returns a NULL-terminated copy of capture group i in out_str */
regx_rcode_t regx_match_group(const regx_match_t* match, size_t i, char** out_str);
/* Allocates and returns a NULL-terminated copy of the full match in out_str */
regx_rcode_t regx_match_full(const regx_match_t* match, size_t i, char** out);
/* Copies all capture groups (byte offsets) except the first one into a buffer */
regx_rcode_t regx_match_subgroups(const regx_match_t* match, regx_span_t** out_arr, size_t out_size);

/*
    Opaque handler for a lazy iterator created by the compiled pattern.

    The parent pattern and input buffer must outlive the iterator.

    It is allocated on the heap and must be released
*/
typedef struct regx_iter_t regx_iter_t;

void regx_iter_destroy(regx_iter_t* iter);

/* Get the next match and store it in `out_obj` or get .REGREX_ENOMATCH */
regx_rcode_t regx_iter_next(regx_iter_t* iter, regx_match_t** out_obj);

/*
    Opaque handler for compiled reusable regex pattern.

    It is allocated on the heap and must be released
*/
typedef struct regx_pattern_t regx_pattern_t;

void regx_pattern_destroy(regx_pattern_t* pattern);

/* */
regx_rcode_t regx_pattern_match(const regx_pattern_t* pattern,
                                const char* input, regx_match_t** out_obj);
/* */
regx_rcode_t regx_pattern_search(const regx_pattern_t* pattern,
                                const char* input, regx_match_t** out_obj);
/* Initializes the lazy iterator */
regx_rcode_t regx_pattern_find_iter(const regx_pattern_t* pattern,
                                    const char* input, regx_iter_t** out_obj);
/* Allocates an array of match types and stores all non-overlapping matches into it */
regx_rcode_t regx_pattern_find_all(const regx_pattern_t* pattern,
                                const char* input, regx_match_t*** out_arr, size_t* out_size);
/* */
regx_rcode_t regx_pattern_sub(const regx_pattern_t* pattern,
                            const char* input, const char* repl,
                            size_t count, char** out_str);

/*
    Regular expression compile flags to modify pattern behaviour
*/
typedef uint8_t regx_flags_t;

#define REGX_IGNORE_CASE ((regx_flags_t)(1u << 0))
#define REGX_MULTILINE ((regx_flags_t)(1u << 1))
#define REGX_DOT_ALL ((regx_flags_t)(1u << 2))

/*
 Takes a return code and returns a static string with error message

 Doesn't need to be freed
*/
const char* regrex_error(regx_rcode_t rcode);

regx_rcode_t regrex_compile(const char* pattern, regx_flags_t flags, regx_pattern_t** out_obj);

regx_rcode_t regrex_match(const char* pattern, const char* input,
                        regx_flags_t flags, regx_match_t** out_obj);

regx_rcode_t regrex_search(const char* pattern, const char* input,
                        regx_flags_t flags, regx_match_t** out_obj);

regx_rcode_t regrex_find_all(const char* pattern, const char* input,
                        regx_match_t*** out_arr, size_t* out_size);

regx_rcode_t regrex_sub(const char* pattern, const char* input,
                        const char* repl, regx_flags_t flags, size_t count, char** out_str);

#ifdef __cplusplus
}
#endif
#endif /* REGREX_H */
