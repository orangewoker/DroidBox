#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface DBZipEntry : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) uint64_t compressedSize;
@property(nonatomic) uint64_t uncompressedSize;
@property(nonatomic) BOOL directory;
@end

@interface DBZipArchive : NSObject
+ (nullable NSArray<DBZipEntry *> *)entriesAtURL:(NSURL *)url error:(NSError **)error;
+ (nullable NSData *)dataForEntry:(NSString *)entry atURL:(NSURL *)url maximumSize:(NSUInteger)maximumSize error:(NSError **)error;
+ (BOOL)extractEntry:(NSString *)entry atURL:(NSURL *)url toURL:(NSURL *)destination maximumSize:(NSUInteger)maximumSize error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

