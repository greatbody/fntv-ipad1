#import <UIKit/UIKit.h>
#import "Sources/UI/FNTVControllers.h"
#import "Sources/Networking/FNTVClient.h"

@interface FNTVAppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
}
@end
@implementation FNTVAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    FNTVRunUISelfTests();
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.rootViewController = FNTVRootController();
    [_window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(authenticationExpired:)
        name:FNTVAuthenticationExpiredNotification object:nil];
    return YES;
}
- (void)authenticationExpired:(NSNotification *)notification {
    (void)notification;
    [[FNTVClient sharedClient] logout];
    [_window.rootViewController dismissModalViewControllerAnimated:NO];
    _window.rootViewController = FNTVRootController();
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"请重新登录" message:@"登录已过期，请重新连接你的飞牛 NAS。"
        delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
    [alert show]; [alert release];
}
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    (void)application; [[FNTVClient sharedClient] clearImageCache];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_window release]; [super dealloc];
}
@end
int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil, NSStringFromClass([FNTVAppDelegate class]));
    [pool drain]; return result;
}
