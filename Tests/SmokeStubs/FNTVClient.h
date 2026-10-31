#import <Foundation/Foundation.h>
@interface FNTVClient : NSObject { BOOL _authenticated; }
@property(nonatomic, getter=isAuthenticated) BOOL authenticated;
+ (FNTVClient *)sharedClient;
@end
