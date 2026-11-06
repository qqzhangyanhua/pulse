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

    /// Per-core ticks in processor order. Nil on failure. Does not affect `read()`.
    static func readCores() -> [HostCPUTicks]? {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let status = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &info,
            &infoCount
        )
        guard status == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }
        let states = Int(CPU_STATE_MAX)
        guard processorCount > 0, states > 0, infoCount >= processorCount * natural_t(states) else {
            return nil
        }
        var cores: [HostCPUTicks] = []
        cores.reserveCapacity(Int(processorCount))
        for index in 0..<Int(processorCount) {
            let base = index * states
            cores.append(
                HostCPUTicks(
                    user: UInt64(truncatingIfNeeded: info[base + Int(CPU_STATE_USER)]),
                    system: UInt64(truncatingIfNeeded: info[base + Int(CPU_STATE_SYSTEM)]),
                    idle: UInt64(truncatingIfNeeded: info[base + Int(CPU_STATE_IDLE)]),
                    nice: UInt64(truncatingIfNeeded: info[base + Int(CPU_STATE_NICE)])
                )
            )
        }
        return cores
    }
}
