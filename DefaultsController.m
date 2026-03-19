//
//  DefaultsController.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import "DefaultsController.h"
#import "AppUtilities.h"

@implementation DefaultsController

/*	
 *	Class methods
 *******************************************************************************
 */

- (id)init {
	
	self = [super init];
	
    if (self != nil)
    {
		defaults = [NSUserDefaults standardUserDefaults];
    }
	
    return self;	
	
}


/*
 *	Data Storage
 *******************************************************************************
 */

- (void)saveSSHConnectionPID:(NSInteger)pid {

	XLog(self, @"Saving PID %ld to user defaults", (long)pid);

	[defaults setInteger:pid forKey:@"sidestep_SSHConnectionPID"];

}

- (NSInteger)getSSHConnectionPID {

	return [defaults integerForKey:@"sidestep_SSHConnectionPID"];

}

- (NSString *)getServerUsername {
	
	return [defaults stringForKey:@"sidestep_ServerUsername"];
	
}

- (NSString *)getServerHostname {
	
	return [defaults stringForKey:@"sidestep_ServerHostname"];
	
}

- (void)setRemotePortNumber :(NSString *)port {
	
	[defaults setObject:port forKey:@"sidestep_RemotePortNumber"];

	
}

- (NSString *)getRemotePortNumber {
	
	return [defaults stringForKey:@"sidestep_RemotePortNumber"];
	
}

- (void)setLocalPortNumber :(NSString *)port {
	
	[defaults setObject:port forKey:@"sidestep_LocalPortNumber"];

	
}

- (NSString *)getLocalPortNumber {
	
	return [defaults stringForKey:@"sidestep_LocalPortNumber"];
	
}

- (void)setAdditionalArguments :(NSString *)args {
	
	[defaults setObject:args forKey:@"sidestep_AdditionalSSHArguments"];

	
}

- (NSString *)getAdditionalArguments {
	
	return [defaults stringForKey:@"sidestep_AdditionalSSHArguments"];
	
}

- (void)setCompressSSHConnection:(BOOL)value {
	
	[defaults setBool:value forKey:@"sidestep_CompressSSHConnection"];

	
}

- (BOOL)getCompressSSHConnection {
	
	return [defaults boolForKey:@"sidestep_CompressSSHConnection"];
	
}


- (void)setGrowlSetting :(BOOL)value {
	
	[defaults setBool:value forKey:@"sidestep_GrowlSetting"];

	
}

- (BOOL)getGrowlSetting {
	
	return [defaults boolForKey:@"sidestep_GrowlSetting"];
	
}

/*
 *	Preferences
 *******************************************************************************
 */

- (void)setRanAtleastOnce :(BOOL)value {

	[defaults setBool:value forKey:@"sidestep_ranAtLeastOnce"];

	
}

- (BOOL)ranAtleastOnce {

	return [defaults boolForKey:@"sidestep_ranAtLeastOnce"];

}

- (void)setRerouteAutomatically :(BOOL)value {

	[defaults setBool:value forKey:@"sidestep_rerouteAutomatically"];

	
}

- (BOOL)rerouteAutomaticallyEnabled {

	return [defaults boolForKey:@"sidestep_rerouteAutomatically"];
	
}

- (void)setRunOnLogin :(BOOL)value {

	[defaults setBool:value forKey:@"sidestep_runOnLogin"];

	
}

- (BOOL)runOnLogin {
	
	return [defaults boolForKey:@"sidestep_runOnLogin"];
	
}

- (void)setSelectedProxy:(NSString *)selection {
	
	[defaults setObject:selection forKey:@"sidestep_selectedProxy"];

	
}

- (NSString *)selectedProxy {
	
	return [defaults stringForKey:@"sidestep_selectedProxy"];
	
}

- (void)setSelectedVPNService:(NSString *)selection {
	
	[defaults setObject:selection forKey:@"sidestep_selectedVPNService"];

	
}

- (NSString *)selectedVPNService {
	
	return [defaults stringForKey:@"sidestep_selectedVPNService"];
	
}

@end
