#import <Foundation/Foundation.h>
@interface FNTVHLSProxy : NSObject {
    NSURL *_origin;
    NSURL *_playbackURL;
    NSString *_token;
    NSString *_nonce;
    NSMutableDictionary *_urls;
    NSMutableDictionary *_pathsByUpstream;
    NSMutableSet *_clientSockets;
    NSOperationQueue *_connections;
    int _listener;
    NSUInteger _port;
    BOOL _running;
    NSString *_metricsPath;
    NSMutableArray *_metricsRows;
    NSTimeInterval _metricsStarted, _metricsStoppedAt, _metricsStartedUnix, _metricsStoppedUnix;
    NSUInteger _metricsAccepted, _metricsFinished, _metricsPending, _metricsRejected, _metricsMaxPending;
    BOOL _metricsStopped, _metricsWritten;
}
- (id)initWithOrigin:(NSURL *)origin token:(NSString *)token;
- (id)initWithOrigin:(NSURL *)origin token:(NSString *)token metricsPath:(NSString *)path;
- (NSURL *)startWithURL:(NSURL *)url error:(NSError **)error;
- (void)stop;
- (BOOL)stopIfPlaybackURL:(NSURL *)url;
// Exposed for protocol self-checks; only same-origin URLs can be registered.
- (NSURL *)localURLForURL:(NSURL *)url;
- (NSString *)rewritePlaylist:(NSString *)playlist source:(NSURL *)source error:(NSError **)error;
@end
