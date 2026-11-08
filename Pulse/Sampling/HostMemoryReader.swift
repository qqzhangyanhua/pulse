import Darwin
import Foundation

enum HostMemoryError: Error, Sendable, Equatable {
    case pageSize(kern_return_t)
    case statistics(kern_return_t)
    case physicalMemoryUnknown
}

struct RawHostMemory: Sendable, Equatable {
    let pageSize: UInt64
    let totalBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let usedBytes: UInt64
    let pressure: PressureLevel
    let pressureMetric: Double
}

/// Reads `vm_statistics64` / `host_statistics64` and maps pages onto Activity Monitor categories.
enum HostMemoryReader {
    static func read() throws -> RawHostMemory {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { throw HostMemoryError.physicalMemoryUnknown }

        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        let pageStatus = host_page_size(host, &pageSize)
        guard pageStatus == KERN_SUCCESS, pageSize > 0 else {
            throw HostMemoryError.pageSize(pageStatus)
        }

        var stats = vm_statistics64()
        var lastStatus: kern_return_t = KERN_FAILURE
        var filled = false
        for candidate in hostVMInfo64Counts {
            var count = candidate
            lastStatus = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    host_statistics64(host, HOST_VM_INFO64, rebound, &count)
                }
            }
            if lastStatus == KERN_SUCCESS {
                filled = true
                break
            }
        }
        guard filled else {
            throw HostMemoryError.statistics(lastStatus)
        }

        let pages = UInt64(pageSize)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

        let appBytes = appPages &* pages
        let wiredBytes = UInt64(stats.wire_count) &* pages
        let compressedBytes = UInt64(stats.compressor_page_count) &* pages
        let cachedBytes = UInt64(stats.external_page_count) &* pages
        let usedBytes = appBytes &+ wiredBytes &+ compressedBytes

        let usedRatio = min(1, Double(usedBytes) / Double(totalBytes))
        let pressure = KernelPressure.resolve(
            reading: PressureProvider.read(),
            usedRatio: usedRatio,
            compressedRatio: Double(compressedBytes) / Double(totalBytes)
        )

        return RawHostMemory(
            pageSize: pages,
            totalBytes: totalBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            usedBytes: min(usedBytes, totalBytes),
            pressure: pressure,
            pressureMetric: usedRatio
        )
    }

    /// Kernel `HOST_VM_INFO64_COUNT` is a C macro and not always imported. Try layout then 38/39.
    private static let hostVMInfo64Counts: [mach_msg_type_number_t] = {
        let layout = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let unique = Array(Set([layout, 38, 39]))
        return unique.sorted(by: >)
    }()
}

/// Layout of `struct xsw_usage`. Kept local so a size mismatch stays a nil sample.
struct SwapUsageRaw {
    var xsu_total: UInt64 = 0
    var xsu_avail: UInt64 = 0
    var xsu_used: UInt64 = 0
    var xsu_pagesize: UInt32 = 0
    var xsu_encrypted: UInt32 = 0
}

/// `vm.swapusage` only. A failed read is nil and never a thrown host-memory error.
enum SwapUsageReader {
    static func read() -> UInt64? {
        var raw = SwapUsageRaw()
        var returnedSize = 0
        let expectedSize = MemoryLayout<SwapUsageRaw>.size
        let status = withUnsafeMutableBytes(of: &raw) { buffer -> Int32 in
            var size = buffer.count
            let result = sysctlbyname("vm.swapusage", buffer.baseAddress, &size, nil, 0)
            returnedSize = size
            return result
        }
        return SwapUsage.usedBytes(
            from: SwapUsageSample(
                status: status,
                returnedSize: returnedSize,
                expectedSize: expectedSize,
                usedBytes: raw.xsu_used
            )
        )
    }
}

/// Raw `kern.memorystatus_vm_pressure_level`. Mapping and the ratio fallback live in `KernelPressure`.
enum PressureProvider {
    static func read() -> KernelPressureSample {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0)
        return KernelPressureSample(status: status, value: value)
    }
}
