#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>

/* Reads counters only for explicitly supplied preview child PIDs. */
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        int pid = atoi(argv[i]);
        struct rusage_info_v4 usage = {0};
        if (pid <= 0 || proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) return 1;
        printf("{\"pid\":%d,\"user_ns\":%llu,\"system_ns\":%llu,\"rss_bytes\":%llu,\"footprint_bytes\":%llu,\"idle_wakeups\":%llu,\"interrupt_wakeups\":%llu}\n",
               pid, usage.ri_user_time, usage.ri_system_time, usage.ri_resident_size,
               usage.ri_phys_footprint, usage.ri_pkg_idle_wkups, usage.ri_interrupt_wkups);
    }
    return 0;
}
