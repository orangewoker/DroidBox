#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface DBZipEntry : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) uint64_t compressedSize;
@property(nonatomic) uint64_t uncompressedSize;
@property(nonatomic) uint64_t localHeaderOffset;
@property(nonatomic) uint32_t crc32;
@property(nonatomic) uint16_t compressionMethod;
@property(nonatomic) BOOL directory;
@end

@interface DBZipArchive : NSObject
+ (nullable NSArray<DBZipEntry *> *)entriesAtURL:(NSURL *)url error:(NSError **)error;
+ (nullable NSData *)dataForEntry:(NSString *)entry atURL:(NSURL *)url maximumSize:(NSUInteger)maximumSize error:(NSError **)error;
+ (nullable NSData *)dataAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                              compressedSize:(uint64_t)compressedSize
                            uncompressedSize:(uint64_t)uncompressedSize
                                       method:(uint16_t)method
                                        crc32:(uint32_t)crc32
                                        atURL:(NSURL *)url
                                  maximumSize:(NSUInteger)maximumSize
                                        error:(NSError **)error
    NS_SWIFT_NAME(data(localHeaderOffset:compressedSize:uncompressedSize:method:crc32:url:maximumSize:));
+ (nullable NSData *)dataAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                              compressedSize:(uint64_t)compressedSize
                            uncompressedSize:(uint64_t)uncompressedSize
                                       method:(uint16_t)method
                                        crc32:(uint32_t)crc32
                                   fileHandle:(NSFileHandle *)handle
                                  maximumSize:(NSUInteger)maximumSize
                                        error:(NSError **)error
    NS_SWIFT_NAME(data(localHeaderOffset:compressedSize:uncompressedSize:method:crc32:fileHandle:maximumSize:));
+ (BOOL)extractEntry:(NSString *)entry atURL:(NSURL *)url toURL:(NSURL *)destination maximumSize:(NSUInteger)maximumSize error:(NSError **)error;
+ (BOOL)extractAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                    compressedSize:(uint64_t)compressedSize
                  uncompressedSize:(uint64_t)uncompressedSize
                             method:(uint16_t)method
                              crc32:(uint32_t)crc32
                              atURL:(NSURL *)url
                              toURL:(NSURL *)destination
                        maximumSize:(NSUInteger)maximumSize
                              error:(NSError **)error
    NS_SWIFT_NAME(extract(localHeaderOffset:compressedSize:uncompressedSize:method:crc32:url:destination:maximumSize:));
+ (BOOL)extractAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                    compressedSize:(uint64_t)compressedSize
                  uncompressedSize:(uint64_t)uncompressedSize
                             method:(uint16_t)method
                              crc32:(uint32_t)crc32
                         fileHandle:(NSFileHandle *)handle
                              toURL:(NSURL *)destination
                        maximumSize:(NSUInteger)maximumSize
                              error:(NSError **)error
    NS_SWIFT_NAME(extract(localHeaderOffset:compressedSize:uncompressedSize:method:crc32:fileHandle:destination:maximumSize:));
@end
NS_ASSUME_NONNULL_END
