// Compile the actual coordinator/dispatch path against small platform stand-ins, without a device or NAS.
#import "../Sources/UI/FNTVForegroundSmoke.m"
NSString * const UIApplicationDidBecomeActiveNotification = @"Active";
NSString * const UIApplicationWillResignActiveNotification = @"Inactive";
NSString * const MPMoviePlayerPlaybackDidFinishNotification = @"Finished";
NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey = @"Reason";
static NSUInteger Presentations, Discards, Cancellations, Dismissals;
static NSInteger LastOutcome;
BOOL FNTVPlaybackAudioLeaseIsCurrent(NSUInteger lease) { return lease == 7; }
NSInteger FNTVReadPlaybackAudioCategory(void) { return 1; }
@implementation UIView
@synthesize window = _window;
- (void)dealloc { [_window release]; [super dealloc]; }
@end
@implementation UIViewController
@synthesize presentingViewController = _presentingViewController, presentedViewController = _presentedViewController, view = _view;
- (void)dismissMoviePlayerViewControllerAnimated { Dismissals++; _presentedViewController.presentingViewController = nil; self.presentedViewController = nil; }
- (void)dealloc { [_presentedViewController release]; [_view release]; [super dealloc]; }
@end
@implementation UIApplication
@synthesize applicationState = _applicationState;
+ (UIApplication *)sharedApplication { static UIApplication *app; if (!app) app = [[self alloc] init]; return app; }
@end
@implementation MPMoviePlayerController
@synthesize currentPlaybackTime = _currentPlaybackTime, duration = _duration, playbackState = _playbackState, loadState = _loadState, isPreparedToPlay = _isPreparedToPlay;
@synthesize playableDuration = _playableDuration, movieMediaTypes = _movieMediaTypes, useApplicationAudioSession = _useApplicationAudioSession, accessLog = _accessLog;
- (void)dealloc { [_accessLog release]; [super dealloc]; }
@end
@implementation MPMovieAccessLogEvent
@synthesize numberOfStalls = _numberOfStalls, numberOfDroppedVideoFrames = _numberOfDroppedVideoFrames, numberOfSegmentsDownloaded = _numberOfSegmentsDownloaded, numberOfBytesTransferred = _numberOfBytesTransferred, observedBitrate = _observedBitrate, indicatedBitrate = _indicatedBitrate;
@end
@implementation MPMovieAccessLog
@synthesize events = _events;
- (void)dealloc { [_events release]; [super dealloc]; }
@end
@interface BareMovie : NSObject {
    NSTimeInterval _currentPlaybackTime, _duration;
    NSInteger _playbackState;
    NSUInteger _loadState;
    BOOL _isPreparedToPlay;
}
@property(nonatomic) NSTimeInterval currentPlaybackTime, duration;
@property(nonatomic) NSInteger playbackState;
@property(nonatomic) NSUInteger loadState;
@property(nonatomic) BOOL isPreparedToPlay;
@end
@implementation BareMovie
@synthesize currentPlaybackTime = _currentPlaybackTime, duration = _duration, playbackState = _playbackState, loadState = _loadState, isPreparedToPlay = _isPreparedToPlay;
@end
@interface PartialMovie : BareMovie { id _accessLog; }
@property(nonatomic, retain) id accessLog;
@end
@implementation PartialMovie
@synthesize accessLog = _accessLog;
- (NSTimeInterval)playableDuration { return 7; }
- (NSUInteger)movieMediaTypes { return 3; }
- (void)dealloc { [_accessLog release]; [super dealloc]; }
@end
@interface PartialAccessEvent : NSObject
@end
@implementation PartialAccessEvent
- (NSInteger)numberOfStalls { return 7; }
@end
@interface ThrowingAccessEvent : PartialAccessEvent
@end
@implementation ThrowingAccessEvent
- (double)observedBitrate { [NSException raise:NSInvalidArgumentException format:@"fixture getter failure"]; return 0; }
@end
@interface ThrowingLegacyMovie : MPMoviePlayerController
@end
@implementation ThrowingLegacyMovie
- (BOOL)useApplicationAudioSession { [NSException raise:NSInvalidArgumentException format:@"fixture legacy getter failure"]; return NO; }
@end
@implementation MPMoviePlayerViewController
@synthesize moviePlayer = _moviePlayer;
- (void)dealloc { [_moviePlayer release]; [super dealloc]; }
@end
@implementation FNTVClient
@synthesize authenticated = _authenticated;
+ (FNTVClient *)sharedClient { static FNTVClient *client; if (!client) { client = [[self alloc] init]; client.authenticated = YES; } return client; }
@end
@interface TestSmoke : FNTVForegroundSmoke
@end
@implementation TestSmoke
- (void)writeReport { LastOutcome = _outcome; }
@end
static void NewRun(id detail, BOOL prepare) {
    NSCAssert(!ActiveSmoke, @"Previous run ended");
    ActiveSmoke = [[TestSmoke alloc] init]; LastOutcome = -1;
    [UIApplication sharedApplication].applicationState = UIApplicationStateActive;
    [FNTVClient sharedClient].authenticated = YES;
    NSCAssert(FNTVSmokeSelectMovie(@"fixture-movie"), @"Select through production coordinator");
    FNTVSmokeBindDetail(@"fixture-movie", detail);
    if (prepare) NSCAssert(FNTVSmokeStartPlayback(@"fixture-movie", detail), @"Existing play path selected once");
}
static NSOperation *Track(void) {
    NSOperation *operation = [[[NSOperation alloc] init] autorelease];
    FNTVSmokeTrackPreparation(@"fixture-movie", operation, ^{ Cancellations++; [operation cancel]; });
    return operation;
}
static void SetElapsed(NSTimeInterval seconds) { [ActiveSmoke->_started release]; ActiveSmoke->_started = [[NSDate dateWithTimeIntervalSinceNow:-seconds] retain]; }
static void Completion(UIViewController *detail, NSOperation *operation, BOOL wasSmoke, BOOL currentDetail) {
    FNTVSmokeCompletePreparation(@"fixture-movie", detail, operation, wasSmoke, currentDetail, ^{
        Presentations++;
        MPMoviePlayerViewController *player = [[[MPMoviePlayerViewController alloc] init] autorelease];
        FNTVSmokeAttachPlayer(@"fixture-movie", operation, player, 7);
        player.presentingViewController = detail; detail.presentedViewController = player;
    }, ^{ Discards++; });
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIViewController *detail = [[[UIViewController alloc] init] autorelease];
    UIViewController *reentered = [[[UIViewController alloc] init] autorelease];
    NewRun(detail, YES); NSOperation *operation = Track(); SetElapsed(61);
    Completion(detail, operation, YES, YES);
    NSCAssert(Presentations == 0 && Discards == 1 && Cancellations == 1 && LastOutcome == 2 && !ActiveSmoke, @"Late completion rejects before present even when timer never ticked");
    NewRun(detail, YES); operation = Track(); ActiveSmoke->_commandAge = 295; SetElapsed(10);
    Completion(detail, operation, YES, YES);
    NSCAssert(Presentations == 0 && Discards == 2 && LastOutcome == 3 && !ActiveSmoke, @"Expired command rechecked in completion");
    NewRun(detail, YES); operation = Track(); [UIApplication sharedApplication].applicationState = UIApplicationStateInactive;
    Completion(detail, operation, YES, YES);
    NSCAssert(Presentations == 0 && Discards == 3 && LastOutcome == 6 && !ActiveSmoke, @"Foreground loss rechecked synchronously");
    NewRun(detail, YES); operation = Track(); Completion(detail, operation, YES, NO);
    NSCAssert(Presentations == 0 && Discards == 4 && !ActiveSmoke, @"Losing the current detail prevents presentation");
    NewRun(detail, YES); operation = Track();
    NSOperation *manual = [[[NSOperation alloc] init] autorelease]; Completion(reentered, manual, NO, NO);
    NSCAssert(Presentations == 1 && ActiveSmoke && !operation.isCancelled, @"Manual playback is not gated by the smoke");
    reentered.presentedViewController = nil;
    Completion(reentered, manual, YES, YES);
    NSCAssert(Presentations == 1 && Discards == 5 && ActiveSmoke && !operation.isCancelled, @"Another operation cannot capture or end this run");
    FNTVSmokeDetailPopped(detail);
    NSCAssert(!ActiveSmoke && operation.isCancelled, @"Back during prepare cancels only its operation");
    Completion(detail, operation, YES, YES);
    NSCAssert(Presentations == 1 && Discards == 6, @"Cancelled late callback cannot become manual playback");
    NewRun(detail, NO); FNTVSmokeDetailPopped(reentered);
    NSCAssert(ActiveSmoke != nil, @"Popping another controller does not cancel this detail");
    FNTVSmokeDetailPopped(detail); FNTVSmokeBindDetail(@"fixture-movie", reentered);
    NSCAssert(!ActiveSmoke && !FNTVSmokeStartPlayback(@"fixture-movie", reentered), @"Back then reenter same movie cannot restart stage1");
    NewRun(detail, YES); operation = Track(); Completion(detail, operation, YES, YES);
    NSCAssert(Presentations == 2 && ActiveSmoke && ActiveSmoke->_stage == 3, @"Valid completion reaches actual attach/presentation branch");
    MPMoviePlayerController *movie = [[[MPMoviePlayerController alloc] init] autorelease];
    ActiveSmoke->_player.moviePlayer = movie;
    ActiveSmoke->_player.view = [[[UIView alloc] init] autorelease]; ActiveSmoke->_player.view.window = detail;
    movie.currentPlaybackTime = 4; movie.duration = 100; movie.playableDuration = 9; movie.movieMediaTypes = 3;
    movie.playbackState = MPMoviePlaybackStatePlaying; movie.loadState = 3; movie.isPreparedToPlay = YES;
    [ActiveSmoke tick:nil];
    NSDictionary *sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"accessLogEvents"] integerValue] == 0 && [[sample objectForKey:@"stalls"] integerValue] == -1, @"Absent access log is unknown, not zero stalls");
    movie.accessLog = [[[MPMovieAccessLog alloc] init] autorelease];
    MPMovieAccessLogEvent *event = [[[MPMovieAccessLogEvent alloc] init] autorelease];
    event.numberOfStalls = 2; event.numberOfDroppedVideoFrames = 3; event.numberOfSegmentsDownloaded = 4;
    event.numberOfBytesTransferred = 5000; event.observedBitrate = 2000000; event.indicatedBitrate = 1000000;
    movie.accessLog.events = [NSArray arrayWithObject:event]; movie.currentPlaybackTime = 5;
    [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"stalls"] integerValue] == 2 && [[sample objectForKey:@"droppedFrames"] integerValue] == 3 && [[sample objectForKey:@"bytes"] longLongValue] == 5000, @"Actual production sampler reports only selected numeric access metrics");
    NSCAssert([[sample objectForKey:@"playableDuration"] doubleValue] == 9 && [[sample objectForKey:@"movieMediaTypes"] integerValue] == 3 && [[sample objectForKey:@"useApplicationAudioSession"] integerValue] == 0, @"Buffer/media/audio policy values are preserved");
    NSCAssert([[sample objectForKey:@"audioCategoryPlayback"] integerValue] == 1 && [[sample objectForKey:@"audioLeaseCurrent"] integerValue] == 1, @"Session readback and this player's ownership are separate numeric values");
    event.observedBitrate = NAN; movie.playableDuration = INFINITY; [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"observedBitrate"] doubleValue] == -1 && [[sample objectForKey:@"playableDuration"] doubleValue] == -1, @"Nonfinite metrics remain valid numeric JSON");
    for (id value in [sample allValues]) NSCAssert([value isKindOfClass:[NSNumber class]], @"No access-log strings or URLs in samples");
    BareMovie *bare = [[[BareMovie alloc] init] autorelease]; bare.playbackState = MPMoviePlaybackStatePlaying;
    ActiveSmoke->_player.moviePlayer = (MPMoviePlayerController *)bare; [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert(![bare respondsToSelector:@selector(useApplicationAudioSession)] && ![bare respondsToSelector:@selector(accessLog)], @"Stand-in genuinely lacks selectors");
    for (NSString *key in [NSArray arrayWithObjects:@"playableDuration", @"movieMediaTypes", @"useApplicationAudioSession", @"accessLogEvents", @"stalls", @"droppedFrames", @"observedBitrate", @"indicatedBitrate", @"segments", @"bytes", nil])
        NSCAssert([[sample objectForKey:key] doubleValue] == -1, @"Missing optional selector is unknown, not a crash");
    PartialMovie *partial = [[[PartialMovie alloc] init] autorelease]; partial.playbackState = MPMoviePlaybackStatePlaying;
    partial.accessLog = [[[NSObject alloc] init] autorelease]; ActiveSmoke->_player.moviePlayer = (MPMoviePlayerController *)partial;
    [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"playableDuration"] doubleValue] == 7 && [[sample objectForKey:@"useApplicationAudioSession"] integerValue] == -1 && [[sample objectForKey:@"accessLogEvents"] integerValue] == -1, @"Getter absence remains safe when other movie getters work and log lacks events");
    MPMovieAccessLog *partialLog = [[[MPMovieAccessLog alloc] init] autorelease]; partial.accessLog = partialLog;
    partialLog.events = [NSArray arrayWithObject:[[[PartialAccessEvent alloc] init] autorelease]];
    [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"stalls"] integerValue] == 7 && [[sample objectForKey:@"droppedFrames"] integerValue] == -1 && [[sample objectForKey:@"bytes"] integerValue] == -1, @"Each access-log selector is checked independently");
    partialLog.events = [NSArray arrayWithObject:[[[ThrowingAccessEvent alloc] init] autorelease]];
    [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([[sample objectForKey:@"observedBitrate"] integerValue] == -1 && [[sample objectForKey:@"stalls"] integerValue] == 7, @"A throwing optional getter cannot terminate or discard the whole sample");
    ThrowingLegacyMovie *throwing = [[[ThrowingLegacyMovie alloc] init] autorelease]; ActiveSmoke->_player.moviePlayer = throwing;
    [ActiveSmoke tick:nil]; sample = [ActiveSmoke->_samples lastObject];
    NSCAssert([throwing respondsToSelector:@selector(useApplicationAudioSession)] && [[sample objectForKey:@"useApplicationAudioSession"] integerValue] == -1, @"Even a advertised but throwing legacy getter is isolated");
    FNTVSmokeDetailPopped(detail);
    NSCAssert(ActiveSmoke && ActiveSmoke->_stage == 3, @"Presenting the owned player is not a stage1/2 pop cancellation");
    [ActiveSmoke finish:1 close:YES];
    NSCAssert(!ActiveSmoke && Dismissals == 1 && !detail.presentedViewController, @"Only the held player is dismissed");
    NewRun(detail, YES); operation = Track(); manual = [[[NSOperation alloc] init] autorelease];
    Completion(reentered, manual, NO, NO);
    UIViewController *manualPlayer = reentered.presentedViewController;
    Completion(detail, operation, YES, NO);
    NSCAssert(!ActiveSmoke && reentered.presentedViewController == manualPlayer && !manual.isCancelled && Dismissals == 1, @"An obsolete smoke completion leaves a later manual player alone");
    reentered.presentedViewController = nil;
    NSUInteger presentedBefore = Presentations;
    NewRun(detail, YES); operation = Track(); Completion(reentered, operation, YES, YES);
    NSCAssert(!ActiveSmoke && Presentations == presentedBefore && LastOutcome == 6, @"Same movie and operation still require the bound detail instance");
    NewRun(detail, YES); operation = Track(); [FNTVClient sharedClient].authenticated = NO;
    Completion(detail, operation, YES, YES);
    NSCAssert(!ActiveSmoke && Presentations == presentedBefore && LastOutcome == 6, @"Expired authentication cannot present an owned smoke");
    NewRun(detail, YES); operation = Track(); SetElapsed(59);
    __block NSUInteger releasedAudio = 0;
    FNTVSmokeCompletePreparation(@"fixture-movie", detail, operation, YES, YES, ^{
        SetElapsed(61); // Simulate blocking audio activation without letting the timer tick.
        FNTVSmokeCompletePreparation(@"fixture-movie", detail, operation, YES, YES,
            ^{ Presentations++; }, ^{ Discards++; releasedAudio++; });
    }, ^{ Discards++; });
    NSCAssert(!ActiveSmoke && Presentations == presentedBefore && LastOutcome == 2 && releasedAudio == 1, @"Blocking activation must recheck presentation and release its new audio lease");
    puts("PASS production smoke flow: unticked deadline callback, command age, foreground/detail/op ownership, manual bypass, Back/reentry, owned presentation/cleanup");
    [pool drain]; return 0;
}
