//
//  NSException+cxxHandler.mm
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#include "NSException+cxxHandler.h"
#include "KSCrash/KSCxaThrowSwapper.h"

#include <cxxabi.h>

#define DESCRIPTION_BUFFER_LENGTH 1024

#define CATCH_VALUE(TYPE, PRINTFTYPE) \
catch(TYPE value)\
{ \
    snprintf(descriptionBuff, sizeof(descriptionBuff), "%" #PRINTFTYPE, value); \
}

#define CALL_STACK_SYMBOLS_KEY @"callStackSymbols"
#define RESERVED_KEY @"reserved"

static void captureStackTrace(void* exc, std::type_info* tinfo, void (*dest)(void*)) __attribute__((disable_tail_calls))
{
    if (tinfo && strcmp(tinfo->name(), "NSException") == 0) {
        [[[NSThread currentThread] threadDictionary] removeObjectForKey:CALL_STACK_SYMBOLS_KEY];
        return;
    }
    // collect call stack symbols and store to the thread dictionary
    [[[NSThread currentThread] threadDictionary] setObject:[NSThread callStackSymbols] forKey:CALL_STACK_SYMBOLS_KEY];

    __asm__ __volatile__(""); // thwart tail-call optimization
}


extern "C" void kscm_enableSwapCxaThrow(void) {
    static bool cxaSwapEnabled = false;
    if (cxaSwapEnabled != true) {
        ksct_swap(captureStackTrace);
        cxaSwapEnabled = true;
    }
}

// set `std::terminate` handler, returns original handler
extern "C" terminate_handler SetCxxExceptionTerminateHandler(terminate_handler handler) {
    return std::set_terminate(handler);
}

@implementation NSException (CPPException)

// get C++ exception currently handled in the `std::terminate` handler
+ (NSException * _Nullable)currentCxxException {
    const char* name = nil;
    std::type_info* tinfo = __cxxabiv1::__cxa_current_exception_type();
    if (tinfo) {
        name = tinfo->name();
    }
    
    // NSException is handled by NSUncaughtExceptionHandler
    if (name && strcmp(name, "NSException") == 0) {
        return nil;
    }

    char descriptionBuff[DESCRIPTION_BUFFER_LENGTH];
    const char* description = descriptionBuff;
    descriptionBuff[0] = 0;

    try {
        throw;
    } catch(std::exception& exc) {
        strncpy(descriptionBuff, exc.what(), sizeof(descriptionBuff));
    }
    CATCH_VALUE(char,                 d)
    CATCH_VALUE(short,                d)
    CATCH_VALUE(int,                  d)
    CATCH_VALUE(long,                ld)
    CATCH_VALUE(long long,          lld)
    CATCH_VALUE(unsigned char,        u)
    CATCH_VALUE(unsigned short,       u)
    CATCH_VALUE(unsigned int,         u)
    CATCH_VALUE(unsigned long,       lu)
    CATCH_VALUE(unsigned long long, llu)
    CATCH_VALUE(float,                f)
    CATCH_VALUE(double,               f)
    CATCH_VALUE(long double,         Lf)
    CATCH_VALUE(char*,                s)
    catch(...) {
        description = nil;
    }

    // create NSException with C++ exception name and description
    NSException *exception = [[NSException alloc] initWithName:[NSString stringWithCString:name encoding:NSUTF8StringEncoding]
                                                        reason:description != nil ? [NSString stringWithCString:description encoding:NSUTF8StringEncoding] : nil
                                                      userInfo:nil];

    id callStackSymbols = [[[NSThread currentThread] threadDictionary] objectForKey:CALL_STACK_SYMBOLS_KEY];
    if (callStackSymbols) {
        NSMutableDictionary *reserved = [exception valueForKey:RESERVED_KEY];
        if (!reserved) {
            reserved = [NSMutableDictionary dictionary];
            [exception setValue:reserved forKey:RESERVED_KEY];
        }
        [reserved setValue:callStackSymbols forKey:CALL_STACK_SYMBOLS_KEY];
    }

    return exception;
}

// prevent crashes if `NSException` has no `reserved` field
- (id)valueForUndefinedKey:(NSString *)key {}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}

@end
