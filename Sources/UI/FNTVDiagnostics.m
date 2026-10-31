#import "FNTVDiagnostics.h"
#import <math.h>
#if FNTV_DIAGNOSTICS
NSDictionary *FNTVConsumeDiagnosticLogin(NSString *path, NSError **error) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
    if (!attributes) return nil;
    NSString *type = [attributes objectForKey:NSFileType];
    if ([type isEqualToString:NSFileTypeDirectory]) {
        if (error) *error = [NSError errorWithDomain:@"FNTVDiagnostics" code:1 userInfo:
            [NSDictionary dictionaryWithObject:@"一次性测试登录路径不是文件，未读取。" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    NSData *data = nil;
    BOOL bounded = [[attributes objectForKey:NSFileSize] unsignedLongLongValue] <= 16384;
    BOOL privateFile = ([[attributes objectForKey:NSFilePosixPermissions] unsignedIntegerValue] & 0777) == 0600;
    if ([type isEqualToString:NSFileTypeRegular] && bounded && privateFile) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
        @try { data = [handle readDataOfLength:16385]; } @catch (NSException *exception) { (void)exception; data = nil; }
        @try { [handle closeFile]; } @catch (NSException *exception) { (void)exception; }
    }
    // Delete before parsing or submitting; a failed deletion must never submit credentials.
    BOOL deleted = [manager removeItemAtPath:path error:NULL];
    id parsed = deleted && [data length] <= 16384 && [data length] > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [NSArray arrayWithObjects:@"server", @"username", @"password", nil];
        NSUInteger limits[] = { 2048, 512, 4096 };
        BOOL valid = YES;
        for (NSUInteger i = 0; i < [keys count]; i++) {
            id value = [parsed objectForKey:[keys objectAtIndex:i]];
            if (![value isKindOfClass:[NSString class]] || ![value length] || [value length] > limits[i]) { valid = NO; break; }
        }
        if (valid) return [NSDictionary dictionaryWithObjectsAndKeys:[parsed objectForKey:@"server"], @"server",
            [parsed objectForKey:@"username"], @"username", [parsed objectForKey:@"password"], @"password", nil];
    }
    if (error) *error = [NSError errorWithDomain:@"FNTVDiagnostics" code:2 userInfo:[NSDictionary dictionaryWithObject:
        (deleted ? @"一次性测试登录文件无效，已删除。" : @"无法删除一次性测试登录文件，未提交登录。") forKey:NSLocalizedDescriptionKey]];
    return nil;
}
NSInteger FNTVConsumeSmokeCommand(NSString *path, NSDate *now, NSTimeInterval *age) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
    if (!attributes) return 0;
    if ([[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) return 4;
    NSData *data = nil;
    BOOL regular = [[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular];
    BOOL bounded = [[attributes objectForKey:NSFileSize] unsignedLongLongValue] <= 1024;
    BOOL privateFile = ([[attributes objectForKey:NSFilePosixPermissions] unsignedIntegerValue] & 0777) == 0600;
    if (regular && bounded && privateFile) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
        @try { data = [handle readDataOfLength:1025]; } @catch (NSException *exception) { (void)exception; data = nil; }
        @try { [handle closeFile]; } @catch (NSException *exception) { (void)exception; }
    }
    if (![manager removeItemAtPath:path error:NULL]) return 4;
    NSDate *modified = [attributes objectForKey:NSFileModificationDate];
    if (![modified isKindOfClass:[NSDate class]]) return 4;
    NSTimeInterval elapsed = [now timeIntervalSinceDate:modified];
    if (!isfinite(elapsed)) return 4;
    if (age) *age = elapsed;
    if (elapsed > 300 || elapsed < -60) return 3;
    id command = [data length] > 0 && [data length] <= 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![command isKindOfClass:[NSDictionary class]] || [command count] != 2) return 4;
    id schema = [command objectForKey:@"schema"];
    if (![schema isKindOfClass:[NSNumber class]] || [schema doubleValue] != 1) return 4;
    return [[command objectForKey:@"action"] isEqual:@"foreground-movie-smoke"] ? 1 : 4;
}
NSTimeInterval FNTVSmokeAdvance(NSTimeInterval previous, NSTimeInterval current, BOOL playing) {
    if (!playing || !isfinite(previous) || !isfinite(current) || previous < 0 || current < 0) return 0;
    NSTimeInterval delta = current - previous;
    return delta > 0.05 && delta <= 2.5 ? delta : 0;
}
BOOL FNTVSmokeWithinDeadline(NSTimeInterval elapsed) { return isfinite(elapsed) && elapsed >= 0 && elapsed < 60; }
#endif
