#import "DBRuntimeProbe.h"
#import <mach/mach.h>
#import <sys/mman.h>
#import <sys/sysctl.h>
#import <sys/proc.h>
#import <unistd.h>

#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

@implementation DBRuntimeProbe
+ (BOOL)canAllocateExecutableMemory {
    return [self jitMode] != 0;
}

+ (NSInteger)jitMode {
    // Mode 1: allow-jit / MAP_JIT entitlement route.
#if defined(MAP_JIT)
    size_t jitPage = (size_t)vm_page_size;
    void *jitPointer = mmap(
        NULL,
        jitPage,
        PROT_READ | PROT_WRITE | PROT_EXEC,
        MAP_PRIVATE | MAP_ANON | MAP_JIT,
        -1,
        0
    );
    if (jitPointer != MAP_FAILED) {
        munmap(jitPointer, jitPage);
        return 1;
    }
#endif

    // Mode 2: debugger JIT route used by StikDebug. StikDebug can leave the
    // process with CS_DEBUGGED after detaching, so P_TRACED alone is not enough.
    BOOL debugged = NO;
    uint32_t codeSigningFlags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &codeSigningFlags, sizeof(codeSigningFlags)) == 0) {
        debugged = (codeSigningFlags & CS_DEBUGGED) != 0;
    }
    if (!debugged) {
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
        struct kinfo_proc info;
        memset(&info, 0, sizeof(info));
        size_t size = sizeof(info);
        if (sysctl(mib, 4, &info, &size, NULL, 0) == 0) {
            debugged = (info.kp_proc.p_flag & P_TRACED) != 0;
        }
    }
    if (!debugged) return 0;

    size_t page = (size_t)vm_page_size;
    void *ptr = mmap(
        NULL,
        page,
        PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON,
        -1,
        0
    );
    if (ptr == MAP_FAILED) return 0;
    BOOL executable = mprotect(ptr, page, PROT_READ | PROT_EXEC) == 0;
    munmap(ptr, page);
    return executable ? 2 : 0;
}
+ (uint64_t)physicalMemory { return NSProcessInfo.processInfo.physicalMemory; }
+ (uint64_t)availableMemoryEstimate {
    mach_msg_type_number_t count=HOST_VM_INFO64_COUNT; vm_statistics64_data_t stats; mach_port_t host=mach_host_self();
    if(host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&stats,&count)!=KERN_SUCCESS)return 0;
    return (uint64_t)(stats.free_count+stats.inactive_count)*(uint64_t)vm_page_size;
}
@end
