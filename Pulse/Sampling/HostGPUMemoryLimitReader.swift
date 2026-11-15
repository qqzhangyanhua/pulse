import Foundation
import Metal

/// Static recommended working set. Not a Metal performance counter.
enum HostGPUMemoryLimitReader {
    static func recommendedMaxWorkingSetBytes() -> UInt64? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return device.recommendedMaxWorkingSetSize
    }
}
