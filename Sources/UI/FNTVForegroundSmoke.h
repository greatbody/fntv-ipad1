#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#if FNTV_DIAGNOSTICS
void FNTVBeginForegroundSmoke(void (^advanceVisibleUI)(void));
BOOL FNTVSmokeSelectMovie(NSString *guid);
void FNTVSmokeBindDetail(NSString *guid, id detail);
BOOL FNTVSmokeStartPlayback(NSString *guid, id detail);
BOOL FNTVSmokeOwnsPreparation(NSString *guid, id detail);
void FNTVSmokeDetailPopped(id detail);
void FNTVSmokeTrackPreparation(NSString *guid, NSOperation *operation, void (^cancel)(void));
void FNTVSmokeCompletePreparation(NSString *guid, id detail, NSOperation *operation, BOOL wasSmoke, BOOL currentDetail,
    void (^present)(void), void (^discard)(void));
void FNTVSmokeAttachPlayer(NSString *guid, NSOperation *operation, MPMoviePlayerViewController *player, NSUInteger audioLease);
void FNTVSmokeFailed(NSString *guid, NSInteger stage, NSError *error, NSOperation *operation);
#endif
