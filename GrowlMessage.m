//
//  GrowlMessage.m
//  Sidestep
//
//  Created by Steve Warren on 11/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "GrowlMessage.h"

@implementation GrowlMessage

- (instancetype)init {
	self = [super init];
	if (self != nil) {
		setting = [NSUserDefaults standardUserDefaults];
	}
	return self;
}

- (void) message:(NSString *)sendMessage {
	if ([setting boolForKey:@"sidestep_GrowlSetting"]) {
		NSLog(@"Sidestep notification: %@", sendMessage);
	}
}

@end
