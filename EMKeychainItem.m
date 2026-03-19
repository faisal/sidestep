/*Copyright (c) 2009 Extendmac, LLC. <support@extendmac.com>

 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */

#import "EMKeychainItem.h"

@implementation EMKeychainItem

static BOOL _logsErrors;

+ (BOOL)logsErrors
{
	@synchronized (self) {
		return _logsErrors;
	}
	return NO;
}

+ (void)setLogsErrors:(BOOL)logsErrors
{
	@synchronized (self) {
		_logsErrors = logsErrors;
	}
}

- (instancetype)_initWithUsername:(NSString *)username password:(NSString *)password
{
	if ((self = [super init])) {
		mUsername = [username copy];
		mPassword = [password copy];
	}
	return self;
}

#pragma mark General Properties

@dynamic username;
- (NSString *)username { return mUsername; }
- (void)setUsername:(NSString *)newUsername
{
	@synchronized (self) {
		if (mUsername == newUsername) return;
		mUsername = [newUsername copy];
	}
}

@dynamic password;
- (NSString *)password { return mPassword; }
- (void)setPassword:(NSString *)newPassword
{
	@synchronized (self) {
		if (mPassword == newPassword) return;
		mPassword = [newPassword copy];
	}
}

@dynamic label;
- (NSString *)label { return mLabel; }
- (void)setLabel:(NSString *)newLabel
{
	@synchronized (self) {
		if (mLabel == newLabel) return;
		mLabel = [newLabel copy];
	}
}

#pragma mark Actions

- (void)removeFromKeychain
{
	// Subclasses override
}

@end

#pragma mark -
@implementation EMGenericKeychainItem

- (instancetype)_initWithServiceName:(NSString *)serviceName
							username:(NSString *)username
							password:(NSString *)password
{
	if ((self = [super _initWithUsername:username password:password])) {
		mServiceName = [serviceName copy];
	}
	return self;
}

@dynamic serviceName;
- (NSString *)serviceName { return mServiceName; }
- (void)setServiceName:(NSString *)newServiceName
{
	@synchronized (self) {
		if (mServiceName == newServiceName) return;
		mServiceName = [newServiceName copy];
	}
}

+ (EMGenericKeychainItem *)genericKeychainItemForService:(NSString *)serviceName
											withUsername:(NSString *)username
{
	if (!serviceName || !username)
		return nil;

	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrAccount: username,
		(__bridge id)kSecReturnData: @YES,
		(__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
	};

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

	if (status != errSecSuccess || !result) {
		if (_logsErrors)
			NSLog(@"Error (%@) - OSStatus %d", NSStringFromSelector(_cmd), (int)status);
		return nil;
	}

	NSData *passwordData = (__bridge_transfer NSData *)result;
	NSString *password = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];

	return [[EMGenericKeychainItem alloc] _initWithServiceName:serviceName username:username password:password];
}

+ (EMGenericKeychainItem *)addGenericKeychainItemForService:(NSString *)serviceName
											   withUsername:(NSString *)username
												   password:(NSString *)password
{
	if (!serviceName || !username || !password)
		return nil;

	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrAccount: username,
		(__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding],
	};

	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);

	if (status != errSecSuccess) {
		if (_logsErrors)
			NSLog(@"Error (%@) - OSStatus %d", NSStringFromSelector(_cmd), (int)status);
		return nil;
	}

	return [[EMGenericKeychainItem alloc] _initWithServiceName:serviceName username:username password:password];
}

- (void)removeFromKeychain
{
	if (!mServiceName) return;

	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: mServiceName,
		(__bridge id)kSecAttrAccount: self.username,
	};

	SecItemDelete((__bridge CFDictionaryRef)query);
}

@end

#pragma mark -
@implementation EMInternetKeychainItem

- (instancetype)_initWithServer:(NSString *)server
						username:(NSString *)username
						password:(NSString *)password
							path:(NSString *)path
							port:(NSInteger)port
						protocol:(SecProtocolType)protocol
{
	if ((self = [super _initWithUsername:username password:password])) {
		mServer = [server copy];
		mPath = [path copy];
		mPort = port;
		mProtocol = protocol;
	}
	return self;
}

- (NSMutableDictionary *)_queryForServer:(NSString *)server
								username:(NSString *)username
									path:(NSString *)path
									port:(NSInteger)port
								protocol:(SecProtocolType)protocol
{
	NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		(__bridge id)kSecClassInternetPassword, (__bridge id)kSecClass,
		server, (__bridge id)kSecAttrServer,
		username, (__bridge id)kSecAttrAccount,
		nil];

	if (path && path.length > 0)
		query[(__bridge id)kSecAttrPath] = path;
	if (port > 0)
		query[(__bridge id)kSecAttrPort] = @(port);
	if (protocol != 0)
		query[(__bridge id)kSecAttrProtocol] = @(protocol);

	return query;
}

+ (EMInternetKeychainItem *)internetKeychainItemForServer:(NSString *)server
											 withUsername:(NSString *)username
													 path:(NSString *)path
													 port:(NSInteger)port
												 protocol:(SecProtocolType)protocol
{
	if (!server || !username)
		return nil;

	EMInternetKeychainItem *temp = [[EMInternetKeychainItem alloc] _initWithServer:server username:username password:nil path:path port:port protocol:protocol];

	NSMutableDictionary *query = [temp _queryForServer:server username:username path:path port:port protocol:protocol];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

	if (status != errSecSuccess && protocol == kSecProtocolTypeFTP) {
		query[(__bridge id)kSecAttrProtocol] = @(kSecProtocolTypeFTPAccount);
		status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
		if (status == errSecSuccess)
			protocol = kSecProtocolTypeFTPAccount;
	}

	if (status != errSecSuccess || !result) {
		if (_logsErrors)
			NSLog(@"Error (%@) - OSStatus %d", NSStringFromSelector(_cmd), (int)status);
		return nil;
	}

	NSData *passwordData = (__bridge_transfer NSData *)result;
	NSString *password = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];

	return [[EMInternetKeychainItem alloc] _initWithServer:server username:username password:password path:path port:port protocol:protocol];
}

+ (EMInternetKeychainItem *)addInternetKeychainItemForServer:(NSString *)server
												withUsername:(NSString *)username
													password:(NSString *)password
														path:(NSString *)path
														port:(NSInteger)port
													protocol:(SecProtocolType)protocol
{
	if (!username || !server || !password)
		return nil;

	NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		(__bridge id)kSecClassInternetPassword, (__bridge id)kSecClass,
		server, (__bridge id)kSecAttrServer,
		username, (__bridge id)kSecAttrAccount,
		[password dataUsingEncoding:NSUTF8StringEncoding], (__bridge id)kSecValueData,
		nil];

	if (path && path.length > 0)
		query[(__bridge id)kSecAttrPath] = path;
	if (port > 0)
		query[(__bridge id)kSecAttrPort] = @(port);
	if (protocol != 0)
		query[(__bridge id)kSecAttrProtocol] = @(protocol);

	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);

	if (status != errSecSuccess) {
		if (_logsErrors)
			NSLog(@"Error (%@) - OSStatus %d", NSStringFromSelector(_cmd), (int)status);
		return nil;
	}

	return [[EMInternetKeychainItem alloc] _initWithServer:server username:username password:password path:path port:port protocol:protocol];
}

- (void)removeFromKeychain
{
	if (!mServer) return;

	NSDictionary *query = [self _queryForServer:mServer username:self.username path:mPath port:mPort protocol:mProtocol];
	SecItemDelete((__bridge CFDictionaryRef)query);
}

#pragma mark Internet Properties

@dynamic server;
- (NSString *)server { return mServer; }
- (void)setServer:(NSString *)newServer
{
	@synchronized (self) {
		if (mServer == newServer) return;
		mServer = [newServer copy];
	}
}

@dynamic path;
- (NSString *)path { return mPath; }
- (void)setPath:(NSString *)newPath
{
	if (mPath == newPath) return;
	mPath = [newPath copy];
}

@dynamic port;
- (NSInteger)port { return mPort; }
- (void)setPort:(NSInteger)newPort
{
	@synchronized (self) {
		mPort = newPort;
	}
}

@dynamic protocol;
- (SecProtocolType)protocol { return mProtocol; }
- (void)setProtocol:(SecProtocolType)newProtocol
{
	@synchronized (self) {
		mProtocol = newProtocol;
	}
}

@end
