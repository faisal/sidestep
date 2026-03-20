//
//  AppUtilities.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//


#include "AppUtilities.h"

@implementation AppUtilities

void XLog(id object, NSString *format, ...) {
    va_list argList;
    va_start(argList, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:argList];
    va_end(argList);
    // Log at debug level under the general category with the class name as context.
    // Debug messages are redacted by default in the unified log; use
    // `log stream --subsystem com.faisal.Sidestep --level debug` to see them.
    os_log_debug(SidestepLogGeneral(), "%{public}@ - %{public}@", [object className], message);
}

void XFTimeLog(id object, CFAbsoluteTime *time, NSString *format, ...) {
    va_list argList;
    va_start(argList, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:argList];
    va_end(argList);
    os_log_debug(SidestepLogGeneral(), "%{public}@ - %{public}@", [object className], message);
    if (time) *time = CFAbsoluteTimeGetCurrent();
}

- (BOOL)object:(NSObject *)object existsInArray:(NSArray *)array
{
    return [array containsObject:object];
}

@end
