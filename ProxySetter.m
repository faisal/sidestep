//
//  ProxySetter.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Modified by Diogo Gomes on 8/8/12.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import "ProxySetter.h"
#import "AppUtilities.h"
#import <SystemConfiguration/SCNetworkConfiguration.h>
#import <SystemConfiguration/SCPreferences.h>
#import <SystemConfiguration/SCDynamicStore.h>

@implementation ProxySetter

- (id) init
{
	self = [super init];
	if (self) {
		auth = NULL;
		rootFlags = kAuthorizationFlagDefaults
			| kAuthorizationFlagExtendRights
			| kAuthorizationFlagInteractionAllowed
			| kAuthorizationFlagPreAuthorize;
	}
	return self;
}

- (BOOL)ensureAuthorization
{
	if (auth != NULL)
		return YES;

	XLog(self, @"Requesting authorization");
	OSStatus authErr = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, rootFlags, &auth);
	if (authErr != noErr) {
		XLog(self, @"Authorization failed: %d", (int)authErr);
		auth = NULL;
		return NO;
	}
	return YES;
}

/*
 * Toggle proxy ON/OFF
 *
 * return true on success
 * return false if an error occurs
 */

- (BOOL)toggleProxy:(BOOL)on interface:(NSString *)interface port:(NSNumber *)port {

	XLog(self, @"toggleProxy %d on interface %@ using port %@", on, interface, port);

	if (![self ensureAuthorization]) {
		return NO;
	}

	// Get System Preferences reference
	SCPreferencesRef prefsRef = SCPreferencesCreateWithAuthorization(NULL, CFSTR("com.faisal.Sidestep"), NULL, auth);
	if (prefsRef == NULL) {
		XLog(self, @"Failed to obtain Preferences Ref");
		return NO;
	}

	BOOL success = NO;

	if (!SCPreferencesLock(prefsRef, TRUE)) {
		XLog(self, @"Failed to obtain PreferencesLock");
		CFRelease(prefsRef);
		return NO;
	}

	SCNetworkSetRef networkSetRef = SCNetworkSetCopyCurrent(prefsRef);
	if (networkSetRef == NULL) {
		XLog(self, @"Failed to get network set");
		SCPreferencesUnlock(prefsRef);
		CFRelease(prefsRef);
		return NO;
	}

	CFArrayRef networkServicesArrayRef = SCNetworkSetCopyServices(networkSetRef);
	SCNetworkServiceRef networkServiceRef = NULL;
	for (CFIndex i = 0; i < CFArrayGetCount(networkServicesArrayRef); i++) {
		SCNetworkServiceRef svc = (SCNetworkServiceRef)CFArrayGetValueAtIndex(networkServicesArrayRef, i);
		if ([(__bridge NSString *)SCNetworkServiceGetName(svc) isEqualToString:interface]) {
			networkServiceRef = svc;
			break;
		}
	}

	if (networkServiceRef == NULL) {
		XLog(self, @"No system interface matching %@", interface);
	} else {
		XLog(self, @"Setting proxy for device %@", (__bridge NSString *)SCNetworkServiceGetName(networkServiceRef));

		SCNetworkProtocolRef proxyProtocolRef = SCNetworkServiceCopyProtocol(networkServiceRef, kSCNetworkProtocolTypeProxies);
		if (proxyProtocolRef == NULL) {
			XLog(self, @"Couldn't acquire copy of proxyProtocol");
		} else {
			NSDictionary *oldPreferences = (__bridge NSDictionary *)SCNetworkProtocolGetConfiguration(proxyProtocolRef);
			NSMutableDictionary *newPreferences = [NSMutableDictionary dictionaryWithDictionary:oldPreferences];

			if (on) {
				[newPreferences setValue:@"localhost" forKey:(__bridge NSString *)kSCPropNetProxiesSOCKSProxy];
				[newPreferences setValue:@1 forKey:(__bridge NSString *)kSCPropNetProxiesSOCKSEnable];
				[newPreferences setValue:@([port integerValue]) forKey:(__bridge NSString *)kSCPropNetProxiesSOCKSPort];
				XLog(self, @"Setting Proxy ON with: %@", newPreferences);
			} else {
				[newPreferences setValue:@0 forKey:(__bridge NSString *)kSCPropNetProxiesSOCKSEnable];
				XLog(self, @"Setting Proxy OFF");
			}

			if (SCNetworkProtocolSetConfiguration(proxyProtocolRef, (__bridge CFDictionaryRef)newPreferences)) {
				if (SCPreferencesCommitChanges(prefsRef)) {
					if (SCPreferencesApplyChanges(prefsRef)) {
						success = YES;
					} else {
						XLog(self, @"Failed to Apply Changes");
					}
				} else {
					XLog(self, @"Failed to Commit Changes");
				}
			} else {
				XLog(self, @"Failed to set Protocol Configuration");
			}

			CFRelease(proxyProtocolRef);
		}
	}

	CFRelease(networkServicesArrayRef);
	CFRelease(networkSetRef);
	SCPreferencesUnlock(prefsRef);
	CFRelease(prefsRef);

	return success;
}

- (BOOL)isProxyEnabled
{
	NSDictionary *proxies = (__bridge_transfer NSDictionary *)SCDynamicStoreCopyProxies(NULL);
	if (!proxies) return NO;

	BOOL enabled = [[proxies objectForKey:(__bridge NSString *)kSCPropNetProxiesSOCKSEnable] boolValue];
	XLog(self, enabled ? @"Proxy is Enabled" : @"Proxy is Disabled");
	return enabled;
}

- (void)dealloc {
	XLog(self, @"dealloc ProxySetter");
	if (auth != NULL) {
		AuthorizationFree(auth, rootFlags);
	}
}

@end
