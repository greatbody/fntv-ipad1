#import <Foundation/Foundation.h>
#import "FNTVLogin.h"
#include <assert.h>

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSError *error = nil;
    NSDictionary *request = FNTVLoginRequest(@"0.9.4", @"fixture-user", @"password", &error);
    assert(request && !error);
    assert([[request objectForKey:@"path"] isEqualToString:@"/v/api/v1/login"]);
    assert([[[request objectForKey:@"body"] objectForKey:@"password"] isEqualToString:@"password"]);
    for (NSString *version in @[@"0.9.5", @"0.9.8", @"0.10.0", @"1.0", @"0.9.5.0"]) {
        request = FNTVLoginRequest(version, @"fixture-user", @"password", &error);
        assert([[request objectForKey:@"path"] isEqualToString:@"/v/api/v2/user/loginByPassword"]);
        assert([[[request objectForKey:@"body"] objectForKey:@"password"] isEqualToString:@"5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"]);
        assert([[[request objectForKey:@"body"] objectForKey:@"app_name"] isEqualToString:@"trimemedia-web"]);
    }
    request = FNTVLoginRequest(@"0.9.8", @"fixture-user", @"密码", &error);
    assert([[[request objectForKey:@"body"] objectForKey:@"password"] isEqualToString:@"a621ab606db2a11f63edc576a729843b8269250dc324206871d90635ac5e531c"]);
    for (id version in @[@"", @"unknown", @"0.9.x", @"0..8", @"0.9.8-beta", @"０.９.８", @"0.9.8.0.1", [NSNull null]]) assert(!FNTVLoginRequest(version, @"fixture-user", @"password", &error));
    assert(!FNTVLoginRequest(@"0.9.8", @"", @"password", &error));
    assert(!FNTVLoginRequest(@"0.9.8", @"fixture-user", @"", &error));
    assert([FNTVLoginToken(@{@"token": @"fixture-token"}, &error) isEqualToString:@"fixture-token"]);
    for (id invalid in @[[NSNull null], @[], @{}, @{@"token": @42}, @{@"token": @""}, @{@"token": @"bad\r\nheader"}]) assert(!FNTVLoginToken(invalid, &error));
    assert(FNTVIsAuthenticationFailure(-2, @"anything"));
    assert(!FNTVIsAuthenticationFailure(5000, @"invalid sign"));
    assert(!FNTVIsAuthenticationFailure(5000, @" INVALID SIGN "));
    assert(!FNTVIsAuthenticationFailure(5000, @"transcoding error"));
    assert(!FNTVIsAuthenticationFailure(5000, nil));
    assert(!FNTVIsAuthenticationFailure(-15, @"password incorrect"));
    assert(!FNTVIsAuthenticationFailure(-5, @"permission denied"));
    puts("PASS: login version branches, ASCII/UTF-8 SHA256 vectors, request fields token response validation and auth error classification");
    [pool drain]; return 0;
}
