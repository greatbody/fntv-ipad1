#import "FNTVSignature.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <math.h>

static NSString *Digest(NSString *text) {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5([bytes bytes], (CC_LONG)[bytes length], digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for (NSUInteger i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
static NSString *EncodedPath(NSURL *url) {
    if (![[url path] length]) return @"/";
    NSString *absolute = [url absoluteString];
    NSRange scheme = [absolute rangeOfString:@"://"];
    if (scheme.location == NSNotFound) return nil;
    NSUInteger start = NSMaxRange(scheme);
    NSRange slash = [absolute rangeOfString:@"/" options:0 range:NSMakeRange(start, [absolute length]-start)];
    if (slash.location == NSNotFound) return @"/";
    NSString *path = [absolute substringFromIndex:slash.location];
    NSRange end = [path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    return end.location == NSNotFound ? path : [path substringToIndex:end.location];
}
static NSString *DecodedQuery(NSURL *url) {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    for (NSString *part in [[url query] componentsSeparatedByString:@"&"]) {
        if (![part length]) continue;
        NSRange equals = [part rangeOfString:@"="];
        NSString *key = equals.location == NSNotFound ? part : [part substringToIndex:equals.location];
        NSString *value = equals.location == NSNotFound ? @"" : [part substringFromIndex:NSMaxRange(equals)];
        key = [[key stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        value = [[value stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (key && value && ![value isEqualToString:@"undefined"] && ![value isEqualToString:@"null"]) [parameters setObject:value forKey:key];
    }
    NSArray *keys = [[parameters allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        for (NSUInteger i = 0; i < MIN([a length], [b length]); i++) {
            unichar x = [a characterAtIndex:i], y = [b characterAtIndex:i];
            if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a length] < [b length] ? NSOrderedAscending : ([a length] > [b length] ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:[keys count]];
    for (NSString *key in keys) [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, [parameters objectForKey:key]]];
    return [pairs componentsJoinedByString:@"&"];
}
BOOL FNTVNeedsRequestSignature(NSURL *url, NSString *method) {
    NSString *path = EncodedPath(url);
    if ([path isEqualToString:@"/v/api/v1/play/record"]) return [[method uppercaseString] isEqualToString:@"DELETE"];
    if ([path isEqualToString:@"/v/api/v1/task/running"] || [path isEqualToString:@"/v/api/v1/subtitle/upload"]) return NO;
    for (NSString *prefix in [NSArray arrayWithObjects:@"/v/api/v1/sys/img/", @"/v/api/v1/img/", @"/v/api/v1/concat/", @"/v/api/v1/media/", nil]) if ([path hasPrefix:prefix]) return NO;
    return YES;
}
NSString *FNTVRequestSignature(NSURL *url, NSString *method, NSData *body, NSString *nonce, NSString *timestamp) {
    NSString *path = EncodedPath(url);
    NSString *payload = [[method uppercaseString] isEqualToString:@"GET"] ? DecodedQuery(url) : (body ? [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] autorelease] : @"");
    if (!path || !payload || ![nonce length] || ![timestamp length]) return nil;
    // These are public client protocol constants from the NAS's shipped Web code, not account secrets.
    NSString *input = [NSString stringWithFormat:@"NDzZTVxnRKP8Z0jXg1VAMonaG8akvh_%@_%@_%@_%@_16CCEB3D-AB42-077D-36A1-F355324E4237", path, nonce, timestamp, Digest(payload)];
    return [NSString stringWithFormat:@"nonce=%@&timestamp=%@&sign=%@", nonce, timestamp, Digest(input)];
}
NSString *FNTVNewRequestSignature(NSURL *url, NSString *method, NSData *body) {
    uint32_t random = 0;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(random), (uint8_t *)&random) != errSecSuccess) return nil;
    NSString *nonce = [NSString stringWithFormat:@"%u", 100000 + random%900000];
    NSString *timestamp = [NSString stringWithFormat:@"%lld", (long long)floor([[NSDate date] timeIntervalSince1970]*1000.)];
    return FNTVRequestSignature(url, method, body, nonce, timestamp);
}
