import Darwin
import Foundation

/// One frame of HID temperature services. Selection and rounding stay in the projection.
/// Symbols are resolved at runtime. A miss is an empty list, not zero.
enum HostChipTemperatureReader {
    private static let frameworkPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let temperatureEventType: Int64 = 15
    private static let temperatureLevelField: Int32 = 15 << 16
    private static let productKey: CFString = "Product" as CFString
    private static let matching: CFDictionary = [
        "PrimaryUsagePage": 0xFF00,
        "PrimaryUsage": 5,
    ] as CFDictionary

    private typealias CreateClient = @convention(c) (UnsafeMutableRawPointer?) -> OpaquePointer?
    private typealias SetMatching = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    private typealias CopyServices = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias CopyProperty = @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias CopyEvent = @convention(c) (OpaquePointer?, Int64, Int32, Int64) -> OpaquePointer?
    private typealias GetFloatValue = @convention(c) (OpaquePointer?, Int32) -> Double

    private struct Symbols {
        var create: CreateClient
        var setMatching: SetMatching
        var copyServices: CopyServices
        var copyProperty: CopyProperty
        var copyEvent: CopyEvent
        var floatValue: GetFloatValue
    }

    private static var library: UnsafeMutableRawPointer?
    private static var symbols: Symbols?
    private static var unavailable = false
    private static var client: OpaquePointer?

    static func read() -> [ChipTemperatureSensor] {
        guard let symbols = loadedSymbols() else { return [] }
        guard let client = ensureClient(symbols) else { return [] }
        return sensors(from: client, symbols: symbols)
    }

    private static func loadedSymbols() -> Symbols? {
        if let symbols { return symbols }
        if unavailable { return nil }
        guard let opened = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
            unavailable = true
            return nil
        }
        guard
            let create: CreateClient = symbol("IOHIDEventSystemClientCreate", in: opened),
            let setMatching: SetMatching = symbol("IOHIDEventSystemClientSetMatching", in: opened),
            let copyServices: CopyServices = symbol("IOHIDEventSystemClientCopyServices", in: opened),
            let copyProperty: CopyProperty = symbol("IOHIDServiceClientCopyProperty", in: opened),
            let copyEvent: CopyEvent = symbol("IOHIDServiceClientCopyEvent", in: opened),
            let floatValue: GetFloatValue = symbol("IOHIDEventGetFloatValue", in: opened)
        else {
            dlclose(opened)
            unavailable = true
            return nil
        }
        library = opened
        let loaded = Symbols(
            create: create,
            setMatching: setMatching,
            copyServices: copyServices,
            copyProperty: copyProperty,
            copyEvent: copyEvent,
            floatValue: floatValue
        )
        symbols = loaded
        return loaded
    }

    private static func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer) -> T? {
        guard let raw = dlsym(library, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func ensureClient(_ symbols: Symbols) -> OpaquePointer? {
        if let client { return client }
        guard let created = symbols.create(nil) else { return nil }
        let match = OpaquePointer(Unmanaged.passUnretained(matching).toOpaque())
        symbols.setMatching(created, match)
        client = created
        return created
    }

    private static func sensors(from client: OpaquePointer, symbols: Symbols) -> [ChipTemperatureSensor] {
        guard let raw = symbols.copyServices(client) else { return [] }
        let services: CFArray = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(raw)).takeRetainedValue()
        let count = CFArrayGetCount(services)
        if count == 0 { return [] }
        var rows: [ChipTemperatureSensor] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            guard let value = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = OpaquePointer(value)
            rows.append(
                ChipTemperatureSensor(
                    productName: productName(of: service, symbols: symbols),
                    celsius: celsius(of: service, symbols: symbols)
                )
            )
        }
        return rows
    }

    private static func productName(of service: OpaquePointer, symbols: Symbols) -> String? {
        let key = OpaquePointer(Unmanaged.passUnretained(productKey).toOpaque())
        guard let raw = symbols.copyProperty(service, key) else { return nil }
        let value: CFTypeRef = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(raw)).takeRetainedValue()
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private static func celsius(of service: OpaquePointer, symbols: Symbols) -> Double? {
        guard let raw = symbols.copyEvent(service, temperatureEventType, Int32(0), Int64(0)) else { return nil }
        let event: CFTypeRef = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(raw)).takeRetainedValue()
        let pointer = OpaquePointer(Unmanaged.passUnretained(event).toOpaque())
        let reading = symbols.floatValue(pointer, temperatureLevelField)
        guard reading.isFinite else { return nil }
        return reading
    }
}
