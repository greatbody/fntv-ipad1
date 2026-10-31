#import "FNTVLogin.h"
#import "FNTVHTTP.h"
#import <CommonCrypto/CommonDigest.h>

NSDictionary *FNTVLoginRequest(NSString *version, NSString *username, NSString *password, NSError **error) {
    NSArray *parts = [FNTVString(version) componentsSeparatedByString:@"."];
    BOOL valid = [parts count] >= 2 && [parts count] <= 4;
    for (NSString *part in parts) {
        if (![part length] || [part length] > 6 || [part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) valid = NO;
    }
    if (!valid) { if (error) *error = FNTVError(502, @"无法确认服务器的登录协议，请检查服务器地址后重试。"); return nil; }
    NSInteger target[] = {0, 9, 5, 0}; BOOL useV2 = YES;
    for (NSUInteger i = 0; i < 4; i++) {
        NSInteger current = i < [parts count] ? [[parts objectAtIndex:i] integerValue] : 0;
        if (current != target[i]) { useV2 = current > target[i]; break; }
    }
    if (![FNTVString(username) length] || ![FNTVString(password) length]) { if (error) *error = FNTVError(400, @"请输入用户名和密码。"); return nil; }
    NSData *utf8 = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8 || [utf8 length] > 16384) { if (error) *error = FNTVError(400, @"密码格式无效或过长。"); return nil; }
    NSString *encoded = password;
    if (useV2) {
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256([utf8 bytes], (CC_LONG)[utf8 length], digest);
        NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
        for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
        encoded = hex;
    }
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:username, @"username", encoded, @"password", @"trimemedia-web", @"app_name", nil];
    return [NSDictionary dictionaryWithObjectsAndKeys:(useV2 ? @"/v/api/v2/user/loginByPassword" : @"/v/api/v1/login"), @"path", body, @"body", nil];
}
NSString *FNTVLoginToken(id payload, NSError **error) {
    NSString *token = [payload isKindOfClass:[NSDictionary class]] ? FNTVString([payload objectForKey:@"token"]) : @"";
    if (![token length] || [token length] > 8192 || [token rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        if (error) *error = FNTVError(502, @"登录响应中没有有效的会话。"); return nil;
    }
    return token;
}

BOOL FNTVIsAuthenticationFailure(NSInteger code, NSString *message) {
    (void)message;
    return code == -2;
}
