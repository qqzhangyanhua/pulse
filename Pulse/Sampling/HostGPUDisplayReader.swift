import AppKit
import CoreGraphics
import Foundation

/// Active screens for the GPU page display card.
/// Called when that page is entered and when screen parameters change. Not from `MemorySampler`.
enum HostGPUDisplayReader {
    /// Nil when the active-display list cannot be read. Empty is a successful read of no screen.
    static func read() -> [GPUDisplayReading]? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        let screens = NSScreen.screens
        return ids.prefix(Int(count)).map { id in
            reading(id: id, screens: screens)
        }
    }

    private static func reading(id: CGDirectDisplayID, screens: [NSScreen]) -> GPUDisplayReading {
        let mode = CGDisplayCopyDisplayMode(id)
        let hertz = mode.map { CGDisplayModeGetRefreshRate($0) }
        let width = mode.map { Int(CGDisplayModeGetPixelWidth($0)) } ?? 0
        let height = mode.map { Int(CGDisplayModeGetPixelHeight($0)) } ?? 0
        let maximum = screens.first { displayID($0) == id }?.maximumFramesPerSecond
        return GPUDisplayReading(
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            pixelWidth: width,
            pixelHeight: height,
            modeRefreshHertz: hertz,
            maximumFramesPerSecond: maximum
        )
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
