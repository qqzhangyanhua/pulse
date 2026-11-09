import XCTest
@testable import SamplingCore

final class ByteFormatTests: XCTestCase {
    func testGroupedBytesMatchOffTheMainThread() {
        let samples: [(UInt64, String)] = [
            (0, "0 字节"),
            (100, "100 字节"),
            (1_024, "1 KB"),
            (2_048, "2 KB"),
            (1_024_000, "1,000 KB"),
            (1_572_864, "1.5 MB"),
            (524_288_000, "500 MB"),
            (1_048_576_000, "1,000 MB"),
            (13_261_991_936, "12.35 GB"),
            (1_073_741_824_000, "1,000 GB"),
            (1_325_534_281_728, "1,234.5 GB"),
        ]
        for _ in 0..<2 {
            assertGrouped(samples, where: "main")
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var mismatches: [String] = []
        var sawBackground = false
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                if !Thread.isMainThread {
                    lock.lock()
                    sawBackground = true
                    lock.unlock()
                }
                for _ in 0..<20 {
                    for (bytes, text) in samples {
                        let formatted = ByteFormat.memory(bytes)
                        if formatted != text {
                            lock.lock()
                            mismatches.append("\(bytes) => \(formatted)")
                            lock.unlock()
                        }
                    }
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(sawBackground)
        XCTAssertEqual(mismatches, [])
    }

    private func assertGrouped(_ samples: [(UInt64, String)], where place: String) {
        for (bytes, text) in samples {
            XCTAssertEqual(ByteFormat.memory(bytes), text, "\(place) \(bytes)")
        }
    }
}
