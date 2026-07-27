// Launcher design follows UTM's Apache-2.0 UTMQemuSystem process boundary.
#import "DBQEMUBridge.h"
#import <dlfcn.h>
#import <pthread.h>
#import <stdlib.h>
#import <string.h>

@interface DBQEMUBridge ()
@property(atomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation DBQEMUBridge

+ (NSURL *)coreURL {
    return [NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"];
}

+ (BOOL)coreBundled { return [[NSFileManager defaultManager] isExecutableFileAtPath:self.coreURL.path]; }

- (BOOL)startWithArguments:(NSArray<NSString *> *)arguments
               environment:(NSDictionary<NSString *,NSString *> *)environment
               exitHandler:(DBQEMUExitHandler)exitHandler
                      error:(NSError *__autoreleasing  _Nullable *)error {
    @synchronized (self) {
        if (self.running) {
            if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:1 userInfo:@{NSLocalizedDescriptionKey:@"QEMU is already running"}];
            return NO;
        }
        if (!DBQEMUBridge.coreBundled) {
            if (error) *error = [NSError errorWithDomain:@"DroidBox.QEMU" code:2 userInfo:@{NSLocalizedDescriptionKey:@"qemu-aarch64-softmmu.framework is missing"}];
            return NO;
        }
        self.running = YES;
    }

    NSArray<NSString *> *capturedArguments = [arguments copy];
    NSDictionary<NSString *, NSString *> *capturedEnvironment = [environment copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            pthread_t qemuThread = pthread_self();
            atexit_b(^{
                if (pthread_equal(pthread_self(), qemuThread)) {
                    self.running = NO;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        exitHandler(-1, @"QEMU terminated its worker thread");
                    });
                    pthread_exit(NULL);
                }
            });
            NSInteger exitCode = -1; NSString *message = nil;
            void *handle = dlopen(DBQEMUBridge.coreURL.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
            if (!handle) {
                message = [NSString stringWithUTF8String:dlerror() ?: "dlopen failed"];
            } else {
                int (*qemuInit)(int, const char *[], const char *[]) = dlsym(handle, "qemu_init");
                void (*qemuMainLoop)(void) = dlsym(handle, "qemu_main_loop");
                void (*qemuCleanup)(void) = dlsym(handle, "qemu_cleanup");
                if (!qemuInit || !qemuMainLoop || !qemuCleanup) {
                    message = @"Required QEMU entry points are missing";
                } else {
                    [capturedEnvironment enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { setenv(key.UTF8String, value.UTF8String, 1); }];
                    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObject:@"qemu-system-x86_64"]; [all addObjectsFromArray:capturedArguments];
                    const char **argv = calloc(all.count + 1, sizeof(char *));
                    for (NSUInteger i = 0; i < all.count; i++) argv[i] = strdup(all[i].fileSystemRepresentation);
                    exitCode = qemuInit((int)all.count, argv, NULL);
                    if (exitCode == 0) { qemuMainLoop(); qemuCleanup(); }
                    for (NSUInteger i = 0; i < all.count; i++) free((void *)argv[i]); free(argv);
                }
                dlclose(handle);
            }
            self.running = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ exitHandler(exitCode, message); });
        }
    });
    return YES;
}
@end
