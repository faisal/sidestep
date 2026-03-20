//
//  SidestepAppDelegate.h
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Sparkle/SPUStandardUpdaterController.h>
#import <Sparkle/SPUUpdater.h>
#import "SSHConnector.h"
#import "DefaultsController.h"
#import "LoginItemController.h"
#import "NetworkNotifier.h"
#import "ProxySetter.h"
#import "VPNInterfacer.h"
#import "PasswordController.h"
#import "AppUtilities.h"
#import <UserNotifications/UserNotifications.h>

@interface AppController : NSObject <NSTextFieldDelegate, UNUserNotificationCenterDelegate>

// Top-level nib objects (strong — not retained by a parent view)
@property (strong, nonatomic) IBOutlet NSMenu *statusMenu;
@property (strong, nonatomic) IBOutlet NSWindow *preferencesWindow;
@property (strong, nonatomic) IBOutlet NSWindow *welcomeWindow;

// Tab views (weak — retained by their parent window)
@property (weak, nonatomic) IBOutlet NSTabView *proxyTabs;
@property (weak, nonatomic) IBOutlet NSTabView *welcomeTabs;

// Menu items (weak — retained by their parent menu)
@property (weak, nonatomic) IBOutlet NSMenuItem *proxyServerStatus;
@property (weak, nonatomic) IBOutlet NSMenuItem *connectionStatus;
@property (weak, nonatomic) IBOutlet NSMenuItem *rerouteOrRestoreConnectionButton;
@property (weak, nonatomic) IBOutlet NSMenuItem *statusMenuFirstSeparator;
@property (weak, nonatomic) IBOutlet NSMenuItem *connectVPNServiceButton;
@property (weak, nonatomic) IBOutlet NSMenuItem *disconnectVPNServiceButton;

// Preference controls (weak — retained by their parent view)
@property (weak, nonatomic) IBOutlet NSTextField *testConnectionStatusFieldInPreferences;
@property (weak, nonatomic) IBOutlet NSTextField *testConnectionStatusFieldInWelcome;
@property (weak, nonatomic) IBOutlet NSPopUpButton *availableVPNServices;
@property (weak, nonatomic) IBOutlet NSTextField *sshCommandDisplayField;

- (void)openSSHConnectionAfterDelay:(int)delay;
- (void)testSSHConnection;
- (void)closeSSHConnection;
- (void)openVPNConnectionAfterDelay:(int)delay;
- (void)closeVPNConnection;
- (void)setRunOnLogin:(BOOL)value;

- (void)showAuthorizationErrorSidestepDialog;
- (void)showRestartSidestepDialog;

- (void)updateUIForVPNServiceList;
- (void)updateUIForSelectedProxy;

- (void)preferencesClicked:(id)sender;
- (void)aboutClicked:(id)sender;
- (void)rerouteOrRestoreConnectionClicked:(id)sender;
- (void)testSSHConnectionClickedFromPreferences:(id)sender;
- (void)testSSHConnectionClickedFromWelcome:(id)sender;
- (void)helpWithProxyClicked:(id)sender;
- (void)nextClickedInWelcome:(id)sender;
- (void)finishClickedInWelcome:(id)sender;
- (void)toggleRunOnLoginClicked:(id)sender;
- (void)selectProxyClicked:(id)sender;
- (void)connectProxyClicked:(id)sender;
- (void)disconnectProxyClicked:(id)sender;

- (IBAction)compressionToggled:(id)sender;
- (NSString *)sshCommand;

@end
