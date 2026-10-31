#import <UIKit/UIKit.h>
typedef NS_ENUM(NSInteger, MPMoviePlaybackState) { MPMoviePlaybackStateStopped, MPMoviePlaybackStatePlaying, MPMoviePlaybackStatePaused };
typedef NS_ENUM(NSInteger, MPMovieFinishReason) { MPMovieFinishReasonPlaybackEnded, MPMovieFinishReasonPlaybackError, MPMovieFinishReasonUserExited };
extern NSString * const MPMoviePlayerPlaybackDidFinishNotification;
extern NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey;
@interface MPMovieAccessLogEvent : NSObject {
    NSInteger _numberOfStalls, _numberOfDroppedVideoFrames;
    NSUInteger _numberOfSegmentsDownloaded;
    long long _numberOfBytesTransferred;
    double _observedBitrate, _indicatedBitrate;
}
@property(nonatomic) NSInteger numberOfStalls, numberOfDroppedVideoFrames;
@property(nonatomic) NSUInteger numberOfSegmentsDownloaded;
@property(nonatomic) long long numberOfBytesTransferred;
@property(nonatomic) double observedBitrate, indicatedBitrate;
@end
@interface MPMovieAccessLog : NSObject { NSArray *_events; }
@property(nonatomic, retain) NSArray *events;
@end
@interface MPMoviePlayerController : NSObject {
    NSTimeInterval _currentPlaybackTime, _duration, _playableDuration;
    NSInteger _playbackState;
    NSUInteger _loadState, _movieMediaTypes;
    BOOL _isPreparedToPlay, _useApplicationAudioSession;
    MPMovieAccessLog *_accessLog;
}
@property(nonatomic) NSTimeInterval currentPlaybackTime, duration, playableDuration;
@property(nonatomic) NSInteger playbackState;
@property(nonatomic) NSUInteger loadState;
@property(nonatomic) BOOL isPreparedToPlay;
@property(nonatomic) NSUInteger movieMediaTypes;
@property(nonatomic) BOOL useApplicationAudioSession;
@property(nonatomic, retain) MPMovieAccessLog *accessLog;
@end
@interface MPMoviePlayerViewController : UIViewController { MPMoviePlayerController *_moviePlayer; }
@property(nonatomic, retain) MPMoviePlayerController *moviePlayer;
@end
