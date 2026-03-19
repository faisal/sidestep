# Sidestep Modernization Plan

## Context

Sidestep is a ~2010-era macOS menu bar app (~3,780 LOC, 14 .m files) that detects insecure Wi-Fi networks and automatically routes traffic through an SSH SOCKS tunnel or VPN. It targeted macOS 10.5 Leopard, used manual retain/release, included dead frameworks (Growl), relied on a private Apple framework for Wi-Fi detection, and had no sleep/wake handling. The goal is to bring it to modern macOS (13+ Ventura) as a universal binary with all deprecated APIs replaced. The PLAN.md file contains the phases, steps, and directions for updating the app. Execute the plan. After each step or phase, test that the change worked, or ask me to test. After confirming the change worked, commit the changes. Use the phase or step title as the commit message title, and the phase or step details as the commit message details.

---

## Phase 1: Build System — Get It Compiling

**Files**: `Sidestep.xcodeproj/project.pbxproj`, `GrowlMessage.m`, `Sidestep-Info.plist`

### 1.1 Update Xcode project build settings
- `MACOSX_DEPLOYMENT_TARGET`: `10.5` → `13.0`
- `ARCHS`: `$(ARCHS_STANDARD_32_64_BIT)` → `$(ARCHS_STANDARD)` (arm64 + x86_64)
- `ONLY_ACTIVE_ARCH`: set to `NO` in both Debug and Release project-level configs so both produce universal binaries
  - Note: when building from xcodebuild CLI, use `-destination 'generic/platform=macOS'` or pass `ONLY_ACTIVE_ARCH=NO` explicitly, as xcodebuild defaults to the host architecture destination
- Remove all `GCC_MODEL_TUNING = G5` (4 occurrences — PowerPC tuning)
- `GCC_C_LANGUAGE_STANDARD`: `gnu99` → `gnu11`
- Remove duplicate system AppKit PCH entries (keep project `Sidestep_Prefix.pch`)
- Remove `GCC_ENABLE_FIX_AND_CONTINUE`, `ZERO_LINK`, `PREBINDING` (obsolete)
- Add `CLANG_ENABLE_OBJC_ARC = YES`
- Add `LD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks"`

### 1.2 Remove Growl.framework (32-bit only, project is dead)
- Deleted `Growl.framework/` directory
- Rewrote `GrowlMessage.m` to use UserNotifications
- Removed `GrowlApplicationBridgeDelegate` from `AppController.h`
- Removed `registrationDictionaryForGrowl` and `setGrowlDelegate:` from `AppController.m`
- Removed from Xcode link/copy build phases in `project.pbxproj`

### 1.3 Replace Sparkle.framework with Sparkle 2.x
- Downloaded Sparkle 2.9.0 from `https://github.com/sparkle-project/Sparkle/releases/download/2.9.0/Sparkle-2.9.0.tar.xz`
- Extracted and copied `Sparkle.framework` over the old one (replaces ppc/i386/x86_64 unsigned binary with arm64+x86_64 signed universal binary)
- Note: Sparkle 2.x uses `Versions/B` (old used `Versions/A`); top-level symlinks handle this transparently
- Migrated API from deprecated `SUUpdater` to `SPUStandardUpdaterController` + `SPUUpdater`:
  - `AppController.h`: `#import <Sparkle/SUUpdater.h>` → `#import <Sparkle/SPUStandardUpdaterController.h>` + `#import <Sparkle/SPUUpdater.h>`
  - `AppController.m`: added `SPUStandardUpdaterController *updaterController` ivar
  - Init: `updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:nil userDriverDelegate:nil]`
  - Usage: `[updaterController startUpdater]` then `updaterController.updater.automaticallyChecksForUpdates` and `[updaterController.updater checkForUpdatesInBackground]`
  - Must import both `SPUStandardUpdaterController.h` and `SPUUpdater.h` because the controller header only forward-declares `SPUUpdater`
- Updated `SUFeedURL` in `Sidestep-Info.plist` to `https://www.faisal.com/projects/sidestep/appcast.xml`
- Replaced `SUPublicDSAKeyFile` with `SUPublicEDKey` (Sparkle 2.x dropped DSA entirely in favor of EdDSA):
  - Generate key pair: `/path/to/Sparkle-2.x/bin/generate_keys` — stores private key in keychain, outputs public key
  - Add the base64 Ed25519 public key as `SUPublicEDKey` in `Sidestep-Info.plist`
  - When publishing updates, sign each archive: `/path/to/Sparkle-2.x/bin/sign_update <archive>` to produce `sparkle:edSignature` for the appcast
  - Without a valid `SUPublicEDKey`, Sparkle 2.x refuses to start and shows "Unable to Check for Updates" at launch
- Fixed `SUEnableAutomaticChecks` and `SUShowReleaseNotes` from string `"true"` to proper plist booleans `<true/>`

### 1.4 Remove Carbon.h import from `EMKeychainItem.h`
- Replaced all SecKeychain* calls with SecItem* APIs
- Removed Carbon.h dependency entirely

### 1.5 Code signing configuration
- Added to all 4 target build configurations (Sidestep Debug/Release, SSHAskPass Debug/Release):
  - `CODE_SIGN_IDENTITY = "Apple Development"`
  - `CODE_SIGN_STYLE = Automatic`
  - `DEVELOPMENT_TEAM = Z55A7CATTU`
  - `PROVISIONING_PROFILE_SPECIFIER = ""`
- Added `PRODUCT_BUNDLE_IDENTIFIER = com.faisal.Sidestep` to Sidestep target configs

---

## Phase 2: Replace Deprecated APIs

**Files**: `AppController.m`, `LoginItemController.m`, `EMKeychainItem.m`, `PasswordController.m`, `ProxySetter.m`, `SSHAskPass.m`

### 2.1 Gestalt() → removed
- Removed the `lion` ivar and all conditional branches
- Hardcoded `@"Wi-Fi"` (always correct on macOS 12+)

### 2.2 NSRunCriticalAlertPanel → NSAlert
- Replaced all 3 call sites with `NSAlert`:
  - `setAlertStyle:NSAlertStyleCritical`
  - `setMessageText:` / `setInformativeText:`
  - `addButtonWithTitle:` for Yes/No
  - Check `[alert runModal] == NSAlertFirstButtonReturn`

### 2.3 NSAppKitVersionNumber template check → unconditional
- Removed the `if (!(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_9))` guard
- Always call `image.template = YES` on all three status images

### 2.4 LoginItemController.m → SMAppService
- Complete rewrite using `SMAppService.mainAppService` (requires macOS 13+, which drove the deployment target to 13.0)
- `+willStartAtLogin:` checks `SMAppService.mainAppService.status == SMAppServiceStatusEnabled`
- `+setStartAtLogin:enabled:` calls `registerAndReturnError:` / `unregisterAndReturnError:`
- `itemURL` parameter kept for API compatibility but unused
- Added `ServiceManagement.framework` to linked frameworks in `project.pbxproj`

### 2.5 EMKeychainItem.m → SecItem* APIs
- Complete rewrite using `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete`
- Uses NSDictionary-based queries with `kSecClass`, `kSecAttrService`, `kSecAttrAccount`, etc.
- `EMInternetKeychainItem` has helper `_queryForServer:username:path:port:protocol:` method
- Still supports `kSecProtocolTypeFTPAccount` fallback for legacy entries
- Removed `SecKeychainItemRef` ivars, `lockKeychain`/`unlockKeychain` methods
- Uses `__bridge` casts for CF↔NS conversions

### 2.6 PasswordController.m → NSAlert with NSSecureTextField
- Replaced `CFUserNotificationCreate`/`CFUserNotificationReceiveResponse` with NSAlert + accessory view
- Accessory view contains NSSecureTextField + NSButton (save to keychain checkbox)
- Returns same array format: `@[password, errorCode, saveToKeychain]`
- Uses `NSAlertFirstButtonReturn`/`NSAlertSecondButtonReturn`
- SSHAskPass.m: added `[NSApplication sharedApplication]` initialization before showing alert (required since it runs as a standalone executable spawned by ssh)

### 2.7 ProxySetter.m — minor fixes
- Fixed typo: `CFSTR("com.chetansurpur.Sitestep")` → `CFSTR("com.chetansurpur.Sidestep")`
- Moved `AuthorizationCreate` from `init` to lazy `ensureAuthorization` method
- Replaced goto-style error handling with sequential if-checks and early returns
- Uses `__bridge_transfer` for `SCDynamicStoreCopyProxies` result

---

## Phase 3: ARC Conversion

**Files**: All `.m` and `.h` files

### 3.1 Mechanical conversion
- Removed all `retain`, `release`, `autorelease`, `[super dealloc]` calls
- Removed all `dealloc` methods (except ProxySetter which needs `AuthorizationFree`)
- Replaced `NSAutoreleasePool` with `@autoreleasepool` blocks
- Set `CLANG_ENABLE_OBJC_ARC = YES` in project-level build settings
- Changed `- (id)init` → `- (instancetype)init`

### 3.2 IBOutlet ownership
- `AppController.h`: `strong` for top-level nib objects (`statusMenu`, `preferencesWindow`, `welcomeWindow`), `weak` for subviews (tab views, menu items, text fields, popup buttons)

### 3.3 Bridge casts
- All CF↔NS conversions use appropriate `__bridge`, `__bridge_retained`, or `__bridge_transfer`
- Key locations: ProxySetter.m, EMKeychainItem.m, AppUtilities.m, VPNInterfacer.m, NetworkNotifier.m

### 3.4 Ivar migration
- Moved ivars from `.h` interface blocks to `.m` class extensions (`@implementation ClassName { ... }`)
- `DefaultsController`: moved `NSUserDefaults *defaults` to implementation
- `SSHConnector`: removed empty ivar block from header
- `AppController`: moved all ivars to implementation, converted public ivars to `@property` in header
- Added `#pragma clang diagnostic ignored "-Warc-performSelector-leaks"` in SSHConnector.m for `performSelector:` calls

---

## Phase 4: Replace Growl with UserNotifications

**Files**: `GrowlMessage.m`, `GrowlMessage.h`, `AppController.m`

### 4.1 GrowlMessage rewritten with UNUserNotificationCenter
- `#import <UserNotifications/UserNotifications.h>`
- `requestAuthorization` requests `UNAuthorizationOptionAlert | UNAuthorizationOptionSound`
- `message:` creates `UNMutableNotificationContent` with title "Sidestep", posts via `UNNotificationRequest`
- Implements `UNUserNotificationCenterDelegate` (`userNotificationCenter:willPresentNotification:withCompletionHandler:`) for banner presentation while app is frontmost
- Checks `sidestep_GrowlSetting` user default before posting

### 4.2 AppController updated
- Calls `[growl requestAuthorization]` in `applicationDidFinishLaunching:`
- Removed `[GrowlApplicationBridge setGrowlDelegate:]` and `registrationDictionaryForGrowl`
- `UserNotifications.framework` added to linked frameworks in `project.pbxproj`

---

## Phase 5: Network Detection Modernization

**Files**: `NetworkNotifier.m`, `NetworkNotifier.h`, `AppController.m`, `VPNInterfacer.m`, `VPNInterfacer.h`

### 5.1 CoreWLAN replaces GetNetworkSecurityType.sh
- `#import <CoreWLAN/CoreWLAN.h>`
- Uses `CWWiFiClient.sharedWiFiClient.interface` to query Wi-Fi security type
- `CoreWLAN.framework` added to linked frameworks in `project.pbxproj`
- `getNetworkSecurityTypeAndNotifyObject:withSelector:` uses `CWInterface.security` property
- Switch on `CWSecurity` enum values: `kCWSecurityNone`, `kCWSecurityWEP`, `kCWSecurityWPAPersonal`/`Enterprise`, `kCWSecurityWPA2Personal`/`Enterprise`, `kCWSecurityWPA3Personal`/`Enterprise`/`Transition`
- Returns strings: "none", "wep", "wpa", "wpa2", "wpa3", "unknown"

### 5.2 Network change monitoring modernized
- `NetworkNotifier` conforms to `CWEventDelegate` protocol
- Monitors `CWEventTypeLinkDidChange` and `CWEventTypeSSIDDidChange` via `[CWWiFiClient.sharedWiFiClient startMonitoringEventWithType:error:]`
- Uses `CWWiFiClient.sharedWiFiClient.interface.interfaceName` for dynamic interface detection (no hardcoded en0/en1)

### 5.3 VPN control modernization
- `getListOfVPNServices`: uses `SCPreferencesCreate` + `SCNetworkServiceCopyAll`, iterates services checking `SCNetworkInterfaceGetInterfaceType` for `kSCNetworkInterfaceTypePPP` or `kSCNetworkInterfaceTypeIPSec`
- `turnVPNOnOrOff:withState:`: finds service by name, gets service ID via `SCNetworkServiceGetServiceID`, creates connection with `SCNetworkConnectionCreateWithServiceID`, calls `SCNetworkConnectionStart`/`SCNetworkConnectionStop`
- Returns: 1=success, 0=failure, 2=no such service, 3=not VPN type
- Important: `kSCNetworkInterfaceTypeVPN` does not exist in the public SystemConfiguration API — only use `kSCNetworkInterfaceTypePPP` and `kSCNetworkInterfaceTypeIPSec`

### 5.3.1 TODO: Validate VPN control
- VPN connect/disconnect (`turnVPNOnOrOff:withState:`) and service listing (`getListOfVPNServices`) have not been manually tested because no VPN services were available in the test environment.
- Before release, configure at least one VPN service in System Preferences > Network and verify: (a) it appears in the Sidestep VPN dropdown, (b) Sidestep can connect and disconnect it.

### 5.4 Obsolete scripts removed
- Deleted: `scripts/GetNetworkSecurityType.sh`, `scripts/GetListOfVPNServices.sh`, `scripts/TurnVPNOnOrOff.sh`, `scripts/TurnProxyOn.sh`, `scripts/TurnProxyOff.sh`
- Kept: `scripts/WatchSSHConnectionForChanges.sh` (still used by SSHConnector for SSH log monitoring)
- Removed script file references and build phase entries from `project.pbxproj`

---

## Phase 6: Sleep/Wake and Reconnection

**Files**: `AppController.m`

### 6.1 Sleep handler
- Registers for `NSWorkspaceWillSleepNotification` in `applicationDidFinishLaunching:`
- Handler records `wasSSHConnectedBeforeSleep` / `wasVPNConnectedBeforeSleep` state
- Kills SSH tunnel if connected, disconnects VPN if connected

### 6.2 Wake handler
- Registers for `NSWorkspaceDidWakeNotification`
- Uses `dispatch_after` with 5-second delay (allow network to stabilize)
- Re-evaluates current network security via `getNetworkSecurityTypeAndNotifyObject:`
- Reconnects SSH/VPN if was connected before sleep and network is still insecure

### 6.3 Auto-reconnect on unexpected SSH drop
- In `SSHConnectionClosed`, if `rerouteAutomatically` is enabled and `currentNetworkSecurityType` indicates insecure network, schedules reconnection after 3 seconds via `dispatch_after`

### 6.4 Network transition handling
- Detects Wi-Fi turning off entirely (nil SSID / no interface)
- Cleans up proxy settings when network disappears

### 6.5 System notifications for non-user-initiated tunnel changes
- Notify via `[growl message:]` whenever the tunnel is opened or closed without direct user action
- Sleep disconnect: `"Going to sleep. Disconnecting tunnel."` — posted in `receiveSleepNote:` before calling `closeSSHConnection`
- Auto-reconnect after unexpected drop: `"Tunnel dropped unexpectedly. Reconnecting..."` — posted in `SSHConnectionClosed` before the `dispatch_after` that triggers reconnection
- Wake reconnect: no additional notification needed — the wake handler flows through `connectedToAirportNetworkWithSecurityType:` → `openSSHConnectionAfterDelay:` which triggers the normal connection notifications ("Connecting...", "Secure connection")

---

## Phase 7: Threading, Modern Syntax, and Polish

**Files**: All `.m` and `.h` files

### 7.1 Replace `detachNewThreadSelector:` with GCD
- All 9 occurrences in `AppController.m` replaced with `dispatch_async(dispatch_get_global_queue(...), ^{ ... })`
- Sleep-loop delay threads replaced with `dispatch_after`

### 7.2 Modern Objective-C syntax
- Array/dictionary/number literals (`@[]`, `@{}`, `@()`)
- `Boolean` → `BOOL`, `TRUE`/`FALSE` → `YES`/`NO`
- Dot syntax for property access
- Removed space before colon in method signatures (`: ` → `:`)
- Removed `[defaults synchronize]` calls (unnecessary since iOS 8 / macOS 10.x)

### 7.3 NSStatusItem modernization
- Removed deprecated `setHighlightMode:YES` (automatic with menu)
- Uses `statusItem.button.image` instead of deprecated `setImage:`

### 7.4 Convert ivars to properties
- `AppController.h`: all public IBOutlets as `@property` declarations
- Private ivars moved to `@implementation` blocks in `.m` files

### 7.5 Update Info.plist
- `CFBundleDevelopmentRegion`: `English` → `en`

### 7.6 Other cleanup
- `AppUtilities.m`: replaced manual `object:existsInArray:` loop with `[array containsObject:]`
- `AppUtilities.m`: fixed potential buffer overrun in `_XLog` (added +1 to buflen)
- `AppUtilities.m`: added `__bridge` cast for `CFStringRef`

---

## Build Verification

### CLI build command (universal binary)
```bash
xcodebuild -scheme Sidestep -configuration Debug -destination 'generic/platform=macOS' build
```
Or equivalently:
```bash
xcodebuild -scheme Sidestep ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" build
```

### Verify universal binary
```bash
lipo -info ~/Library/Developer/Xcode/DerivedData/Sidestep-*/Build/Products/Debug/Sidestep.app/Contents/MacOS/Sidestep
# Expected: Architectures in the fat file: ... are: x86_64 arm64
```

### Verify code signing
```bash
codesign -vv ~/Library/Developer/Xcode/DerivedData/Sidestep-*/Build/Products/Debug/Sidestep.app
# Expected: valid on disk, satisfies its Designated Requirement
```

---

## Frameworks Added to Project

| Framework | Build Phase ID (file ref / build file) | Purpose |
|-----------|----------------------------------------|---------|
| CoreWLAN.framework | AABB000100000000CW000001 / CW000002 | Wi-Fi security detection |
| UserNotifications.framework | AABB000100000000UN000003 / UN000004 | Notifications (replaces Growl) |
| ServiceManagement.framework | AABB000100000000SM000005 / SM000006 | Login item management (SMAppService) |

---

## Phase Dependency Graph

```
Phase 1 (Build System)
  └→ Phase 2 (Deprecated APIs)
       └→ Phase 3 (ARC)
            ├→ Phase 4 (Notifications)
            ├→ Phase 5 (Network Detection)
            ├→ Phase 6 (Sleep/Wake)
            └→ Phase 7 (Polish)
```

---

## Risk Areas (for testing)

1. **EMKeychainItem rewrite** — SecItem API has a very different paradigm. Users with existing keychain entries must still be able to read them (SecItem can access legacy entries).
2. **SSHAskPass** — Runs as a separate executable spawned by `ssh`. Needs `[NSApplication sharedApplication]` initialized to show NSAlert. Must test that modal alert works in this context.
3. **ProxySetter authorization** — `SCPreferencesCreateWithAuthorization` may need a privileged helper via `SMJobBless` on modern macOS with SIP. Test thoroughly.
4. **VPN control** — SCNetworkConnection is less documented than NEVPNManager but doesn't require entitlements.

## Remaining Work

1. **End-to-end testing** — Full test on both Intel and Apple Silicon hardware: launch → detect insecure Wi-Fi → tunnel connects → notification → sleep/wake → reconnect → switch to secure network → tunnel disconnects.

2. **VPN validation** — No VPN services available in current test environment. Validate VPN detection (`getListOfVPNServices`) and control (`turnVPNOnOrOff`) with a real VPN configuration before shipping.

3. **iCloud Private Relay interaction (Phase 7 polish)** — On macOS 12+ with Private Relay enabled, Safari routes HTTPS via Apple/Cloudflare relays and ignores system SOCKS proxy settings. macOS automatically pauses Private Relay when a SOCKS proxy is set, but existing Safari connections (already established via relay) do not re-route — only new connections use the tunnel. This is a macOS-level behaviour change, not a Sidestep bug. Mitigations to explore: (a) surface a menu item or notification banner saying "Tunnel connected — reopen Safari tabs to route through proxy", (b) investigate whether posting a `kSCPrefChangesCurrent`/`kSCPrefChangesCommitted` CFNotification more aggressively causes Safari to drop relay sessions sooner.

4. **Slow proxy cutover (requires restarting Safari)** — Investigate why proxy changes don't take effect for existing browser sessions. Related to item 3 above: explore whether more aggressive `kSCPrefChangesCurrent`/`kSCPrefChangesCommitted` CFNotifications force Safari to drop existing connections and re-route through the proxy sooner, or whether a UX prompt ("Tunnel connected — reopen Safari tabs to route through proxy") is the right mitigation.
