#import "DBZipArchive.h"
#import <zlib.h>

@implementation DBZipEntry @end

static NSString * const DBZipErrorDomain = @"DroidBox.Zip";
static const NSUInteger DBCentralHeaderSize = 46;
static const NSUInteger DBLocalHeaderSize = 30;

static uint16_t DBReadUInt16(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t DBReadUInt32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
        ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static BOOL DBFail(NSError **error, NSInteger code, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:DBZipErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

static NSInteger DBFindEOCD(NSData *tail) {
    const uint8_t *bytes = tail.bytes;
    if (tail.length < 22) return -1;
    for (NSInteger index = (NSInteger)tail.length - 22; index >= 0; index--) {
        if (DBReadUInt32(bytes + index) == 0x06054b50) return index;
    }
    return -1;
}

@implementation DBZipArchive
+ (NSArray<DBZipEntry *> *)entriesAtURL:(NSURL *)url error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return nil;

    unsigned long long fileSize = [handle seekToEndOfFile];
    NSUInteger tailSize = (NSUInteger)MIN(fileSize, 65557);
    [handle seekToFileOffset:fileSize - tailSize];
    NSData *tail = [handle readDataToEndOfFile];
    NSInteger eocd = DBFindEOCD(tail);
    if (eocd < 0) {
        [handle closeFile];
        DBFail(error, 1, @"Missing ZIP directory");
        return nil;
    }

    const uint8_t *end = (const uint8_t *)tail.bytes + eocd;
    uint16_t diskNumber = DBReadUInt16(end + 4);
    uint16_t directoryDisk = DBReadUInt16(end + 6);
    uint16_t count = DBReadUInt16(end + 10);
    uint32_t directorySize = DBReadUInt32(end + 12);
    uint32_t directoryOffset = DBReadUInt32(end + 16);
    if (diskNumber != 0 || directoryDisk != 0 ||
        count == UINT16_MAX || directorySize == UINT32_MAX || directoryOffset == UINT32_MAX) {
        [handle closeFile];
        DBFail(error, 2, @"Multi-disk and ZIP64 archives are not supported");
        return nil;
    }
    if ((uint64_t)directoryOffset + directorySize > fileSize) {
        [handle closeFile];
        DBFail(error, 3, @"ZIP directory lies outside the archive");
        return nil;
    }

    [handle seekToFileOffset:directoryOffset];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        NSData *raw = [handle readDataOfLength:DBCentralHeaderSize];
        if (raw.length != DBCentralHeaderSize) {
            [handle closeFile];
            DBFail(error, 4, @"Truncated ZIP directory");
            return nil;
        }
        const uint8_t *header = raw.bytes;
        if (DBReadUInt32(header) != 0x02014b50) {
            [handle closeFile];
            DBFail(error, 5, @"Invalid ZIP directory entry");
            return nil;
        }
        uint16_t flags = DBReadUInt16(header + 8);
        uint16_t method = DBReadUInt16(header + 10);
        uint32_t crc = DBReadUInt32(header + 16);
        uint32_t compressedSize = DBReadUInt32(header + 20);
        uint32_t uncompressedSize = DBReadUInt32(header + 24);
        uint16_t nameLength = DBReadUInt16(header + 28);
        uint16_t extraLength = DBReadUInt16(header + 30);
        uint16_t commentLength = DBReadUInt16(header + 32);
        uint32_t localOffset = DBReadUInt32(header + 42);
        if ((flags & 0x1) != 0) {
            [handle closeFile];
            DBFail(error, 6, @"Encrypted ZIP entries are not supported");
            return nil;
        }
        NSData *nameData = [handle readDataOfLength:nameLength];
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        [handle seekToFileOffset:handle.offsetInFile + extraLength + commentLength];
        if (!name) continue;

        DBZipEntry *entry = [DBZipEntry new];
        entry.path = name;
        entry.compressedSize = compressedSize;
        entry.uncompressedSize = uncompressedSize;
        entry.localHeaderOffset = localOffset;
        entry.crc32 = crc;
        entry.compressionMethod = method;
        entry.directory = [name hasSuffix:@"/"];
        [result addObject:entry];
    }
    [handle closeFile];
    return result;
}

+ (NSData *)dataForEntry:(NSString *)entry atURL:(NSURL *)url maximumSize:(NSUInteger)maximumSize error:(NSError **)error {
    NSArray<DBZipEntry *> *entries = [self entriesAtURL:url error:error];
    if (!entries) return nil;
    for (DBZipEntry *candidate in entries) {
        if ([candidate.path isEqualToString:entry]) {
            return [self dataAtLocalHeaderOffset:candidate.localHeaderOffset
                               compressedSize:candidate.compressedSize
                             uncompressedSize:candidate.uncompressedSize
                                        method:candidate.compressionMethod
                                         crc32:candidate.crc32
                                         atURL:url
                                   maximumSize:maximumSize
                                         error:error];
        }
    }
    DBFail(error, 7, [NSString stringWithFormat:@"ZIP entry not found: %@", entry]);
    return nil;
}

+ (NSData *)dataAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                   compressedSize:(uint64_t)compressedSize
                 uncompressedSize:(uint64_t)uncompressedSize
                            method:(uint16_t)method
                             crc32:(uint32_t)expectedCRC
                             atURL:(NSURL *)url
                       maximumSize:(NSUInteger)maximumSize
                             error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return nil;
    NSData *result = [self dataAtLocalHeaderOffset:localHeaderOffset
                                compressedSize:compressedSize
                              uncompressedSize:uncompressedSize
                                         method:method
                                          crc32:expectedCRC
                                     fileHandle:handle
                                    maximumSize:maximumSize
                                          error:error];
    [handle closeFile];
    return result;
}

+ (NSData *)dataAtLocalHeaderOffset:(uint64_t)localHeaderOffset
                   compressedSize:(uint64_t)compressedSize
                 uncompressedSize:(uint64_t)uncompressedSize
                            method:(uint16_t)method
                             crc32:(uint32_t)expectedCRC
                        fileHandle:(NSFileHandle *)handle
                       maximumSize:(NSUInteger)maximumSize
                             error:(NSError **)error {
    if (uncompressedSize > maximumSize || compressedSize > NSUIntegerMax ||
        uncompressedSize > NSUIntegerMax || compressedSize > UINT_MAX ||
        uncompressedSize > UINT_MAX) {
        DBFail(error, 8, @"ZIP entry exceeds the configured size limit");
        return nil;
    }
    unsigned long long fileSize = [handle seekToEndOfFile];
    if (localHeaderOffset + DBLocalHeaderSize > fileSize) {
        DBFail(error, 9, @"ZIP local header lies outside the archive");
        return nil;
    }
    [handle seekToFileOffset:localHeaderOffset];
    NSData *local = [handle readDataOfLength:DBLocalHeaderSize];
    const uint8_t *header = local.bytes;
    if (local.length != DBLocalHeaderSize || DBReadUInt32(header) != 0x04034b50) {
        DBFail(error, 10, @"Invalid ZIP local header");
        return nil;
    }
    uint16_t nameLength = DBReadUInt16(header + 26);
    uint16_t extraLength = DBReadUInt16(header + 28);
    uint64_t dataOffset = localHeaderOffset + DBLocalHeaderSize + nameLength + extraLength;
    if (dataOffset + compressedSize > fileSize) {
        DBFail(error, 11, @"Truncated ZIP entry data");
        return nil;
    }
    [handle seekToFileOffset:dataOffset];
    NSData *compressed = [handle readDataOfLength:(NSUInteger)compressedSize];
    if (compressed.length != compressedSize) {
        DBFail(error, 12, @"Truncated ZIP entry data");
        return nil;
    }

    NSData *result = nil;
    if (method == 0) {
        if (compressedSize != uncompressedSize) {
            DBFail(error, 13, @"Stored ZIP entry has inconsistent sizes");
            return nil;
        }
        result = compressed;
    } else if (method == 8) {
        NSMutableData *output = [NSMutableData dataWithLength:(NSUInteger)uncompressedSize];
        z_stream stream = {0};
        stream.next_in = (Bytef *)compressed.bytes;
        stream.avail_in = (uInt)compressed.length;
        stream.next_out = output.mutableBytes;
        stream.avail_out = (uInt)output.length;
        if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
            DBFail(error, 14, @"Unable to initialize ZIP inflater");
            return nil;
        }
        int status = inflate(&stream, Z_FINISH);
        inflateEnd(&stream);
        if (status != Z_STREAM_END || stream.total_out != uncompressedSize) {
            DBFail(error, 15, @"Unable to inflate ZIP entry");
            return nil;
        }
        result = output;
    } else {
        DBFail(error, 16, [NSString stringWithFormat:@"Unsupported ZIP compression method: %u", method]);
        return nil;
    }

    uLong actualCRC = crc32(0L, Z_NULL, 0);
    actualCRC = crc32(actualCRC, result.bytes, (uInt)result.length);
    if ((uint32_t)actualCRC != expectedCRC) {
        DBFail(error, 17, @"ZIP entry CRC check failed");
        return nil;
    }
    return result;
}

+ (BOOL)extractEntry:(NSString *)entry atURL:(NSURL *)url toURL:(NSURL *)destination maximumSize:(NSUInteger)maximumSize error:(NSError **)error {
    NSData *data = [self dataForEntry:entry atURL:url maximumSize:maximumSize error:error];
    if (!data) return NO;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) return NO;
    return [data writeToURL:destination options:NSDataWritingAtomic error:error];
}

+ (BOOL)extractAtLocalHeaderOffset:(uint64_t)localHeaderOffset
              compressedSize:(uint64_t)compressedSize
            uncompressedSize:(uint64_t)uncompressedSize
                       method:(uint16_t)method
                        crc32:(uint32_t)crc32
                        atURL:(NSURL *)url
                        toURL:(NSURL *)destination
                  maximumSize:(NSUInteger)maximumSize
                        error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return NO;
    BOOL result = [self extractAtLocalHeaderOffset:localHeaderOffset
                              compressedSize:compressedSize
                            uncompressedSize:uncompressedSize
                                       method:method
                                        crc32:crc32
                                   fileHandle:handle
                                        toURL:destination
                                  maximumSize:maximumSize
                                        error:error];
    [handle closeFile];
    return result;
}

+ (BOOL)extractAtLocalHeaderOffset:(uint64_t)localHeaderOffset
              compressedSize:(uint64_t)compressedSize
            uncompressedSize:(uint64_t)uncompressedSize
                       method:(uint16_t)method
                        crc32:(uint32_t)crc32
                   fileHandle:(NSFileHandle *)handle
                        toURL:(NSURL *)destination
                  maximumSize:(NSUInteger)maximumSize
                        error:(NSError **)error {
    NSData *data = [self dataAtLocalHeaderOffset:localHeaderOffset
                               compressedSize:compressedSize
                             uncompressedSize:uncompressedSize
                                        method:method
                                         crc32:crc32
                                    fileHandle:handle
                                   maximumSize:maximumSize
                                         error:error];
    if (!data) return NO;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) return NO;
    return [data writeToURL:destination options:NSDataWritingAtomic error:error];
}
@end
