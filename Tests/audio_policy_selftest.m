#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "FNTVAudio.h"
NSString * const AVAudioSessionCategoryPlayback = @"Playback";
static BOOL CategoryOK = YES, ActivationOK = YES, DeactivationOK = YES, MethodsAvailable = YES;
static BOOL CategoryThrows;
static NSUInteger CategoryCalls, ActivateCalls, DeactivateCalls;
@implementation AVAudioSession
+ (AVAudioSession *)sharedInstance { static AVAudioSession *session; if (!session) session = [[self alloc] init]; return session; }
- (BOOL)respondsToSelector:(SEL)selector {
    if (!MethodsAvailable && (selector == @selector(setCategory:error:) || selector == @selector(setActive:error:))) return NO;
    return [super respondsToSelector:selector];
}
- (BOOL)setCategory:(NSString *)category error:(NSError **)error {
    CategoryCalls++; NSCAssert([category isEqualToString:AVAudioSessionCategoryPlayback], @"Only Playback category");
    if (!CategoryOK && error) *error = [NSError errorWithDomain:@"fixture" code:101 userInfo:nil];
    return CategoryOK;
}
- (BOOL)setActive:(BOOL)active error:(NSError **)error {
    if (active) { ActivateCalls++; if (!ActivationOK && error) *error = [NSError errorWithDomain:@"fixture" code:102 userInfo:nil]; return ActivationOK; }
    DeactivateCalls++; if (!DeactivationOK && error) *error = [NSError errorWithDomain:@"fixture" code:103 userInfo:nil]; return DeactivationOK;
}
- (NSString *)category { if (CategoryThrows) [NSException raise:NSInvalidArgumentException format:@"fixture category getter"]; return AVAudioSessionCategoryPlayback; }
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSError *error = nil;
    MethodsAvailable = NO;
    NSCAssert(FNTVBeginPlaybackAudio(&error) == 0 && error && CategoryCalls == 0, @"Absent standard API fails before calls");
    MethodsAvailable = YES; CategoryOK = NO; error = nil;
    NSCAssert(FNTVBeginPlaybackAudio(&error) == 0 && [error code] == 101 && ActivateCalls == 0, @"Category failure prevents activation");
    CategoryOK = YES; ActivationOK = NO; error = nil;
    NSCAssert(FNTVBeginPlaybackAudio(&error) == 0 && [error code] == 102, @"Activation failure is returned");
    ActivationOK = YES; NSUInteger first = FNTVBeginPlaybackAudio(&error), second = FNTVBeginPlaybackAudio(&error);
    NSCAssert(first && second && first != second && !FNTVPlaybackAudioLeaseIsCurrent(first) && FNTVPlaybackAudioLeaseIsCurrent(second), @"New player owns a new audio lease");
    NSCAssert(FNTVEndPlaybackAudio(first, &error) && DeactivateCalls == 0, @"Late old cleanup cannot deactivate current audio");
    DeactivationOK = NO; error = nil;
    NSCAssert(!FNTVEndPlaybackAudio(second, &error) && [error code] == 103 && FNTVPlaybackAudioLeaseIsCurrent(second), @"Failed deactivation remains retryable");
    DeactivationOK = YES;
    NSCAssert(FNTVEndPlaybackAudio(second, &error) && !FNTVPlaybackAudioLeaseIsCurrent(second) && DeactivateCalls == 2, @"Current lease can release its session");
    NSCAssert(FNTVEndPlaybackAudio(second, &error) && DeactivateCalls == 2, @"Repeated release is harmless");
    NSCAssert(FNTVReadPlaybackAudioCategory() == 1, @"Read back the actual session category");
    CategoryThrows = YES; NSCAssert(FNTVReadPlaybackAudioCategory() == -1, @"Diagnostic category read cannot crash playback");
    puts("PASS audio policy: capability checks, category/activation errors, exact lease ownership, retry and idempotent release");
    [pool drain]; return 0;
}
