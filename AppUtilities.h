//
//  AppUtilities.h
//  Sidestep
//
//  Created by Chetan Surpur on 10/28/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SidestepLog.h"

@interface AppUtilities : NSObject
{
}
extern void XLog(id object, NSString *format, ...) NS_FORMAT_FUNCTION(2,3);
extern void XFTimeLog(id object, CFAbsoluteTime *time, NSString *format, ...) NS_FORMAT_FUNCTION(3,4);

// Loops thorugh an array checking if given object's value already
// exists in the given array.  If it does, returns true.
- (BOOL)object:(NSObject *)object existsInArray:(NSArray *)array;

@end