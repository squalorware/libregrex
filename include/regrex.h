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

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>

typedef enum : unsigned int 
{
    REGREX_OK = 0, 
    REGREX_EARG,            /* Invalid argument */
    REGREX_ENOMATCH,        /* No matching group */
    REGREX_ENOSPACE,        /* Memory allocation error */
    REGREX_EBADGRP,         /* Group index is out of range */
    REGREX_EBADUTF8,        /* Invalid or malformed UTF-8  */
    REGREX_ETOKEN,          /* Unexpected Token */
    REGREX_EEND,            /* Unexpected end of pattern */
    REGREX_EEXPR,           /* Expected expression */
    REGREX_EBADESC,         /* Trailing backslash */
    REGREX_EBADREP,         /* Invalid repetition operator */
    REGREX_ERPAREN,         /* Closing parenthesis missing */
    REGREX_ERBRACK,         /* Closing bracket missing */
    REGREX_EINTERNAL = 255, /* Generic error (unknown) */
} regx_errcode_t;

/* Maps status code to a string message */
const char *regrex_error(regx_errcode_t code);

typedef struct {
    size_t start;
    size_t end;
} regx_group_t;

typedef struct regx_match_t regx_match_t;

typedef struct regx_match_list_t regx_match_list_t;

typedef struct regx_pattern_t regx_pattern_t;
void regx_pattern_destroy(regx_pattern_t *pattern);

regx_errcode_t regrex_compile(char *pattern_str, size_t pattern_len, regx_pattern_t *out_obj );

#ifdef __cplusplus
}
#endif

#endif /* REGREX_H */
