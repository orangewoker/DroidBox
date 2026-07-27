#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DBRuntimeProbe : NSObject
+ (BOOL)canAllocateExecutableMemory;
+ (NSInteger)jitMode;
+ (uint64_t)physicalMemory;
+ (uint64_t)availableMemoryEstimate;
@end
NS_ASSUME_NONNULL_END
