#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import "FNTVHLSProxy.h"
#import "FNTVHTTP.h"
#include <assert.h>

static NSString *SHA256(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], hash);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [result appendFormat:@"%02x", hash[i]];
    return result;
}
static FNTVHLSProxy *FixedProxy(NSURL *origin) {
    FNTVHLSProxy *proxy = [[[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:nil] autorelease];
    [proxy setValue:@"0123456789abcdef0123456789abcdef" forKey:@"nonce"];
    [proxy setValue:@12345 forKey:@"port"];
    return proxy;
}
static NSString *Playlist(void) {
    NSMutableString *list = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-KEY:METHOD=AES-128,URI=\"../keys/key.bin?v=1\"\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"audio/index.m3u8?lang=en\"\n"];
    for (NSUInteger i=0;i<1393;i++) [list appendFormat:@"#EXTINF:4.0,\nseg/%04lu.ts?part=%lu&label=alpha%%20beta\n",(unsigned long)i,(unsigned long)i];
    [list appendString:@"./seg/0000.ts?part=0&label=alpha%20beta\nhttp://fixture.invalid:5666/movie/seg/0000.ts?part=0&label=alpha%20beta\nseg/0000.ts?label=alpha%20beta&part=0\nseg/0000.ts?part=1&label=alpha%20beta\n#EXT-X-ENDLIST\n"];
    return list;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSURL *origin = [NSURL URLWithString:@"http://fixture.invalid:5666"];
    NSURL *source = [NSURL URLWithString:@"http://fixture.invalid:5666/movie/master.m3u8"];
    FNTVHLSProxy *ordinary = [[[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token"] autorelease];
#if FNTV_DIAGNOSTICS
    assert([ordinary valueForKey:@"metricsPath"]);
#else
    assert(![ordinary valueForKey:@"metricsPath"]);
#endif
    FNTVHLSProxy *proxy = FixedProxy(origin);
    NSString *input = Playlist(); NSError *error = nil;
    double start = FNTVMonotonicTime();
    NSString *first = [proxy rewritePlaylist:input source:source error:&error];
    double firstSeconds = FNTVMonotonicTime()-start;
    start = FNTVMonotonicTime();
    NSString *second = [proxy rewritePlaylist:input source:source error:&error];
    double repeatSeconds = FNTVMonotonicTime()-start;
    assert(first && !error && [first isEqualToString:second]);
#ifdef FNTV_RECORD_BASELINE
    printf("input_sha256=%s\noutput_sha256=%s\nunique=%lu\nfirst_seconds=%.6f\nrepeat_seconds=%.6f\n",[SHA256(input) UTF8String],[SHA256(first) UTF8String],(unsigned long)[[proxy valueForKey:@"urls"] count],firstSeconds,repeatSeconds);
    [pool drain]; return 0;
#else
    // Captured from the unmodified build11 scanner with the same fixed nonce/port.
    assert([SHA256(input) isEqualToString:@"4a72b25b07e0acc7bebfcfed894a7ad0b5dc894075be07d23af2aa5f4024999d"]);
    assert([SHA256(first) isEqualToString:@"f7a748a7d687092f3be0fa94fdf9d83df31af3c7b7e027ea766047baafd380b7"]);
    assert([[proxy valueForKey:@"urls"] count] == 1397);
#endif
    NSURL *absolute = [NSURL URLWithString:@"http://fixture.invalid:5666/movie/seg/0000.ts?part=0&label=alpha%20beta"];
    NSURL *relative = [[NSURL URLWithString:@"./seg/0000.ts?part=0&label=alpha%20beta" relativeToURL:source] absoluteURL];
    assert([absolute isEqual:relative]);
    assert([[proxy localURLForURL:absolute] isEqual:[proxy localURLForURL:relative]]);
    NSURL *differentQuery = [NSURL URLWithString:@"http://fixture.invalid:5666/movie/seg/0000.ts?part=1&label=alpha%20beta"];
    assert(![[proxy localURLForURL:absolute] isEqual:[proxy localURLForURL:differentQuery]]);
    NSArray *variants = @[
        @"http://fixture.invalid:5666/movie/a.ts?q=1",
        @"http://fixture.invalid:5666/movie/./a.ts?q=1",
        @"http://fixture.invalid:5666/movie/a.ts?q=%31",
        @"http://fixture.invalid:5666/movie/a.ts?q=1&b=2",
        @"http://fixture.invalid:5666/movie/a.ts?b=2&q=1"
    ];
    for (NSString *left in variants) for (NSString *right in variants) {
        NSURL *a=[NSURL URLWithString:left], *b=[NSURL URLWithString:right];
        assert([[proxy localURLForURL:a] isEqual:[proxy localURLForURL:b]] == [a isEqual:b]);
    }
    assert(![proxy localURLForURL:[NSURL URLWithString:@"http://outside.invalid/a.ts"]]);
    assert(![proxy localURLForURL:[NSURL URLWithString:@"http://fixture.invalid:5666/a.ts#fragment"]]);

    FNTVHLSProxy *concurrent = FixedProxy(origin);
    NSMutableDictionary *byUpstream = [NSMutableDictionary dictionary];
    dispatch_apply(512, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^(size_t i) {
        NSAutoreleasePool *threadPool = [[NSAutoreleasePool alloc] init];
        NSURL *upstream = [NSURL URLWithString:[NSString stringWithFormat:@"http://fixture.invalid:5666/concurrent/%lu.ts?v=1",(unsigned long)(i%32)]];
        NSURL *local = [concurrent localURLForURL:upstream]; assert(local);
        @synchronized(byUpstream) {
            NSURL *existing = [byUpstream objectForKey:upstream];
            if (existing) assert([existing isEqual:local]); else [byUpstream setObject:local forKey:upstream];
        }
        [threadPool drain];
    });
    assert([byUpstream count]==32 && [[concurrent valueForKey:@"urls"] count]==32);
    assert([[NSSet setWithArray:[byUpstream allValues]] count]==32);
    [concurrent stop];
    assert([[concurrent valueForKey:@"urls"] count]==0);
    assert([[[[concurrent localURLForURL:absolute] path] lastPathComponent] isEqualToString:@"0"]);

    FNTVHLSProxy *limited = FixedProxy(origin);
    for (NSUInteger i=0;i<10000;i++) assert(([limited localURLForURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://fixture.invalid:5666/limit/%lu.ts",(unsigned long)i]]]));
    NSURL *oldURL = [NSURL URLWithString:@"http://fixture.invalid:5666/limit/0.ts"];
    assert([limited localURLForURL:oldURL]);
    assert(![limited localURLForURL:[NSURL URLWithString:@"http://fixture.invalid:5666/limit/10000.ts"]]);
    [limited stop];
    assert([[[[limited localURLForURL:oldURL] path] lastPathComponent] isEqualToString:@"0"]);

    FNTVHLSProxy *sessionA = [[[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:nil] autorelease];
    FNTVHLSProxy *sessionB = [[[FNTVHLSProxy alloc] initWithOrigin:origin token:@"fixture-token" metricsPath:nil] autorelease];
    NSURL *a = [sessionA localURLForURL:absolute], *b = [sessionB localURLForURL:absolute];
    assert(![a isEqual:b]); [sessionA stop];
    assert([[sessionB localURLForURL:absolute] isEqual:b]);
    printf("PASS: 1393-URI byte-equivalence, NSURL equality/query, concurrent deduplication, limit/stop/session isolation; first=%.6fs repeat=%.6fs\n",firstSeconds,repeatSeconds);
    [pool drain]; return 0;
}
