#import "FNTVHLSProxy.h"
#import "FNTVHTTP.h"
#import <Security/Security.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>
#import <dispatch/dispatch.h>
#import <errno.h>

static BOOL ProxyWrite(int fd, NSData *data, FNTVHTTPMetrics *metrics) {
    const char *p = [data bytes]; NSUInteger remaining = [data length];
    while (remaining) {
        NSTimeInterval before = metrics ? FNTVMonotonicTime() : 0;
        ssize_t n = send(fd, p, remaining, 0);
        int savedError = n < 0 ? errno : 0;
        if (metrics) { metrics->sendSeconds += FNTVMonotonicTime() - before; if (n > 0) metrics->sentBytes += n; else metrics->sendError = savedError; }
        if (n <= 0) return NO; p += n; remaining -= n;
    }
    return YES;
}
static void ProxyResponse(int fd, NSInteger status, NSData *data, BOOL head, NSString *type, FNTVHTTPMetrics *metrics) {
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %ld Status\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Type: %@\r\nContent-Length: %lu\r\n\r\n", (long)status, type, (unsigned long)[data length]];
    if (ProxyWrite(fd, [header dataUsingEncoding:NSUTF8StringEncoding], metrics) && !head) ProxyWrite(fd, data, metrics);
}
static void WriteMetricsReport(NSDictionary *report, NSString *path) {
    if (!report || ![path length]) return;
    static dispatch_queue_t writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ writer = dispatch_queue_create("ink.sunrui.fntv.proxy-metrics", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(writer, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        NSData *oldData = [[attributes objectForKey:NSFileSize] unsignedLongLongValue] <= 1024*1024 ? [NSData dataWithContentsOfFile:path] : nil;
        id old = oldData ? [NSJSONSerialization JSONObjectWithData:oldData options:0 error:NULL] : nil;
        if (![old isKindOfClass:[NSDictionary class]] || [[old objectForKey:@"startedAtUnix"] doubleValue] <= [[report objectForKey:@"startedAtUnix"] doubleValue]) {
            NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithDictionary:report];
            [saved setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:@"writtenAtUnix"];
            NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:NULL];
            if ([data writeToFile:path options:NSDataWritingAtomic error:NULL]) [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:@0600 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
        }
        [pool drain];
    });
}
@interface FNTVHLSProxy ()
- (void)finishMetricsRecord:(NSMutableDictionary *)record timing:(FNTVHTTPMetrics)timing acceptedAt:(NSTimeInterval)accepted;
- (NSDictionary *)takeMetricsReport;
- (void)serveClient:(int)fd operation:(NSOperation *)operation record:(NSMutableDictionary *)record timing:(FNTVHTTPMetrics *)timing;
@end
@implementation FNTVHLSProxy
- (id)initWithOrigin:(NSURL *)origin token:(NSString *)token {
    NSString *path = nil;
#if FNTV_DIAGNOSTICS
    NSArray *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    path = [documents count] ? [[documents objectAtIndex:0] stringByAppendingPathComponent:@"FNTV-proxy-metrics.json"] : nil;
#endif
    return [self initWithOrigin:origin token:token metricsPath:path];
}
- (id)initWithOrigin:(NSURL *)origin token:(NSString *)token metricsPath:(NSString *)path {
    if ((self = [super init])) {
        _origin = [origin copy]; _token = [token copy]; _listener = -1;
        _metricsPath = [path copy]; _metricsRows = [[NSMutableArray alloc] init];
        _urls = [[NSMutableDictionary alloc] init]; _pathsByUpstream = [[NSMutableDictionary alloc] init]; _clientSockets = [[NSMutableSet alloc] init]; _connections = [[NSOperationQueue alloc] init];
        [_connections setMaxConcurrentOperationCount:3];
        unsigned char bytes[16];
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != 0) { [self release]; return nil; }
        NSMutableString *nonce = [NSMutableString string];
        for (int i = 0; i < 16; ++i) [nonce appendFormat:@"%02x", bytes[i]];
        _nonce = [nonce copy];
    }
    return self;
}
- (NSURL *)localURLForURL:(NSURL *)url {
    if (!FNTVSameOrigin(url, _origin) || [url fragment]) return nil;
    @synchronized(self) {
        NSString *key = [_pathsByUpstream objectForKey:url];
        if (!key) {
            // Bound the map to one feature-length session; long live streams need eviction.
            if ([_urls count] >= 10000) return nil;
            key = [NSString stringWithFormat:@"/%@/%lu%@", _nonce, (unsigned long)[_urls count], [[[url path] lowercaseString] hasSuffix:@".m3u8"] ? @".m3u8" : @""];
            [_urls setObject:url forKey:key];
            [_pathsByUpstream setObject:key forKey:url];
        }
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu%@", (unsigned long)_port, key]];
    }
}
- (NSURL *)startWithURL:(NSURL *)url error:(NSError **)error {
    if (!FNTVSameOrigin(url, _origin)) { if (error) *error = FNTVError(403, @"播放地址不属于已配置的服务器。"); return nil; }
    @synchronized(self) {
        if (_running) {
            NSURL *entry = [self localURLForURL:url];
            [_playbackURL release]; _playbackURL = [entry copy];
            return entry;
        }
        _listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in addr; memset(&addr, 0, sizeof(addr)); addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); addr.sin_port = 0;
        if (_listener < 0 || bind(_listener, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(_listener, 6) < 0) {
            if (_listener >= 0) close(_listener); _listener = -1;
            if (error) *error = FNTVError(500, @"无法启动设备内的播放连接。"); return nil;
        }
        socklen_t len = sizeof(addr); getsockname(_listener, (struct sockaddr *)&addr, &len);
        _port = ntohs(addr.sin_port); _running = YES;
        _metricsStarted = FNTVMonotonicTime(); _metricsStartedUnix = [[NSDate date] timeIntervalSince1970];
    }
    [NSThread detachNewThreadSelector:@selector(acceptClients:) toTarget:self withObject:[NSNumber numberWithInt:_listener]];
    NSURL *entry = [self localURLForURL:url];
    @synchronized(self) { [_playbackURL release]; _playbackURL = [entry copy]; }
    return entry;
}
- (void)acceptClients:(NSNumber *)listenerNumber {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int listener = [listenerNumber intValue];
    while (YES) {
        int fd = accept(listener, NULL, NULL); if (fd < 0) break;
        NSTimeInterval accepted = FNTVMonotonicTime();
        NSMutableDictionary *record = nil;
        @synchronized(self) {
            if (!_running) { close(fd); break; }
            _metricsAccepted++; _metricsPending++; _metricsMaxPending = MAX(_metricsMaxPending, _metricsPending);
            if ([_metricsRows count] < 64) {
                record = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"OTHER", @"method", @"unknown", @"kind",
                    [NSNumber numberWithDouble:accepted-_metricsStarted], @"acceptedOffsetSeconds", @0, @"clientStatus", @0, @"rewriteSeconds", @NO, @"queueRejected", nil];
                [_metricsRows addObject:record];
            }
        }
        if ([_connections operationCount] >= 6) {
            close(fd);
            @synchronized(self) { _metricsRejected++; }
            [record setObject:@YES forKey:@"queueRejected"];
            FNTVHTTPMetrics empty = {0};
            [self finishMetricsRecord:record timing:empty acceptedAt:accepted];
            continue;
        }
        @synchronized(self) { [_clientSockets addObject:[NSNumber numberWithInt:fd]]; }
        int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        struct timeval timeout = {15, 0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)); setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        FNTVOperation *op = [[FNTVOperation alloc] initWithWork:^id(NSOperation *operation, NSError **error) {
            (void)error;
            FNTVHTTPMetrics timing = {0};
            [record setObject:[NSNumber numberWithDouble:FNTVMonotonicTime()-accepted] forKey:@"queueWaitSeconds"];
            @try { [self serveClient:fd operation:operation record:record timing:record ? &timing : NULL]; } @finally {
                @synchronized(self) { [_clientSockets removeObject:[NSNumber numberWithInt:fd]]; close(fd); }
                [self finishMetricsRecord:record timing:timing acceptedAt:accepted];
            }
            return nil;
        } completion:nil];
        // Cancellation is checked in serveClient; queued sockets still need to reach their close.
        [_connections addOperation:op]; [op release];
    }
    close(listener);
    [pool drain];
}
- (void)serveClient:(int)fd operation:(NSOperation *)operation record:(NSMutableDictionary *)record timing:(FNTVHTTPMetrics *)timing {
    @synchronized(self) { if (!_running) return; }
    NSMutableData *input = [NSMutableData data]; BOOL complete = NO;
    while ([input length] < 16384) {
        char bytes[1024]; ssize_t n = recv(fd, bytes, sizeof(bytes), 0); if (n <= 0) return;
        [input appendBytes:bytes length:n];
        NSString *text = [[[NSString alloc] initWithData:input encoding:NSASCIIStringEncoding] autorelease];
        if ([text rangeOfString:@"\r\n\r\n"].location != NSNotFound) { complete = YES; break; }
    }
    if (!complete) { [record setObject:@431 forKey:@"clientStatus"]; ProxyResponse(fd, 431, [NSData data], NO, @"text/plain", timing); return; }
    NSString *request = [[[NSString alloc] initWithData:input encoding:NSASCIIStringEncoding] autorelease];
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSArray *first = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
    if ([first count] != 3) { [record setObject:@400 forKey:@"clientStatus"]; ProxyResponse(fd, 400, [NSData data], NO, @"text/plain", timing); return; }
    BOOL head = [[first objectAtIndex:0] isEqualToString:@"HEAD"];
    [record setObject:(head ? @"HEAD" : ([[first objectAtIndex:0] isEqualToString:@"GET"] ? @"GET" : @"OTHER")) forKey:@"method"];
    if (!head && ![[first objectAtIndex:0] isEqualToString:@"GET"]) { [record setObject:@405 forKey:@"clientStatus"]; ProxyResponse(fd, 405, [NSData data], NO, @"text/plain", timing); return; }
    NSURL *upstream = nil;
    @synchronized(self) { upstream = [[[_urls objectForKey:[first objectAtIndex:1]] retain] autorelease]; }
    if (!upstream) { [record setObject:@404 forKey:@"clientStatus"]; ProxyResponse(fd, 404, [NSData data], head, @"text/plain", timing); return; }
    NSString *range = nil;
    for (NSString *line in lines) if ([[line lowercaseString] hasPrefix:@"range:"]) {
        NSString *candidate = [[line substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^bytes=[0-9]*-[0-9]*$" options:0 error:NULL];
        if ([regex numberOfMatchesInString:candidate options:0 range:NSMakeRange(0, [candidate length])] == 1) range = candidate;
    }
    NSError *error = nil;
    BOOL playlist = [[[upstream path] lowercaseString] hasSuffix:@".m3u8"];
    [record setObject:(playlist ? @"playlist" : @"segment") forKey:@"kind"];
    if (playlist) {
        NSData *data = [FNTVHTTP fetchURL:upstream origin:_origin method:@"GET" body:nil token:_token range:nil limit:2*1024*1024 operation:operation streamFD:-1 response:NULL error:&error metrics:timing];
        NSString *raw = data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
        NSTimeInterval rewriteStarted = record ? FNTVMonotonicTime() : 0;
        NSString *rewritten = raw ? [self rewritePlaylist:raw source:upstream error:&error] : nil;
        if (record) [record setObject:[NSNumber numberWithDouble:FNTVMonotonicTime()-rewriteStarted] forKey:@"rewriteSeconds"];
        [record setObject:(rewritten ? @200 : @502) forKey:@"clientStatus"];
        if (rewritten) ProxyResponse(fd, 200, [rewritten dataUsingEncoding:NSUTF8StringEncoding], head, @"application/vnd.apple.mpegurl", timing);
        else ProxyResponse(fd, 502, [NSData data], head, @"text/plain", timing);
    } else {
        NSHTTPURLResponse *response = nil;
        [FNTVHTTP fetchURL:upstream origin:_origin method:(head ? @"HEAD" : @"GET") body:nil token:_token range:range limit:0 operation:operation streamFD:fd response:&response error:&error metrics:timing];
        [record setObject:[NSNumber numberWithInteger:response ? [response statusCode] : 502] forKey:@"clientStatus"];
        if (!response) ProxyResponse(fd, 502, [NSData data], head, @"text/plain", timing);
    }
    if (timing && error) timing->errorCode = [error code];
}
- (NSString *)rewritePlaylist:(NSString *)playlist source:(NSURL *)source error:(NSError **)error {
    if (![playlist hasPrefix:@"#EXTM3U"]) { if (error) *error = FNTVError(502, @"服务器未返回有效的 HLS 播放列表。"); return nil; }
    NSMutableArray *result = [NSMutableArray array];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"URI=\"([^\"]+)\"" options:0 error:NULL];
    for (NSString *line in [playlist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![trimmed length]) continue;
        if (![trimmed hasPrefix:@"#"]) {
            NSURL *local = [self localURLForURL:[[NSURL URLWithString:trimmed relativeToURL:source] absoluteURL]];
            if (!local) { if (error) *error = FNTVError(403, @"播放列表包含不受信任的地址。"); return nil; }
            [result addObject:[local absoluteString]];
        } else {
            NSMutableString *tag = [NSMutableString stringWithString:trimmed];
            NSArray *matches = [regex matchesInString:trimmed options:0 range:NSMakeRange(0, [trimmed length])];
            for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
                NSString *uri = [trimmed substringWithRange:[match rangeAtIndex:1]];
                NSURL *local = [self localURLForURL:[[NSURL URLWithString:uri relativeToURL:source] absoluteURL]];
                if (!local) { if (error) *error = FNTVError(403, @"播放列表包含不受信任的地址。"); return nil; }
                [tag replaceCharactersInRange:[match rangeAtIndex:1] withString:[local absoluteString]];
            }
            [result addObject:tag];
        }
    }
    return [[result componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}
- (NSDictionary *)takeMetricsReport {
    if (!_metricsStopped || _metricsPending || _metricsWritten || !_metricsStarted) return nil;
    _metricsWritten = YES;
    return [NSDictionary dictionaryWithObjectsAndKeys:@1, @"schemaVersion",
        [NSNumber numberWithInteger:[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue]], @"appBuild",
        [NSNumber numberWithDouble:_metricsStartedUnix], @"startedAtUnix",
        [NSNumber numberWithDouble:_metricsStoppedUnix], @"stoppedAtUnix",
        [NSNumber numberWithDouble:MAX(0, _metricsStoppedAt-_metricsStarted)], @"sessionSeconds",
        [NSNumber numberWithDouble:MAX(0, FNTVMonotonicTime()-_metricsStoppedAt)], @"drainSeconds",
        [NSNumber numberWithUnsignedInteger:_metricsAccepted], @"accepted",
        [NSNumber numberWithUnsignedInteger:_metricsFinished], @"finished",
        [NSNumber numberWithUnsignedInteger:_metricsRejected], @"queueRejected",
        [NSNumber numberWithUnsignedInteger:_metricsMaxPending], @"maxPending",
        [NSNumber numberWithUnsignedInteger:_metricsAccepted-[_metricsRows count]], @"unrecorded",
        @YES, @"allFinished", [NSArray arrayWithArray:_metricsRows], @"requests", nil];
}
- (void)finishMetricsRecord:(NSMutableDictionary *)record timing:(FNTVHTTPMetrics)timing acceptedAt:(NSTimeInterval)accepted {
    NSDictionary *report = nil;
    @synchronized(self) {
        [record setObject:[NSNumber numberWithDouble:FNTVMonotonicTime()-accepted] forKey:@"requestSeconds"];
        [record setObject:[NSNumber numberWithDouble:timing.response ? timing.response-timing.started : -1] forKey:@"upstreamResponseSeconds"];
        [record setObject:[NSNumber numberWithDouble:timing.firstByte ? timing.firstByte-timing.started : -1] forKey:@"firstByteSeconds"];
        [record setObject:[NSNumber numberWithDouble:timing.completed ? timing.completed-timing.started : -1] forKey:@"upstreamCompleteSeconds"];
        [record setObject:[NSNumber numberWithInteger:timing.status] forKey:@"upstreamStatus"];
        [record setObject:[NSNumber numberWithUnsignedLongLong:timing.receivedBytes] forKey:@"upstreamBytes"];
        [record setObject:[NSNumber numberWithDouble:timing.sendSeconds] forKey:@"sendSeconds"];
        [record setObject:[NSNumber numberWithUnsignedLongLong:timing.sentBytes] forKey:@"sentBytes"];
        [record setObject:[NSNumber numberWithInteger:timing.sendError] forKey:@"sendError"];
        [record setObject:[NSNumber numberWithInteger:timing.errorCode] forKey:@"errorCode"];
        [record setObject:[NSNumber numberWithBool:timing.networkCompleted] forKey:@"upstreamFinished"];
        [record setObject:[NSNumber numberWithBool:timing.cancelled] forKey:@"cancelled"];
        [record setObject:[NSNumber numberWithBool:_metricsStopped] forKey:@"finishedAfterStop"];
        if (_metricsPending) _metricsPending--;
        _metricsFinished++;
        report = [self takeMetricsReport];
    }
    WriteMetricsReport(report, _metricsPath);
}
- (BOOL)stopIfPlaybackURL:(NSURL *)url {
    @synchronized(self) {
        if (![url isKindOfClass:[NSURL class]] || ![[_playbackURL absoluteString] isEqualToString:[url absoluteString]]) return NO;
        [self stop];
        return YES;
    }
}
- (void)stop {
    NSDictionary *report = nil;
    @synchronized(self) {
        _running = NO;
        [_playbackURL release]; _playbackURL = nil;
        if (_listener >= 0) { shutdown(_listener, SHUT_RDWR); _listener = -1; }
        for (NSNumber *fd in _clientSockets) shutdown([fd intValue], SHUT_RDWR);
        [_urls removeAllObjects]; [_pathsByUpstream removeAllObjects];
        if (_metricsStarted && !_metricsStopped) {
            _metricsStopped = YES; _metricsStoppedAt = FNTVMonotonicTime(); _metricsStoppedUnix = [[NSDate date] timeIntervalSince1970];
        }
        report = [self takeMetricsReport];
    }
    WriteMetricsReport(report, _metricsPath);
    // Existing bounded requests finish or time out; queued clients observe _running and close.
}
- (void)dealloc { [self stop]; [_origin release]; [_token release]; [_nonce release]; [_urls release]; [_pathsByUpstream release]; [_clientSockets release]; [_connections release]; [_metricsRows release]; [_metricsPath release]; [super dealloc]; }
@end
