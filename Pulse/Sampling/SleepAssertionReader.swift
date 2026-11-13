import Foundation
import IOKit
import IOKit.pwr_mgt

/// One `IOPMCopyAssertionsByProcess` read for the energy page.
/// Not called from `MemorySampler`. A failure returns nil so the previous rows stay.
enum SleepAssertionReader {
    static func read(now: Date = Date()) -> [SleepAssertionRow]? {
        var holder: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&holder)
        guard status == kIOReturnSuccess, let holder else { return nil }
        let dictionary = holder.takeRetainedValue() as NSDictionary
        return SleepAssertionDecoder.rows(from: normalize(dictionary), now: now)
    }

    /// CFNumber pid keys and CFArray values become the decoder's Swift shape.
    private static func normalize(_ dictionary: NSDictionary) -> [AnyHashable: Any] {
        var result: [AnyHashable: Any] = [:]
        for (key, value) in dictionary {
            guard let pid = processIdentifier(key) else { continue }
            guard let list = value as? NSArray else { continue }
            var assertions: [[String: Any]] = []
            for item in list {
                guard let entry = item as? NSDictionary else { continue }
                var fields: [String: Any] = [:]
                for (fieldKey, fieldValue) in entry {
                    guard let name = fieldKey as? String else { continue }
                    fields[name] = normalizedField(name, fieldValue)
                }
                assertions.append(fields)
            }
            result[pid] = assertions
        }
        return result
    }

    private static func processIdentifier(_ key: Any) -> Int? {
        if let number = key as? NSNumber { return number.intValue }
        if let pid = key as? Int { return pid }
        return nil
    }

    private static func normalizedField(_ name: String, _ value: Any) -> Any {
        if name == "AssertStartWhen" || name == "AssertTimedOutWhen" {
            if let date = value as? Date { return date }
        }
        return value
    }
}
