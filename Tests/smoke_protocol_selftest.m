#import <Foundation/Foundation.h>
#import "FNTVDiagnostics.h"
#import <math.h>
static void Write(NSString *path, id command, NSDate *modified) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:NULL];
    NSCAssert([data writeToFile:path atomically:YES], @"Write fixture");
    [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:@0600, NSFilePosixPermissions, modified, NSFileModificationDate, nil] ofItemAtPath:path error:NULL];
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [directory stringByAppendingPathComponent:@".fntv-player-smoke.json"];
    NSDictionary *valid = [NSDictionary dictionaryWithObjectsAndKeys:@1, @"schema", @"foreground-movie-smoke", @"action", nil];
    NSDate *now = [NSDate date]; NSTimeInterval age = 0;
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 0, @"Absent command does nothing");
    Write(path, valid, now);
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 1 && ![files fileExistsAtPath:path], @"One-shot command consumed before execution");
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 0, @"Cannot replay a consumed command");
    Write(path, valid, [now dateByAddingTimeInterval:-301]);
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 3 && ![files fileExistsAtPath:path], @"Stale command deleted without execution");
    Write(path, valid, [now dateByAddingTimeInterval:120]);
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 3 && ![files fileExistsAtPath:path], @"Future command cannot schedule playback");
    NSMutableDictionary *extra = [NSMutableDictionary dictionaryWithDictionary:valid]; [extra setObject:@"http://example.invalid" forKey:@"url"];
    Write(path, extra, now);
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 4 && ![files fileExistsAtPath:path], @"Reject arbitrary URL/extra fields");
    Write(path, [NSDictionary dictionaryWithObjectsAndKeys:@1, @"schema", @"other", @"action", nil], now);
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 4, @"No general command dispatcher");
    Write(path, valid, now); [files setAttributes:[NSDictionary dictionaryWithObject:@0644 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 4 && ![files fileExistsAtPath:path], @"Private command file required");
    [[NSMutableData dataWithLength:1025] writeToFile:path atomically:YES];
    NSCAssert(FNTVConsumeSmokeCommand(path, now, &age) == 4 && ![files fileExistsAtPath:path], @"Bounded command read");
    NSCAssert(FNTVSmokeAdvance(10, 11, YES) == 1, @"Observed normal advancement");
    NSCAssert(FNTVSmokeAdvance(10, 11, NO) == 0 && FNTVSmokeAdvance(10, 10, YES) == 0, @"Paused/stalled does not pass");
    NSCAssert(FNTVSmokeAdvance(10, 300, YES) == 0 && FNTVSmokeAdvance(10, 2, YES) == 0, @"Seek jumps do not fake continuous advancement");
    NSCAssert(FNTVSmokeAdvance(-1, 0, YES) == 0 && FNTVSmokeAdvance(NAN, 1, YES) == 0, @"Unknown/nonfinite time is not evidence");
    NSCAssert(FNTVSmokeWithinDeadline(0) && FNTVSmokeWithinDeadline(59.99), @"Waiting consumes the same bounded deadline");
    NSCAssert(!FNTVSmokeWithinDeadline(60) && !FNTVSmokeWithinDeadline(-1) && !FNTVSmokeWithinDeadline(NAN), @"No late or invalid-clock autoplay");
    [files removeItemAtPath:directory error:NULL];
    puts("PASS smoke protocol: consume-once, age bounds, fixed action, private/bounded file, real-time advancement criteria");
    [pool drain]; return 0;
}
