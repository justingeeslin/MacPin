/*
 * https://github.com/WebKit/webkit/blob/master/Source/WebKit/Shared/API/c/WKDictionary.h
 *
 * Copyright (C) 2010 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef WKDictionary_h
#define WKDictionary_h

#include <WebKitPrivates/WKBase.h>

#ifndef __cplusplus
#include <stddef.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

WK_EXPORT WKTypeID WKDictionaryGetTypeID(void);

WK_EXPORT WKDictionaryRef WKDictionaryCreate(const WKStringRef* keys, const WKTypeRef* values, size_t numberOfValues);

WK_EXPORT WKTypeRef WKDictionaryGetItemForKey(WKDictionaryRef dictionary, WKStringRef key);
WK_EXPORT size_t WKDictionaryGetSize(WKDictionaryRef dictionary);

WK_EXPORT WKArrayRef WKDictionaryCopyKeys(WKDictionaryRef dictionary);

#ifdef __cplusplus
}
#endif

#endif /* WKDictionary_h */