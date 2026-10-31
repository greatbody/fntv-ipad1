#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
extern NSString * const UIApplicationDidBecomeActiveNotification;
extern NSString * const UIApplicationWillResignActiveNotification;
@interface UIView : NSObject { id _window; }
@property(nonatomic, retain) id window;
@end
@interface UIViewController : NSObject {
    UIViewController *_presentingViewController, *_presentedViewController;
    UIView *_view;
}
@property(nonatomic, assign) UIViewController *presentingViewController;
@property(nonatomic, retain) UIViewController *presentedViewController;
@property(nonatomic, retain) UIView *view;
- (void)dismissMoviePlayerViewControllerAnimated;
@end
@interface UIApplication : NSObject { UIApplicationState _applicationState; }
@property(nonatomic) UIApplicationState applicationState;
+ (UIApplication *)sharedApplication;
@end
