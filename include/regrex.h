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

typedef struct {
    size_t start;
    size_t end;
} regx_group_t;

typedef struct regx_match_t regx_match_t;
typedef struct regx_match_list_t regx_match_list_t;
typedef struct regx_pattern_t regx_pattern_t;
typedef struct regx_iter_t regx_iter_t;

void regx_match_destroy(regx_match_t *match);

regx_errcode_t regx_match_groups_len(
    const regx_match_t *match,
    size_t *out_i
);

regx_errcode_t regx_match_span(
    const regx_match_t *match,
    size_t i,
    regx_group_t *out_obj
);

regx_errcode_t regx_match_group(
    const regx_match_t *match,
    size_t i,
    const char **out_ptr
);

void regx_match_list_destroy(regx_match_list_t *list);

regx_errcode_t regx_match_list_span(
    const regx_match_list_t *list,
    size_t match_idx,
    size_t group_idx,
    regx_group_t *out_obj
);

regx_errcode_t regx_match_list_group(
    const regx_match_list_t *list,
    size_t match_idx,
    size_t group_idx,
    const char **out_ptr
);

void regx_pattern_destroy(regx_pattern_t *pattern);

regx_errcode_t regx_pattern_search(
    const regx_pattern_t *pattern,
    const char *input_ptr,
    size_t input_len,
    regx_match_t **out_obj
);

regx_errcode_t regx_pattern_match(
    const regx_pattern_t *pattern,
    const char *input_ptr,
    size_t input_len,
    regx_match_t **out_obj
);

regx_errcode_t regx_pattern_find_iter(
    const regx_pattern_t *pattern,
    const char *input_ptr,
    size_t input_len,
    regx_iter_t **out_obj
);

regx_errcode_t regx_pattern_find_all(
    const regx_pattern_t *pattern,
    const char *input_ptr,
    size_t input_len,
    regx_match_list_t **out_obj
);

regx_errcode_t regx_pattern_sub(
    const regx_pattern_t *pattern,
    const char *repl_ptr,
    size_t repl_len,
    const char *input_ptr,
    size_t input_len,
    size_t count,
    unsigned char **out_ptr,
    size_t *out_len
);

regx_errcode_t regx_iter_next(
    regx_iter_t *iter,
    regx_match_t **out_obj
);

void regx_iter_destroy(regx_iter_t *iter);

void regx_str_destroy(const char *ptr);

void regx_buf_destroy(unsigned char *ptr, size_t len);

/* Maps return code to a string message */
const char *regrex_error(regx_errcode_t code);

regx_errcode_t regrex_compile(
    const char *pattern_ptr, 
    size_t pattern_len, 
    regx_pattern_t **out_obj
);

regx_errcode_t regrex_search(
    const char *pattern_ptr,
    size_t pattern_len,
    const char *input_ptr,
    size_t input_len,
    regx_match_t **out_obj
);

regx_errcode_t regrex_match(
    const char *pattern_ptr,
    size_t pattern_len,
    const char *input_ptr,
    size_t input_len,
    regx_match_t **out_obj
);

regx_errcode_t regrex_find_all(
    const char *pattern_ptr,
    size_t pattern_len,
    const char *input_ptr,
    size_t input_len,
    regx_match_list_t **out_obj
);

regx_errcode_t regrex_sub(
    const char *pattern_ptr,
    size_t pattern_len,
    const char *repl_ptr,
    size_t repl_len,
    const char *input_ptr,
    size_t input_len,
    size_t count,
    unsigned char **out_ptr,
    size_t *out_len
);

#ifdef __cplusplus
}
#endif

#endif /* REGREX_H */
