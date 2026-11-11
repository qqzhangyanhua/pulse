import Darwin
import Foundation

struct RawProcessSample: Sendable, Equatable {
    let pid: Int32
    let comm: String
    let path: String?
    /// `proc_taskinfo` resident size. The sampler chooses the row value.
    let residentBytes: UInt64
    /// `ri_phys_footprint` from the same rusage read as disk IO. Nil when that call fails.
    let footprintBytes: UInt64?
    let threadCount: Int
    /// Nanoseconds from Mach ticks. Nil when the timebase or either conversion is missing.
    let userTimeNs: UInt64?
    let systemTimeNs: UInt64?
    /// `ri_diskio_*` from `proc_pid_rusage`. Nil when the call fails (EPERM / ESRCH / other).
    let diskBytesRead: UInt64?
    let diskBytesWritten: UInt64?
    /// `ri_energy_nj` nanojoules from the same rusage read. Nil when that call fails.
    let energyNanojoules: UInt64?
    /// `ri_interrupt_wkups` from the same rusage read. Nil when that call fails. No resident fallback.
    let interruptWakeups: UInt64?
    /// `pbi_ppid` from `PROC_PIDTBSDINFO`. Nil when the read byte count is not the struct size.
    let parentPid: Int32?
}

/// One `list()` walk. Denied pids are a count, not rows.
struct ProcessListReading: Sendable {
    let samples: [RawProcessSample]
    let permissionDeniedCount: Int
}

/// `proc_listpids` / `proc_pidinfo` walk. Display names are resolved later with a cache.
enum ProcessEnumerator {
    private static let procAllPids: UInt32 = 1
    private static let procPidTbsdInfo: Int32 = 3
    private static let procPidTaskInfo: Int32 = 4
    /// `sizeof(struct proc_bsdinfo)`. `pbi_ppid` is the UInt32 at byte 16.
    private static let procBsdInfoSize: Int32 = 136
    private static let procBsdPpidOffset = 16
    private static let rusageInfoV6: Int32 = 6
    private static let pathBufferSize: Int32 = 4_096

    static func list() -> ProcessListReading? {
        let bytesNeeded = pulse_proc_listpids(procAllPids, 0, nil, 0)
        guard bytesNeeded > 0 else { return nil }

        let capacity = Int(bytesNeeded) / MemoryLayout<pid_t>.stride + 16
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            pulse_proc_listpids(
                procAllPids,
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard written > 0 else { return nil }

        let count = Int(written) / MemoryLayout<pid_t>.stride
        let timebase = readMachTimebase()
        var samples: [RawProcessSample] = []
        samples.reserveCapacity(count)
        var permissionDeniedCount = 0

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }
            let inspected = inspect(pid: pid, timebase: timebase)
            if let sample = inspected.sample {
                samples.append(sample)
            } else if inspected.permissionDenied {
                permissionDeniedCount += 1
            }
        }
        return ProcessListReading(
            samples: samples,
            permissionDeniedCount: permissionDeniedCount
        )
    }

    private static func inspect(
        pid: pid_t,
        timebase: (numer: Int64, denom: Int64)?
    ) -> InspectedTask {
        var info = ProcTaskInfo()
        let infoSize = Int32(MemoryLayout<ProcTaskInfo>.stride)
        var taskInfoErrno: Int32 = 0
        let filled = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            errno = 0
            let written = pulse_proc_pidinfo(pid, procPidTaskInfo, 0, pointer, infoSize)
            if written != infoSize {
                taskInfoErrno = errno
            }
            return written
        }
        guard filled == infoSize else {
            return InspectedTask(
                sample: nil,
                permissionDenied: ProcessPermissionFootnote.countsTaskInfoFailure(errno: taskInfoErrno)
            )
        }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        _ = nameBuffer.withUnsafeMutableBufferPointer { buffer in
            pulse_proc_name(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        let comm = String(cString: nameBuffer)
        let name = comm.isEmpty ? "pid \(pid)" : comm

        var pathBuffer = [CChar](repeating: 0, count: Int(pathBufferSize))
        let pathLen = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            pulse_proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        let path = pathLen > 0 ? String(cString: pathBuffer) : nil
        let rusage = readRusage(pid: pid)
        let parentPid = readParentPid(pid: pid)
        let cpu = convertedCPU(
            user: info.pti_total_user,
            system: info.pti_total_system,
            timebase: timebase
        )

        return InspectedTask(
            sample: RawProcessSample(
                pid: pid,
                comm: name,
                path: path,
                residentBytes: info.pti_resident_size,
                footprintBytes: rusage?.footprintBytes,
                threadCount: max(0, Int(info.pti_threadnum)),
                userTimeNs: cpu?.user,
                systemTimeNs: cpu?.system,
                diskBytesRead: rusage?.bytesRead,
                diskBytesWritten: rusage?.bytesWritten,
                energyNanojoules: rusage?.energyNanojoules,
                interruptWakeups: rusage?.interruptWakeups,
                parentPid: parentPid
            ),
            permissionDenied: false
        )
    }

    /// One read per `list()` frame. A failure leaves every process CPU time missing.
    private static func readMachTimebase() -> (numer: Int64, denom: Int64)? {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS else { return nil }
        return (Int64(info.numer), Int64(info.denom))
    }

    /// Both counters convert, or both are missing. A failed conversion is not stored as 0.
    private static func convertedCPU(
        user userTick: UInt64,
        system systemTick: UInt64,
        timebase: (numer: Int64, denom: Int64)?
    ) -> (user: UInt64, system: UInt64)? {
        guard let timebase,
              let user = MachTimebase.nanoseconds(tick: userTick, numer: timebase.numer, denom: timebase.denom),
              let system = MachTimebase.nanoseconds(tick: systemTick, numer: timebase.numer, denom: timebase.denom)
        else {
            return nil
        }
        return (user, system)
    }

    /// A short read is a missing parent, not ppid 0. Same rule as rusage: the row still returns.
    private static func readParentPid(pid: pid_t) -> Int32? {
        var buffer = [UInt8](repeating: 0, count: Int(procBsdInfoSize))
        let written = buffer.withUnsafeMutableBytes { raw -> Int32 in
            pulse_proc_pidinfo(pid, procPidTbsdInfo, 0, raw.baseAddress, procBsdInfoSize)
        }
        guard written == procBsdInfoSize else { return nil }
        let ppid = buffer.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: procBsdPpidOffset, as: UInt32.self)
        }
        return Int32(bitPattern: ppid)
    }

    /// rusage failure must not drop the row. SIP / kernel tasks often return EPERM.
    /// One v6 call supplies disk counters, footprint, energy, and wakeups. No v4 retry.
    /// A zero footprint is a real reading. Energy has no fallback: failure leaves both nil.
    private static func readRusage(pid: pid_t) -> ProcessRusageSample? {
        var info = PulseRusageInfoV6()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pulse_proc_pid_rusage(pid, rusageInfoV6, pointer)
        }
        guard status == 0 else { return nil }
        return ProcessRusageSample(
            bytesRead: info.ri_diskio_bytesread,
            bytesWritten: info.ri_diskio_byteswritten,
            footprintBytes: info.ri_phys_footprint,
            energyNanojoules: info.ri_energy_nj,
            interruptWakeups: info.ri_interrupt_wkups
        )
    }
}

private struct InspectedTask {
    let sample: RawProcessSample?
    let permissionDenied: Bool
}

private struct ProcessRusageSample {
    let bytesRead: UInt64
    let bytesWritten: UInt64
    let footprintBytes: UInt64
    let energyNanojoules: UInt64
    let interruptWakeups: UInt64
}

struct ProcessIdentity: Sendable, Equatable {
    let name: String
    let bundleIdentifier: String?
    let path: String?
}

enum ProcessIdentityResolver {
    static func resolve(sample: RawProcessSample, cached: ProcessIdentity?) -> ProcessIdentity {
        if let cached, cached.path == sample.path {
            return cached
        }
        return makeIdentity(sample: sample)
    }

    private static func makeIdentity(sample: RawProcessSample) -> ProcessIdentity {
        guard let path = sample.path, let appURL = applicationURL(from: path) else {
            return ProcessIdentity(name: sample.comm, bundleIdentifier: nil, path: sample.path)
        }
        guard let bundle = Bundle(url: appURL) else {
            return ProcessIdentity(name: sample.comm, bundleIdentifier: nil, path: sample.path)
        }
        let display =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? sample.comm
        return ProcessIdentity(
            name: display,
            bundleIdentifier: bundle.bundleIdentifier,
            path: sample.path
        )
    }

    private static func applicationURL(from path: String) -> URL? {
        let marker = ".app/"
        guard let range = path.range(of: marker, options: [.caseInsensitive]) else {
            if path.lowercased().hasSuffix(".app") {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        let appPath = String(path[..<range.upperBound].dropLast())
        return URL(fileURLWithPath: appPath)
    }
}

/// Matches Darwin `struct proc_taskinfo` (libproc.h). Times are Mach absolute ticks.
struct ProcTaskInfo {
    var pti_virtual_size: UInt64 = 0
    var pti_resident_size: UInt64 = 0
    var pti_total_user: UInt64 = 0
    var pti_total_system: UInt64 = 0
    var pti_threads_user: UInt64 = 0
    var pti_threads_system: UInt64 = 0
    var pti_policy: Int32 = 0
    var pti_faults: Int32 = 0
    var pti_pageins: Int32 = 0
    var pti_cow_faults: Int32 = 0
    var pti_messages_sent: Int32 = 0
    var pti_messages_received: Int32 = 0
    var pti_syscalls_mach: Int32 = 0
    var pti_syscalls_unix: Int32 = 0
    var pti_csw: Int32 = 0
    var pti_threadnum: Int32 = 0
    var pti_numrunning: Int32 = 0
    var pti_priority: Int32 = 0
}

@_silgen_name("proc_listpids")
private func pulse_proc_listpids(
    _ type: UInt32,
    _ typeinfo: UInt32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int32
) -> Int32

@_silgen_name("proc_pidinfo")
private func pulse_proc_pidinfo(
    _ pid: Int32,
    _ flavor: Int32,
    _ arg: UInt64,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int32
) -> Int32

@_silgen_name("proc_name")
private func pulse_proc_name(
    _ pid: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: UInt32
) -> Int32

@_silgen_name("proc_pidpath")
private func pulse_proc_pidpath(
    _ pid: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: UInt32
) -> Int32

@_silgen_name("proc_pid_rusage")
private func pulse_proc_pid_rusage(
    _ pid: Int32,
    _ flavor: Int32,
    _ buffer: UnsafeMutableRawPointer?
) -> Int32

/// Matches Darwin `struct rusage_info_v6` (macOS 14 sys/resource.h). Same size on later SDKs.
/// `ri_energy_nj` follows `ri_billed_energy`; they are not the same field.
private struct PulseRusageInfoV6 {
    var ri_uuid: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var ri_user_time: UInt64 = 0
    var ri_system_time: UInt64 = 0
    var ri_pkg_idle_wkups: UInt64 = 0
    var ri_interrupt_wkups: UInt64 = 0
    var ri_pageins: UInt64 = 0
    var ri_wired_size: UInt64 = 0
    var ri_resident_size: UInt64 = 0
    var ri_phys_footprint: UInt64 = 0
    var ri_proc_start_abstime: UInt64 = 0
    var ri_proc_exit_abstime: UInt64 = 0
    var ri_child_user_time: UInt64 = 0
    var ri_child_system_time: UInt64 = 0
    var ri_child_pkg_idle_wkups: UInt64 = 0
    var ri_child_interrupt_wkups: UInt64 = 0
    var ri_child_pageins: UInt64 = 0
    var ri_child_elapsed_abstime: UInt64 = 0
    var ri_diskio_bytesread: UInt64 = 0
    var ri_diskio_byteswritten: UInt64 = 0
    var ri_cpu_time_qos_default: UInt64 = 0
    var ri_cpu_time_qos_maintenance: UInt64 = 0
    var ri_cpu_time_qos_background: UInt64 = 0
    var ri_cpu_time_qos_utility: UInt64 = 0
    var ri_cpu_time_qos_legacy: UInt64 = 0
    var ri_cpu_time_qos_user_initiated: UInt64 = 0
    var ri_cpu_time_qos_user_interactive: UInt64 = 0
    var ri_billed_system_time: UInt64 = 0
    var ri_serviced_system_time: UInt64 = 0
    var ri_logical_writes: UInt64 = 0
    var ri_lifetime_max_phys_footprint: UInt64 = 0
    var ri_instructions: UInt64 = 0
    var ri_cycles: UInt64 = 0
    var ri_billed_energy: UInt64 = 0
    var ri_serviced_energy: UInt64 = 0
    var ri_interval_max_phys_footprint: UInt64 = 0
    var ri_runnable_time: UInt64 = 0
    var ri_flags: UInt64 = 0
    var ri_user_ptime: UInt64 = 0
    var ri_system_ptime: UInt64 = 0
    var ri_pinstructions: UInt64 = 0
    var ri_pcycles: UInt64 = 0
    var ri_energy_nj: UInt64 = 0
    var ri_penergy_nj: UInt64 = 0
    /// macOS 14 `ri_reserved[14]`. Later SDKs name some of these slots; the size stays 112 bytes.
    var ri_reserved: (
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
