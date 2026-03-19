//
//  LoginItemController.m
//  Sidestep
//
//  Rewritten to use SMAppService (macOS 13+)
//

#import "LoginItemController.h"

@implementation LoginItemController

+ (BOOL)willStartAtLogin:(NSURL *)itemURL
{
	return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
}

+ (void)setStartAtLogin:(NSURL *)itemURL enabled:(BOOL)enabled
{
	NSError *error = nil;
	if (enabled) {
		[SMAppService.mainAppService registerAndReturnError:&error];
	} else {
		[SMAppService.mainAppService unregisterAndReturnError:&error];
	}
	if (error) {
		NSLog(@"LoginItemController: %@", error);
	}
}

@end
