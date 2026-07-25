#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^DBQEMUExitHandler)(NSInteger exitCode, NSString * _Nullable message);

@interface DBQEMUBridge : NSObject
@property(class, nonatomic, readonly) BOOL coreBundled;
@property(atomic, readonly, getter=isRunning) BOOL running;
- (BOOL)startWithArguments:(NSArray<NSString *> *)arguments
               environment:(NSDictionary<NSString *, NSString *> *)environment
               exitHandler:(DBQEMUExitHandler)exitHandler
                      error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

