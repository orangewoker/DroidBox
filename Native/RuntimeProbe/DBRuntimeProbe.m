#import "DBRuntimeProbe.h"
#import <mach/mach.h>
#import <sys/mman.h>

@implementation DBRuntimeProbe
+ (BOOL)canAllocateExecutableMemory {
    size_t page=(size_t)vm_page_size; void *ptr=mmap(NULL,page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0); if(ptr==MAP_FAILED)return NO;
    BOOL ok=mprotect(ptr,page,PROT_READ|PROT_EXEC)==0; munmap(ptr,page); return ok;
}
+ (uint64_t)physicalMemory { return NSProcessInfo.processInfo.physicalMemory; }
+ (uint64_t)availableMemoryEstimate {
    mach_msg_type_number_t count=HOST_VM_INFO64_COUNT; vm_statistics64_data_t stats; mach_port_t host=mach_host_self();
    if(host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&stats,&count)!=KERN_SUCCESS)return 0;
    return (uint64_t)(stats.free_count+stats.inactive_count)*(uint64_t)vm_page_size;
}
@end

