#import <Foundation/Foundation.h>

BOOL FNTVSameOrigin(NSURL *a, NSURL *b);
NSError *FNTVError(NSInteger code, NSString *message);
NSString *FNTVString(id value);
NSString *FNTVEscape(NSString *value);
NSURL *FNTVImageURL(NSURL *origin, NSString *path);
BOOL FNTVImageDimensionsAllowed(NSInteger width, NSInteger height);
NSDictionary *FNTVNormalizeItem(NSDictionary *item);
NSArray *FNTVNormalizeItems(id items);

typedef struct {
    NSTimeInterval started, response, firstByte, completed, sendSeconds;
    unsigned long long receivedBytes, sentBytes;
    NSInteger status, errorCode, sendError;
    BOOL networkCompleted, cancelled;
} FNTVHTTPMetrics;
NSTimeInterval FNTVMonotonicTime(void);

typedef id (^FNTVWork)(NSOperation *operation, NSError **error);
@interface FNTVOperation : NSOperation {
    FNTVWork _work;
    void (^_result)(id, NSError *);
}
- (id)initWithWork:(FNTVWork)work completion:(void (^)(id, NSError *))completion;
@end

// streamFD < 0 buffers a bounded response; otherwise response bytes go directly to the socket.
@interface FNTVHTTP : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate> {
    NSURL *_origin;
    NSURLConnection *_connection;
    NSMutableData *_data;
    NSError *_error;
    NSHTTPURLResponse *_response;
    NSOperation *_operation;
    BOOL _finished;
    BOOL _head;
    NSUInteger _limit;
    NSUInteger _received;
    int _streamFD;
    BOOL _collectMetrics;
    FNTVHTTPMetrics _metrics;
}
+ (NSData *)fetchURL:(NSURL *)url origin:(NSURL *)origin method:(NSString *)method body:(NSData *)body token:(NSString *)token range:(NSString *)range limit:(NSUInteger)limit operation:(NSOperation *)operation streamFD:(int)streamFD response:(NSHTTPURLResponse **)response error:(NSError **)error;
+ (NSData *)fetchURL:(NSURL *)url origin:(NSURL *)origin method:(NSString *)method body:(NSData *)body token:(NSString *)token range:(NSString *)range limit:(NSUInteger)limit operation:(NSOperation *)operation streamFD:(int)streamFD response:(NSHTTPURLResponse **)response error:(NSError **)error metrics:(FNTVHTTPMetrics *)metrics;
@end
