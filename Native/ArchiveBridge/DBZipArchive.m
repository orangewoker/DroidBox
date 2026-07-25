#import "DBZipArchive.h"
#import <zlib.h>

@implementation DBZipEntry @end

typedef struct __attribute__((packed)) {
    uint32_t signature; uint16_t versionMade, versionNeeded, flags, method, modTime, modDate;
    uint32_t crc32, compressedSize, uncompressedSize; uint16_t nameLength, extraLength, commentLength, disk, intAttrs;
    uint32_t extAttrs, localOffset;
} DBCentralHeader;

@implementation DBZipArchive
+ (NSArray<DBZipEntry *> *)entriesAtURL:(NSURL *)url error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error]; if (!handle) return nil;
    unsigned long long size = [handle seekToEndOfFile]; NSUInteger tailSize = (NSUInteger)MIN(size, 65557);
    [handle seekToFileOffset:size-tailSize]; NSData *tail = [handle readDataToEndOfFile]; const uint8_t *bytes=tail.bytes;
    NSInteger eocd=-1; for (NSInteger i=(NSInteger)tail.length-22;i>=0;i--) if (*(const uint32_t *)(bytes+i)==0x06054b50) { eocd=i; break; }
    if (eocd<0) { if(error)*error=[NSError errorWithDomain:@"DroidBox.Zip" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Missing ZIP directory"}]; return nil; }
    uint16_t count=*(const uint16_t *)(bytes+eocd+10); uint32_t offset=*(const uint32_t *)(bytes+eocd+16);
    [handle seekToFileOffset:offset]; NSMutableArray *result=[NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i=0;i<count;i++) {
        NSData *raw=[handle readDataOfLength:sizeof(DBCentralHeader)]; if(raw.length!=sizeof(DBCentralHeader)) return nil;
        DBCentralHeader h; [raw getBytes:&h length:sizeof(h)]; if(h.signature!=0x02014b50) return nil;
        NSData *nameData=[handle readDataOfLength:h.nameLength]; NSString *name=[[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        [handle seekToFileOffset:handle.offsetInFile+h.extraLength+h.commentLength]; if(!name) continue;
        DBZipEntry *entry=[DBZipEntry new]; entry.path=name; entry.compressedSize=h.compressedSize; entry.uncompressedSize=h.uncompressedSize; entry.directory=[name hasSuffix:@"/"]; [result addObject:entry];
    }
    [handle closeFile]; return result;
}

+ (NSData *)dataForEntry:(NSString *)entry atURL:(NSURL *)url maximumSize:(NSUInteger)maximumSize error:(NSError **)error {
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingFromURL:url error:error]; if(!handle)return nil;
    unsigned long long size=[handle seekToEndOfFile]; NSUInteger tailSize=(NSUInteger)MIN(size,65557); [handle seekToFileOffset:size-tailSize]; NSData *tail=[handle readDataToEndOfFile]; const uint8_t *b=tail.bytes; NSInteger e=-1;
    for(NSInteger i=(NSInteger)tail.length-22;i>=0;i--)if(*(const uint32_t *)(b+i)==0x06054b50){e=i;break;} if(e<0)return nil;
    uint16_t count=*(const uint16_t *)(b+e+10); uint32_t offset=*(const uint32_t *)(b+e+16); [handle seekToFileOffset:offset];
    for(NSUInteger i=0;i<count;i++){
        NSData *raw=[handle readDataOfLength:sizeof(DBCentralHeader)]; DBCentralHeader h; if(raw.length!=sizeof(h))break; [raw getBytes:&h length:sizeof(h)];
        NSData *nd=[handle readDataOfLength:h.nameLength]; NSString *name=[[NSString alloc]initWithData:nd encoding:NSUTF8StringEncoding]; [handle seekToFileOffset:handle.offsetInFile+h.extraLength+h.commentLength];
        if(![name isEqualToString:entry])continue; if(h.uncompressedSize>maximumSize)return nil; unsigned long long returnOffset=handle.offsetInFile;
        [handle seekToFileOffset:h.localOffset]; NSData *local=[handle readDataOfLength:30]; const uint8_t *l=local.bytes; if(local.length<30||*(uint32_t *)l!=0x04034b50)return nil; uint16_t nl=*(uint16_t *)(l+26),xl=*(uint16_t *)(l+28); [handle seekToFileOffset:h.localOffset+30+nl+xl]; NSData *compressed=[handle readDataOfLength:h.compressedSize]; [handle seekToFileOffset:returnOffset];
        if(h.method==0){[handle closeFile];return compressed;} if(h.method!=8)return nil;
        NSMutableData *out=[NSMutableData dataWithLength:h.uncompressedSize]; z_stream s={0}; s.next_in=(Bytef *)compressed.bytes;s.avail_in=(uInt)compressed.length;s.next_out=out.mutableBytes;s.avail_out=(uInt)out.length;
        if(inflateInit2(&s,-MAX_WBITS)!=Z_OK)return nil; int status=inflate(&s,Z_FINISH); inflateEnd(&s); [handle closeFile]; return status==Z_STREAM_END?out:nil;
    }
    [handle closeFile]; return nil;
}

+ (BOOL)extractEntry:(NSString *)entry atURL:(NSURL *)url toURL:(NSURL *)destination maximumSize:(NSUInteger)maximumSize error:(NSError **)error {
    NSData *data=[self dataForEntry:entry atURL:url maximumSize:maximumSize error:error]; if(!data)return NO;
    [[NSFileManager defaultManager] createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]; return [data writeToURL:destination options:NSDataWritingAtomic error:error];
}
@end

