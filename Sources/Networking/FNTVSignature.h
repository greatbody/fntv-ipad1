#import <Foundation/Foundation.h>

// The current NAS Web client signs ordinary API requests in addition to Authorization.
BOOL FNTVNeedsRequestSignature(NSURL *url, NSString *method);
NSString *FNTVRequestSignature(NSURL *url, NSString *method, NSData *body, NSString *nonce, NSString *timestamp);
NSString *FNTVNewRequestSignature(NSURL *url, NSString *method, NSData *body);
