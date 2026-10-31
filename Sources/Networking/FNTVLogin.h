#import <Foundation/Foundation.h>

// Produces one version-selected request; callers never retry a password on another endpoint.
NSDictionary *FNTVLoginRequest(NSString *version, NSString *username, NSString *password, NSError **error);
NSString *FNTVLoginToken(id payload, NSError **error);

BOOL FNTVIsAuthenticationFailure(NSInteger code, NSString *message);
