import Darwin
import Foundation

enum MachineInfo {
    static var processorCount: Int {
        let count = ProcessInfo.processInfo.processorCount
        return count > 0 ? count : 1
    }

    static func toolbarLabel() -> String {
        let model = hardwareModel() ?? "Mac"
        let cores = "\(processorCount) 核"
        if let ram = memoryLabel() {
            return "\(model) · \(cores) · \(ram)"
        }
        return "\(model) · \(cores)"
    }

    static func hardwareModel() -> String? {
        stringSysctl("hw.model")
    }

    /// Marketing chip name, such as "Apple M3 Pro". Nil when sysctl fails or returns empty.
    /// Not a substitute for `hw.model`.
    static func chipName() -> String? {
        stringSysctl("machdep.cpu.brand_string")
    }

    static func memoryLabel() -> String? {
        let bytes = ProcessInfo.processInfo.physicalMemory
        guard bytes > 0 else { return nil }
        return ByteFormat.gibWhole(bytes)
    }

    private static func stringSysctl(_ name: String) -> String? {
        var size = 0
        let probe = sysctlbyname(name, nil, &size, nil, 0)
        guard probe == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let status = buffer.withUnsafeMutableBufferPointer { pointer in
            sysctlbyname(name, pointer.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}
