//
//  LoginItemController.h
//  Sidestep
//
//  Rewritten to use SMAppService (macOS 13+)
//

#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>

@interface LoginItemController : NSObject

+ (BOOL)willStartAtLogin:(NSURL *)itemURL;
+ (void)setStartAtLogin:(NSURL *)itemURL enabled:(BOOL)enabled;

@end
