// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

#include <stdlib.h>
#include "pal_locale_internal.h"
#include "pal_collation.h"

#import <Foundation/Foundation.h>

#if defined(TARGET_OSX) || defined(TARGET_MACCATALYST) || defined(TARGET_IOS) || defined(TARGET_TVOS)

// Enum that corresponds to C# CompareOptions
typedef enum
{
    None = 0,
    IgnoreCase = 1,
    IgnoreNonSpace = 2,
    IgnoreWidth = 16,    
} CompareOptions;

#define CompareOptionsMask 0x1f

static NSStringCompareOptions ConvertFromCompareOptionsToNSStringCompareOptions(int32_t comparisonOptions)
{
    comparisonOptions &= CompareOptionsMask;
    switch(comparisonOptions)
    {
        case None:
            return NSLiteralSearch;
        case IgnoreCase:
            return NSCaseInsensitiveSearch;
        case IgnoreNonSpace:
            return NSDiacriticInsensitiveSearch;
        case (IgnoreNonSpace | IgnoreCase):
            return NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
        case IgnoreWidth:
            return NSWidthInsensitiveSearch;
        case (IgnoreWidth | IgnoreCase):
            return NSWidthInsensitiveSearch | NSCaseInsensitiveSearch;
        case (IgnoreWidth | IgnoreNonSpace):
            return NSWidthInsensitiveSearch | NSDiacriticInsensitiveSearch;
        case (IgnoreWidth | IgnoreNonSpace | IgnoreCase):
            return NSWidthInsensitiveSearch | NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch;
        default:
            return 0;
    }
}

#endif

/*
Function:
CompareString
*/
int32_t GlobalizationNative_CompareStringNative(const char* localeName, int32_t lNameLength, const char* lpStr1, int32_t cwStr1Length, 
                                                const char* lpStr2, int32_t cwStr2Length, int32_t comparisonOptions)
{    
    NSLocale *currentLocale;
    if(localeName == NULL || lNameLength == 0)
    {
        currentLocale = [NSLocale systemLocale];
    }
    else
    {
        NSString *locName = [NSString stringWithCharacters: (const unichar *)localeName length: lNameLength];
        currentLocale = [[NSLocale alloc] initWithLocaleIdentifier:locName];
    }

    NSString *firstString = [NSString stringWithCharacters: (const unichar *)lpStr1 length: cwStr1Length];
    NSString *secondString = [NSString stringWithCharacters: (const unichar *)lpStr2 length: cwStr2Length];
    NSRange string1Range = NSMakeRange(0, cwStr1Length);
    NSStringCompareOptions options = ConvertFromCompareOptionsToNSStringCompareOptions(comparisonOptions);
    
    // in case mapping is not found
    if (options == 0)
        return -2;
        
    return [firstString compare:secondString
                        options:options
                        range:string1Range
                        locale:currentLocale];
}

/*
Function:
IndexOf
*/
int32_t GlobalizationNative_IndexOfNative(
                        const char* localeName,
                        int32_t lNameLen,
                        int32_t cwTargetLength,
                        const char* lpSource,
                        int32_t cwSourceLength,
                        int32_t options,
                        int32_t* pMatchedLength)
{
    assert(cwTargetLength > 0);

    int32_t result = USEARCH_DONE;

    // It's possible somebody passed us (source = <empty>, target = <non-empty>).
    // ICU's usearch_* APIs don't handle empty source inputs properly. However,
    // if this occurs the user really just wanted us to perform an equality check.
    // We can't short-circuit the operation because depending on the collation in
    // use, certain code points may have zero weight, which means that empty
    // strings may compare as equal to non-empty strings.

    if (cwSourceLength == 0)
    {
        result = GlobalizationNative_CompareString(pSortHandle, lpTarget, cwTargetLength, lpSource, cwSourceLength, options);
        if (result == UCOL_EQUAL && pMatchedLength != NULL)
        {
            *pMatchedLength = cwSourceLength;
        }

        return (result == UCOL_EQUAL) ? 0 : -1;
    }

    UErrorCode err = U_ZERO_ERROR;

    UStringSearch* pSearch;
    int32_t searchCacheSlot = GetSearchIterator(pSortHandle, lpTarget, cwTargetLength, lpSource, cwSourceLength, options, &pSearch);
    if (searchCacheSlot < 0)
    {
        return result;
    }

    result = usearch_first(pSearch, &err);

    // if the search was successful,
    // we'll try to get the matched string length.
    if (result != USEARCH_DONE && pMatchedLength != NULL)
    {
        *pMatchedLength = usearch_getMatchedLength(pSearch);
    }

    RestoreSearchHandle(pSortHandle, pSearch, searchCacheSlot);

    return result;
}

/*
Function:
LastIndexOf
*/
int32_t GlobalizationNative_LastIndexOfNative(
                        const char* localeName,
                        int32_t lNameLen,
                        int32_t cwTargetLength,
                        const char* lpSource,
                        int32_t cwSourceLength,
                        int32_t options,
                        int32_t* pMatchedLength)
{
    assert(cwTargetLength > 0);

    int32_t result = USEARCH_DONE;

    // It's possible somebody passed us (source = <empty>, target = <non-empty>).
    // ICU's usearch_* APIs don't handle empty source inputs properly. However,
    // if this occurs the user really just wanted us to perform an equality check.
    // We can't short-circuit the operation because depending on the collation in
    // use, certain code points may have zero weight, which means that empty
    // strings may compare as equal to non-empty strings.

    if (cwSourceLength == 0)
    {
        result = GlobalizationNative_CompareString(pSortHandle, lpTarget, cwTargetLength, lpSource, cwSourceLength, options);
        if (result == UCOL_EQUAL && pMatchedLength != NULL)
        {
            *pMatchedLength = cwSourceLength;
        }

        return (result == UCOL_EQUAL) ? 0 : -1;
    }

    UErrorCode err = U_ZERO_ERROR;
    UStringSearch* pSearch;

    int32_t searchCacheSlot = GetSearchIterator(pSortHandle, lpTarget, cwTargetLength, lpSource, cwSourceLength, options, &pSearch);
    if (searchCacheSlot < 0)
    {
        return result;
    }

    result = usearch_last(pSearch, &err);

    // if the search was successful, we'll try to get the matched string length.
    if (result != USEARCH_DONE)
    {
        int32_t matchLength = -1;

        if (pMatchedLength != NULL)
        {
            matchLength = usearch_getMatchedLength(pSearch);
            *pMatchedLength = matchLength;
        }

        // In case the search result is pointing at the last character (including Surrogate case) of the source string, we need to check if the target string
        // was constructed with characters which have no sort weights. The way we do that is to check that the matched length is 0.
        // We need to update the returned index to have consistent behavior with Ordinal and NLS operations, and satisfy the condition:
        //      index = source.LastIndexOf(value, comparisonType);
        //      originalString.Substring(index).StartsWith(value, comparisonType) == true.
        // https://github.com/dotnet/runtime/issues/13383
        if (result >= cwSourceLength - 2)
        {
            if (pMatchedLength == NULL)
            {
                matchLength = usearch_getMatchedLength(pSearch);
            }

            if (matchLength == 0)
            {
                result = cwSourceLength;
            }
        }
    }

    RestoreSearchHandle(pSortHandle, pSearch, searchCacheSlot);

    return result;
}
