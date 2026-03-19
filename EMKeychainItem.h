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

#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

@interface EMKeychainItem : NSObject
{
	@private
	NSString *mUsername;
	NSString *mPassword;
	NSString *mLabel;
}

+ (BOOL)logsErrors;
+ (void)setLogsErrors:(BOOL)logsErrors;

@property (readwrite, copy) NSString *username;
@property (readwrite, copy) NSString *password;
@property (readwrite, copy) NSString *label;

- (void)removeFromKeychain;

@end

#pragma mark -

@interface EMGenericKeychainItem : EMKeychainItem
{
	@private
	NSString *mServiceName;
}

@property (readwrite, copy) NSString *serviceName;

+ (EMGenericKeychainItem *)genericKeychainItemForService:(NSString *)serviceName
											withUsername:(NSString *)username;

+ (EMGenericKeychainItem *)addGenericKeychainItemForService:(NSString *)serviceName
											   withUsername:(NSString *)username
												   password:(NSString *)password;
@end

#pragma mark -

@interface EMInternetKeychainItem : EMKeychainItem
{
	@private
	NSString *mServer;
	NSString *mPath;
	NSInteger mPort;
	SecProtocolType mProtocol;
}

+ (EMInternetKeychainItem *)internetKeychainItemForServer:(NSString *)server
											 withUsername:(NSString *)username
													 path:(NSString *)path
													 port:(NSInteger)port
												 protocol:(SecProtocolType)protocol;

+ (EMInternetKeychainItem *)addInternetKeychainItemForServer:(NSString *)server
												withUsername:(NSString *)username
													password:(NSString *)password
														path:(NSString *)path
														port:(NSInteger)port
													protocol:(SecProtocolType)protocol;

@property (readwrite, copy) NSString *server;
@property (readwrite, copy) NSString *path;
@property (readwrite, assign) NSInteger port;
@property (readwrite, assign) SecProtocolType protocol;

@end
