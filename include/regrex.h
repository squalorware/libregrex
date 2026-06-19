/* 
    regrex.h - Public C ABI declarations for the regrex library.
    regrex is a simple regular expression engine 
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

typedef enum {
    REGREX_OK = 0, 
    REGREX_ENOMATCH,        /* No matching group */
    REGREX_ENOSPACE,        /* Memory allocation error */
    REGREX_EBADGRP,         /* Group index is out of range */
    REGREX_EBADUTF8,        /* Invalid or malformed UTF-8  */
    REGREX_ETOKEN,          /* "Unexpected Token */
    REGREX_EEND,            /* Unexpected end of pattern */
    REGREX_EEXPR,           /* Expected expression */
    REGREX_EBADESC,         /* Trailing backslash */
    REGREX_EBADREP,         /* Invalid repetition operator */
    REGREX_ERPAREN,         /* Closing parenthesis missing */
    REGREX_ERBRACK,         /* Closing bracket missing */
    REGREX_EINTERNAL = 255, /* Generic error (unknown) */
} regrex_errcode_t;

#define REGX_OK REGREX_OK
#define REGX_ENOMATCH REGREX_ENOMATCH
#define REGX_ENOSPACE REGREX_ENOSPACE
#define REGX_EBADGRP REGREX_EBADGRP
#define REGX_EBADUTF8 REGREX_EBADUTF8
#define REGX_ETOKEN REGREX_ETOKEN
#define REGX_EEND REGREX_EEND
#define REGX_EEXPR REGREX_EEXPR
#define REGX_EBADESC REGREX_EBADESC
#define REGX_EBADREP REGREX_EBADREP
#define REGX_ERPAREN REGREX_ERPAREN
#define REGX_ERBRACK REGREX_ERBRACK
#define REGX_EINTERNAL REGREX_EINTERNAL

/*
    Maps status code to a string message
*/
const char *regrex_error(regrex_errcode_t code);

#ifdef __cplusplus
}
#endif

#endif /* REGREX_H */
