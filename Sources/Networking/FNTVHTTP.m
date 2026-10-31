#import "FNTVHTTP.h"
#import "FNTVSignature.h"
#import <dispatch/dispatch.h>
#import <sys/socket.h>
#import <mach/mach_time.h>
#import <errno.h>

NSTimeInterval FNTVMonotonicTime(void) {
    static double scale = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        scale = (double)info.numer / (double)info.denom / 1000000000.;
    });
    return mach_absolute_time() * scale;
}
NSError *FNTVError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"FNTV" code:code userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}
NSString *FNTVString(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }
NSString *FNTVEscape(NSString *value) {
    return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)value, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8) autorelease];
}
static NSInteger FNTVPort(NSURL *u) { return [u port] ? [[u port] integerValue] : ([[[u scheme] lowercaseString] isEqualToString:@"https"] ? 443 : 80); }
BOOL FNTVSameOrigin(NSURL *a, NSURL *b) {
    return a && b && ![a user] && ![a password] && ![b user] && ![b password] &&
        [[[a scheme] lowercaseString] isEqualToString:[[b scheme] lowercaseString]] &&
        [[[a host] lowercaseString] isEqualToString:[[b host] lowercaseString]] && FNTVPort(a) == FNTVPort(b);
}
NSURL *FNTVImageURL(NSURL *origin, NSString *path) {
    if (![path length]) return nil;
    NSURL *url;
    if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"]) url = [NSURL URLWithString:path];
    else {
        NSString *imagePath = [path hasPrefix:@"/"] ? path : [@"/" stringByAppendingString:path];
        url = [[NSURL URLWithString:[@"/v/api/v1/sys/img" stringByAppendingString:imagePath] relativeToURL:origin] absoluteURL];
    }
    if (!FNTVSameOrigin(url, origin) || [url fragment]) return nil;
    NSMutableArray *query = [NSMutableArray array];
    for (NSString *part in [[url query] componentsSeparatedByString:@"&"]) {
        if (![part length]) continue;
        NSString *key = [[[part componentsSeparatedByString:@"="] objectAtIndex:0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (![key isEqualToString:@"w"]) [query addObject:part];
    }
    // NAS thumbnailing keeps large originals within the iPad's unchanged decode limits.
    [query addObject:@"w=320"];
    NSString *base = [[[url absoluteString] componentsSeparatedByString:@"?"] objectAtIndex:0];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", base, [query componentsJoinedByString:@"&"]]];
}
BOOL FNTVImageDimensionsAllowed(NSInteger width, NSInteger height) {
    return width > 0 && height > 0 && width <= 4096 && height <= 4096 && (long long)width*height <= 4000000;
}
static double FNTVNumber(id v) { return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0; }
NSDictionary *FNTVNormalizeItem(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:item];
    NSString *title = FNTVString([item objectForKey:@"title"]);
    if (![title length]) title = FNTVString([item objectForKey:@"name"]);
    if (![title length]) title = FNTVString([item objectForKey:@"original_title"]);
    if (![title length]) title = @"未命名";
    NSString *poster = FNTVString([item objectForKey:@"poster"]);
    if (![poster length]) poster = FNTVString([item objectForKey:@"posters"]);
    if (![poster length]) poster = FNTVString([item objectForKey:@"still_path"]);
    id posters = [item objectForKey:@"poster_list"];
    if (![poster length] && [posters isKindOfClass:[NSArray class]] && [posters count]) poster = FNTVString([posters objectAtIndex:0]);
    [result setObject:FNTVString([item objectForKey:@"guid"]) forKey:@"guid"];
    [result setObject:title forKey:@"title"];
    [result setObject:title forKey:@"name"];
    NSString *type = FNTVString([item objectForKey:@"type"]);
    if (![type length] && [[item objectForKey:@"episode_number"] respondsToSelector:@selector(integerValue)]) type = @"Episode";
    if (![type length] && [[item objectForKey:@"season_number"] respondsToSelector:@selector(integerValue)]) type = @"Season";
    [result setObject:type forKey:@"type"];
    [result setObject:poster forKey:@"poster"];
    [result setObject:FNTVString([item objectForKey:@"overview"]) forKey:@"overview"];
    [result setObject:[NSNumber numberWithDouble:MAX(0, FNTVNumber([item objectForKey:@"duration"]))] forKey:@"duration"];
    [result setObject:[NSNumber numberWithDouble:MAX(0, FNTVNumber([item objectForKey:@"watched_ts"]))] forKey:@"resumeSeconds"];
    NSString *date = FNTVString([item objectForKey:@"release_date"]);
    if (![date length]) date = FNTVString([item objectForKey:@"air_date"]);
    [result setObject:([date length] >= 4 ? [date substringToIndex:4] : @"") forKey:@"year"];
    return result;
}
NSArray *FNTVNormalizeItems(id items) {
    NSMutableArray *result = [NSMutableArray array];
    if ([items isKindOfClass:[NSArray class]]) for (id item in items) {
        NSDictionary *normalized = FNTVNormalizeItem(item);
        if ([[normalized objectForKey:@"guid"] length]) [result addObject:normalized];
    }
    return result;
}
@implementation FNTVOperation
- (id)initWithWork:(FNTVWork)work completion:(void (^)(id, NSError *))completion {
    if ((self = [super init])) { _work = [work copy]; _result = [completion copy]; }
    return self;
}
- (void)main {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    FNTVWork work = nil;
    @synchronized(self) { work = [_work copy]; [_work release]; _work = nil; }
    if (work && ![self isCancelled]) {
        NSError *error = nil;
        id value = work(self, &error);
        void (^completion)(id, NSError *) = nil;
        @synchronized(self) { completion = [_result copy]; [_result release]; _result = nil; }
        if (completion && ![self isCancelled]) dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isCancelled]) completion(value, error);
        });
        [completion release];
    }
    [work release]; [pool drain];
}
- (void)cancel {
    [super cancel];
    // Dropping captures breaks controller -> operation -> controller cycles on logout.
    FNTVWork work;
    void (^completion)(id, NSError *);
    @synchronized(self) { work = _work; _work = nil; completion = _result; _result = nil; }
    [work release]; [completion release];
}
- (void)dealloc { [_work release]; [_result release]; [super dealloc]; }
@end

static BOOL FNTVSocketWrite(int fd, NSData *data, FNTVHTTPMetrics *metrics) {
    const char *bytes = [data bytes]; NSUInteger remaining = [data length];
    while (remaining) {
        NSTimeInterval before = metrics ? FNTVMonotonicTime() : 0;
        ssize_t n = send(fd, bytes, remaining, 0);
        int savedError = n < 0 ? errno : 0;
        if (metrics) { metrics->sendSeconds += FNTVMonotonicTime() - before; if (n > 0) metrics->sentBytes += n; else metrics->sendError = savedError; }
        if (n <= 0) return NO; bytes += n; remaining -= n;
    }
    return YES;
}
@implementation FNTVHTTP
+ (NSData *)fetchURL:(NSURL *)url origin:(NSURL *)origin method:(NSString *)method body:(NSData *)body token:(NSString *)token range:(NSString *)range limit:(NSUInteger)limit operation:(NSOperation *)operation streamFD:(int)streamFD response:(NSHTTPURLResponse **)response error:(NSError **)error {
    return [self fetchURL:url origin:origin method:method body:body token:token range:range limit:limit operation:operation streamFD:streamFD response:response error:error metrics:NULL];
}
+ (NSData *)fetchURL:(NSURL *)url origin:(NSURL *)origin method:(NSString *)method body:(NSData *)body token:(NSString *)token range:(NSString *)range limit:(NSUInteger)limit operation:(NSOperation *)operation streamFD:(int)streamFD response:(NSHTTPURLResponse **)response error:(NSError **)error metrics:(FNTVHTTPMetrics *)metrics {
    if (metrics) memset(metrics, 0, sizeof(*metrics));
    if (!FNTVSameOrigin(url, origin)) { if (error) *error = FNTVError(400, @"服务器返回了不受信任的外部地址。"); return nil; }
    FNTVHTTP *transfer = [[[self alloc] init] autorelease];
    transfer->_origin = [origin retain]; transfer->_limit = limit; transfer->_streamFD = streamFD;
    transfer->_collectMetrics = metrics != NULL;
    if (metrics) transfer->_metrics.started = FNTVMonotonicTime();
    transfer->_data = [[NSMutableData alloc] init]; transfer->_operation = [operation retain];
    transfer->_head = [method isEqualToString:@"HEAD"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:35];
    [request setHTTPMethod:method]; [request setHTTPShouldHandleCookies:NO];
    [request setValue:@"mode=relay" forHTTPHeaderField:@"Cookie"];
    [request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    if ([token length]) [request setValue:token forHTTPHeaderField:@"Authorization"];
    if ([range length]) [request setValue:range forHTTPHeaderField:@"Range"];
    if (body) { [request setHTTPBody:body]; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; }
    if (FNTVNeedsRequestSignature(url, method)) {
        NSString *signature = FNTVNewRequestSignature(url, method, body);
        if (!signature) { if (error) *error = FNTVError(500, @"无法生成请求签名。"); return nil; }
        [request setValue:signature forHTTPHeaderField:@"authx"];
    }
    transfer->_connection = [[NSURLConnection alloc] initWithRequest:request delegate:transfer startImmediately:YES];
    if (!transfer->_connection) transfer->_error = [FNTVError(503, @"无法建立网络连接。") retain];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:65];
    while (transfer->_connection && !transfer->_finished && ![operation isCancelled] && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!transfer->_finished && !transfer->_error) transfer->_error = [FNTVError([operation isCancelled] ? NSUserCancelledError : NSURLErrorTimedOut, @"连接已取消或服务器响应超时。") retain];
    [transfer->_connection cancel];
    if (metrics) {
        transfer->_metrics.errorCode = [transfer->_error code];
        transfer->_metrics.cancelled = [operation isCancelled];
        *metrics = transfer->_metrics;
    }
    if (response) *response = [[transfer->_response retain] autorelease];
    if (error) *error = [[transfer->_error retain] autorelease];
    return transfer->_error ? nil : [[transfer->_data retain] autorelease];
}
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse {
    if (redirectResponse && !FNTVSameOrigin([request URL], _origin)) {
        [_error release]; _error = [FNTVError(403, @"已阻止服务器跳转到外部地址。") retain];
        _finished = YES; [connection cancel]; return nil;
    }
    return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [_response release]; _response = [(NSHTTPURLResponse *)response retain];
    NSInteger status = [_response statusCode];
    if (_collectMetrics) { _metrics.response = FNTVMonotonicTime(); _metrics.status = status; }
    if (_streamFD < 0 && (status < 200 || status >= 300)) {
        _error = [FNTVError(status, status == 401 || status == 403 ? @"登录已失效，请重新登录。" : [NSString stringWithFormat:@"服务器请求失败（HTTP %ld）。", (long)status]) retain];
        _finished = YES; [connection cancel]; return;
    }
    if (_limit && [response expectedContentLength] > (long long)_limit) {
        _error = [FNTVError(413, @"服务器返回的数据过大。") retain]; _finished = YES; [connection cancel]; return;
    }
    if (_streamFD >= 0) {
        NSMutableString *header = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld Status\r\nConnection: close\r\n", (long)status];
        NSDictionary *headers = [_response allHeaderFields];
        for (NSString *key in headers) {
            NSString *lower = [key lowercaseString];
            if ([[@"content-type content-length content-range accept-ranges" componentsSeparatedByString:@" "] containsObject:lower]) {
                NSString *v = [[headers objectForKey:key] description];
                if ([v rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound) [header appendFormat:@"%@: %@\r\n", key, v];
            }
        }
        [header appendString:@"\r\n"];
        if (!FNTVSocketWrite(_streamFD, [header dataUsingEncoding:NSUTF8StringEncoding], _collectMetrics ? &_metrics : NULL)) { _finished = YES; [connection cancel]; }
    }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    _received += [data length];
    if (_collectMetrics) {
        if (!_metrics.firstByte) _metrics.firstByte = FNTVMonotonicTime();
        _metrics.receivedBytes += [data length];
    }
    if ((_limit && _received > _limit) || [_operation isCancelled]) {
        _error = [FNTVError(413, @"响应过大或连接已取消。") retain]; _finished = YES; [connection cancel]; return;
    }
    if (_streamFD >= 0) {
        if (!_head && !FNTVSocketWrite(_streamFD, data, _collectMetrics ? &_metrics : NULL)) { _finished = YES; [connection cancel]; }
    } else [_data appendData:data];
}
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse { return nil; }
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (_collectMetrics) { _metrics.completed = FNTVMonotonicTime(); _metrics.networkCompleted = YES; }
    _finished = YES;
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (!_error) _error = [FNTVError([error code], @"无法连接飞牛影视，请检查服务器地址、网络及证书。") retain];
    _finished = YES;
}
- (void)dealloc {
    [_connection cancel]; [_connection release]; [_origin release]; [_data release]; [_response release]; [_operation release]; [_error release]; [super dealloc];
}
@end
