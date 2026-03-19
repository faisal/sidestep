//
//  GrowlMessage.m
//  Sidestep
//
//  Created by Steve Warren on 11/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "GrowlMessage.h"

@implementation GrowlMessage {
	NSUserDefaults *setting;
}

- (instancetype)init {
	self = [super init];
	if (self != nil) {
		setting = [NSUserDefaults standardUserDefaults];
		UNUserNotificationCenter.currentNotificationCenter.delegate = self;
	}
	return self;
}

- (void)requestAuthorization {
	UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
	[UNUserNotificationCenter.currentNotificationCenter
		requestAuthorizationWithOptions:options
		completionHandler:^(BOOL granted, NSError *error) {
			if (error) {
				NSLog(@"UserNotifications authorization error: %@", error);
			}
		}];
}

- (void)message:(NSString *)sendMessage {
	if (![setting boolForKey:@"sidestep_GrowlSetting"])
		return;

	UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
	content.title = @"Sidestep";
	content.body = sendMessage;
	content.sound = UNNotificationSound.defaultSound;

	NSString *identifier = [NSString stringWithFormat:@"sidestep-%@", [[NSUUID UUID] UUIDString]];
	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
																		  content:content
																		  trigger:nil];
	[UNUserNotificationCenter.currentNotificationCenter
		addNotificationRequest:request
		withCompletionHandler:^(NSError *error) {
			if (error) {
				NSLog(@"UserNotifications error: %@", error);
			}
		}];
}

// Show banner even when app is in the foreground
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
	   willPresentNotification:(UNNotification *)notification
		 withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
	completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

@end
