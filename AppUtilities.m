//
//  AppUtilities.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//


#include "AppUtilities.h"
#import "Configurations.h"

@implementation AppUtilities

void _XLog(CFAbsoluteTime *lastTime, NSString *format, va_list argList)
{
	CFStringRef log = CFStringCreateWithFormatAndArguments(NULL, NULL, (__bridge CFStringRef)format, argList);
	char *ptr = (char *)CFStringGetCStringPtr(log, kCFStringEncodingUTF8);
	if (ptr) 	
		NSLog(@"%s\n", ptr);
	else {
		CFIndex buflen = CFStringGetLength(log) * 4 + 1;
		ptr = malloc((size_t)buflen);
		if (CFStringGetCString(log, ptr, buflen, kCFStringEncodingUTF8));
		NSLog(@"%s\n", ptr);
		free(ptr);
	}
	CFRelease(log);
	
}

void XLog(id object, NSString *format, ...) {
	format = [NSString stringWithFormat:@"%@ - %@", [object className], format];
	if (debuggingEnabled) {
		va_list argList;
		va_start(argList, format);
		_XLog(nil, format, argList);
		va_end(argList);
	}
}

void XFTimeLog(id object, CFAbsoluteTime *time, NSString *format, ...)
{
	format = [NSString stringWithFormat:@"%@ - %@", [object className], format];
	if (debuggingEnabled) {
		va_list argList;
		va_start(argList, format);
		_XLog(time, format, argList);
		va_end(argList);
        
		if (time) *time = CFAbsoluteTimeGetCurrent();
	}
}

- (BOOL)object:(NSObject *)object existsInArray:(NSArray *)array
{
    return [array containsObject:object];
}

@end