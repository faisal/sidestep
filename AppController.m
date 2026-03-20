//
//  AppController.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import "AppController.h"

@interface AppController () {
    NSStatusItem *statusItem;
    NSImage *statusImageDirectInsecure;
    NSImage *statusImageDirectSecure;
    NSImage *statusImageReroutedSecure;

    SSHConnector *SSHconnector;
    DefaultsController *defaultsController;
    NetworkNotifier *networkNotifier;
    ProxySetter *proxySetter;
    VPNInterfacer *vpnInterfacer;

    SPUStandardUpdaterController *updaterController;

    BOOL initiatedDelayedConnectionAttempt;
    int retryCounter;
    BOOL testingConnection;
    NSTextField *testConnectionStatusField;

    NSTask *SSHConnection;
    BOOL SSHConnecting;
    BOOL SSHConnected;
    BOOL VPNConnected;

    BOOL wasSSHConnectedBeforeSleep;
    BOOL wasVPNConnectedBeforeSleep;

    NSString *currentNetworkSecurityType;
}
@end

@implementation AppController

// Synthesize with matching ivar names so existing code can access without self.
@synthesize statusMenu, preferencesWindow, welcomeWindow;
@synthesize proxyTabs, welcomeTabs;
@synthesize proxyServerStatus, connectionStatus;
@synthesize rerouteOrRestoreConnectionButton, statusMenuFirstSeparator;
@synthesize connectVPNServiceButton, disconnectVPNServiceButton;
@synthesize testConnectionStatusFieldInPreferences, testConnectionStatusFieldInWelcome;
@synthesize availableVPNServices, sshCommandDisplayField;

/*
 *	Constants
 *******************************************************************************
 */

NSString *noNetworkConnectionStatusText            = @"No wireless connection";
NSString *determiningConnectionStatusText          = @"Determining connection status...";
NSString *connectingConnectionStatusText           = @"Connecting...";
NSString *retryingConnectionStatusText             = @"Reconnecting...";
NSString *proxyConnectedConnectionStatusText       = @"Secure connection";
NSString *protectedConnectionStatusText            = @"Secure network";
NSString *openConnectionStatusText                 = @"Unsecure network";

NSString *notConnectedServerStatusText             = @"Not connected";
NSString *authorizationErrorServerStatusText       = @"Failed connecting - authorization failure";
NSString *connectionErrorServerStatusText          = @"Failed connecting - network failure";
NSString *connectedServerStatusText                = @"Connected to SSH";

NSString *connectedVPNText                         = @"Connected to VPN";
NSString *disconnectedVPNText                      = @"Disconnected from VPN";
NSString *unknownVPNText                           = @"VPN service not found";
NSString *noVPNText                                = @"No VPN service selected";

NSString *testingConnectionStatusText              = @"Testing connection...";
NSString *authFailedTestingConnectionStatusText    = @"Failed connecting - authorization failure";
NSString *reachFailedTestingConnectionStatusText   = @"Failed connecting - network failure";
NSString *sucessTestingConnectionStatusText        = @"Connection succeeded!";

NSString *restoredDirectConnectionStatusText       = @"Disconnected";

NSString *rerouteConnectionButtonTitle             = @"Connect";
NSString *restoreConnectionButtonTitle             = @"Disconnect";

NSString *helpWithProxyURL = @"http://chetansurpur.com/projects/sidestep/#proxy-servers";

/* Growl spam reduction
 *     Growl outputs 10 - 12 error messages simultaneously when connecting to an unsecured network.
 *     This hack only allows the notification to occur once.
 */
NSInteger GrowlSpam_ConnectionType    = 0;
NSInteger GrowlSpam_ConnectingToProxy = 0;
NSInteger GrowlSpam_TestConnection    = 0;

/*
 *	Class methods
 *******************************************************************************
 */

- (instancetype)init {

    self = [super init];

    if (self != nil) {
        SSHconnector      = [[SSHConnector alloc] init];
        defaultsController = [[DefaultsController alloc] init];
        networkNotifier   = [[NetworkNotifier alloc] init];
        proxySetter       = [[ProxySetter alloc] init];
        vpnInterfacer     = [[VPNInterfacer alloc] init];

        UNUserNotificationCenter.currentNotificationCenter.delegate = self;

        updaterController = [[SPUStandardUpdaterController alloc]
                             initWithStartingUpdater:NO
                             updaterDelegate:nil
                             userDriverDelegate:self];

        initiatedDelayedConnectionAttempt = NO;
        retryCounter = 0;

        SSHConnection = nil;
        SSHConnecting = NO;
        SSHConnected  = NO;
        VPNConnected  = NO;

        wasSSHConnectedBeforeSleep = NO;
        wasVPNConnectedBeforeSleep = NO;

        currentNetworkSecurityType = nil;
    }

    return self;
}


/*
 *	UI Event Handlers
 *******************************************************************************
 */

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

    [UNUserNotificationCenter.currentNotificationCenter
        requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
        completionHandler:^(BOOL granted, NSError *error) {
            if (error) NSLog(@"UserNotifications authorization error: %@", error);
        }];

    NSInteger previousPID = [defaultsController getSSHConnectionPID];

    if (previousPID != 0) {
        XLog(self, @"Turning proxy off");
        [self turnWirelessProxyOffThread];

        // Terminate previous SSH connection attempt if still running
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self terminateSSHConnectionAttemptThread];
        });

        // Kill previous SSH connection
        [SSHconnector killSSHConnectionForPID:previousPID];
    }

    [networkNotifier listenForAirportConnectionAndNotifyObject:self
                                                  withSelector:@selector(connectedToAirportNetwork)];

    // Check if current network type is insecure
    if (![networkNotifier getNetworkSecurityTypeAndNotifyObject:self
                                                   withSelector:@selector(connectedToAirportNetworkWithSecurityType:)]) {
        [self showRestartSidestepDialog];
    }

    // These notifications are filed on NSWorkspace's notification center, not the default
    // notification center. You will not receive sleep/wake notifications if you file
    // with the default notification center.
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(receiveSleepNote:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:NULL];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(receiveWakeNote:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:NULL];
}

- (void)awakeFromNib {

    // Set selected proxy if not already set
    if ([defaultsController selectedProxy] == nil ||
        [[defaultsController selectedProxy] isEqualToString:@""]) {
        [defaultsController setSelectedProxy:@"1"];
    }

    // Update VPN service lists
    [self updateUIForVPNServiceList];

    // Update UI for the selected proxy
    [self updateUIForSelectedProxy];

    // Create status menu item
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = statusImageDirectSecure;
    statusItem.menu = statusMenu;

    // Allocate and load images for the NSStatusItem
    statusImageDirectInsecure = [NSImage imageNamed:@"direct-insecure-icon"];
    statusImageDirectSecure   = [NSImage imageNamed:@"direct-secure-icon"];
    statusImageReroutedSecure = [NSImage imageNamed:@"rerouted-secure-icon"];

    // Enable template mode for dark menu bar support
    statusImageDirectInsecure.template = YES;
    statusImageDirectSecure.template   = YES;
    statusImageReroutedSecure.template = YES;

    // Start the updater
    [updaterController startUpdater];

    // Check for updates if not first run and automatic checks are enabled
    if ([defaultsController ranAtleastOnce] &&
        updaterController.updater.automaticallyChecksForUpdates) {
        XLog(self, @"Checking for updates");
        [updaterController.updater checkForUpdatesInBackground];
    }

    // Set first-run default preferences
    if (![defaultsController ranAtleastOnce]) {

        [defaultsController setRerouteAutomatically:YES];
        [defaultsController setRanAtleastOnce:YES];

        [defaultsController setRunOnLogin:YES];
        [self setRunOnLogin:YES];

        [defaultsController setGrowlSetting:YES];
        [defaultsController setCompressSSHConnection:NO];

        // Show welcome window
        [welcomeWindow center];
        [welcomeTabs selectFirstTabViewItem:self];
        welcomeWindow.isVisible = YES;
        [welcomeWindow makeKeyAndOrderFront:self];
    }

    // Set default remote port number if not already set
    if ([defaultsController getRemotePortNumber] == nil ||
        [[defaultsController getRemotePortNumber] isEqualToString:@""]) {
        [defaultsController setRemotePortNumber:@"22"];
    }

    // Enable notifications if preference is not found (user updated from previous version)
    if (![defaultsController getGrowlSetting]) {
        [defaultsController setGrowlSetting:YES];
    }

    // Set default local port number if not already set
    if ([defaultsController getLocalPortNumber] == nil ||
        [[defaultsController getLocalPortNumber] isEqualToString:@""]) {
        [defaultsController setLocalPortNumber:@"9050"];
    }

    // Update connection status
    connectionStatus.title = determiningConnectionStatusText;

    // Update proxy server status
    proxyServerStatus.title = notConnectedServerStatusText;

    // Set reroute or restore button title
    rerouteOrRestoreConnectionButton.title = rerouteConnectionButtonTitle;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {

    XLog(self, @"User clicked Quit");

    if (!SSHConnecting && !SSHConnected && !VPNConnected) {
        return NSTerminateNow;
    }

    // Kill the SSH process immediately
    if (SSHConnection) {
        XLog(self, @"Killing SSH connection on quit");
        [SSHConnection terminate];
    }
    if (SSHConnecting) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self terminateSSHConnectionAttemptThread];
        });
    }

    // Turn off proxy and VPN on a background thread, then notify and quit.
    // Skip error dialogs — we're exiting regardless.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self->proxySetter toggleProxy:NO interface:@"Wi-Fi" port:0];
        if (self->VPNConnected) {
            [self->vpnInterfacer turnVPNOnOrOff:[self->defaultsController selectedVPNService]
                                      withState:NO];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postNotification:@"Tunnel disconnected."];
            [NSApp replyToApplicationShouldTerminate:YES];
        });
    });

    return NSTerminateLater;
}

/*
 *	Functions
 *******************************************************************************
 */

- (void)openSSHConnectionAfterDelay:(int)delay {

    if (!SSHConnected || testingConnection) {
        if (SSHConnecting) {
            if (SSHConnection) {
                XLog(self, @"Killing current SSH connection");
                [SSHConnection terminate];
            }

            XLog(self, @"Terminating current SSH connection attempt");
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self terminateSSHConnectionAttemptThread];
            });

            SSHConnecting = NO;
        }

        // Reset retry counter
        retryCounter = 0;

        // Initiate connection attempt after delay if not already initiated
        if (!initiatedDelayedConnectionAttempt && !SSHConnecting) {
            XLog(self, @"Opening new SSH connection after delay");

            initiatedDelayedConnectionAttempt = YES;

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self openSSHConnectionNow];
            });
        }
    }
}

- (void)testSSHConnection {

    testingConnection = YES;
    [self openSSHConnectionAfterDelay:0];
}

- (void)closeSSHConnection {

    if (SSHConnection) {
        XLog(self, @"Turning proxy off");
        [self turnWirelessProxyOffThread];

        XLog(self, @"Killing current SSH connection");
        [SSHConnection terminate];
    }

    if (SSHConnecting) {
        XLog(self, @"Terminating current SSH connection attempt");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self terminateSSHConnectionAttemptThread];
        });
    }

    SSHConnecting = NO;
    SSHConnected  = NO;

    /* Set process to 0.
     * Otherwise, next launch of Sidestep will read this variable and think it crashed.
     * Sidestep would then try to kill the PID stored the last time it ran, potentially
     * killing an unintended process.
     */
    [defaultsController saveSSHConnectionPID:0];
}

- (void)openVPNConnectionAfterDelay:(int)delay {

    // Initiate connection attempt after delay if not already initiated
    if (!initiatedDelayedConnectionAttempt) {
        XLog(self, @"Opening VPN connection after delay");

        initiatedDelayedConnectionAttempt = YES;

        if (![[defaultsController selectedVPNService] isEqualToString:@"None"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self openVPNConnectionNow];
            });
        } else {
            [self postNotification:noVPNText];
        }
    }
}

- (void)closeVPNConnection {

    XLog(self, @"Closing VPN connection");

    if (![[defaultsController selectedVPNService] isEqualToString:@"None"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self closeVPNConnectionThread];
        });
    } else {
        [self postNotification:noVPNText];
    }
}

- (void)setRunOnLogin:(BOOL)value {

    [self willChangeValueForKey:@"startAtLogin"];

    NSURL *appURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];

    if (value) {
        XLog(self, @"Enabling run on login");
        [LoginItemController setStartAtLogin:appURL enabled:YES];
    } else {
        XLog(self, @"Disabling run on login");
        [LoginItemController setStartAtLogin:appURL enabled:NO];
    }

    [self didChangeValueForKey:@"startAtLogin"];
}


/*
 *	Background tasks
 *******************************************************************************
 */

- (void)openSSHConnectionNow {

    @autoreleasepool {

    NSString *username      = [defaultsController getServerUsername];
    NSString *hostname      = [defaultsController getServerHostname];
    NSString *remoteport    = [defaultsController getRemotePortNumber];
    NSNumber *localport     = (NSNumber *)[defaultsController getLocalPortNumber];
    NSString *additionalargs = [defaultsController getAdditionalArguments];
    BOOL sshCompression     = [defaultsController getCompressSSHConnection];

    if (username && hostname) {
        if (![SSHconnector openSSHConnectionAndNotifyObject:self
                                        withOpeningSelector:@selector(SSHConnectionOpening:)
                                        withSuccessSelector:@selector(SSHConnectionOpened:)
                                        withFailureSelector:@selector(SSHConnectionFailed:)
                                               withUsername:username
                                               withHostname:hostname
                                             withRemotePort:(NSString *)remoteport
                                          withLocalBindPort:(NSNumber *)localport
                                      withAdditionalArguments:additionalargs
                                         withSSHCompression:sshCompression]) {
            [self showRestartSidestepDialog];
        }
    } else {
        XLog(self, @"No username or hostname found");
    }

    initiatedDelayedConnectionAttempt = NO;

    } // @autoreleasepool
}

- (void)watchSSHConnectionForCloseThread:(NSTask *)connection {

    @autoreleasepool {
        [SSHconnector watchSSHConnectionAndOnCloseNotifyObject:self
                                                  withSelector:@selector(SSHConnectionClosed)
                                                withConnection:connection];
    }
}

- (void)terminateSSHConnectionAttemptThread {

    @autoreleasepool {
        [SSHconnector terminateSSHConnectionAttempt];
    }
}

- (void)turnWirelessProxyOnThread:(NSNumber *)port {

    @autoreleasepool {
        if (![proxySetter toggleProxy:YES interface:@"Wi-Fi" port:port]) {
            [self showAuthorizationErrorSidestepDialog];
        }
    }
}

- (void)turnWirelessProxyOffThread {

    @autoreleasepool {
        if (![proxySetter toggleProxy:NO interface:@"Wi-Fi" port:0]) {
            [self showAuthorizationErrorSidestepDialog];
        }
    }
}

- (void)openVPNConnectionNow {

    @autoreleasepool {

    int result = [vpnInterfacer turnVPNOnOrOff:[defaultsController selectedVPNService] withState:YES];
    if (!result) {
        [self showRestartSidestepDialog];
    } else {
        if (result == 1) {
            VPNConnected = YES;
            [self postNotification:connectedVPNText];
        } else {
            [self postNotification:unknownVPNText];
        }
    }

    initiatedDelayedConnectionAttempt = NO;

    } // @autoreleasepool
}

- (void)closeVPNConnectionThread {

    @autoreleasepool {

    int result = [vpnInterfacer turnVPNOnOrOff:[defaultsController selectedVPNService] withState:NO];
    if (!result) {
        [self showRestartSidestepDialog];
    } else {
        if (result == 1) {
            VPNConnected = NO;
            [self postNotification:disconnectedVPNText];
        } else {
            [self postNotification:unknownVPNText];
        }
    }

    } // @autoreleasepool
}


/*
 *	Event handlers
 *******************************************************************************
 */

- (void)SSHConnectionOpening:(NSTask *)connection {

    XLog(self, @"Called SSHConnectionOpening. Connection task PID: %d", [connection processIdentifier]);

    [defaultsController saveSSHConnectionPID:[connection processIdentifier]];

    if (testingConnection) {
        [self performSelectorOnMainThread:@selector(updateUIForTestingSSHConnectionOpening)
                               withObject:nil
                            waitUntilDone:NO];
    } else {
        [self performSelectorOnMainThread:@selector(updateUIForSSHConnectionOpening)
                               withObject:nil
                            waitUntilDone:NO];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self watchSSHConnectionForCloseThread:connection];
    });

    SSHConnection = connection;
    SSHConnecting = YES;
}

- (void)SSHConnectionOpened:(NSTask *)connection {

    XLog(self, @"Called SSHConnectionOpened. Connection task PID: %d", [connection processIdentifier]);

    SSHConnected  = YES;
    SSHConnecting = NO;

    if (testingConnection) {
        if (SSHConnection) {
            XLog(self, @"Killing current SSH connection");
            [SSHConnection terminate];
        }

        XLog(self, @"Terminating current SSH connection attempt");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self terminateSSHConnectionAttemptThread];
        });

        testingConnection = NO;

        [self performSelectorOnMainThread:@selector(updateUIForTestingSSHConnectionSucceeded)
                               withObject:nil
                            waitUntilDone:NO];
    } else {
        XLog(self, @"Turning proxy on");
        NSNumber *localport = (NSNumber *)[defaultsController getLocalPortNumber];
        [self turnWirelessProxyOnThread:@([localport intValue])];

        [self performSelectorOnMainThread:@selector(updateUIForSSHConnectionOpened)
                               withObject:nil
                            waitUntilDone:NO];
    }
}

- (void)SSHConnectionFailed:(NSString *)errorCode {

    XLog(self, @"Called SSHConnectionFailed.");

    SSHConnection = nil;
    SSHConnected  = NO;
    SSHConnecting = NO;

    XLog(self, @"Resetting keychain entry");

    if ([errorCode isEqualToString:@"2"]) {
        BOOL result = [PasswordController deleteKeychainEntryForHost:[defaultsController getServerHostname]
                                                               user:[defaultsController getServerUsername]];
        XLog(self, @"Result of trying to delete keychain entry: %d", result);
    }

    if (testingConnection) {
        testingConnection = NO;

        [self performSelectorOnMainThread:@selector(updateUIForTestingSSHConnectionFailedWithError:)
                               withObject:errorCode
                            waitUntilDone:NO];
    } else {
        [self performSelectorOnMainThread:@selector(updateUIForSSHConnectionFailedWithError:)
                               withObject:errorCode
                            waitUntilDone:NO];

        if (![errorCode isEqualToString:@"2"] && ![errorCode isEqualToString:@"5"] &&
            retryCounter < 2) {
            XLog(self, @"Retrying connection attempt after delay. Retry counter: %d", retryCounter);

            [self performSelectorOnMainThread:@selector(updateUIForSSHConnectionRetrying)
                                   withObject:nil
                                waitUntilDone:NO];

            initiatedDelayedConnectionAttempt = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self openSSHConnectionNow];
            });

            retryCounter++;
        } else if (retryCounter >= 2) {
            [self performSelectorOnMainThread:@selector(updateConnectionStatusForCurrentNetwork)
                                   withObject:nil
                                waitUntilDone:NO];
        }
    }
}

- (void)SSHConnectionClosed {

    XLog(self, @"SSH Connection was closed.");

    if (SSHConnecting) {
        // Connection was closed while connecting, before SSH watcher started
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self terminateSSHConnectionAttemptThread];
        });
    }

    if (SSHConnected) {
        XLog(self, @"Turning proxy off");
        [self turnWirelessProxyOffThread];
    }

    if (!testingConnection) {
        [self performSelectorOnMainThread:@selector(updateUIForSSHConnectionClosed)
                               withObject:nil
                            waitUntilDone:NO];
    }

    BOOL wasConnected = SSHConnected;
    SSHConnection = nil;
    SSHConnected  = NO;
    SSHConnecting = NO;

    // Auto-reconnect if the tunnel dropped unexpectedly (not from sleep, not user-initiated)
    if (!testingConnection && wasConnected && !wasSSHConnectedBeforeSleep &&
        [defaultsController rerouteAutomaticallyEnabled] &&
        [currentNetworkSecurityType isEqualToString:@"none"]) {
        [self postNotification:@"Tunnel dropped unexpectedly. Reconnecting..."];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            [self openSSHConnectionAfterDelay:0];
        });
    } else {
        [self postNotification:restoredDirectConnectionStatusText];
    }
}

- (void)connectedToAirportNetwork {

    if (![networkNotifier getNetworkSecurityTypeAndNotifyObject:self
                                                   withSelector:@selector(connectedToAirportNetworkWithSecurityType:)]) {
        [self showRestartSidestepDialog];
    }
}

- (void)connectedToAirportNetworkWithSecurityType:(NSString *)security {

    XLog(self, @"Network security type: %@", security);

    currentNetworkSecurityType = security;

    [self performSelectorOnMainThread:@selector(updateConnectionStatusForCurrentNetwork)
                           withObject:nil
                        waitUntilDone:NO];

    // Kill process if there's one running
    if ([defaultsController getSSHConnectionPID] != 0) {
        [self closeSSHConnection];
    }
    if ([[defaultsController selectedProxy] isEqualToString:@"0"]) {
        [self closeVPNConnection];
    }

    // Launch new process if needed
    if ([security isEqualToString:@"none"] && [defaultsController rerouteAutomaticallyEnabled]) {
        if ([[defaultsController selectedProxy] isEqualToString:@"1"]) {
            [self openSSHConnectionAfterDelay:3];
        } else {
            [self openVPNConnectionAfterDelay:3];
        }
    }
}

- (void)receiveSleepNote:(NSNotification *)note {
    XLog(self, @"System going to sleep");

    wasSSHConnectedBeforeSleep = SSHConnected || SSHConnecting;
    wasVPNConnectedBeforeSleep = VPNConnected;

    if (wasSSHConnectedBeforeSleep || wasVPNConnectedBeforeSleep) {
        [self postNotification:@"Going to sleep. Disconnecting tunnel."];
    }

    if (wasSSHConnectedBeforeSleep) {
        [self closeSSHConnection];
    }
    if (wasVPNConnectedBeforeSleep) {
        [self closeVPNConnection];
    }
}

- (void)receiveWakeNote:(NSNotification *)note {
    XLog(self, @"System woke from sleep — waiting 5 seconds for network");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self->networkNotifier getNetworkSecurityTypeAndNotifyObject:self
                                                       withSelector:@selector(connectedToAirportNetworkWithSecurityType:)];
    });
}


/*
 *	UI Functions
 *******************************************************************************
 */

- (void)updateConnectionStatusForCurrentNetwork {

    XLog(self, @"Called updateConnectionStatusForCurrentNetwork");

    if ([currentNetworkSecurityType isEqualToString:@""]) {
        connectionStatus.title = noNetworkConnectionStatusText;

        if (GrowlSpam_ConnectionType != 1 && GrowlSpam_TestConnection != 1) {
            [self postNotification:noNetworkConnectionStatusText];
            GrowlSpam_ConnectionType = 1;
            GrowlSpam_TestConnection = 0;
        }
        statusItem.button.image = statusImageDirectSecure;

    } else if ([currentNetworkSecurityType isEqualToString:@"none"]) {
        connectionStatus.title = openConnectionStatusText;
        if (GrowlSpam_ConnectionType != 2) {
            [self postNotification:openConnectionStatusText];
            GrowlSpam_ConnectionType = 2;
        }
        statusItem.button.image = statusImageDirectInsecure;

    } else {
        connectionStatus.title = protectedConnectionStatusText;
        if (GrowlSpam_ConnectionType != 3) {
            [self postNotification:protectedConnectionStatusText];
            GrowlSpam_ConnectionType = 3;
        }
        statusItem.button.image = statusImageDirectSecure;
    }
}

- (void)updateUIForSSHConnectionRetrying {

    XLog(self, @"Called updateUIForSSHConnectionRetrying");
    connectionStatus.title = retryingConnectionStatusText;
}

- (void)updateUIForSSHConnectionOpening {

    XLog(self, @"Called updateUIForSSHConnectionOpening");

    connectionStatus.title = connectingConnectionStatusText;
    if (GrowlSpam_ConnectingToProxy == 0) {
        [self postNotification:connectingConnectionStatusText];
        GrowlSpam_ConnectingToProxy = 1;
    }

    rerouteOrRestoreConnectionButton.enabled = NO;
}

- (void)updateUIForSSHConnectionOpened {

    XLog(self, @"Called updateUIForSSHConnectionOpened");

    connectionStatus.title = proxyConnectedConnectionStatusText;
    [self postNotification:proxyConnectedConnectionStatusText];

    // Reset GrowlSpam variable to allow notifications now that spam should have ended
    GrowlSpam_ConnectingToProxy = 0;

    // Proxy server status is updated in another growl message. No need to add one here.
    proxyServerStatus.title = connectedServerStatusText;

    rerouteOrRestoreConnectionButton.title   = restoreConnectionButtonTitle;
    rerouteOrRestoreConnectionButton.enabled = YES;

    statusItem.button.image = statusImageReroutedSecure;
}

- (void)updateUIForSSHConnectionFailedWithError:(NSString *)errorCode {

    XLog(self, @"Called updateUIForSSHConnectionFailedWithError");

    if ([errorCode isEqualToString:@"2"]) {
        proxyServerStatus.title = authorizationErrorServerStatusText;
    } else if ([errorCode isEqualToString:@"3"] || [errorCode isEqualToString:@"4"]) {
        proxyServerStatus.title = connectionErrorServerStatusText;
    }

    [self updateConnectionStatusForCurrentNetwork];

    rerouteOrRestoreConnectionButton.title   = rerouteConnectionButtonTitle;
    rerouteOrRestoreConnectionButton.enabled = YES;
}

- (void)updateUIForSSHConnectionClosed {

    XLog(self, @"Called updateUIForSSHConnectionClosed");

    [self updateConnectionStatusForCurrentNetwork];

    proxyServerStatus.title                = notConnectedServerStatusText;
    rerouteOrRestoreConnectionButton.title = rerouteConnectionButtonTitle;
}

- (void)updateUIForTestingSSHConnectionOpening {
    XLog(self, @"Called updateUIForTestingSSHConnectionOpening");

    testConnectionStatusField.stringValue = testingConnectionStatusText;
    [self postNotification:testingConnectionStatusText];

    // Prevent wireless status from appearing after test
    GrowlSpam_TestConnection = 1;
}

- (void)updateUIForTestingSSHConnectionSucceeded {

    XLog(self, @"Called updateUIForTestingSSHConnectionSucceeded");

    testConnectionStatusField.stringValue = sucessTestingConnectionStatusText;
    [self postNotification:sucessTestingConnectionStatusText];

    // Allow messages to appear if the user connects to a different network of the same type
    GrowlSpam_ConnectionType = 0;
}

- (void)updateUIForTestingSSHConnectionFailedWithError:(NSString *)errorCode {

    XLog(self, @"Called updateUIForTestingSSHConnectionFailedWithError");

    if ([errorCode isEqualToString:@"2"]) {
        testConnectionStatusField.stringValue = authFailedTestingConnectionStatusText;
        [self postNotification:authFailedTestingConnectionStatusText];
    } else if ([errorCode isEqualToString:@"3"] || [errorCode isEqualToString:@"4"] ||
               [errorCode isEqualToString:@"5"]) {
        testConnectionStatusField.stringValue = reachFailedTestingConnectionStatusText;
        [self postNotification:reachFailedTestingConnectionStatusText];
    }

    // Allow messages to appear if the user connects to a different network of the same type
    GrowlSpam_ConnectionType = 0;
}

- (void)showAuthorizationErrorSidestepDialog {

    XLog(self, @"Showing user Authorization Error Sidestep dialog");

    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle      = NSAlertStyleCritical;
    alert.messageText     = @"Error accessing your System Preferences";
    alert.informativeText = @"It seems that you didn't allow Sidestep to modify your System Preferences.\n\n"
                             "Please close and open Sidestep again in order to ensure smooth running, "
                             "by authorizing Sidestep to modify your System.\n\n"
                             "Until you do so, you will not benefit from Sidestep functionalities.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showRestartSidestepDialog {

    XLog(self, @"Showing user restart Sidestep dialog");

    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle      = NSAlertStyleCritical;
    alert.messageText     = @"Please restart Sidestep";
    alert.informativeText = @"It seems that you've moved Sidestep to somewhere else on your computer "
                             "or have renamed the application.\n\n"
                             "Please close and open Sidestep again in order to ensure smooth running.\n\n"
                             "Until you do so, you might experience problems with Sidestep and your "
                             "Internet connection.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)updateUIForVPNServiceList {

    XLog(self, @"Currently selected VPN service: %@", [defaultsController selectedVPNService]);
    XLog(self, @"Updating UI for VPN Service List");

    NSArray *services = [vpnInterfacer getListOfVPNServices];
    XLog(self, @"Service list found: %@", services);

    if (services == nil) {
        [self showRestartSidestepDialog];
    } else {
        [availableVPNServices addItemsWithTitles:services];
    }

    if ([services containsObject:[defaultsController selectedVPNService]]) {
        [availableVPNServices selectItemWithTitle:[defaultsController selectedVPNService]];
    } else {
        [defaultsController setSelectedVPNService:@"None"];
    }
}

- (void)updateUIForSelectedProxy {

    XLog(self, @"Updating UI for selected proxy");
    XLog(self, @"Selected proxy: %@", [defaultsController selectedProxy]);

    [proxyTabs selectTabViewItemWithIdentifier:[defaultsController selectedProxy]];

    if ([[defaultsController selectedProxy] isEqualToString:@"1"]) {	// SSH selected
        rerouteOrRestoreConnectionButton.hidden = NO;
        connectVPNServiceButton.hidden          = YES;
        disconnectVPNServiceButton.hidden       = YES;

        statusMenuFirstSeparator.hidden = NO;
        connectionStatus.hidden         = NO;
        proxyServerStatus.hidden        = NO;
    } else {                                                            // VPN selected
        rerouteOrRestoreConnectionButton.hidden = YES;
        connectVPNServiceButton.hidden          = NO;
        disconnectVPNServiceButton.hidden       = NO;

        statusMenuFirstSeparator.hidden = YES;
        connectionStatus.hidden         = YES;
        proxyServerStatus.hidden        = YES;
    }
}

/*
 *	UI Receivers
 *******************************************************************************
 */

- (void)preferencesClicked:(id)sender {

    [NSApp activateIgnoringOtherApps:YES];

    [preferencesWindow center];
    preferencesWindow.isVisible = YES;
    [preferencesWindow makeKeyAndOrderFront:self];
}

- (void)aboutClicked:(id)sender {

    [NSApp activateIgnoringOtherApps:YES];

    [welcomeWindow center];
    [welcomeTabs selectFirstTabViewItem:self];
    welcomeWindow.isVisible = YES;
    [welcomeWindow makeKeyAndOrderFront:self];
}

- (void)rerouteOrRestoreConnectionClicked:(id)sender {

    if ([rerouteOrRestoreConnectionButton.title isEqualToString:rerouteConnectionButtonTitle]) {
        XLog(self, @"Reroute connection button clicked");
        [self openSSHConnectionAfterDelay:0];
    } else if ([rerouteOrRestoreConnectionButton.title isEqualToString:restoreConnectionButtonTitle]) {
        XLog(self, @"Restore connection button clicked");
        [self closeSSHConnection];
    }
}

- (void)testSSHConnectionClickedFromPreferences:(id)sender {

    testConnectionStatusField = testConnectionStatusFieldInPreferences;
    [preferencesWindow makeFirstResponder:sender];
    [self testSSHConnection];
}

- (void)testSSHConnectionClickedFromWelcome:(id)sender {

    testConnectionStatusField = testConnectionStatusFieldInWelcome;
    [welcomeWindow makeFirstResponder:sender];
    [self testSSHConnection];
}

- (void)helpWithProxyClicked:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:helpWithProxyURL]];
}

- (void)nextClickedInWelcome:(id)sender {
    [welcomeTabs selectNextTabViewItem:self];
}

- (void)finishClickedInWelcome:(id)sender {
    welcomeWindow.isVisible = NO;
}

- (void)toggleRunOnLoginClicked:(id)sender {
    [self setRunOnLogin:[defaultsController runOnLogin]];
}

- (void)selectProxyClicked:(id)sender {

    XLog(self, @"Selected proxy: %@", [defaultsController selectedProxy]);
    [self updateUIForSelectedProxy];
}

- (void)connectProxyClicked:(id)sender {

    XLog(self, @"Selected VPN service: %@", [defaultsController selectedVPNService]);
    [self openVPNConnectionAfterDelay:0];
}

- (void)disconnectProxyClicked:(id)sender {

    XLog(self, @"Selected VPN service: %@", [defaultsController selectedVPNService]);
    [self closeVPNConnection];
}

- (NSString *)sshCommand {

    NSString *username       = [defaultsController getServerUsername];
    NSString *hostname       = [defaultsController getServerHostname];
    NSString *remoteport     = [defaultsController getRemotePortNumber];
    NSNumber *localport      = (NSNumber *)[defaultsController getLocalPortNumber];
    NSString *additionalargs = [defaultsController getAdditionalArguments];
    BOOL sshCompression      = [defaultsController getCompressSSHConnection];

    NSTask *task = [SSHconnector sshTaskWithUsername:username
                                        withHostname:hostname
                                      withRemotePort:remoteport
                                   withLocalBindPort:localport
                             withAdditionalArguments:additionalargs
                                  withSSHCompression:sshCompression];

    return [NSString stringWithFormat:@"%@ %@",
            task.launchPath,
            [task.arguments componentsJoinedByString:@" "]];
}

- (void)updateSSHCommand {
    sshCommandDisplayField.stringValue = [self sshCommand];
}

- (IBAction)compressionToggled:(id)sender {
    [self updateSSHCommand];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self updateSSHCommand];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {

    NSControl *control     = aNotification.object;
    NSString  *identifier  = control.identifier;

    // If the text field being updated is on the advanced tab, show the update in real-time
    if ([@"AdditionalSSHArguments" isEqualToString:identifier]) {
        [defaultsController setAdditionalArguments:control.stringValue];
        [self updateSSHCommand];
    }
}


/*
 *  Notifications
 *******************************************************************************
 */

- (void)postNotification:(NSString *)message {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"sidestep_GrowlSetting"])
        return;

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Sidestep";
    content.body = message;
    content.sound = UNNotificationSound.defaultSound;

    NSString *identifier = [NSString stringWithFormat:@"sidestep-%@", [[NSUUID UUID] UUIDString]];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter
        addNotificationRequest:request
        withCompletionHandler:^(NSError *error) {
            if (error) NSLog(@"UserNotifications error: %@", error);
        }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (BOOL)supportsGentleScheduledUpdateReminders {
    return YES;
}

- (void)standardUserDriverWillHandleShowingUpdate:(BOOL)handleShowingUpdate
                                        forUpdate:(SUAppcastItem *)update
                                            state:(SPUUserUpdateState *)state {
    if (!state.userInitiated) {
        [self postNotification:@"A Sidestep update is available."];
    }
}

@end
