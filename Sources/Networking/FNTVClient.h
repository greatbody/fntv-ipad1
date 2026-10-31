#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString * const FNTVAuthenticationExpiredNotification;
typedef void (^FNTVCompletion)(id result, NSError *error);
@class FNTVHLSProxy;

@interface FNTVClient : NSObject {
    NSString *_serverURL;
    NSString *_username;
    NSString *_token;
    NSOperationQueue *_queue;
    NSOperationQueue *_imageQueue;
    NSOperationQueue *_recordQueue;
    NSOperation *_lastRecord;
    NSCache *_imageCache;
    FNTVHLSProxy *_proxy;
    NSUInteger _generation;
}
@property(nonatomic, readonly, copy) NSString *serverURL;
@property(nonatomic, readonly, copy) NSString *username;
@property(nonatomic, readonly, getter=isAuthenticated) BOOL authenticated;
+ (FNTVClient *)sharedClient;
- (BOOL)configureServer:(NSString *)server error:(NSError **)error;
- (NSOperation *)loginUsername:(NSString *)username password:(NSString *)password completion:(FNTVCompletion)completion;
- (void)logout;
- (NSOperation *)libraries:(FNTVCompletion)completion;
- (NSOperation *)itemsInLibrary:(NSString *)guid page:(NSUInteger)page search:(NSString *)search completion:(FNTVCompletion)completion;
- (NSOperation *)itemsInDirectory:(NSString *)guid page:(NSUInteger)page completion:(FNTVCompletion)completion;
- (NSOperation *)detailForItem:(NSString *)guid completion:(FNTVCompletion)completion;
- (NSOperation *)seasonsForTV:(NSString *)guid completion:(FNTVCompletion)completion;
- (NSOperation *)episodesForSeason:(NSString *)guid completion:(FNTVCompletion)completion;
- (NSOperation *)imageForPath:(NSString *)path completion:(FNTVCompletion)completion;
- (NSOperation *)preparePlaybackForItem:(NSString *)guid startTime:(NSTimeInterval)seconds completion:(FNTVCompletion)completion;
- (NSOperation *)recordPlayback:(NSDictionary *)playback seconds:(NSTimeInterval)seconds completion:(FNTVCompletion)completion;
#if FNTV_DIAGNOSTICS
- (NSOperation *)readOnlySelfCheck:(FNTVCompletion)completion;
#endif
- (void)discardPreparedPlayback:(NSDictionary *)playback;
- (void)stopPlayback;
- (void)clearImageCache;
@end
