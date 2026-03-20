//
//  SidestepLog.h
//  Sidestep
//
//  Per-category os_log_t accessors for structured, privacy-aware logging.
//  Use %{private}@ for usernames, hostnames, IPs, and other sensitive values.
//  Use %{public}@ for non-sensitive status strings.
//

#import <os/log.h>

static inline os_log_t SidestepLogSSH(void) {
    static os_log_t log;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ log = os_log_create("com.faisal.Sidestep", "ssh"); });
    return log;
}

static inline os_log_t SidestepLogNetwork(void) {
    static os_log_t log;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ log = os_log_create("com.faisal.Sidestep", "network"); });
    return log;
}

static inline os_log_t SidestepLogProxy(void) {
    static os_log_t log;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ log = os_log_create("com.faisal.Sidestep", "proxy"); });
    return log;
}

static inline os_log_t SidestepLogVPN(void) {
    static os_log_t log;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ log = os_log_create("com.faisal.Sidestep", "vpn"); });
    return log;
}

static inline os_log_t SidestepLogGeneral(void) {
    static os_log_t log;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ log = os_log_create("com.faisal.Sidestep", "general"); });
    return log;
}
