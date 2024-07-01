//
//  KSLogger.h
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

#ifndef KSLogger_h

#include <stdio.h>
#define KSLogger_h

#define KSLOG_DEBUG(X...)
#define KSLOG_WARN(X...)
#define KSLOG_TRACE(X...)
#define KSLOG_ERROR(format, ...) \
    fprintf(stderr, "[ERROR] " format "\n", ##__VA_ARGS__)

#endif /* KSLogger_h */
