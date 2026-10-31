#import <Foundation/Foundation.h>
// Main-thread playback ownership; zero means setup failed.
NSUInteger FNTVBeginPlaybackAudio(NSError **error);
BOOL FNTVPlaybackAudioLeaseIsCurrent(NSUInteger lease);
BOOL FNTVEndPlaybackAudio(NSUInteger lease, NSError **error);
void FNTVStopPlaybackAudioIOOnce(NSUInteger lease, BOOL *stopped, void (^stopIO)(void));
void FNTVSchedulePlaybackAudioRelease(NSUInteger lease);
#if FNTV_DIAGNOSTICS
NSInteger FNTVReadPlaybackAudioCategory(void);
#endif
