@import Foundation;

@interface Log : NSObject
+ (void)log:(char *)message;
@end

@implementation Log
+ (void)log:(char *)message {
    NSLog(@"%s", message);
}
@end
