//
//  PasswordController.m
//	Sidestep
//
//  Created by Ira Cooke on 27/07/2009. Modified with permission by Chetan Surpur.
//  Copyright 2009 Mudflat Software. 
//

#import "PasswordController.h"

@implementation PasswordController

/*
 *	Prompts the user for a password.
 *
 *	returns: array - {password, error code, save in keychain?}
 */

+ (NSArray *) promptForPassword:(NSString*)hostname user:(NSString*) username {
	NSMutableArray *returnArray = [NSMutableArray arrayWithObjects:@"PasswordString",
								   [NSNumber numberWithInt:0],
								   [NSNumber numberWithBool:TRUE], nil];

	NSString *passwordMessageString = [NSString stringWithFormat:@"Please enter your password for %@@%@.",
									   username, hostname];

	// Build accessory view: secure text field + "Save in Keychain" checkbox
	NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 28, 300, 22)];
	NSButton *saveCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
	[saveCheckbox setButtonType:NSButtonTypeSwitch];
	[saveCheckbox setTitle:@"Save in Keychain"];
	[saveCheckbox setState:NSControlStateValueOn];

	NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 56)];
	[accessoryView addSubview:passwordField];
	[accessoryView addSubview:saveCheckbox];

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleInformational];
	[alert setMessageText:@"Sidestep: Connecting to your secure server..."];
	[alert setInformativeText:passwordMessageString];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setAccessoryView:accessoryView];
	[[alert window] setInitialFirstResponder:passwordField];

	NSModalResponse response = [alert runModal];

	if (response == NSAlertSecondButtonReturn) {
		// User clicked Cancel
		[returnArray replaceObjectAtIndex:1 withObject:[NSNumber numberWithInt:1]];
		return returnArray;
	}

	NSString *password = [passwordField stringValue];
	BOOL saveToKeychain = ([saveCheckbox state] == NSControlStateValueOn);

	[returnArray replaceObjectAtIndex:0 withObject:password];
	[returnArray replaceObjectAtIndex:2 withObject:[NSNumber numberWithBool:saveToKeychain]];

	return returnArray;
}

/*
 *	Looks for the keychain entry corresponding to a username and hostname.
 *
 *	returns: password string if found
 *	returns: nil if password not found or username or hostname is nil
 */

+ (NSString*) passwordForHost:(NSString*)hostname user:(NSString*) username {
	if ( hostname == nil || username == nil ){
		return nil;
	}
	
	// Grab the keychain item
	EMInternetKeychainItem *keychainItem = [EMInternetKeychainItem internetKeychainItemForServer	:hostname
																						withUsername:username
																								path:@""
																								port:0
																							protocol:kSecProtocolTypeSSH];

	if (keychainItem) {
		return [keychainItem password];
	}
	else {
		return nil;
	}
	
}

/*
 *	Sets the password for the keychain entry corresponding to a username and hostname.
 *
 *	If the username/hostname combo already has an entry in the keychain then change it.
 *	If not then add a new entry.
 *
 *	returns: true if success
 *	returns: false if username or hostname is nil
 */

+ (BOOL) setPassword:(NSString*)newPassword forHost:(NSString*)hostname user:(NSString*) username {
	
	if ( hostname == nil || username == nil ){
		return FALSE;
	}
	
	// Grab the keychain item
	EMInternetKeychainItem *keychainItem = [EMInternetKeychainItem internetKeychainItemForServer	:hostname
																						withUsername:username
																								path:@""
																								port:0
																							protocol:kSecProtocolTypeSSH];
	
	if (keychainItem) {
		// Update existing item: delete and re-add with new password
		[keychainItem removeFromKeychain];
	}
	// Add (or re-add) the keychain item
	[EMInternetKeychainItem addInternetKeychainItemForServer:hostname
												withUsername:username
													password:newPassword
														path:@""
														port:0
													protocol:kSecProtocolTypeSSH];
	
	return TRUE;
	
}

/*
 *	Deletes the keychain entry corresponding to a username and hostname.
 *
 *	returns: true if success
 *	returns: false if username or hostname is nil or entry doesn't exist
 */

+ (BOOL) deleteKeychainEntryForHost:(NSString*)hostname user:(NSString*) username {
	
	if ( hostname == nil || username == nil ){
		return FALSE;
	}
	
	// Grab the keychain item
	EMInternetKeychainItem *keychainItem = [EMInternetKeychainItem internetKeychainItemForServer	:hostname
																						withUsername:username
																								path:@""
																								port:0
																							protocol:kSecProtocolTypeSSH];
	
	if (keychainItem) {
		[keychainItem removeFromKeychain];
		
		return TRUE;
	}
	else {
		return FALSE;
	}
	
}

@end
