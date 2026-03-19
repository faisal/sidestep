//
//  NetworkNotifier.m
//  Sidestep
//
//	From NetworkNotifier.m
//  HardwareGrowler
//
//  Created by Ingmar Stein on 18.02.05. Modified by Chetan Surpur on 11/19/10.
//  Copyright 2005 The Growl Project. All rights reserved.
//  Copyright (C) 2004 Scott Lamb <slamb@slamb.org>
//

#import <Cocoa/Cocoa.h>
#import <CoreWLAN/CoreWLAN.h>

#import "NetworkNotifier.h"
#import "AppController.h"
#import "AppUtilities.h"

@implementation NetworkNotifier {
	id airportConnectionNotifyObject;
	SEL airportConnectionNotifySelector;
	CWWiFiClient *wifiClient;
}

- (instancetype)init {
	if (!(self = [super init])) return nil;

	airportConnectionNotifyObject = nil;
	airportConnectionNotifySelector = nil;

	wifiClient = [CWWiFiClient sharedWiFiClient];
	wifiClient.delegate = self;

	NSError *error = nil;
	if (![wifiClient startMonitoringEventWithType:CWEventTypeLinkDidChange error:&error]) {
		NSLog(@"Failed to monitor CWEventTypeLinkDidChange: %@", error);
	}
	if (![wifiClient startMonitoringEventWithType:CWEventTypeSSIDDidChange error:&error]) {
		NSLog(@"Failed to monitor CWEventTypeSSIDDidChange: %@", error);
	}

	return self;
}

- (void)listenForAirportConnectionAndNotifyObject:(id)object withSelector:(SEL)selector {
	airportConnectionNotifyObject = object;
	airportConnectionNotifySelector = selector;
}

#pragma mark - CWEventDelegate

- (void)linkDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName {
	if (airportConnectionNotifyObject && airportConnectionNotifySelector) {
		[airportConnectionNotifyObject performSelector:airportConnectionNotifySelector];
	}
}

- (void)ssidDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName {
	if (airportConnectionNotifyObject && airportConnectionNotifySelector) {
		[airportConnectionNotifyObject performSelector:airportConnectionNotifySelector];
	}
}

#pragma mark - Security Type Detection

+ (NSString *)securityTypeStringForCWSecurity:(CWSecurity)security {
	switch (security) {
		case kCWSecurityNone:
			return @"none";
		case kCWSecurityWEP:
			return @"wep";
		case kCWSecurityWPAPersonal:
		case kCWSecurityWPAEnterprise:
			return @"wpa";
		case kCWSecurityWPA2Personal:
		case kCWSecurityWPA2Enterprise:
			return @"wpa2";
		case kCWSecurityWPA3Personal:
		case kCWSecurityWPA3Enterprise:
		case kCWSecurityWPA3Transition:
			return @"wpa3";
		default:
			return @"unknown";
	}
}

- (BOOL)getNetworkSecurityTypeAndNotifyObject:(id)object withSelector:(SEL)selector {

	XLog(self, @"Getting network security type");

	CWInterface *iface = wifiClient.interface;
	if (!iface) {
		XLog(self, @"No Wi-Fi interface found");
		[object performSelector:selector withObject:@"unknown"];
		return YES;
	}

	CWSecurity security = iface.security;
	NSString *securityString = [NetworkNotifier securityTypeStringForCWSecurity:security];

	XLog(self, @"Network security type: %@", securityString);

	[object performSelector:selector withObject:securityString];

	return YES;
}

- (void)dealloc {
	[wifiClient stopMonitoringAllEventsAndReturnError:nil];
}

@end
