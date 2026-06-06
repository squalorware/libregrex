/* 
    regrex.h — definitions to ensure compatibility with the POSIX 
    standards and the GNU C Library implementation of regular expressions
    for the regrex library written in the Zig programming language.
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

#include <stdint.h>
#include <stddef.h>

#if __STDC_VERSION__ >= 201112L || __cplusplus >= 201103L
typedef max_align_t REGREX_ALIGN_T;
#else
typedef long double REGREX_ALIGN_T;
#endif

void regrex_compile(void);
void regrex_search(void);
void regrex_match(void);
void regrex_getAllMatches(void);

#ifdef __cplusplus
}
#endif

#endif /* REGREX_H */
