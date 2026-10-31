// Actual release scheduler, with deterministic main-queue/audio stand-ins and no system audio calls.
#import "../Sources/UI/FNTVAudio.m"
NSString * const AVAudioSessionCategoryPlayback = @"Playback";
static NSMutableArray *Tasks, *Records, *Delays;
static NSArray *Answers;
static NSUInteger DeactivateCalls, ActivateCalls, StopCalls;
static BOOL FrameworkReleased, RequireFrameworkRelease;
@implementation AVAudioSession
+ (AVAudioSession *)sharedInstance { static AVAudioSession *session; if (!session) session = [[self alloc] init]; return session; }
- (BOOL)setCategory:(NSString *)category error:(NSError **)error { (void)error; return [category isEqual:AVAudioSessionCategoryPlayback]; }
- (BOOL)setActive:(BOOL)active error:(NSError **)error {
    if (active) { ActivateCalls++; return YES; }
    NSCAssert(!RequireFrameworkRelease || FrameworkReleased, @"Deactivate cannot precede superclass I/O release");
    BOOL answer = DeactivateCalls < [Answers count] ? [[Answers objectAtIndex:DeactivateCalls] boolValue] : YES;
    DeactivateCalls++;
    if (!answer && error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:560030580 userInfo:nil];
    return answer;
}
- (NSString *)category { return AVAudioSessionCategoryPlayback; }
@end
static void Schedule(NSTimeInterval delay, void (^work)(void)) {
    void (^copy)(void) = [work copy];
    [Tasks addObject:[NSDictionary dictionaryWithObjectsAndKeys:copy, @"work", [NSNumber numberWithDouble:delay], @"delay", nil]];
    [copy release];
}
static void Record(NSUInteger lease, NSUInteger attempt, NSInteger result, NSInteger error, NSTimeInterval elapsed) {
    (void)elapsed; [Records addObject:[NSDictionary dictionaryWithObjectsAndKeys:@(lease), @"lease", @(attempt), @"attempt", @(result), @"result", @(error), @"error", nil]];
}
static void Next(void) {
    NSDictionary *entry = [[[Tasks objectAtIndex:0] retain] autorelease]; [Tasks removeObjectAtIndex:0];
    [Delays addObject:[entry objectForKey:@"delay"]]; void (^work)(void) = [entry objectForKey:@"work"]; work();
}
static void Drain(void) { NSUInteger count = 0; while ([Tasks count]) { NSCAssert(++count <= 8, @"Retry chain is bounded"); Next(); } }
static void Reset(NSArray *answers) {
    NSCAssert(![Tasks count], @"No pending work between fixtures");
    [Records removeAllObjects]; [Delays removeAllObjects]; Answers = answers;
    AudioSequence = CurrentAudioLease = ScheduledAudioLease = 0;
    DeactivateCalls = ActivateCalls = StopCalls = 0; FrameworkReleased = NO; RequireFrameworkRelease = NO;
}
@interface FrameworkPlayer : NSObject
@end
@implementation FrameworkPlayer
- (void)dealloc { FrameworkReleased = YES; [super dealloc]; }
@end
@interface ClosingPlayer : FrameworkPlayer { NSUInteger _lease; BOOL _stopped; }
- (id)initWithLease:(NSUInteger)lease;
- (void)disappear;
@end
@implementation ClosingPlayer
- (id)initWithLease:(NSUInteger)lease { if ((self = [super init])) _lease = lease; return self; }
- (void)disappear { FNTVStopPlaybackAudioIOOnce(_lease, &_stopped, ^{ StopCalls++; [self disappear]; }); }
- (void)dealloc { [self disappear]; NSUInteger lease = _lease; [super dealloc]; FNTVSchedulePlaybackAudioRelease(lease); }
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Tasks = [[NSMutableArray alloc] init]; Records = [[NSMutableArray alloc] init]; Delays = [[NSMutableArray alloc] init];
    AudioReleaseSchedule = Schedule; AudioReleaseRecord = Record;
    Reset(@[@YES]); RequireFrameworkRelease = YES;
    NSUInteger lease = FNTVBeginPlaybackAudio(NULL); ClosingPlayer *player = [[ClosingPlayer alloc] initWithLease:lease];
    [player disappear]; [player disappear]; [player release];
    NSCAssert(FrameworkReleased && StopCalls == 1 && DeactivateCalls == 0 && [Tasks count] == 1, @"Synchronous stop reentry is once-only; queued work does not retain controller");
    Drain(); NSCAssert(DeactivateCalls == 1 && !FNTVPlaybackAudioLeaseIsCurrent(lease), @"Release runs after superclass disposal");
    Reset(@[@NO, @NO, @YES]); lease = FNTVBeginPlaybackAudio(NULL);
    FNTVSchedulePlaybackAudioRelease(lease); Drain();
    NSCAssert(DeactivateCalls == 3 && ActivateCalls == 1 && [[[Records lastObject] objectForKey:@"result"] integerValue] == 1, @"Delayed BOOL success releases without reactivation");
    NSCAssert([[Delays objectAtIndex:1] doubleValue] == 0.1 && [[Delays objectAtIndex:2] doubleValue] == 0.2, @"Fixed retry delays");
    Reset(@[@NO, @NO, @NO, @NO]); lease = FNTVBeginPlaybackAudio(NULL);
    FNTVSchedulePlaybackAudioRelease(lease); Drain();
    NSCAssert(DeactivateCalls == 4 && ActivateCalls == 1 && FNTVPlaybackAudioLeaseIsCurrent(lease), @"Four failures are not treated as released");
    NSCAssert([[[Records lastObject] objectForKey:@"result"] integerValue] == 4 && [[[Records lastObject] objectForKey:@"error"] integerValue] == 560030580 && [[Delays lastObject] doubleValue] == 0.7, @"Final !act and fixed one-second backoff are retained");
    FNTVSchedulePlaybackAudioRelease(lease); Drain(); NSCAssert(DeactivateCalls == 4, @"Duplicate scheduling cannot create an unbounded retry");
    Reset(@[@YES]); NSUInteger old = FNTVBeginPlaybackAudio(NULL); FNTVSchedulePlaybackAudioRelease(old);
    NSUInteger newer = FNTVBeginPlaybackAudio(NULL); Drain(); BOOL stopped = NO;
    FNTVStopPlaybackAudioIOOnce(old, &stopped, ^{ StopCalls++; });
    NSCAssert(DeactivateCalls == 0 && StopCalls == 0 && FNTVPlaybackAudioLeaseIsCurrent(newer) && [[[Records lastObject] objectForKey:@"result"] integerValue] == 2, @"Old queued release cannot stop or deactivate a new player");
    Reset(@[@NO]); old = FNTVBeginPlaybackAudio(NULL); FNTVSchedulePlaybackAudioRelease(old); Next();
    newer = FNTVBeginPlaybackAudio(NULL); Drain();
    NSCAssert(DeactivateCalls == 1 && FNTVPlaybackAudioLeaseIsCurrent(newer) && [[[Records lastObject] objectForKey:@"result"] integerValue] == 2, @"Ownership is rechecked between retry attempts");
    Reset(@[@YES]); lease = FNTVBeginPlaybackAudio(NULL); FNTVSchedulePlaybackAudioRelease(lease);
    NSCAssert(DeactivateCalls == 0, @"Rejected preparation/no-player cleanup is also asynchronous");
    Drain(); NSCAssert(DeactivateCalls == 1 && !FNTVPlaybackAudioLeaseIsCurrent(lease), @"No-player paths release their own lease");
    puts("PASS actual audio release flow: stop reentry, post-super scheduling, lease-only lifetime, old/new ownership, delayed success, final !act failure, no-player cleanup");
    [Tasks release]; [Records release]; [Delays release]; [pool drain]; return 0;
}
