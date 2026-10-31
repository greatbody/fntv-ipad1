#import "FNTVAudio.h"
#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>
static NSUInteger AudioSequence, CurrentAudioLease;
static NSError *AudioError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"FNTVAudio" code:code userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}
static AVAudioSession *PlaybackSession(NSError **error) {
    AVAudioSession *session = [AVAudioSession respondsToSelector:@selector(sharedInstance)] ? [AVAudioSession sharedInstance] : nil;
    if (!session || ![session respondsToSelector:@selector(setCategory:error:)] || ![session respondsToSelector:@selector(setActive:error:)]) {
        if (error) *error = AudioError(1, @"本设备无法配置播放音频会话。");
        return nil;
    }
    return session;
}
NSUInteger FNTVBeginPlaybackAudio(NSError **error) {
    AVAudioSession *session = PlaybackSession(error); if (!session) return 0;
    NSError *failure = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&failure]) {
        if (error) *error = failure ?: AudioError(2, @"无法设置播放音频类别。"); return 0;
    }
    failure = nil;
    if (![session setActive:YES error:&failure]) {
        if (error) *error = failure ?: AudioError(3, @"无法启用播放声音。"); return 0;
    }
    if (++AudioSequence == 0) ++AudioSequence;
    CurrentAudioLease = AudioSequence; return CurrentAudioLease;
}
BOOL FNTVPlaybackAudioLeaseIsCurrent(NSUInteger lease) { return lease && lease == CurrentAudioLease; }
BOOL FNTVEndPlaybackAudio(NSUInteger lease, NSError **error) {
    if (!FNTVPlaybackAudioLeaseIsCurrent(lease)) return YES;
    AVAudioSession *session = PlaybackSession(error); if (!session) return NO;
    NSError *failure = nil;
    if (![session setActive:NO error:&failure]) {
        if (error) *error = failure ?: AudioError(4, @"无法释放播放音频会话。"); return NO;
    }
    if (CurrentAudioLease == lease) CurrentAudioLease = 0;
    return YES;
}
void FNTVStopPlaybackAudioIOOnce(NSUInteger lease, BOOL *stopped, void (^stopIO)(void)) {
    if (*stopped) return;
    *stopped = YES;
    if (FNTVPlaybackAudioLeaseIsCurrent(lease)) stopIO();
}
static void EnqueueAudioRelease(NSTimeInterval delay, void (^work)(void)) {
    if (delay <= 0) dispatch_async(dispatch_get_main_queue(), work);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}
static void LogAudioRelease(NSUInteger lease, NSUInteger attempt, NSInteger result, NSInteger error, NSTimeInterval elapsed) {
#if FNTV_DIAGNOSTICS
    NSLog(@"FNTV_AUDIO_RELEASE lease=%lu attempt=%lu result=%ld error=%ld elapsed=%.3f",
        (unsigned long)lease, (unsigned long)attempt, (long)result, (long)error, elapsed);
#else
    (void)lease; (void)attempt; (void)result; (void)error; (void)elapsed;
#endif
}
// Private seams let fixtures exercise the production retry flow without real audio or delays.
static void (*AudioReleaseSchedule)(NSTimeInterval, void (^)(void)) = EnqueueAudioRelease;
static void (*AudioReleaseRecord)(NSUInteger, NSUInteger, NSInteger, NSInteger, NSTimeInterval) = LogAudioRelease;
static NSUInteger ScheduledAudioLease;
static void AttemptAudioRelease(NSUInteger lease, NSUInteger attempt, NSTimeInterval started) {
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - started;
    if (!FNTVPlaybackAudioLeaseIsCurrent(lease)) { AudioReleaseRecord(lease, attempt, 2, 0, elapsed); return; }
    NSError *error = nil;
    if (FNTVEndPlaybackAudio(lease, &error)) { AudioReleaseRecord(lease, attempt, 1, 0, elapsed); return; }
    AudioReleaseRecord(lease, attempt, attempt < 4 ? 3 : 4, [error code], elapsed);
    if (attempt < 4) {
        const NSTimeInterval delays[] = { 0.1, 0.2, 0.7 };
        AudioReleaseSchedule(delays[attempt - 1], ^{ AttemptAudioRelease(lease, attempt + 1, started); });
    }
}
void FNTVSchedulePlaybackAudioRelease(NSUInteger lease) {
    if (!lease) return;
    // This block captures only the scalar lease, never a controller or movie object.
    AudioReleaseSchedule(0, ^{
        if (ScheduledAudioLease == lease) return;
        if (!FNTVPlaybackAudioLeaseIsCurrent(lease)) { AudioReleaseRecord(lease, 0, 2, 0, 0); return; }
        ScheduledAudioLease = lease;
        AudioReleaseRecord(lease, 0, 0, 0, 0);
        AttemptAudioRelease(lease, 1, [NSDate timeIntervalSinceReferenceDate]);
    });
}
#if FNTV_DIAGNOSTICS
NSInteger FNTVReadPlaybackAudioCategory(void) {
    @try {
        if (![AVAudioSession respondsToSelector:@selector(sharedInstance)]) return -1;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        if (![session respondsToSelector:@selector(category)]) return -1;
        NSString *category = session.category;
        return [category isKindOfClass:[NSString class]] ? ([category isEqualToString:AVAudioSessionCategoryPlayback] ? 1 : 0) : -1;
    } @catch (NSException *exception) { (void)exception; return -1; }
}
#endif
