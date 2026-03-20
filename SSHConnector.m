//
//  SSHConnector.m
//  Sidestep
//
//  Created by Chetan Surpur on 11/18/10.
//  Copyright 2010 Chetan Surpur. All rights reserved.
//

#import "SSHConnector.h"
#import "AppUtilities.h"
#import "SidestepLog.h"
#include <signal.h>
#include <unistd.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

// Private state for in-progress connection monitoring
@interface SSHConnector () {
    BOOL _terminating;
    dispatch_source_t _watchdogTimer;
    dispatch_once_t _resultToken;       // ensures success/failure callback fires exactly once
    NSMutableData *_stderrBuffer;       // accumulates partial SSH stderr lines
}
@end

@implementation SSHConnector

/*
 *  Creates a NSTask object for the SSH connection.
 */
- (NSTask *)sshTaskWithUsername:(NSString *)username
                   withHostname:(NSString *)hostname
                 withRemotePort:(NSString *)remoteport
              withLocalBindPort:(NSNumber *)localPort
        withAdditionalArguments:(NSString *)additionalArgs
             withSSHCompression:(BOOL)sshCompression {

    NSTask *taskObject = [[NSTask alloc] init];

    // Build argv entries — each flag and its value are separate elements so that
    // NSTask (via execve) passes them correctly to ssh's getopt() parser.
    NSMutableArray *args = [NSMutableArray new];
    [args addObject:[NSString stringWithFormat:@"%@@%@", username, hostname]];
    [args addObject:@"-D"]; [args addObject:[localPort description]];
    [args addObject:@"-p"]; [args addObject:remoteport];
    if (sshCompression) {
        [args addObject:@"-C"];
    }
    [args addObject:@"-N"];
    [args addObject:@"-v"];
    [args addObject:@"-o"]; [args addObject:@"TCPKeepAlive=yes"];
    [args addObject:@"-o"]; [args addObject:@"ServerAliveInterval=30"];
    [args addObject:@"-o"]; [args addObject:@"ConnectTimeout=30"];

    if ([additionalArgs length]) {
        NSArray *separatedArgs = [additionalArgs componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *filtered = [separatedArgs filteredArrayUsingPredicate:
                             [NSPredicate predicateWithFormat:@"length > 0"]];
        if ([filtered count]) {
            [args addObjectsFromArray:filtered];
        }
    }

    [taskObject setArguments:args];
    [taskObject setLaunchPath:@"/usr/bin/ssh"];

    return taskObject;
}


/*
 *  Opens SSH connection and monitors stderr in-process for connection state.
 *  Calls callback selectors on notable events.
 *
 *  return: YES on successful launch
 *  return: NO if SSHAskPass helper not found
 */
- (BOOL)openSSHConnectionAndNotifyObject:(id)object
                     withOpeningSelector:(SEL)openingSelector
                     withSuccessSelector:(SEL)successSelector
                     withFailureSelector:(SEL)failureSelector
                            withUsername:(NSString *)username
                            withHostname:(NSString *)hostname
                          withRemotePort:(NSString *)remoteport
                       withLocalBindPort:(NSNumber *)localPort
                 withAdditionalArguments:(NSString *)additionalArgs
                      withSSHCompression:(BOOL)sshCompression {

    os_log(SidestepLogSSH(), "Opening SSH connection to %{private}@@%{private}@",
           username, hostname);

    NSTask *taskObject = [self sshTaskWithUsername:username
                                      withHostname:hostname
                                    withRemotePort:remoteport
                                 withLocalBindPort:localPort
                           withAdditionalArguments:additionalArgs
                                withSSHCompression:sshCompression];

    // Pipe stdout (unused by ssh -N but required) and stderr (connection events)
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe  = [NSPipe pipe];

    [taskObject setStandardOutput:outputPipe];
    // stdin must be null so that ssh uses SSH_ASKPASS rather than prompting interactively
    [taskObject setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
    [taskObject setStandardError:errorPipe];

    NSString *askPassPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"SSHAskPass"];
    os_log_debug(SidestepLogSSH(), "SSHAskPass path: %{private}@", askPassPath);

    if (askPassPath == nil) {
        os_log_error(SidestepLogSSH(), "SSHAskPass helper not found in bundle");
        return NO;
    }

    // Build a minimal environment: suppress inherited state, set what ssh needs
    NSDictionary *currentEnvironment = [[NSProcessInfo processInfo] environment];
    NSMutableDictionary *newEnvironment = [@{
        // DISPLAY=NONE forces ssh to use SSH_ASKPASS instead of a terminal prompt
        @"DISPLAY":       @"NONE",
        @"SSH_ASKPASS":   askPassPath,
        @"AUTH_USERNAME": username,
        @"AUTH_HOSTNAME": hostname,
    } mutableCopy];

    // Preserve SSH agent socket for key-based auth if an agent is running
    NSString *authSock = currentEnvironment[@"SSH_AUTH_SOCK"];
    if (authSock) {
        newEnvironment[@"SSH_AUTH_SOCK"] = authSock;
    }

    os_log_debug(SidestepLogSSH(), "SSH environment configured for user %{private}@ on %{private}@",
                 username, hostname);

    [taskObject setEnvironment:newEnvironment];

    // Launch SSH
    [taskObject launch];

    // Notify "opening" callback
    [object performSelector:openingSelector withObject:taskObject];

    // Begin async monitoring of SSH stderr for connection outcome
    [self watchSSHConnectionAndOnOpenOrErrorNotifyObject:object
                                     withSuccessSelector:successSelector
                                     withFailureSelector:failureSelector
                                          withConnection:taskObject];

    return YES;
}


/*
 *  Monitors SSH stderr asynchronously via readabilityHandler.
 *  Scans each line for keywords indicating success or failure.
 *  Arms a 35-second watchdog in case SSH hangs without producing expected output.
 *
 *  Result codes (unchanged from previous shell-script protocol):
 *    1 — Connection successful
 *    2 — Authentication error
 *    3 — Server not found
 *    4 — Connection timed out
 *    5 — Manually terminated
 *    6 — Watchdog timeout (no result within 35 s)
 */
- (void)watchSSHConnectionAndOnOpenOrErrorNotifyObject:(id)object
                                   withSuccessSelector:(SEL)successSelector
                                   withFailureSelector:(SEL)failureSelector
                                        withConnection:(NSTask *)connection {

    os_log_debug(SidestepLogSSH(), "Watching SSH stderr for connection outcome");

    // Reset per-connection state
    _terminating  = NO;
    _resultToken  = 0;
    _stderrBuffer = [NSMutableData new];

    NSFileHandle *stderrHandle = [[connection standardError] fileHandleForReading];

    // Helper block that fires at most once regardless of which path triggers it
    __block typeof(self) weakSelf = self;
    void (^sendResult)(NSString *code) = ^(NSString *code) {
        dispatch_once(&weakSelf->_resultToken, ^{
            // Cancel the watchdog before calling back so it can't fire afterward
            if (weakSelf->_watchdogTimer) {
                dispatch_source_cancel(weakSelf->_watchdogTimer);
                weakSelf->_watchdogTimer = nil;
            }
            stderrHandle.readabilityHandler = nil;

            if ([code isEqualToString:@"1"]) {
                os_log(SidestepLogSSH(), "SSH connection established");
                [object performSelector:successSelector withObject:connection];
            } else {
                os_log(SidestepLogSSH(), "SSH connection failed with code %{public}@", code);
                [object performSelector:failureSelector withObject:code];
            }
        });
    };

    // Read SSH stderr chunk by chunk, accumulating into lines
    stderrHandle.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = [handle availableData];

        if ([data length] == 0) {
            // EOF: process exited
            if (weakSelf->_terminating) {
                sendResult(@"5");
            } else {
                // SSH exited without producing a recognised outcome — treat as timeout/generic failure
                sendResult(@"6");
            }
            return;
        }

        [weakSelf->_stderrBuffer appendData:data];

        // Extract complete lines from the buffer
        NSString *buffered = [[NSString alloc] initWithData:weakSelf->_stderrBuffer
                                                   encoding:NSUTF8StringEncoding];
        if (!buffered) return;

        NSArray<NSString *> *lines = [buffered componentsSeparatedByString:@"\n"];
        // Keep the last (possibly incomplete) fragment in the buffer
        NSUInteger count = [lines count];
        if (count > 1) {
            NSString *remainder = lines[count - 1];
            weakSelf->_stderrBuffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]
                                      ?: [NSMutableData new];
        }

        for (NSUInteger i = 0; i < count - 1; i++) {
            NSString *line = lines[i];
            if (![line length]) continue;

            os_log_debug(SidestepLogSSH(), "ssh: %{private}@", line);

            if ([line rangeOfString:@"Entering interactive session"].location != NSNotFound) {
                sendResult(@"1");
            } else if ([line rangeOfString:@"Permission denied ("].location != NSNotFound) {
                sendResult(@"2");
            } else if ([line rangeOfString:@"Could not resolve hostname"].location != NSNotFound) {
                sendResult(@"3");
            } else if ([line rangeOfString:@"Connection timed out"].location != NSNotFound) {
                sendResult(@"4");
            }
            // code 5 (manual termination) is sent via EOF path above
        }
    };

    // Watchdog: if no result arrives within 35 seconds, give up
    dispatch_queue_t timerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _watchdogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
    dispatch_source_set_timer(_watchdogTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC),
                              DISPATCH_TIME_FOREVER,
                              1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_watchdogTimer, ^{
        os_log_error(SidestepLogSSH(), "SSH connection watchdog fired — no outcome in 35 s");
        [connection terminate];
        sendResult(@"6");
    });
    dispatch_resume(_watchdogTimer);
}


/*
 *  Waits for SSH connection's task to close, then calls the given selector.
 */
- (void)watchSSHConnectionAndOnCloseNotifyObject:(id)object
                                    withSelector:(SEL)selector
                                  withConnection:(NSTask *)connection {

    os_log_debug(SidestepLogSSH(), "Waiting for SSH task to exit");
    [connection waitUntilExit];
    [object performSelector:selector];
}


/*
 *  Signals that the in-progress connection attempt should be aborted.
 *  Sets _terminating so the readabilityHandler EOF path sends result code 5.
 */
- (void)terminateSSHConnectionAttempt {

    os_log(SidestepLogSSH(), "Terminating SSH connection attempt");
    _terminating = YES;

    // Cancel the watchdog immediately so it doesn't race with the EOF handler
    if (_watchdogTimer) {
        dispatch_source_cancel(_watchdogTimer);
        _watchdogTimer = nil;
    }
}


/*
 *  Kills the SSH task identified by PID.
 */
- (void)killSSHConnectionForPID:(NSInteger)pid {

    os_log(SidestepLogSSH(), "Killing SSH connection PID %{public}ld", (long)pid);
    kill((pid_t)pid, SIGTERM);
}

@end
