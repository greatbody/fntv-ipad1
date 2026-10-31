#import "FNTVClient.h"
#import "FNTVHTTP.h"
#import "FNTVLogin.h"
#import "FNTVHLSProxy.h"
#import <Security/Security.h>
#import <ImageIO/ImageIO.h>
#import <webp/decode.h>
#import <math.h>

NSString * const FNTVAuthenticationExpiredNotification = @"FNTVAuthenticationExpiredNotification";
static NSString * const TokenService = @"ink.sunrui.fntv.ipad1.session";
typedef id (^FNTVNetworkWork)(NSOperation *, NSURL *, NSString *, NSError **);

static NSMutableDictionary *TokenQuery(void) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass, TokenService, (id)kSecAttrService, @"session", (id)kSecAttrAccount, nil];
}
static id API(NSURL *origin, NSString *token, NSString *path, NSDictionary *body, NSOperation *operation, NSError **error) {
    NSData *request = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:error] : nil;
    if (body && !request) return nil;
    NSString *apiPath = [path hasPrefix:@"/"] ? path : [@"/v/api/v1/" stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:apiPath relativeToURL:origin];
    NSData *data = [FNTVHTTP fetchURL:[url absoluteURL] origin:origin method:(body ? @"POST" : @"GET") body:request token:token range:nil limit:8*1024*1024 operation:operation streamFD:-1 response:NULL error:error];
    if (!data) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]] || ![[root objectForKey:@"code"] respondsToSelector:@selector(integerValue)]) {
        if (error) *error = FNTVError(502, @"服务器返回的内容不是飞牛影视接口数据，请检查地址。"); return nil;
    }
    NSInteger code = [[root objectForKey:@"code"] integerValue];
    if (code != 0) {
        if (FNTVIsAuthenticationFailure(code, [root objectForKey:@"msg"])) { if (error) *error = FNTVError(401, @"登录已失效，请重新登录。"); return nil; }
        NSString *message = code == 5000 ? @"请求签名验证失败，请检查设备日期和时间。" : FNTVString([root objectForKey:@"msg"]);
        if (![message length] || [message length] > 200) message = @"飞牛影视拒绝了请求。";
        if (error) *error = FNTVError(code, message); return nil;
    }
    id payload = [root objectForKey:@"data"];
    return !payload || payload == [NSNull null] ? [NSNumber numberWithBool:YES] : payload;
}
static NSArray *PayloadItems(id payload) {
    if ([payload isKindOfClass:[NSArray class]]) return payload;
    if ([payload isKindOfClass:[NSDictionary class]]) {
        id list = [payload objectForKey:@"list"];
        if ([list isKindOfClass:[NSArray class]]) return list;
    }
    return [NSArray array];
}
static void FreeImageBuffer(void *info, const void *data, size_t size) { (void)info; (void)size; free((void *)data); }
static UIImage *DecodeImage(NSData *data) {
    int width = 0, height = 0;
    CGImageRef image = NULL;
    if (WebPGetInfo([data bytes], [data length], &width, &height)) {
        if (!FNTVImageDimensionsAllowed(width, height)) return nil;
        WebPDecoderConfig config;
        if (!WebPInitDecoderConfig(&config)) return nil;
        double scale = MIN(1., 320. / MAX(width, height));
        width = MAX(1, (int)floor(width * scale)); height = MAX(1, (int)floor(height * scale));
        config.options.use_scaling = 1; config.options.scaled_width = width; config.options.scaled_height = height;
        config.output.colorspace = MODE_RGBA; config.output.is_external_memory = 1;
        size_t size = (size_t)width * height * 4;
        uint8_t *pixels = malloc(size); if (!pixels) return nil;
        config.output.u.RGBA.rgba = pixels; config.output.u.RGBA.stride = width*4; config.output.u.RGBA.size = size;
        VP8StatusCode status = WebPDecode([data bytes], [data length], &config);
        WebPFreeDecBuffer(&config.output);
        if (status != VP8_STATUS_OK) { free(pixels); return nil; }
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, size, FreeImageBuffer);
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        image = CGImageCreate(width, height, 8, 32, width*4, colors, kCGBitmapByteOrderDefault | kCGImageAlphaLast, provider, NULL, NO, kCGRenderingIntentDefault);
        CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
    } else {
        CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
        if (!source) return nil;
        NSDictionary *properties = [(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) autorelease];
        double sourceWidth = [[properties objectForKey:(id)kCGImagePropertyPixelWidth] doubleValue];
        double sourceHeight = [[properties objectForKey:(id)kCGImagePropertyPixelHeight] doubleValue];
        if (!FNTVImageDimensionsAllowed((NSInteger)sourceWidth, (NSInteger)sourceHeight)) { CFRelease(source); return nil; }
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:(id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways, [NSNumber numberWithInt:320], (id)kCGImageSourceThumbnailMaxPixelSize, (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform, nil];
        image = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options); CFRelease(source);
    }
    UIImage *result = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image);
    return result;
}
@implementation FNTVClient
@synthesize serverURL = _serverURL, username = _username;
+ (FNTVClient *)sharedClient {
    static FNTVClient *client = nil;
    @synchronized(self) { if (!client) client = [[self alloc] init]; }
    return client;
}
- (id)init {
    if ((self = [super init])) {
        _queue = [[NSOperationQueue alloc] init]; [_queue setMaxConcurrentOperationCount:3];
        _imageQueue = [[NSOperationQueue alloc] init]; [_imageQueue setMaxConcurrentOperationCount:1];
        _recordQueue = [[NSOperationQueue alloc] init]; [_recordQueue setMaxConcurrentOperationCount:1];
        _imageCache = [[NSCache alloc] init]; [_imageCache setTotalCostLimit:12*1024*1024]; [_imageCache setCountLimit:48];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _serverURL = [FNTVString([defaults objectForKey:@"FNTVServer"]) copy];
        _username = [FNTVString([defaults objectForKey:@"FNTVUsername"]) copy];
        NSMutableDictionary *query = TokenQuery(); [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
        CFTypeRef value = NULL;
        if (SecItemCopyMatching((CFDictionaryRef)query, &value) == errSecSuccess && value) {
            id session = [NSJSONSerialization JSONObjectWithData:(NSData *)value options:0 error:NULL];
            if ([session isKindOfClass:[NSDictionary class]] && [[session objectForKey:@"server"] isEqual:_serverURL] && [[session objectForKey:@"username"] isEqual:_username]) _token = [FNTVString([session objectForKey:@"token"]) copy];
            CFRelease(value);
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearImageCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}
- (BOOL)isAuthenticated { return [_token length] > 0; }
- (BOOL)configureServer:(NSString *)server error:(NSError **)error {
    NSString *trimmed = [FNTVString(server) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:trimmed];
    NSString *scheme = [[url scheme] lowercaseString]; NSString *path = [url path];
    BOOL valid = ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && [[url host] length] && ![url user] && ![url password] && ![url query] && ![url fragment] && (![path length] || [path isEqualToString:@"/"] || [path isEqualToString:@"/v"] || [path isEqualToString:@"/v/"]);
    if (!valid || ([url port] && ([[url port] integerValue] <= 0 || [[url port] integerValue] > 65535))) {
        if (error) *error = FNTVError(400, @"请输入飞牛影视地址，例如 http://NAS地址:5666/v。"); return NO;
    }
    NSString *host = [url host]; if ([host rangeOfString:@":"].location != NSNotFound && ![host hasPrefix:@"["]) host = [NSString stringWithFormat:@"[%@]", host];
    NSString *origin = [NSString stringWithFormat:@"%@://%@%@", scheme, host, [url port] ? [NSString stringWithFormat:@":%@", [url port]] : @""];
    if (![_serverURL isEqual:origin]) {
        [self logout]; [_serverURL release]; _serverURL = [origin copy];
        [[NSUserDefaults standardUserDefaults] setObject:_serverURL forKey:@"FNTVServer"];
    }
    return YES;
}
- (NSOperation *)enqueueOnQueue:(NSOperationQueue *)queue work:(FNTVNetworkWork)work completion:(FNTVCompletion)completion {
    NSURL *origin = [NSURL URLWithString:_serverURL]; NSString *token = [[_token copy] autorelease]; NSUInteger generation = _generation;
    FNTVOperation *operation = [[[FNTVOperation alloc] initWithWork:^id(NSOperation *op, NSError **error) {
        if (!origin) { *error = FNTVError(400, @"请先配置飞牛影视服务器。"); return nil; }
        return work(op, origin, token, error);
    } completion:^(id value, NSError *error) {
        if (generation != _generation) return;
        if ([error code] == 401 && [self isAuthenticated]) {
            [self logout]; [[NSNotificationCenter defaultCenter] postNotificationName:FNTVAuthenticationExpiredNotification object:self];
        }
        if (completion) completion(value, error);
    }] autorelease];
    if (queue == _recordQueue) {
        if (_lastRecord && ![_lastRecord isFinished]) [operation addDependency:_lastRecord];
        [_lastRecord release]; _lastRecord = [operation retain];
    }
    [queue addOperation:operation]; return operation;
}
- (NSOperation *)loginUsername:(NSString *)username password:(NSString *)password completion:(FNTVCompletion)completion {
    NSString *name = [FNTVString(username) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [self enqueueOnQueue:_queue work:^id(NSOperation *operation, NSURL *origin, NSString *token, NSError **error) {
        (void)token;
        if (![name length] || ![password length]) { *error = FNTVError(400, @"请输入用户名和密码。"); return nil; }
        id version = API(origin, nil, @"sys/version", nil, operation, error);
        if (!version || [operation isCancelled]) return nil;
        NSDictionary *request = FNTVLoginRequest([version isKindOfClass:[NSDictionary class]] ? [version objectForKey:@"version"] : nil, name, password, error);
        if (!request) return nil;
        id result = API(origin, nil, [request objectForKey:@"path"], [request objectForKey:@"body"], operation, error);
        return result && FNTVLoginToken(result, error) ? result : nil;
    } completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSString *token = [result objectForKey:@"token"];
        NSDictionary *session = [NSDictionary dictionaryWithObjectsAndKeys:_serverURL, @"server", name, @"username", token, @"token", nil];
        NSMutableDictionary *query = TokenQuery(); SecItemDelete((CFDictionaryRef)query);
        [query setObject:[NSJSONSerialization dataWithJSONObject:session options:0 error:NULL] forKey:(id)kSecValueData];
        [query setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
        OSStatus status = SecItemAdd((CFDictionaryRef)query, NULL);
        if (status != errSecSuccess) { if (completion) completion(nil, FNTVError(status, @"系统无法安全保存登录会话，请检查应用签名。")); return; }
        [_token release]; _token = [token copy]; [_username release]; _username = [name copy];
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"FNTVUsername"];
        if (completion) completion([NSNumber numberWithBool:YES], nil);
    }];
}
- (void)logout {
    _generation++; [_queue cancelAllOperations]; [_imageQueue cancelAllOperations]; [_recordQueue cancelAllOperations]; [_lastRecord release]; _lastRecord = nil;
    [_token release]; _token = nil; SecItemDelete((CFDictionaryRef)TokenQuery());
    [self stopPlayback]; [self clearImageCache];
}
- (NSOperation *)libraries:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id data = API(origin, token, @"mediadb/list", nil, op, error);
        return data ? FNTVNormalizeItems(PayloadItems(data)) : nil;
    } completion:completion];
}
- (NSOperation *)itemsInLibrary:(NSString *)guid page:(NSUInteger)page search:(NSString *)search completion:(FNTVCompletion)completion {
    return [self listItemsInLibrary:guid parent:nil page:page search:search completion:completion];
}
- (NSOperation *)itemsInDirectory:(NSString *)guid page:(NSUInteger)page completion:(FNTVCompletion)completion {
    return [self listItemsInLibrary:nil parent:guid page:page search:nil completion:completion];
}
- (NSOperation *)listItemsInLibrary:(NSString *)guid parent:(NSString *)parent page:(NSUInteger)page search:(NSString *)search completion:(FNTVCompletion)completion {
    NSUInteger currentPage = MAX((NSUInteger)1, MIN(page, (NSUInteger)100000));
    NSString *query = [FNTVString(search) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id payload;
        if ([query length]) {
            payload = API(origin, token, [@"search/list?q=" stringByAppendingString:FNTVEscape(query)], nil, op, error);
        } else {
            NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedInteger:currentPage], @"page", @30, @"page_size", @"create_time", @"sort_column", @"DESC", @"sort_type", @1, @"exclude_grouped_video",
                [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:@"Movie", @"TV", @"Directory", @"Video", nil] forKey:@"type"], @"tags", nil];
            if ([guid length]) [body setObject:guid forKey:@"ancestor_guid"];
            if ([parent length]) [body setObject:parent forKey:@"parent_guid"];
            payload = API(origin, token, @"item/list", body, op, error);
        }
        if (!payload) return nil;
        NSArray *items = FNTVNormalizeItems(PayloadItems(payload)); NSUInteger total = [items count]; BOOL more;
        if ([query length]) {
            // Official search is global and returns one array; paginate that array locally.
            NSUInteger start = MIN([items count], (currentPage - 1)*30);
            items = [items subarrayWithRange:NSMakeRange(start, MIN((NSUInteger)30, [items count]-start))];
            more = currentPage*30 < total;
        } else {
            id count = [payload isKindOfClass:[NSDictionary class]] ? [payload objectForKey:@"total"] : nil;
            if ([count respondsToSelector:@selector(unsignedIntegerValue)]) total = [count unsignedIntegerValue];
            more = count ? currentPage*30 < total : [items count] == 30;
        }
        return [NSDictionary dictionaryWithObjectsAndKeys:items, @"items", [NSNumber numberWithUnsignedInteger:currentPage], @"page", [NSNumber numberWithUnsignedInteger:total], @"total", [NSNumber numberWithBool:more], @"hasMore", nil];
    } completion:completion];
}
- (NSOperation *)detailForItem:(NSString *)guid completion:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id data = API(origin, token, [@"item/" stringByAppendingString:FNTVEscape(guid)], nil, op, error);
        NSDictionary *item = FNTVNormalizeItem(data);
        if (data && !item) *error = FNTVError(502, @"服务器返回的详情格式不正确。");
        return item;
    } completion:completion];
}
- (NSOperation *)seasonsForTV:(NSString *)guid completion:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id data = API(origin, token, [@"season/list/" stringByAppendingString:FNTVEscape(guid)], nil, op, error);
        return data ? FNTVNormalizeItems(PayloadItems(data)) : nil;
    } completion:completion];
}
- (NSOperation *)episodesForSeason:(NSString *)guid completion:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id data = API(origin, token, [@"episode/list/" stringByAppendingString:FNTVEscape(guid)], nil, op, error);
        return data ? FNTVNormalizeItems(PayloadItems(data)) : nil;
    } completion:completion];
}
- (NSOperation *)imageForPath:(NSString *)path completion:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_imageQueue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        if (![path length]) { *error = FNTVError(404, @"暂无海报。"); return nil; }
        UIImage *cached = [_imageCache objectForKey:path]; if (cached) return cached;
        NSURL *url = FNTVImageURL(origin, path);
        NSData *bytes = [FNTVHTTP fetchURL:url origin:origin method:@"GET" body:nil token:token range:nil limit:4*1024*1024 operation:op streamFD:-1 response:NULL error:error];
        if (!bytes || [op isCancelled]) return nil;
        UIImage *image = DecodeImage(bytes);
        if (!image) { *error = FNTVError(415, @"海报图片无法解码。"); return nil; }
        return image;
    } completion:^(id image, NSError *error) {
        // Main-queue generation/cancellation checks above prevent old sessions repopulating this cache.
        if (image && !error) [_imageCache setObject:image forKey:path cost:(NSUInteger)([image size].width*[image size].height*4)];
        if (completion) completion(image, error);
    }];
}
- (NSOperation *)preparePlaybackForItem:(NSString *)guid startTime:(NSTimeInterval)seconds completion:(FNTVCompletion)completion {
    [self stopPlayback];
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        id info = API(origin, token, @"play/info", [NSDictionary dictionaryWithObject:guid forKey:@"item_guid"], op, error);
        if (!info) return nil;
        if (![info isKindOfClass:[NSDictionary class]] || ![FNTVString([info objectForKey:@"media_guid"]) length]) { *error = FNTVError(415, @"此条目没有可播放的媒体文件。"); return nil; }
        NSString *media = [info objectForKey:@"media_guid"];
        id qualities = API(origin, token, @"play/quality", [NSDictionary dictionaryWithObject:media forKey:@"media_guid"], op, error);
        if (!qualities) return nil;
        NSString *resolution = @"480"; long long bitrate = 1000000;
        NSInteger bestHeight = 0; long long bestBitrate = 0;
        for (id quality in PayloadItems(qualities)) if ([quality isKindOfClass:[NSDictionary class]]) {
            NSInteger height = [FNTVString([quality objectForKey:@"resolution"]) integerValue];
            id rawBitrate = [quality objectForKey:@"bitrate"];
            long long rate = [rawBitrate respondsToSelector:@selector(longLongValue)] ? [rawBitrate longLongValue] : 0;
            if (height > 0 && height <= 480 && rate > 0 && rate <= 1500000 && (height > bestHeight || (height == bestHeight && rate > bestBitrate))) {
                bestHeight = height; bestBitrate = rate; resolution = [[quality objectForKey:@"resolution"] description]; bitrate = rate;
            }
        }
        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:media, @"media_guid", resolution, @"resolution", [NSNumber numberWithLongLong:bitrate], @"bitrate", @0, @"startTimestamp", @"h264", @"video_encoder", @"aac", @"audio_encoder", @2, @"channels", @1, @"forced_sdr", [NSNumber numberWithBool:NO], @"without_stream", @"", @"subtitle_guid", nil];
        for (NSString *key in [NSArray arrayWithObjects:@"video_guid", @"audio_guid", nil]) if ([FNTVString([info objectForKey:key]) length]) [body setObject:[info objectForKey:key] forKey:key];
        id play = API(origin, token, @"play/play", body, op, error);
        if (!play) return nil;
        NSString *link = [play isKindOfClass:[NSDictionary class]] ? FNTVString([play objectForKey:@"play_link"]) : @"";
        NSURL *url = [link length] ? [[NSURL URLWithString:link relativeToURL:origin] absoluteURL] : nil;
        if (!FNTVSameOrigin(url, origin)) { *error = FNTVError(415, @"服务器没有返回本机可用的 HLS 播放地址。"); return nil; }
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:body];
        [result setObject:guid forKey:@"item_guid"]; [result setObject:link forKey:@"play_link"]; [result setObject:url forKey:@"upstreamURL"];
        [result setObject:[NSNumber numberWithDouble:isfinite(seconds) ? MAX(0, seconds) : 0] forKey:@"startTime"];
        id duration = [info objectForKey:@"duration"];
        if (![duration respondsToSelector:@selector(doubleValue)] && [[info objectForKey:@"item"] isKindOfClass:[NSDictionary class]]) duration = [[info objectForKey:@"item"] objectForKey:@"duration"];
        [result setObject:[NSNumber numberWithDouble:[duration respondsToSelector:@selector(doubleValue)] ? MAX(0, [duration doubleValue]) : 0] forKey:@"duration"];
        return result;
    } completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        _proxy = [[FNTVHLSProxy alloc] initWithOrigin:[NSURL URLWithString:_serverURL] token:_token];
        NSURL *url = [_proxy startWithURL:[result objectForKey:@"upstreamURL"] error:&error];
        if (!url) { [self stopPlayback]; if (completion) completion(nil, error ?: FNTVError(500, @"无法建立播放连接。")); return; }
        NSMutableDictionary *playback = [NSMutableDictionary dictionaryWithDictionary:result];
        [playback removeObjectForKey:@"upstreamURL"]; [playback setObject:url forKey:@"URL"];
        if (completion) completion(playback, nil);
    }];
}
- (NSOperation *)recordPlayback:(NSDictionary *)playback seconds:(NSTimeInterval)seconds completion:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_recordQueue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        if (!isfinite(seconds) || seconds < 0 || ![FNTVString([playback objectForKey:@"item_guid"]) length]) { *error = FNTVError(400, @"播放进度无效。"); return nil; }
        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"", @"user_guid", [NSNumber numberWithLongLong:(long long)seconds], @"ts", @"00000000-0000-0000-0000-000000000000", @"subtitle_guid", nil];
        for (NSString *key in [NSArray arrayWithObjects:@"item_guid", @"media_guid", @"video_guid", @"audio_guid", @"play_link", @"resolution", @"bitrate", nil]) {
            id value = [playback objectForKey:key]; if (value) [body setObject:value forKey:key];
        }
        return API(origin, token, @"play/record", body, op, error);
    } completion:completion];
}
#if FNTV_DIAGNOSTICS
- (NSOperation *)readOnlySelfCheck:(FNTVCompletion)completion {
    return [self enqueueOnQueue:_queue work:^id(NSOperation *op, NSURL *origin, NSString *token, NSError **error) {
        (void)error;
        NSMutableDictionary *report = [NSMutableDictionary dictionaryWithObjectsAndKeys:@1, @"schemaVersion", @"not_run", @"libraryCheck", @"not_run", @"itemCheck", @"not_run", @"detailCheck", @"not_run", @"imageCheck", nil];
        NSMutableDictionary *query = TokenQuery(); [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
        CFTypeRef saved = NULL; BOOL keychainOK = NO;
        if (SecItemCopyMatching((CFDictionaryRef)query, &saved) == errSecSuccess && saved) {
            id session = [NSJSONSerialization JSONObjectWithData:(NSData *)saved options:0 error:NULL];
            keychainOK = [session isKindOfClass:[NSDictionary class]] && [[session objectForKey:@"token"] isEqual:token];
            CFRelease(saved);
        }
        [report setObject:(keychainOK ? @"passed" : @"failed") forKey:@"keychainCheck"];
        NSError *failure = nil;
        id payload = API(origin, token, @"mediadb/list", nil, op, &failure);
        if (!payload) { [report setObject:@"failed" forKey:@"libraryCheck"]; [report setObject:[NSNumber numberWithInteger:[failure code]] forKey:@"errorCode"]; return report; }
        NSArray *libraries = FNTVNormalizeItems(PayloadItems(payload));
        [report setObject:@"passed" forKey:@"libraryCheck"]; [report setObject:[NSNumber numberWithUnsignedInteger:[libraries count]] forKey:@"libraryCount"];
        NSArray *items = nil;
        NSUInteger checkedLibraries = 0;
        for (NSDictionary *library in libraries) {
            if (checkedLibraries++ >= 5) break;
            NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:[library objectForKey:@"guid"], @"ancestor_guid", @1, @"page", @10, @"page_size", @"create_time", @"sort_column", @"DESC", @"sort_type", @1, @"exclude_grouped_video", nil];
            payload = API(origin, token, @"item/list", body, op, &failure);
            if (!payload) break;
            items = FNTVNormalizeItems(PayloadItems(payload));
            if ([items count] || [op isCancelled]) break;
        }
        [report setObject:(payload ? @"passed" : @"failed") forKey:@"itemCheck"];
        [report setObject:[NSNumber numberWithUnsignedInteger:[items count]] forKey:@"itemCount"];
        if (![items count]) return report;
        NSDictionary *first = [items objectAtIndex:0];
        payload = API(origin, token, [@"item/" stringByAppendingString:FNTVEscape([first objectForKey:@"guid"])], nil, op, &failure);
        NSDictionary *detail = FNTVNormalizeItem(payload);
        [report setObject:(detail ? @"passed" : @"failed") forKey:@"detailCheck"];
        NSString *type = [detail objectForKey:@"type"] ?: [first objectForKey:@"type"];
        if ([[NSArray arrayWithObjects:@"Movie", @"TV", @"Season", @"Episode", @"Video", @"Directory", nil] containsObject:type]) [report setObject:type forKey:@"itemType"];
        NSString *poster = [detail objectForKey:@"poster"];
        if (![poster length]) poster = [first objectForKey:@"poster"];
        if ([poster length]) {
            NSData *data = [FNTVHTTP fetchURL:FNTVImageURL(origin, poster) origin:origin method:@"GET" body:nil token:token range:nil limit:4*1024*1024 operation:op streamFD:-1 response:NULL error:&failure];
            UIImage *image = data ? DecodeImage(data) : nil;
            [report setObject:(image ? @"passed" : @"failed") forKey:@"imageCheck"];
            if (image) { [report setObject:[NSNumber numberWithInt:(int)image.size.width] forKey:@"imageWidth"]; [report setObject:[NSNumber numberWithInt:(int)image.size.height] forKey:@"imageHeight"]; }
        } else [report setObject:@"no_poster" forKey:@"imageCheck"];
        if (failure) [report setObject:[NSNumber numberWithInteger:[failure code]] forKey:@"errorCode"];
        return report;
    } completion:completion];
}
#endif
- (void)discardPreparedPlayback:(NSDictionary *)playback {
    if ([playback isKindOfClass:[NSDictionary class]] && [_proxy stopIfPlaybackURL:[playback objectForKey:@"URL"]]) {
        [_proxy release]; _proxy = nil;
    }
}
- (void)stopPlayback { [_proxy stop]; [_proxy release]; _proxy = nil; }
- (void)clearImageCache { [_imageCache removeAllObjects]; }
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; [self logout];
    [_queue release]; [_imageQueue release]; [_recordQueue release]; [_imageCache release]; [_serverURL release]; [_username release]; [super dealloc];
}
@end
