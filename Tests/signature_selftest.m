#import <Foundation/Foundation.h>
#import "FNTVSignature.h"
#include <assert.h>
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; assert(argc == 2);
    NSData *fixtureData = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:NULL]; assert([fixtures count] == 7);
    for (NSDictionary *fixture in fixtures) {
        NSString *signature = FNTVRequestSignature([NSURL URLWithString:[fixture objectForKey:@"url"]], [fixture objectForKey:@"method"], [[fixture objectForKey:@"body"] dataUsingEncoding:NSUTF8StringEncoding], [fixture objectForKey:@"nonce"], [fixture objectForKey:@"timestamp"]);
        assert([signature isEqualToString:[fixture objectForKey:@"expected"]]);
    }
    assert(FNTVNeedsRequestSignature([NSURL URLWithString:@"http://fixture.invalid/v/api/v1/item/list"], @"POST"));
    assert(!FNTVNeedsRequestSignature([NSURL URLWithString:@"http://fixture.invalid/v/api/v1/play/record"], @"POST"));
    assert(FNTVNeedsRequestSignature([NSURL URLWithString:@"http://fixture.invalid/v/api/v1/play/record"], @"DELETE"));
    assert(!FNTVNeedsRequestSignature([NSURL URLWithString:@"http://fixture.invalid/v/api/v1/sys/img/poster.webp"], @"GET"));
    assert(!FNTVNeedsRequestSignature([NSURL URLWithString:@"http://fixture.invalid/v/api/v1/media/session/1.ts"], @"GET"));
    puts("PASS: authx empty/Unicode/sorted/duplicate queries, encoded paths, exact JSON bytes and exemption rules");
    [pool drain]; return 0;
}
