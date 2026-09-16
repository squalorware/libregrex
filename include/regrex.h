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
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Return codes used within the library */
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
    REGREX_EBADUTF8,         /* Invalid or malformed UTF-8 codepoint */
    REGREX_ETOKEN,           /* Token unexpected in current context */
    REGREX_EEND,             /* Unexpected end of pattern (EOF before construct complete) */
    REGREX_EEXPR,            /* Expected expression */
    REGREX_EBADESC,          /* Malformed escape sequence */
    REGREX_ETRAILESC,        /* Trailing backslash at the pattern end */
    REGREX_EBADREP,          /* Invalid repetition operator */
    REGREX_ERPAREN,          /* Closing parenthesis missing */
    REGREX_ERBRACK,          /* Closing bracket missing */
    REGREX_EINSTERR          /* Instruction unexpected in current context */
};

/* Bits representing flags for compiling the pattern to modify its behaviour. Unset by default */
typedef uint8_t regx_flags_t;

#define REGX_ICASE ((regx_flags_t) 1)                     /* If set: matching ignores case; else: matching is case-sensitive */
#define REGX_NEWLINE ((regx_flags_t) (REGX_ICASE << 1))   /* If set: `^` and `$` mark new line boundaries; else: the whole input */
#define REGX_DOT_ALL ((regx_flags_t) (REGX_NEWLINE << 1)) /* If set: wildcard includes new line chars in matching; else: ignored */

/* Start and end byte offsets of a capture group */
typedef struct
{
    size_t start;
    size_t end;
} regx_span_t;

/* Releases an array of byte offset ranges */
void regx_span_buf_free(regx_span_t *ptr, size_t len);

/* Data structure that holds the match result data */
typedef struct
{
    /* A pointer to an internal Match object */
    void *ptr;
    /* Byte offsets of matches within the input. 
                        `cgroups[0]` always represents the full match.
                        `cgroups[1..]` contains capture groups */
    regx_span_t *cgroups;
    size_t groups_len;
} regx_match_t;

/* Releases the opaque handler wrapping the match object representation */
void regx_match_destroy(regx_match_t *ptr);

/* Releases memory allocated to store a buffer of match objects */
void regx_match_buf_free(regx_match_t **ptr, size_t len);

/* Retrieves a capture group at `cgroups[i]`; */
regx_rcode_t regx_match_span(regx_match_t *match, size_t i, regx_span_t *out_p);

/* Allocates a NULL-terminated buffer, stores in it a substring of input outlined by byte offset at `cgroups[i]` */
regx_rcode_t regx_match_group(regx_match_t *match, size_t i, char **out_buf, size_t *out_len);

/* Allocates a NULL-terminated buffer, stores in it a copy of the full match */
regx_rcode_t regx_match_full(regx_match_t *match, size_t i, char **out_buf, size_t *out_len);

/* Allocates a buffer with capture groups of the match excluding the full match at `cgroups[0]` */
regx_rcode_t regx_match_subgroups(regx_match_t *match, regx_span_t **out_buf, size_t *out_len);

/* Lazy iterator */
typedef struct regx_iter_t regx_iter_t;

void regx_iter_destroy(regx_iter_t *iter);

/* Retrieves the next match and stores it in `out_p` */
regx_rcode_t regx_iter_next(regx_iter_t *iter, regx_match_t *out_p);

/* Represents the compiled regex pattern. Contains the bytecode buffer executed by internal VM.

    Has no public fields and is immutable. Provides a public interface for interaction.

    Can only be created by compiling the string pattern, and discarded using associated destructor */
typedef struct regx_pattern_t regx_pattern_t;

void regx_pattern_destroy(regx_pattern_t *pattern);

/* Retrieves the first match encountered at the beginning of the input */
regx_rcode_t regx_pattern_match(regx_pattern_t *pattern,
                                const char *input, regx_match_t *out_p);

/* Retrieves the first match produced at any position within the input */
regx_rcode_t regx_pattern_search(regx_pattern_t *pattern,
                                const char *input, regx_match_t *out_p);

/* Initializes the lazy iterator */
regx_rcode_t regx_pattern_find_iter(regx_pattern_t *pattern,
                                    const char *input, regx_iter_t **out_p);

/* Allocates a buffer and stores in it all non-overlapping matches */
size_t regx_pattern_find_all(regx_pattern_t *pattern, const char *input,
                        regx_match_t **out_buf, size_t *out_len);

/* Copies the input string, then substitutes all matches with a replacement string 
        Writes result into an allocated NULL-terminated buffer */
regx_rcode_t regx_pattern_sub(regx_pattern_t *pattern, const char *input,  const char *repl,
                        size_t count, char **out_buf, size_t *out_len);

void regrex_str_free(char *ptr, size_t len);

/* Retrieve a human-readable error message from the return code. 
    Returned string is not allocated and does not need to be released  */
const char* regrex_error(regx_rcode_t rcode);

/* Compiles regular expression pattern string 
    Provides a pointer to an opaque type encapsulating the compiled pattern data and exposing a public interface */
regx_rcode_t regrex_compile(const char *pattern, regx_flags_t flags, regx_pattern_t **out_p);

/* One-off lookup for the first match at the beginning of the input */
regx_rcode_t regrex_match(const char *pattern, const char *input,
                        regx_flags_t flags, regx_match_t *out_p);

/* One-off lookup for the first match at any position within the input */
regx_rcode_t regrex_search(const char *pattern, const char *input,
                        regx_flags_t flags, regx_match_t *out_p);

/* One-off lookup for all non-overlapping matches within the input */
regx_rcode_t regrex_find_all(const char *pattern, const char *input,
                        regx_match_t **out_buf, size_t *out_len);

/* One-off substitution of matches in the input with a replacement string.
    Allocates a copy, does not mutate the input */
regx_rcode_t regrex_sub(const char *pattern, const char *input, const char *repl, 
                        regx_flags_t flags, size_t count, char **out_buf, size_t *out_len);

#ifdef __cplusplus
}
#endif
#endif /* REGREX_H */
