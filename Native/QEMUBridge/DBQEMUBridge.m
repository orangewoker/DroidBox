// Launcher design follows UTM's Apache-2.0 UTMQemuSystem process boundary.
#import "DBQEMUBridge.h"
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <pthread.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <unistd.h>

typedef int (*DBQEMUInitFunction)(int, const char *[], const char *[]);
typedef void (*DBQEMUVoidFunction)(void);

static void DBQEMUBridgeBinaryAnchor(void) {}
static BOOL DBQEMUProcessRunning = NO;

@interface DBQEMUBridge ()
@property(atomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic) BOOL ownsProcessSlot;
@property(nonatomic, copy) NSArray<NSString *> *arguments;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
@property(nonatomic, copy) DBQEMUExitHandler exitHandler;
@property(nonatomic) NSURL *currentDirectory;
@property(nonatomic) NSURL *diagnosticLogURL;
@property(nonatomic) dispatch_semaphore_t done;
@property(nonatomic) dispatch_queue_t completionQueue;
@property(nonatomic) NSInteger status;
@property(nonatomic) BOOL fatal;
@property(nonatomic) void *coreHandle;
@property(nonatomic) DBQEMUInitFunction qemuInit;
@property(nonatomic) DBQEMUVoidFunction qemuMainLoop;
@property(nonatomic) DBQEMUVoidFunction qemuCleanup;
@property(nonatomic) pthread_t qemuThread;
@end

static void DBQEMUWriteStage(DBQEMUBridge *bridge, NSString *stage) {
    NSURL *url = bridge.diagnosticLogURL;
    if (!url) return;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSString *line = [NSString stringWithFormat:@"%@\t%@\n", [formatter stringFromDate:NSDate.date], stage];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    int descriptor = open(url.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (descriptor < 0) return;
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(descriptor, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    fsync(descriptor);
    close(descriptor);
}

// UTM's QEMU core is intended to be initialized once per process. LiveContainer
// can retain a framework image after replacing/restarting its guest app, leaving
// these local option registries populated. A later qemu_init() then aborts with
// "ran out of space in drive_config_groups". Since the symbols are local, read
// their addresses from the loaded framework's Mach-O symbol table.
static uintptr_t DBQEMULocalSymbolAddress(NSURL *binaryURL, const void *loadedSymbol, const char *wantedName) {
    Dl_info imageInfo = {0};
    if (dladdr(loadedSymbol, &imageInfo) == 0 || !imageInfo.dli_fbase) return 0;

    int descriptor = open(binaryURL.fileSystemRepresentation, O_RDONLY);
    if (descriptor < 0) return 0;
    struct stat metadata = {0};
    if (fstat(descriptor, &metadata) != 0 || metadata.st_size < (off_t)sizeof(struct mach_header_64)) {
        close(descriptor);
        return 0;
    }
    size_t fileSize = (size_t)metadata.st_size;
    uint8_t *file = mmap(NULL, fileSize, PROT_READ, MAP_PRIVATE, descriptor, 0);
    close(descriptor);
    if (file == MAP_FAILED) return 0;

    uintptr_t result = 0;
    const struct mach_header_64 *header = (const struct mach_header_64 *)file;
    if (header->magic != MH_MAGIC_64 || sizeof(*header) + header->sizeofcmds > fileSize) goto finished;

    const struct symtab_command *symtab = NULL;
    uint64_t textVMAddress = 0;
    const uint8_t *commandBytes = file + sizeof(*header);
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (commandBytes + sizeof(struct load_command) > file + fileSize) goto finished;
        const struct load_command *command = (const struct load_command *)commandBytes;
        if (command->cmdsize < sizeof(*command) || commandBytes + command->cmdsize > file + fileSize) goto finished;
        if (command->cmd == LC_SYMTAB && command->cmdsize >= sizeof(struct symtab_command)) {
            symtab = (const struct symtab_command *)command;
        } else if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) textVMAddress = segment->vmaddr;
        }
        commandBytes += command->cmdsize;
    }
    if (!symtab || symtab->symoff > fileSize || symtab->stroff > fileSize ||
        (uint64_t)symtab->nsyms * sizeof(struct nlist_64) > fileSize - symtab->symoff ||
        symtab->strsize > fileSize - symtab->stroff) goto finished;

    const struct nlist_64 *symbols = (const struct nlist_64 *)(file + symtab->symoff);
    const char *strings = (const char *)(file + symtab->stroff);
    for (uint32_t index = 0; index < symtab->nsyms; index++) {
        uint32_t stringIndex = symbols[index].n_un.n_strx;
        if (stringIndex >= symtab->strsize) continue;
        if (strcmp(strings + stringIndex, wantedName) == 0) {
            uintptr_t slide = (uintptr_t)imageInfo.dli_fbase - (uintptr_t)textVMAddress;
            result = slide + (uintptr_t)symbols[index].n_value;
            break;
        }
    }

finished:
    munmap(file, fileSize);
    return result;
}

static NSUInteger DBQEMUNonNullPointerCount(void *const *pointers, NSUInteger count) {
    if (!pointers) return 0;
    NSUInteger nonNull = 0;
    for (NSUInteger index = 0; index < count; index++) {
        if (pointers[index]) nonNull++;
    }
    return nonNull;
}

static void DBQEMUResetStaleOptionRegistries(DBQEMUBridge *bridge, NSURL *coreURL) {
    void **driveGroups = (void **)DBQEMULocalSymbolAddress(coreURL, (const void *)bridge.qemuInit, "_drive_config_groups");
    void **vmGroups = (void **)DBQEMULocalSymbolAddress(coreURL, (const void *)bridge.qemuInit, "_vm_config_groups");
    NSUInteger driveCount = DBQEMUNonNullPointerCount(driveGroups, 5);
    NSUInteger vmCount = DBQEMUNonNullPointerCount(vmGroups, 48);
    DBQEMUWriteStage(bridge, [NSString stringWithFormat:@"option_registry_state drive=%lu vm=%lu", (unsigned long)driveCount, (unsigned long)vmCount]);

    if (driveCount == 0 && vmCount == 0) return;
    if (driveGroups) memset(driveGroups, 0, sizeof(void *) * 5);
    if (vmGroups) memset(vmGroups, 0, sizeof(void *) * 48);
    DBQEMUWriteStage(bridge, @"option_registry_reset stale LiveContainer QEMU state cleared");
}

static void *DBQEMUStartProcess(void *opaque) {
    DBQEMUBridge *bridge = (__bridge_transfer DBQEMUBridge *)opaque;
    @autoreleasepool {
        NSMutableArray<NSString *> *environmentStrings = [NSMutableArray arrayWithCapacity:bridge.environment.count];
        [bridge.environment enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [environmentStrings addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
            setenv(key.UTF8String, value.UTF8String, 1);
        }];
        const char **envp = calloc(environmentStrings.count + 1, sizeof(char *));
        for (NSUInteger index = 0; index < environmentStrings.count; index++) {
            envp[index] = environmentStrings[index].UTF8String;
        }

        if (bridge.currentDirectory.path.length > 0) {
            chdir(bridge.currentDirectory.fileSystemRepresentation);
        }

        NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObject:@"qemu-system-x86_64"];
        [allArguments addObjectsFromArray:bridge.arguments];
        const char **argv = calloc(allArguments.count + 1, sizeof(char *));
        for (NSUInteger index = 0; index < allArguments.count; index++) {
            argv[index] = allArguments[index].UTF8String;
        }

        DBQEMUWriteStage(bridge, [NSString stringWithFormat:@"argv=%@", [allArguments componentsJoinedByString:@" | "]]);
        int savedStdout = -1;
        int savedStderr = -1;
        int diagnosticDescriptor = open(bridge.diagnosticLogURL.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (diagnosticDescriptor >= 0) {
            savedStdout = dup(STDOUT_FILENO);
            savedStderr = dup(STDERR_FILENO);
            dup2(diagnosticDescriptor, STDOUT_FILENO);
            dup2(diagnosticDescriptor, STDERR_FILENO);
            close(diagnosticDescriptor);
            setvbuf(stdout, NULL, _IONBF, 0);
            setvbuf(stderr, NULL, _IONBF, 0);
            DBQEMUWriteStage(bridge, @"stdio_redirect_end");
        } else {
            DBQEMUWriteStage(bridge, [NSString stringWithFormat:@"stdio_redirect_failed errno=%d", errno]);
        }

        DBQEMUWriteStage(bridge, [NSString stringWithFormat:@"qemu_init_begin argc=%lu", (unsigned long)allArguments.count]);
        bridge.status = bridge.qemuInit((int)allArguments.count, argv, envp);
        DBQEMUWriteStage(bridge, [NSString stringWithFormat:@"qemu_init_end status=%ld", (long)bridge.status]);
        if (bridge.status == 0) {
            DBQEMUWriteStage(bridge, @"qemu_main_loop_begin");
            bridge.qemuMainLoop();
            DBQEMUWriteStage(bridge, @"qemu_main_loop_end");
            bridge.qemuCleanup();
            DBQEMUWriteStage(bridge, @"qemu_cleanup_end");
        }
        if (savedStdout >= 0) {
            fflush(stdout);
            dup2(savedStdout, STDOUT_FILENO);
            close(savedStdout);
        }
        if (savedStderr >= 0) {
            fflush(stderr);
            dup2(savedStderr, STDERR_FILENO);
            close(savedStderr);
        }
        free(argv);
        free(envp);
        dispatch_semaphore_signal(bridge.done);
    }
    return NULL;
}

@implementation DBQEMUBridge

- (void)releaseProcessSlot {
    @synchronized (DBQEMUBridge.class) {
        if (self.ownsProcessSlot) {
            DBQEMUProcessRunning = NO;
            self.ownsProcessSlot = NO;
        }
        self.running = NO;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, QOS_MIN_RELATIVE_PRIORITY);
        _completionQueue = dispatch_queue_create("DroidBox QEMU Completion Queue", attributes);
    }
    return self;
}

+ (NSURL *)binaryBundleURL {
    Dl_info info = {0};
    if (dladdr((const void *)&DBQEMUBridgeBinaryAnchor, &info) != 0 && info.dli_fname) {
        NSURL *binaryURL = [NSURL fileURLWithFileSystemRepresentation:info.dli_fname
                                                         isDirectory:NO
                                                       relativeToURL:nil];
        return binaryURL.URLByDeletingLastPathComponent;
    }
    return NSBundle.mainBundle.bundleURL;
}

+ (NSArray<NSURL *> *)coreCandidates {
    NSMutableArray<NSURL *> *roots = [NSMutableArray array];
    NSURL *binaryRoot = self.binaryBundleURL;
    if (binaryRoot) [roots addObject:binaryRoot];
    NSBundle *classBundle = [NSBundle bundleForClass:self];
    if (classBundle.bundleURL) [roots addObject:classBundle.bundleURL];
    if (NSBundle.mainBundle.bundleURL) [roots addObject:NSBundle.mainBundle.bundleURL];
    for (NSBundle *bundle in NSBundle.allBundles) {
        if (bundle.bundleURL) [roots addObject:bundle.bundleURL];
    }

    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSURL *root in roots) {
        NSURL *frameworks = [root URLByAppendingPathComponent:@"Frameworks" isDirectory:YES];
        NSArray<NSURL *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:frameworks
                                                               includingPropertiesForKeys:nil
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];
        NSArray<NSURL *> *versioned = [[entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *entry, NSDictionary *bindings) {
            return [entry.lastPathComponent hasPrefix:@"qemu-x86_64-softmmu-droidbox-"] && [entry.pathExtension isEqualToString:@"framework"];
        }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
            return [right.lastPathComponent compare:left.lastPathComponent options:NSNumericSearch];
        }];
        for (NSURL *framework in versioned) {
            NSURL *candidate = [framework URLByAppendingPathComponent:framework.URLByDeletingPathExtension.lastPathComponent];
            if (![seen containsObject:candidate.path]) {
                [seen addObject:candidate.path];
                [candidates addObject:candidate];
            }
        }
        NSURL *legacyCandidate = [frameworks URLByAppendingPathComponent:@"qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"];
        if (![seen containsObject:legacyCandidate.path]) {
            [seen addObject:legacyCandidate.path];
            [candidates addObject:legacyCandidate];
        }
    }
    return candidates;
}

+ (NSURL *)coreURL {
    for (NSURL *candidate in self.coreCandidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) return candidate;
    }
    return self.coreCandidates.firstObject;
}

+ (BOOL)coreBundled {
    NSURL *url = self.coreURL;
    return url && [[NSFileManager defaultManager] fileExistsAtPath:url.path];
}

+ (NSURL *)runtimeBundleURL {
    NSURL *core = self.coreURL;
    if (core && [[NSFileManager defaultManager] fileExistsAtPath:core.path]) {
        return core.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    }
    return self.binaryBundleURL;
}

- (BOOL)startWithArguments:(NSArray<NSString *> *)arguments
               environment:(NSDictionary<NSString *,NSString *> *)environment
          currentDirectory:(NSURL *)currentDirectory
          diagnosticLogURL:(NSURL *)diagnosticLogURL
               exitHandler:(DBQEMUExitHandler)exitHandler
                      error:(NSError *__autoreleasing  _Nullable *)error {
    @synchronized (DBQEMUBridge.class) {
        if (self.running || DBQEMUProcessRunning) {
            if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:@"Android VM 正在启动或运行，请勿重复启动。"}];
            return NO;
        }
        if (!DBQEMUBridge.coreBundled) {
            if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:2 userInfo:@{NSLocalizedDescriptionKey:@"qemu-x86_64-softmmu.framework is missing"}];
            return NO;
        }
        DBQEMUProcessRunning = YES;
        self.ownsProcessSlot = YES;
        self.running = YES;
    }

    self.arguments = arguments;
    self.environment = environment;
    self.currentDirectory = currentDirectory;
    self.diagnosticLogURL = diagnosticLogURL;
    self.exitHandler = exitHandler;
    self.done = dispatch_semaphore_create(0);
    self.status = -1;
    self.fatal = NO;

    NSURL *coreURL = DBQEMUBridge.coreURL;
    DBQEMUWriteStage(self, [NSString stringWithFormat:@"bridge_start core=%@", coreURL.path]);
    DBQEMUWriteStage(self, @"core_dlopen_begin");
    self.coreHandle = dlopen(coreURL.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
    if (!self.coreHandle) {
        NSString *message = [NSString stringWithUTF8String:dlerror() ?: "dlopen failed"];
        DBQEMUWriteStage(self, [NSString stringWithFormat:@"core_dlopen_failed error=%@", message]);
        [self releaseProcessSlot];
        if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:3 userInfo:@{NSLocalizedDescriptionKey: message}];
        return NO;
    }
    DBQEMUWriteStage(self, @"core_dlopen_end");

    dlerror();
    self.qemuInit = (DBQEMUInitFunction)dlsym(self.coreHandle, "qemu_init");
    self.qemuMainLoop = (DBQEMUVoidFunction)dlsym(self.coreHandle, "qemu_main_loop");
    self.qemuCleanup = (DBQEMUVoidFunction)dlsym(self.coreHandle, "qemu_cleanup");
    const char *symbolError = dlerror();
    if (!self.qemuInit || !self.qemuMainLoop || !self.qemuCleanup || symbolError) {
        NSString *message = symbolError ? [NSString stringWithUTF8String:symbolError] : @"Required QEMU entry points are missing";
        DBQEMUWriteStage(self, [NSString stringWithFormat:@"symbol_resolution_failed error=%@", message]);
        dlclose(self.coreHandle);
        self.coreHandle = NULL;
        [self releaseProcessSlot];
        if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:4 userInfo:@{NSLocalizedDescriptionKey: message}];
        return NO;
    }
    DBQEMUWriteStage(self, @"symbol_resolution_end");
    DBQEMUResetStaleOptionRegistries(self, coreURL);

    __weak typeof(self) weakSelf = self;
    if (atexit_b(^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && pthread_equal(pthread_self(), strongSelf.qemuThread)) {
            strongSelf.fatal = YES;
            DBQEMUWriteStage(strongSelf, @"qemu_called_exit");
            dispatch_semaphore_signal(strongSelf.done);
            pthread_exit(NULL);
        }
    }) != 0) {
        DBQEMUWriteStage(self, @"atexit_registration_failed");
        dlclose(self.coreHandle);
        self.coreHandle = NULL;
        [self releaseProcessSlot];
        if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Unable to register QEMU exit handler"}];
        return NO;
    }

    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_set_qos_class_np(&attributes, QOS_CLASS_USER_INTERACTIVE, 0);
    DBQEMUWriteStage(self, @"pthread_create_begin");
    void *threadContext = (__bridge_retained void *)self;
    int threadResult = pthread_create(&_qemuThread, &attributes, DBQEMUStartProcess, threadContext);
    pthread_attr_destroy(&attributes);
    if (threadResult != 0) {
        CFBridgingRelease(threadContext);
        NSString *message = [NSString stringWithFormat:@"pthread_create failed: %s", strerror(threadResult)];
        DBQEMUWriteStage(self, message);
        dlclose(self.coreHandle);
        self.coreHandle = NULL;
        [self releaseProcessSlot];
        if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:6 userInfo:@{NSLocalizedDescriptionKey: message}];
        return NO;
    }
    DBQEMUWriteStage(self, @"pthread_create_end");

    dispatch_async(self.completionQueue, ^{
        dispatch_semaphore_wait(self.done, DISPATCH_TIME_FOREVER);
        NSInteger exitCode = self.fatal || self.status != 0 ? -1 : 0;
        NSString *message = self.fatal ? @"QEMU terminated its worker thread" : nil;
        DBQEMUWriteStage(self, [NSString stringWithFormat:@"worker_finished status=%ld fatal=%d", (long)self.status, self.fatal]);
        if (dlclose(self.coreHandle) != 0 && !message) {
            message = [NSString stringWithUTF8String:dlerror() ?: "dlclose failed"];
            exitCode = -1;
        }
        self.coreHandle = NULL;
        [self releaseProcessSlot];
        dispatch_async(dispatch_get_main_queue(), ^{ self.exitHandler(exitCode, message); });
    });
    return YES;
}
@end
