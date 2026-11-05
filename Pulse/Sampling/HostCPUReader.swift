import Darwin

/// One cheap `host_statistics(HOST_CPU_LOAD_INFO)` read. Only `MemorySampler.sample()` calls this.
enum HostCPUReader {
    static func read() -> HostCPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        // cpu_ticks: CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE.
        let ticks = info.cpu_ticks
        return HostCPUTicks(
            user: UInt64(ticks.0),
            system: UInt64(ticks.1),
            idle: UInt64(ticks.2),
            nice: UInt64(ticks.3)
        )
    }
}
