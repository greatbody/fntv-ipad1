#import <Foundation/Foundation.h>
#import "FNTVHTTP.h"
#import "FNTVHLSProxy.h"
#include <assert.h>
#import <dispatch/dispatch.h>

static int releasedProbe = 0;
@interface FNTVLifetimeProbe : NSObject
@end
@implementation FNTVLifetimeProbe
- (void)dealloc { releasedProbe++; [super dealloc]; }
@end
@interface FNTVReentrantOwner : NSObject { @public NSOperation *operation; }
@end
@implementation FNTVReentrantOwner
- (void)dealloc { [operation cancel]; [operation release]; releasedProbe++; [super dealloc]; }
@end
static NSData *Get(NSURL *url, NSInteger *status) {
    NSHTTPURLResponse *response = nil; NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5] returningResponse:&response error:&error];
    *status = [response statusCode]; return data;
}
static NSDictionary *WaitMetrics(NSString *path, double minimumStart) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    do {
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        id report = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL] : nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        if ([report isKindOfClass:[NSDictionary class]] && [[report objectForKey:@"startedAtUnix"] doubleValue] >= minimumStart && [[report objectForKey:@"allFinished"] boolValue] && ([[attributes objectForKey:NSFilePosixPermissions] unsignedIntegerValue]&0777)==0600) return report;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    } while ([deadline timeIntervalSinceNow]>0);
    return nil;
}
static void CheckMetricsPrivacy(NSDictionary *report) {
    assert(report);
    NSSet *top = [NSSet setWithArray:@[@"schemaVersion",@"appBuild",@"startedAtUnix",@"stoppedAtUnix",@"writtenAtUnix",@"sessionSeconds",@"drainSeconds",@"accepted",@"finished",@"queueRejected",@"maxPending",@"unrecorded",@"allFinished",@"requests"]];
    NSSet *fields = [NSSet setWithArray:@[@"method",@"kind",@"acceptedOffsetSeconds",@"clientStatus",@"rewriteSeconds",@"queueRejected",@"queueWaitSeconds",@"requestSeconds",@"upstreamResponseSeconds",@"firstByteSeconds",@"upstreamCompleteSeconds",@"upstreamStatus",@"upstreamBytes",@"sendSeconds",@"sentBytes",@"sendError",@"errorCode",@"upstreamFinished",@"cancelled",@"finishedAfterStop"]];
    for (NSString *key in report) {
        assert([top containsObject:key]);
        if (![key isEqualToString:@"requests"]) assert([[report objectForKey:key] isKindOfClass:[NSNumber class]]);
    }
    NSArray *rows = [report objectForKey:@"requests"]; assert([rows isKindOfClass:[NSArray class]] && [rows count]<=64);
    for (NSDictionary *row in rows) for (NSString *key in row) {
        assert([fields containsObject:key]); id value = [row objectForKey:key];
        if ([key isEqualToString:@"method"]) assert(([@[@"GET",@"HEAD",@"OTHER"] containsObject:value]));
        else if ([key isEqualToString:@"kind"]) assert(([@[@"playlist",@"segment",@"unknown"] containsObject:value]));
        else assert([value isKindOfClass:[NSNumber class]]);
    }
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
    NSString *text = [[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] autorelease];
    assert([text rangeOfString:@"http://"].location==NSNotFound && [text rangeOfString:@"fixture-token"].location==NSNotFound && [text rangeOfString:@".m3u8"].location==NSNotFound);
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    assert(argc == 3);
    NSString *metricsPath = [NSString stringWithUTF8String:argv[2]];
    NSURL *origin = [NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]];
    assert(FNTVSameOrigin(origin, [NSURL URLWithString:@"/relative" relativeToURL:origin]));
    assert(!FNTVSameOrigin(origin, [NSURL URLWithString:@"https://example.test/"]));
    assert(!FNTVSameOrigin([NSURL URLWithString:@"http://user:pass@localhost:80"], [NSURL URLWithString:@"http://localhost:80"]));
    assert(FNTVSameOrigin([NSURL URLWithString:@"http://localhost"], [NSURL URLWithString:@"http://localhost:80"]));
    assert(!FNTVSameOrigin([NSURL URLWithString:@"http://localhost:81"], [NSURL URLWithString:@"http://localhost:80"]));
    NSURL *imageOrigin = [NSURL URLWithString:@"http://fixture.invalid:5666"];
    assert([[FNTVImageURL(imageOrigin, @"/poster.webp") absoluteString] isEqualToString:@"http://fixture.invalid:5666/v/api/v1/sys/img/poster.webp?w=320"]);
    assert([[FNTVImageURL(imageOrigin, @"poster.webp?x=%E4%B8%AD&w=900&v=1") absoluteString] isEqualToString:@"http://fixture.invalid:5666/v/api/v1/sys/img/poster.webp?x=%E4%B8%AD&v=1&w=320"]);
    assert([[FNTVImageURL(imageOrigin, @"http://fixture.invalid:5666/v/api/v1/sys/img/p.webp?%77=999&w=700") absoluteString] isEqualToString:@"http://fixture.invalid:5666/v/api/v1/sys/img/p.webp?w=320"]);
    assert(!FNTVImageURL(imageOrigin, @"http://outside.invalid/poster.webp"));
    assert(!FNTVImageURL(imageOrigin, @"/poster.webp#fragment"));
    assert(!FNTVImageURL(imageOrigin, @""));
    assert(FNTVImageDimensionsAllowed(320, 480));
    assert(FNTVImageDimensionsAllowed(2000, 2000));
    assert(FNTVImageDimensionsAllowed(4096, 976));
    assert(!FNTVImageDimensionsAllowed(2000, 3000));
    assert(!FNTVImageDimensionsAllowed(4096, 977));
    assert(!FNTVImageDimensionsAllowed(4097, 1));
    assert(!FNTVImageDimensionsAllowed(0, 100));
    assert(!FNTVImageDimensionsAllowed(-1, 100));
    NSDictionary *normalized = FNTVNormalizeItem(@{@"guid": @"g", @"poster_list": @[@"/poster.webp"], @"watched_ts": @42, @"duration": @100, @"overview": [NSNull null]});
    assert([[normalized objectForKey:@"poster"] isEqualToString:@"/poster.webp"]);
    assert([[normalized objectForKey:@"resumeSeconds"] intValue] == 42);
    assert([[normalized objectForKey:@"overview"] isEqualToString:@""]);
    assert([FNTVNormalizeItems(@[[NSNull null], @{}, normalized]) count] == 1);
    FNTVLifetimeProbe *probe = [[FNTVLifetimeProbe alloc] init];
    FNTVOperation *cancelled = [[FNTVOperation alloc] initWithWork:^id(NSOperation *operation, NSError **failure) { (void)operation; (void)failure; return [probe description]; } completion:^(id value, NSError *failure) { (void)value; (void)failure; assert(NO); }];
    [probe release]; assert(releasedProbe == 0); [cancelled cancel]; assert(releasedProbe == 1); [cancelled release];
    FNTVReentrantOwner *owner = [[FNTVReentrantOwner alloc] init];
    FNTVOperation *reentrant = [[FNTVOperation alloc] initWithWork:^id(NSOperation *operation, NSError **failure) { (void)operation; (void)failure; return @1; } completion:^(id value, NSError *failure) { (void)value; (void)failure; (void)[owner description]; }];
    owner->operation = [reentrant retain]; [owner release];
    [reentrant cancel]; assert(releasedProbe == 2); [reentrant release];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    dispatch_semaphore_t started = dispatch_semaphore_create(0), proceed = dispatch_semaphore_create(0);
    __block BOOL called = NO;
    FNTVOperation *running = [[FNTVOperation alloc] initWithWork:^id(NSOperation *operation, NSError **failure) {
        (void)operation; (void)failure;
        dispatch_semaphore_signal(started); dispatch_semaphore_wait(proceed, DISPATCH_TIME_FOREVER); return @42;
    } completion:^(id value, NSError *failure) { (void)value; (void)failure; called = YES; }];
    [queue addOperation:running];
    assert(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
    [running cancel]; dispatch_semaphore_signal(proceed); [queue waitUntilAllOperationsAreFinished];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    assert(!called); [running release]; [queue release]; dispatch_release(started); dispatch_release(proceed);
    NSError *error = nil;
    NSData *data = [FNTVHTTP fetchURL:[[NSURL URLWithString:@"/auth" relativeToURL:origin] absoluteURL] origin:origin method:@"GET" body:nil token:@"fixture-token" range:nil limit:1024 operation:nil streamFD:-1 response:NULL error:&error];
    assert(data && !error && [data length] == 2);
    data = [FNTVHTTP fetchURL:[[NSURL URLWithString:@"/redirect" relativeToURL:origin] absoluteURL] origin:origin method:@"GET" body:nil token:@"fixture-token" range:nil limit:1024 operation:nil streamFD:-1 response:NULL error:&error];
    assert(!data && [error code] == 403);
    data = [FNTVHTTP fetchURL:[[NSURL URLWithString:@"/big" relativeToURL:origin] absoluteURL] origin:origin method:@"GET" body:nil token:@"fixture-token" range:nil limit:16 operation:nil streamFD:-1 response:NULL error:&error];
    assert(!data && [error code] == 413);
    data = [FNTVHTTP fetchURL:[[NSURL URLWithString:@"/huge-poster.webp" relativeToURL:origin] absoluteURL] origin:origin method:@"GET" body:nil token:@"fixture-token" range:nil limit:4*1024*1024 operation:nil streamFD:-1 response:NULL error:&error];
    assert(!data && [error code] == 413);
    FNTVHLSProxy *proxy = [[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:metricsPath];
    NSURL *entry = [proxy startWithURL:[[NSURL URLWithString:@"/master.m3u8" relativeToURL:origin] absoluteURL] error:&error];
    assert(entry && [[entry host] isEqualToString:@"127.0.0.1"]);
    assert(![proxy localURLForURL:[NSURL URLWithString:@"http://outside.test/secret"]]);
    NSString *bad = [proxy rewritePlaylist:@"#EXTM3U\nhttp://outside.test/media.ts\n" source:origin error:&error];
    assert(!bad && [error code] == 403);
    bad = [proxy rewritePlaylist:@"#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"http://outside.test/key\"\n" source:origin error:&error];
    assert(!bad);
    NSInteger status = 0;
    data = Get(entry, &status); assert(status == 200);
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    assert([text hasPrefix:@"#EXTM3U"]);
    assert([text rangeOfString:[origin absoluteString]].location == NSNotFound);
    NSMutableArray *segments = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if ([line hasPrefix:@"http://127.0.0.1"]) [segments addObject:line];
    assert([segments count] == 1);
    data = Get([NSURL URLWithString:[segments objectAtIndex:0]], &status); assert(status == 200 && [data length] == 6);
    NSMutableURLRequest *rangeRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[segments objectAtIndex:0]]];
    [rangeRequest setValue:@"bytes=2-4" forHTTPHeaderField:@"Range"];
    NSHTTPURLResponse *rangeResponse = nil;
    data = [NSURLConnection sendSynchronousRequest:rangeRequest returningResponse:&rangeResponse error:NULL];
    assert([rangeResponse statusCode] == 206 && [data length] == 3);
    NSURL *unauthorized = [NSURL URLWithString:@"/no-nonce/0" relativeToURL:entry];
    Get(unauthorized, &status); assert(status == 404);
    FNTVHLSProxy *replacement = [[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:metricsPath];
    NSURL *replacementEntry = [replacement startWithURL:[[NSURL URLWithString:@"/master.m3u8" relativeToURL:origin] absoluteURL] error:&error];
    assert(replacementEntry && ![[entry absoluteString] isEqualToString:[replacementEntry absoluteString]]);
    [proxy stop];
    assert(![proxy stopIfPlaybackURL:entry]);
    assert(![replacement stopIfPlaybackURL:entry]);
    assert(![replacement stopIfPlaybackURL:nil]);
    assert(![replacement stopIfPlaybackURL:(NSURL *)[replacementEntry absoluteString]]);
    assert(![replacement stopIfPlaybackURL:[NSURL URLWithString:[[replacementEntry absoluteString] stringByAppendingString:@"?stale=1"]]]);
    data = Get(replacementEntry, &status); assert(status == 200 && [data length]);
    assert([replacement stopIfPlaybackURL:[NSURL URLWithString:[replacementEntry absoluteString]]]);
    assert(![replacement stopIfPlaybackURL:replacementEntry]);
    data = Get(replacementEntry, &status); assert(!data && status == 0);
    NSDictionary *reported = WaitMetrics(metricsPath, 0); CheckMetricsPrivacy(reported);
    assert([[reported objectForKey:@"accepted"] unsignedIntegerValue] == [[reported objectForKey:@"finished"] unsignedIntegerValue]);

    NSString *slowPath = [metricsPath stringByAppendingString:@".slow"];
    FNTVHLSProxy *slow = [[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:slowPath];
    NSURL *slowEntry = [slow startWithURL:[[NSURL URLWithString:@"/slow-segment.ts" relativeToURL:origin] absoluteURL] error:NULL];
    NSOperationQueue *slowQueue = [[NSOperationQueue alloc] init];
    [slowQueue addOperationWithBlock:^{
        NSAutoreleasePool *threadPool = [[NSAutoreleasePool alloc] init];
        NSInteger slowStatus; Get(slowEntry, &slowStatus);
        [threadPool drain];
    }];
    data = [FNTVHTTP fetchURL:[[NSURL URLWithString:@"/wait-slow-start" relativeToURL:origin] absoluteURL] origin:origin method:@"GET" body:nil token:@"fixture-token" range:nil limit:1024 operation:nil streamFD:-1 response:NULL error:NULL];
    assert(data);
    [slow stop];
    assert(![[NSFileManager defaultManager] fileExistsAtPath:slowPath]);
    NSDictionary *slowReport = WaitMetrics(slowPath, 0); CheckMetricsPrivacy(slowReport);
    assert([[slowReport objectForKey:@"accepted"] unsignedIntegerValue]==1 && [[slowReport objectForKey:@"finished"] unsignedIntegerValue]==1);
    assert([[[[slowReport objectForKey:@"requests"] objectAtIndex:0] objectForKey:@"finishedAfterStop"] boolValue]);
    NSData *beforeRepeat = [NSData dataWithContentsOfFile:slowPath];
    [slow stop]; [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    assert([beforeRepeat isEqual:[NSData dataWithContentsOfFile:slowPath]]);
    [slowQueue waitUntilAllOperationsAreFinished]; [slowQueue release]; [slow release];

    NSString *boundedPath = [metricsPath stringByAppendingString:@".bounded"];
    FNTVHLSProxy *bounded = [[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:boundedPath];
    NSURL *boundedEntry = [bounded startWithURL:[[NSURL URLWithString:@"/master.m3u8" relativeToURL:origin] absoluteURL] error:NULL];
    for (NSUInteger i=0;i<70;i++) { Get([NSURL URLWithString:@"/unknown" relativeToURL:boundedEntry], &status); assert(status==404); }
    [bounded stop];
    NSDictionary *boundedReport = WaitMetrics(boundedPath, 0); CheckMetricsPrivacy(boundedReport);
    assert([[boundedReport objectForKey:@"requests"] count]==64 && [[boundedReport objectForKey:@"accepted"] unsignedIntegerValue]==70 && [[boundedReport objectForKey:@"unrecorded"] unsignedIntegerValue]==6);
    // A future/newer report must not be replaced by a late completion from this process.
    NSMutableDictionary *newer = [NSMutableDictionary dictionaryWithDictionary:boundedReport];
    [newer setObject:@4102444800 forKey:@"startedAtUnix"];
    NSData *newerBytes = [NSJSONSerialization dataWithJSONObject:newer options:0 error:NULL];
    assert([newerBytes writeToFile:metricsPath atomically:YES]);
    FNTVHLSProxy *late = [[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:metricsPath];
    [late startWithURL:[[NSURL URLWithString:@"/master.m3u8" relativeToURL:origin] absoluteURL] error:NULL]; [late stop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    assert([newerBytes isEqual:[NSData dataWithContentsOfFile:metricsPath]]);
    [late release]; [bounded release]; [replacement release]; [proxy release];
    puts("PASS: image URL/size/4MiB guards, normalization, origin/redirect/body limits, HLS rewrite, nonce, auth headers, streaming, byte ranges and stale A/current B discard isolation, bounded/private metrics and stop-drain publication");
    [pool drain]; return 0;
}
