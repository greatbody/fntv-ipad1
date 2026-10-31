#import "FNTVForegroundSmoke.h"
#import "FNTVDiagnostics.h"
#import "FNTVClient.h"
#import "FNTVAudio.h"
#import <math.h>
#if FNTV_DIAGNOSTICS
@interface FNTVForegroundSmoke : NSObject {
@public
    NSDate *_started;
    NSTimer *_timer;
    NSString *_guid;
    id _detail;
    MPMoviePlayerViewController *_player;
    NSOperation *_operation;
    NSUInteger _audioLease;
    void (^_advanceUI)(void);
    void (^_cancelPreparation)(void);
    NSMutableArray *_samples;
    NSTimeInterval _commandAge, _previousTime, _advanceSeconds;
    NSInteger _stage, _outcome, _errorCode, _finishReason, _cleanup;
    BOOL _terminal, _sawPresentation, _deferClose;
}
- (void)tick:(id)sender;
- (void)finish:(NSInteger)outcome close:(BOOL)close;
- (void)writeReport;
- (BOOL)canAdvance;
@end
static FNTVForegroundSmoke *ActiveSmoke;
static NSString *DocumentPath(NSString *name) {
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:name];
}
static double SafeTime(double value) { return isfinite(value) ? value : -1; }
static id ReadOptional(id target, SEL selector, id (^read)(void), BOOL *supported) {
    if (supported) *supported = NO;
    @try {
        if (target && [target respondsToSelector:selector]) {
            id value = read(); if (supported) *supported = YES; return value;
        }
    } @catch (NSException *exception) { (void)exception; }
    return nil;
}
static NSNumber *OptionalNumber(id target, SEL selector, NSNumber *(^read)(void)) {
    id value = ReadOptional(target, selector, read, NULL);
    return [value isKindOfClass:[NSNumber class]] ? value : [NSNumber numberWithInt:-1];
}
@implementation FNTVForegroundSmoke
- (id)init {
    if ((self = [super init])) {
        _started = [[NSDate alloc] init]; _samples = [[NSMutableArray alloc] init];
        _previousTime = -1; _finishReason = -1;
    }
    return self;
}
- (BOOL)canAdvance {
    NSTimeInterval elapsed = -[_started timeIntervalSinceNow];
    return !_terminal && FNTVSmokeWithinDeadline(elapsed) && _commandAge + elapsed <= 300 &&
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive && [FNTVClient sharedClient].isAuthenticated;
}
- (void)writeReport {
    NSDictionary *report = [NSDictionary dictionaryWithObjectsAndKeys:@1, @"schemaVersion",
        [NSNumber numberWithInteger:_outcome], @"outcome", [NSNumber numberWithInteger:_stage], @"stage",
        [NSNumber numberWithDouble:SafeTime(-[_started timeIntervalSinceNow])], @"elapsedSeconds",
        [NSNumber numberWithDouble:SafeTime(_commandAge)], @"commandAgeSeconds",
        [NSNumber numberWithInteger:[UIApplication sharedApplication].applicationState], @"appState",
        [NSNumber numberWithInt:[FNTVClient sharedClient].isAuthenticated ? 1 : 0], @"authenticated",
        [NSNumber numberWithInteger:_errorCode], @"errorCode", [NSNumber numberWithInteger:_finishReason], @"finishReason",
        [NSNumber numberWithInteger:_cleanup], @"cleanup", [NSNumber numberWithDouble:_advanceSeconds], @"advanceSeconds", _samples, @"samples", nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *path = DocumentPath(@"FNTV-player-smoke.json");
    if ([data writeToFile:path options:NSDataWritingAtomic error:NULL])
        [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:@0600 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
}
- (void)releaseRun {
    [self retain];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate]; [_timer release]; _timer = nil;
    if (ActiveSmoke == self) { ActiveSmoke = nil; [self release]; }
    [self autorelease];
}
- (void)closeOwnedPlayer {
    UIViewController *presenter = _player.presentingViewController;
    if (!presenter || presenter.presentedViewController != _player) { _cleanup = _player ? 3 : 0; return; }
    if (_player.presentedViewController) { _cleanup = 4; _outcome = 6; return; }
    _cleanup = 1;
    [presenter dismissMoviePlayerViewControllerAnimated];
}
- (void)finish:(NSInteger)outcome close:(BOOL)close {
    if (_terminal) return;
    _terminal = YES; _outcome = outcome;
    [_timer invalidate]; [_timer release]; _timer = nil;
    void (^cancel)(void) = [_cancelPreparation copy]; [_cancelPreparation release]; _cancelPreparation = nil;
    if (cancel) cancel(); [cancel release];
    [_operation release]; _operation = nil;
    if (close && _player && _player.presentingViewController.presentedViewController == _player &&
        (_deferClose || [UIApplication sharedApplication].applicationState != UIApplicationStateActive)) {
        _cleanup = 2; [self writeReport]; return;
    }
    if (close) [self closeOwnedPlayer];
    [self writeReport]; [self releaseRun];
}
- (void)active:(NSNotification *)notification {
    (void)notification;
    if (_terminal) { [self closeOwnedPlayer]; [self writeReport]; [self releaseRun]; }
    else [self tick:nil];
}
- (void)inactive:(NSNotification *)notification {
    (void)notification;
    if (!_terminal && _stage > 0) { _deferClose = YES; [self finish:6 close:YES]; }
}
- (void)movieFinished:(NSNotification *)notification {
    if (_terminal) return;
    _finishReason = [[[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    id error = [[notification userInfo] objectForKey:@"error"];
    if ([error isKindOfClass:[NSError class]]) _errorCode = [error code];
    [self finish:(_finishReason == MPMovieFinishReasonPlaybackError ? 5 : (_finishReason == MPMovieFinishReasonPlaybackEnded ? 8 : 7)) close:NO];
}
- (void)tick:(id)sender {
    (void)sender; if (_terminal) return;
    NSTimeInterval elapsed = -[_started timeIntervalSinceNow];
    if (!FNTVSmokeWithinDeadline(elapsed)) { [self finish:2 close:YES]; return; }
    if (_stage < 3 && _commandAge + elapsed > 300) { [self finish:3 close:YES]; return; }
    if (!_player) {
        if ([self canAdvance] && _advanceUI) _advanceUI();
    } else {
        BOOL visible = _player.presentingViewController.presentedViewController == _player && _player.view.window != nil;
        if (visible) _sawPresentation = YES;
        else if (_sawPresentation) { [self finish:7 close:NO]; return; }
        MPMoviePlayerController *movie = _player.moviePlayer;
        BOOL logSupported = NO, eventsSupported = NO;
        id log = ReadOptional(movie, @selector(accessLog), ^{ return movie.accessLog; }, &logSupported);
        id list = ReadOptional(log, @selector(events), ^{ return [(MPMovieAccessLog *)log events]; }, &eventsSupported);
        NSArray *accessEvents = [list isKindOfClass:[NSArray class]] ? list : nil;
        NSInteger eventCount = logSupported && (!log || (eventsSupported && (!list || accessEvents))) ? (NSInteger)[accessEvents count] : -1;
        MPMovieAccessLogEvent *access = [accessEvents lastObject];
        NSTimeInterval current = SafeTime(movie.currentPlaybackTime);
        NSInteger appState = [UIApplication sharedApplication].applicationState;
        NSDictionary *sample = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:elapsed], @"t",
            [NSNumber numberWithInteger:appState], @"app", [NSNumber numberWithInteger:movie.playbackState], @"state",
            [NSNumber numberWithUnsignedInteger:movie.loadState], @"load", [NSNumber numberWithInt:movie.isPreparedToPlay ? 1 : 0], @"prepared",
            [NSNumber numberWithInt:visible ? 1 : 0], @"visible", [NSNumber numberWithDouble:current], @"time",
            [NSNumber numberWithDouble:SafeTime(movie.duration)], @"duration",
            OptionalNumber(movie, @selector(playableDuration), ^{ return [NSNumber numberWithDouble:SafeTime(movie.playableDuration)]; }), @"playableDuration",
            OptionalNumber(movie, @selector(movieMediaTypes), ^{ return [NSNumber numberWithUnsignedInteger:movie.movieMediaTypes]; }), @"movieMediaTypes",
            OptionalNumber(movie, @selector(useApplicationAudioSession), ^{ return [NSNumber numberWithInt:movie.useApplicationAudioSession ? 1 : 0]; }), @"useApplicationAudioSession",
            [NSNumber numberWithInteger:FNTVReadPlaybackAudioCategory()], @"audioCategoryPlayback",
            [NSNumber numberWithInt:FNTVPlaybackAudioLeaseIsCurrent(_audioLease) ? 1 : 0], @"audioLeaseCurrent",
            [NSNumber numberWithInteger:eventCount], @"accessLogEvents",
            OptionalNumber(access, @selector(numberOfStalls), ^{ return [NSNumber numberWithInteger:access.numberOfStalls]; }), @"stalls",
            OptionalNumber(access, @selector(numberOfDroppedVideoFrames), ^{ return [NSNumber numberWithInteger:access.numberOfDroppedVideoFrames]; }), @"droppedFrames",
            OptionalNumber(access, @selector(observedBitrate), ^{ return [NSNumber numberWithDouble:SafeTime(access.observedBitrate)]; }), @"observedBitrate",
            OptionalNumber(access, @selector(indicatedBitrate), ^{ return [NSNumber numberWithDouble:SafeTime(access.indicatedBitrate)]; }), @"indicatedBitrate",
            OptionalNumber(access, @selector(numberOfSegmentsDownloaded), ^{ return [NSNumber numberWithUnsignedInteger:access.numberOfSegmentsDownloaded]; }), @"segments",
            OptionalNumber(access, @selector(numberOfBytesTransferred), ^{ return [NSNumber numberWithLongLong:access.numberOfBytesTransferred]; }), @"bytes", nil];
        [_samples addObject:sample];
        NSTimeInterval delta = FNTVSmokeAdvance(_previousTime, current, visible && appState == UIApplicationStateActive && movie.playbackState == MPMoviePlaybackStatePlaying);
        _advanceSeconds = delta > 0 ? _advanceSeconds + delta : 0; _previousTime = current;
        if (_advanceSeconds >= 8) { [self finish:1 close:YES]; return; }
    }
    // A small bounded checkpoint survives termination without logging media or URLs.
    [self writeReport];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; [_timer invalidate]; [_timer release];
    [_started release]; [_guid release]; [_detail release]; [_player release]; [_operation release]; [_advanceUI release]; [_cancelPreparation release]; [_samples release]; [super dealloc];
}
@end
void FNTVBeginForegroundSmoke(void (^advanceVisibleUI)(void)) {
    if (ActiveSmoke) { [ActiveSmoke finish:6 close:YES]; if (ActiveSmoke) return; }
    NSTimeInterval age = 0;
    NSInteger command = FNTVConsumeSmokeCommand(DocumentPath(@".fntv-player-smoke.json"), [NSDate date], &age);
    if (!command) return;
    ActiveSmoke = [[FNTVForegroundSmoke alloc] init]; ActiveSmoke->_commandAge = age;
    if (command != 1) { [ActiveSmoke finish:command close:NO]; return; }
    ActiveSmoke->_advanceUI = [advanceVisibleUI copy];
    [[NSNotificationCenter defaultCenter] addObserver:ActiveSmoke selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:ActiveSmoke selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    ActiveSmoke->_timer = [[NSTimer scheduledTimerWithTimeInterval:1 target:ActiveSmoke selector:@selector(tick:) userInfo:nil repeats:YES] retain];
    [ActiveSmoke writeReport];
}
BOOL FNTVSmokeSelectMovie(NSString *guid) {
    if (!ActiveSmoke || ActiveSmoke->_stage != 0 || ![ActiveSmoke canAdvance] || ![guid length]) return NO;
    ActiveSmoke->_guid = [guid copy]; ActiveSmoke->_stage = 1; return YES;
}
void FNTVSmokeBindDetail(NSString *guid, id detail) {
    if (ActiveSmoke && ActiveSmoke->_stage == 1 && !ActiveSmoke->_detail && [ActiveSmoke->_guid isEqualToString:guid]) ActiveSmoke->_detail = [detail retain];
}
BOOL FNTVSmokeStartPlayback(NSString *guid, id detail) {
    if (!ActiveSmoke || ActiveSmoke->_stage != 1 || ActiveSmoke->_detail != detail || ![ActiveSmoke canAdvance] || ![ActiveSmoke->_guid isEqualToString:guid]) return NO;
    ActiveSmoke->_stage = 2; return YES;
}
BOOL FNTVSmokeOwnsPreparation(NSString *guid, id detail) {
    return ActiveSmoke && !ActiveSmoke->_terminal && ActiveSmoke->_stage == 2 && ActiveSmoke->_detail == detail && [ActiveSmoke->_guid isEqualToString:guid];
}
void FNTVSmokeDetailPopped(id detail) {
    if (ActiveSmoke && !ActiveSmoke->_terminal && ActiveSmoke->_detail == detail && (ActiveSmoke->_stage == 1 || ActiveSmoke->_stage == 2)) [ActiveSmoke finish:6 close:NO];
}
void FNTVSmokeTrackPreparation(NSString *guid, NSOperation *operation, void (^cancel)(void)) {
    if (ActiveSmoke && ActiveSmoke->_stage == 2 && !ActiveSmoke->_terminal && !ActiveSmoke->_operation && [ActiveSmoke->_guid isEqualToString:guid]) {
        ActiveSmoke->_operation = [operation retain]; ActiveSmoke->_cancelPreparation = [cancel copy];
    }
}
void FNTVSmokeCompletePreparation(NSString *guid, id detail, NSOperation *operation, BOOL wasSmoke, BOOL currentDetail,
    void (^present)(void), void (^discard)(void)) {
    // The marker is captured before preparation; an ended smoke can never become a manual callback.
    if (!wasSmoke) { present(); return; }
    if (!ActiveSmoke || ActiveSmoke->_terminal || ActiveSmoke->_stage != 2 || ActiveSmoke->_operation != operation) { discard(); return; }
    NSTimeInterval elapsed = -[ActiveSmoke->_started timeIntervalSinceNow];
    NSInteger failure = !FNTVSmokeWithinDeadline(elapsed) ? 2 : (ActiveSmoke->_commandAge + elapsed > 300 ? 3 : 6);
    if (!currentDetail || ActiveSmoke->_detail != detail || ![ActiveSmoke->_guid isEqualToString:guid] || ![ActiveSmoke canAdvance]) {
        [ActiveSmoke finish:failure close:NO]; discard(); return;
    }
    present();
}
void FNTVSmokeAttachPlayer(NSString *guid, NSOperation *operation, MPMoviePlayerViewController *player, NSUInteger audioLease) {
    if (!ActiveSmoke || ActiveSmoke->_stage != 2 || ActiveSmoke->_terminal || ActiveSmoke->_operation != operation || ![ActiveSmoke->_guid isEqualToString:guid]) return;
    [ActiveSmoke->_cancelPreparation release]; ActiveSmoke->_cancelPreparation = nil;
    [ActiveSmoke->_operation release]; ActiveSmoke->_operation = nil;
    ActiveSmoke->_player = [player retain]; ActiveSmoke->_audioLease = audioLease; ActiveSmoke->_stage = 3;
    [[NSNotificationCenter defaultCenter] addObserver:ActiveSmoke selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:player.moviePlayer];
}
void FNTVSmokeFailed(NSString *guid, NSInteger stage, NSError *error, NSOperation *operation) {
    if (ActiveSmoke && !ActiveSmoke->_terminal && (stage == 1 || ActiveSmoke->_operation == operation) && [ActiveSmoke->_guid isEqualToString:guid]) {
        ActiveSmoke->_stage = stage; ActiveSmoke->_errorCode = [error code]; [ActiveSmoke finish:5 close:NO];
    }
}
#endif
