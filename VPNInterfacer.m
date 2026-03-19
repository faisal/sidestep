//
//  VPNInterfacer.m
//  Sidestep
//
//  Created by Chetan Surpur on 12/6/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import "VPNInterfacer.h"
#import "AppUtilities.h"
#import <SystemConfiguration/SystemConfiguration.h>

@implementation VPNInterfacer

/*
 *	Gets a list of VPN services configured in System Settings > Network.
 *	Uses SystemConfiguration framework to enumerate network services and
 *	filter for PPP or IPSec interface types (VPN services).
 *
 *	return: (NSArray *)services — array of VPN service name strings
 */
- (NSArray *)getListOfVPNServices {

	XLog(self, @"Getting list of VPN services");

	SCPreferencesRef prefs = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("com.faisal.Sidestep"), NULL);
	if (!prefs) {
		XLog(self, @"SCPreferencesCreate failed");
		return @[];
	}

	CFArrayRef allServices = SCNetworkServiceCopyAll(prefs);
	if (!allServices) {
		CFRelease(prefs);
		XLog(self, @"SCNetworkServiceCopyAll failed");
		return @[];
	}

	NSMutableArray *vpnServices = [NSMutableArray array];
	CFIndex count = CFArrayGetCount(allServices);

	for (CFIndex i = 0; i < count; i++) {
		SCNetworkServiceRef service = (SCNetworkServiceRef)CFArrayGetValueAtIndex(allServices, i);
		SCNetworkInterfaceRef iface = SCNetworkServiceGetInterface(service);
		if (!iface) continue;

		CFStringRef ifaceType = SCNetworkInterfaceGetInterfaceType(iface);
		if (ifaceType &&
			(CFStringCompare(ifaceType, kSCNetworkInterfaceTypePPP, 0) == kCFCompareEqualTo ||
			 CFStringCompare(ifaceType, kSCNetworkInterfaceTypeIPSec, 0) == kCFCompareEqualTo)) {
			NSString *name = (__bridge NSString *)SCNetworkServiceGetName(service);
			if (name) {
				[vpnServices addObject:name];
				XLog(self, @"Found VPN service: %@", name);
			}
		}
	}

	CFRelease(allServices);
	CFRelease(prefs);

	XLog(self, @"VPN services found: %@", vpnServices);
	return vpnServices;
}

/*
 *	Turns on or off the VPN connection for the service name given.
 *
 *	return: 1 = success
 *	return: 0 = failure (could not create connection or start/stop failed)
 *	return: 2 = no such service
 *	return: 3 = service found was not of type VPN
 */
- (BOOL)turnVPNOnOrOff:(NSString *)serviceName withState:(BOOL)state {

	XLog(self, @"Turning VPN %@ with service name: %@", state ? @"on" : @"off", serviceName);

	SCPreferencesRef prefs = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("com.faisal.Sidestep"), NULL);
	if (!prefs) {
		XLog(self, @"SCPreferencesCreate failed");
		return 0;
	}

	CFArrayRef allServices = SCNetworkServiceCopyAll(prefs);
	if (!allServices) {
		CFRelease(prefs);
		XLog(self, @"SCNetworkServiceCopyAll failed");
		return 0;
	}

	// Find the service by name
	SCNetworkServiceRef targetService = NULL;
	CFIndex count = CFArrayGetCount(allServices);

	for (CFIndex i = 0; i < count; i++) {
		SCNetworkServiceRef service = (SCNetworkServiceRef)CFArrayGetValueAtIndex(allServices, i);
		NSString *name = (__bridge NSString *)SCNetworkServiceGetName(service);
		if ([name isEqualToString:serviceName]) {
			targetService = service;
			break;
		}
	}

	if (!targetService) {
		XLog(self, @"No service found with name: %@", serviceName);
		CFRelease(allServices);
		CFRelease(prefs);
		return 2;
	}

	// Verify it's a VPN-type service
	SCNetworkInterfaceRef iface = SCNetworkServiceGetInterface(targetService);
	CFStringRef ifaceType = iface ? SCNetworkInterfaceGetInterfaceType(iface) : NULL;

	if (!ifaceType ||
		(CFStringCompare(ifaceType, kSCNetworkInterfaceTypePPP, 0) != kCFCompareEqualTo &&
		 CFStringCompare(ifaceType, kSCNetworkInterfaceTypeIPSec, 0) != kCFCompareEqualTo)) {
		XLog(self, @"Service '%@' is not a VPN type", serviceName);
		CFRelease(allServices);
		CFRelease(prefs);
		return 3;
	}

	// Get the service ID and create a connection
	CFStringRef serviceID = SCNetworkServiceGetServiceID(targetService);
	SCNetworkConnectionRef connection = SCNetworkConnectionCreateWithServiceID(
		kCFAllocatorDefault, serviceID, NULL, NULL);

	if (!connection) {
		XLog(self, @"SCNetworkConnectionCreateWithServiceID failed for service: %@", serviceName);
		CFRelease(allServices);
		CFRelease(prefs);
		return 0;
	}

	BOOL result;
	if (state) {
		result = SCNetworkConnectionStart(connection, NULL, TRUE);
		XLog(self, @"SCNetworkConnectionStart result: %d", result);
	} else {
		result = SCNetworkConnectionStop(connection, TRUE);
		XLog(self, @"SCNetworkConnectionStop result: %d", result);
	}

	CFRelease(connection);
	CFRelease(allServices);
	CFRelease(prefs);

	return result ? 1 : 0;
}

@end
