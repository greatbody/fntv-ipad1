#import <Foundation/Foundation.h>
#import "FNTVDiagnostics.h"
static void Write(NSString *path, NSData *bytes) {
    NSCAssert([bytes writeToFile:path atomically:YES], @"Fixture write");
    [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:@0600 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSCAssert([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL], @"Fixture directory");
    NSString *path = [directory stringByAppendingPathComponent:@".fntv-test-login.json"];
    NSError *error = nil;
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, &error) && !error, @"Absent file is a no-op");
    NSDictionary *valid = [NSDictionary dictionaryWithObjectsAndKeys:@"http://127.0.0.1:5666", @"server", @"fixture-user", @"username", @"fixture-only-password", @"password", nil];
    Write(path, [NSJSONSerialization dataWithJSONObject:valid options:0 error:NULL]);
    NSCAssert([[FNTVConsumeDiagnosticLogin(path, &error) objectForKey:@"username"] isEqualToString:@"fixture-user"] && ![files fileExistsAtPath:path], @"Valid file consumed exactly once");
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL), @"Consumed file cannot resubmit");
    NSArray *invalid = [NSArray arrayWithObjects:[NSArray array], [NSDictionary dictionaryWithObjectsAndKeys:@"http://localhost", @"server", @"fixture", @"username", @1, @"password", nil], nil];
    for (id value in invalid) {
        Write(path, [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL]);
        NSCAssert(!FNTVConsumeDiagnosticLogin(path, &error) && error && ![files fileExistsAtPath:path], @"Bad shape is removed without submitting");
    }
    Write(path, [@"not json" dataUsingEncoding:NSUTF8StringEncoding]);
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && ![files fileExistsAtPath:path], @"Malformed JSON removed");
    Write(path, [NSMutableData dataWithLength:16385]);
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && ![files fileExistsAtPath:path], @"Oversized file removed");
    Write(path, [NSJSONSerialization dataWithJSONObject:valid options:0 error:NULL]);
    [files setAttributes:[NSDictionary dictionaryWithObject:@0644 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && ![files fileExistsAtPath:path], @"Publicly readable file rejected and removed");
    Write(path, [NSJSONSerialization dataWithJSONObject:valid options:0 error:NULL]);
    [files setAttributes:[NSDictionary dictionaryWithObject:@0500 forKey:NSFilePosixPermissions] ofItemAtPath:directory error:NULL];
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && [files fileExistsAtPath:path], @"Failed removal must never return credentials");
    [files setAttributes:[NSDictionary dictionaryWithObject:@0700 forKey:NSFilePosixPermissions] ofItemAtPath:directory error:NULL];
    [files removeItemAtPath:path error:NULL];
    NSString *target = [directory stringByAppendingPathComponent:@"target.json"];
    Write(target, [NSJSONSerialization dataWithJSONObject:valid options:0 error:NULL]);
    NSCAssert([files createSymbolicLinkAtPath:path withDestinationPath:target error:NULL], @"Symlink fixture");
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && ![files fileExistsAtPath:path] && [files fileExistsAtPath:target], @"Reject symlink without deleting target");
    NSCAssert([files createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL], @"Directory fixture");
    NSCAssert(!FNTVConsumeDiagnosticLogin(path, NULL) && [files fileExistsAtPath:path], @"Never recursively remove a directory");
    [files removeItemAtPath:directory error:NULL];
    puts("PASS diagnostic login: bounds, permissions, shapes, consume once, deletion failure, symlink/directory safety");
    [pool drain]; return 0;
}
