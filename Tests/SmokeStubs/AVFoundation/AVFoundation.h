#import <Foundation/Foundation.h>
#define AVAudioSession FNTVTestAudioSession
#define AVAudioSessionCategoryPlayback FNTVTestAudioSessionCategoryPlayback
extern NSString * const AVAudioSessionCategoryPlayback;
@interface AVAudioSession : NSObject
+ (AVAudioSession *)sharedInstance;
- (BOOL)setCategory:(NSString *)category error:(NSError **)error;
- (BOOL)setActive:(BOOL)active error:(NSError **)error;
- (NSString *)category;
@end
