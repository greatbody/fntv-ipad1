#import <Foundation/Foundation.h>
#if FNTV_DIAGNOSTICS
NSDictionary *FNTVConsumeDiagnosticLogin(NSString *path, NSError **error);
// 0 absent, 1 accepted, 3 stale, 4 invalid; command files are consumed before execution.
NSInteger FNTVConsumeSmokeCommand(NSString *path, NSDate *now, NSTimeInterval *age);
NSTimeInterval FNTVSmokeAdvance(NSTimeInterval previous, NSTimeInterval current, BOOL playing);
BOOL FNTVSmokeWithinDeadline(NSTimeInterval elapsed);
#endif
