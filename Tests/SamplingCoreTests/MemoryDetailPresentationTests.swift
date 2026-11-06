import XCTest
@testable import SamplingCore

/// Phase 17 resident-memory detail copy. Pure functions only.
/// A pass here is not a SwiftUI sidebar, not a snapshot, and not a Mac click.
final class MemoryDetailPresentationTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824

    func testMemoryPagePositiveTotalUsesResidentTitleAndShareCaption() {
        let cases: [(UInt64, UInt64)] = shareBands() + [(0, 16 * gib)]
        for (part, total) in cases {
            let share = ByteFormat.share(part: part, total: total)
            let copy = MemoryDetailPresentation.field(page: .memory, part: part, total: total)
            XCTAssertEqual(copy.title, "驻留内存", "part \(part) total \(total)")
            XCTAssertEqual(copy.caption, "占物理内存的 \(share)（按驻留内存计算）")
            XCTAssertNil(copy.help)
            XCTAssertFalse(copy.caption.contains("GB"))
        }
    }

    func testShareFormatterBoundariesStayOnByteFormat() {
        XCTAssertEqual(ByteFormat.share(part: 1, total: 10_000), "<0.1%")
        XCTAssertEqual(ByteFormat.share(part: 999, total: 1_000_000), "<0.1%")
        XCTAssertEqual(ByteFormat.share(part: 1, total: 1_000), "0.1%")
        XCTAssertEqual(ByteFormat.share(part: 1, total: 100), "1.0%")
        XCTAssertEqual(ByteFormat.share(part: 25, total: 1_000), "2.5%")
        XCTAssertEqual(ByteFormat.share(part: 5, total: 100), "5.0%")
        XCTAssertEqual(ByteFormat.share(part: 9, total: 100), "9.0%")
        XCTAssertEqual(ByteFormat.share(part: 99, total: 1_000), "9.9%")
        XCTAssertEqual(ByteFormat.share(part: 10, total: 100), "10%")
        XCTAssertEqual(ByteFormat.share(part: 50, total: 100), "50%")
        XCTAssertEqual(ByteFormat.share(part: 100, total: 100), "100%")
        XCTAssertEqual(ByteFormat.share(part: 0, total: 16 * gib), "0.0%")
        XCTAssertEqual(ByteFormat.share(part: 1, total: 0), "0%")
        XCTAssertEqual(ByteFormat.wholePercent(part: 1, total: 0), "0%")
    }

    func testMemoryPageMissingTotalKeepsShareLabelWithoutAFabricatedPercent() {
        for total in [UInt64?.none, UInt64(0)] {
            let copy = MemoryDetailPresentation.field(page: .memory, part: 12_345, total: total)
            XCTAssertEqual(copy.caption, "占物理内存")
            XCTAssertFalse(copy.caption.contains("0%"), "total \(String(describing: total))")
            XCTAssertFalse(copy.caption.contains("100%"))
            XCTAssertFalse(copy.caption.contains("%"))
            let help = copy.help ?? ""
            XCTAssertFalse(help.contains("0%"))
            XCTAssertFalse(help.contains("100%"))
        }
    }

    func testMemoryPageMissingTotalHelpStatesResidentAndNoShare() {
        let help = "此数值为驻留内存。当前没有物理内存总量，不显示占比。"
        for total in [UInt64?.none, UInt64(0)] {
            let copy = MemoryDetailPresentation.field(page: .memory, part: 12_345, total: total)
            XCTAssertEqual(copy.title, "驻留内存")
            XCTAssertEqual(copy.caption, "占物理内存")
            XCTAssertEqual(copy.help, help)
        }
    }

    func testNonMemoryPagesKeepMemoryTitleAndTodaysCaption() {
        let pages: [DashboardPage] = [.cpu, .disk, .network, .gpu]
        let bands = shareBands() + [(UInt64(0), 16 * gib)]
        for page in pages {
            for (part, total) in bands {
                let copy = MemoryDetailPresentation.field(page: page, part: part, total: total)
                XCTAssertEqual(copy.title, "内存", page.rawValue)
                XCTAssertEqual(
                    copy.caption,
                    "占 \(ByteFormat.gibWhole(total)) 的 \(ByteFormat.share(part: part, total: total))"
                )
                XCTAssertNil(copy.help)
            }
            for total in [UInt64?.none, UInt64(0)] {
                let copy = MemoryDetailPresentation.field(page: page, part: 12_345, total: total)
                XCTAssertEqual(copy.title, "内存", page.rawValue)
                XCTAssertEqual(copy.caption, "占物理内存")
                XCTAssertNil(copy.help)
                XCTAssertFalse(copy.caption.contains("%"))
            }
        }
        let sixteen = MemoryDetailPresentation.field(page: .cpu, part: 8 * gib, total: 16 * gib)
        XCTAssertEqual(ByteFormat.gibWhole(16 * gib), "16 GB")
        XCTAssertEqual(ByteFormat.share(part: 8 * gib, total: 16 * gib), "50%")
        XCTAssertEqual(sixteen.caption, "占 16 GB 的 50%")
    }

    func testRisingDetailCaptionAndBasis() {
        XCTAssertEqual(MemoryGrowthCopy.rising, "近期驻留内存上涨")
        XCTAssertEqual(MemoryGrowthCopy.basis, "当前进程近期趋势 · 基于现有驻留采样序列")
        XCTAssertEqual(MemoryGrowthCopy.basis(for: .rising), MemoryGrowthCopy.basis)
        XCTAssertFalse(MemoryGrowthCopy.rising.contains("分钟"))
        XCTAssertFalse(MemoryGrowthCopy.basis.contains("分钟"))
        XCTAssertFalse(MemoryGrowthCopy.rising.contains("每点都在涨"))
        XCTAssertFalse(MemoryGrowthCopy.basis.contains("每点都在涨"))

        let slot = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 42,
            detailSeries: series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        )
        XCTAssertEqual(slot?.title, "内存趋势")
        XCTAssertEqual(slot?.caption, "近期驻留内存上涨")
        XCTAssertEqual(slot?.basis, "当前进程近期趋势 · 基于现有驻留采样序列")
        XCTAssertNotEqual(slot?.caption, MemoryGrowthListCopy.title)
        XCTAssertNotEqual(slot?.caption, MemoryGrowthListCopy.help)
    }

    func testInsufficientKeepsTheOldCaptionAndHasNoBasis() {
        XCTAssertEqual(MemoryGrowthCopy.insufficient, "样本不足，暂不判断")
        XCTAssertNil(MemoryGrowthCopy.basis(for: .insufficient))
        let short = series(count: 79, step: 8_388_608)
        XCTAssertEqual(short.count, 79)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(short), .insufficient)
        let slot = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 7, detailSeries: short)
        XCTAssertEqual(slot?.caption, "样本不足，暂不判断")
        XCTAssertNil(slot?.basis)
        let cleared = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 7, detailSeries: nil)
        XCTAssertEqual(cleared?.caption, "样本不足，暂不判断")
        XCTAssertNil(cleared?.basis)
    }

    func testNoneDrawsNoSlotAndNoStableSentence() {
        let flat = series(count: 90, step: 0)
        XCTAssertEqual(flat.count, 90)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(flat), .none)
        XCTAssertNil(MemoryGrowthSidebar.slot(page: .memory, selectedPid: 4, detailSeries: flat))
        XCTAssertNil(MemoryGrowthCopy.caption(for: .none))
        XCTAssertNil(MemoryGrowthCopy.basis(for: .none))
        let blob = [
            MemoryGrowthCopy.title,
            MemoryGrowthCopy.rising,
            MemoryGrowthCopy.insufficient,
            MemoryGrowthCopy.basis,
        ].joined(separator: "\n")
        XCTAssertFalse(blob.contains("稳定"))
        XCTAssertFalse(blob.contains("正常"))
    }

    func testEightyPointBoundariesStayOnEvaluate() {
        let climb = series(count: 80, step: 1_048_576)
        XCTAssertEqual(climb.count, 80)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(climb), .rising)
        XCTAssertEqual(MemoryGrowthSignal.minSamples, 80)
        XCTAssertEqual(MemoryGrowthSignal.deltaThreshold, 8 * 1_024 * 1_024)
        XCTAssertEqual(MemoryGrowthSignal.riseFloor, 0.6)

        let exact = line(count: 80, net: MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(exact.last!.value - exact.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(exact), .none)

        let justOver = line(count: 80, net: MemoryGrowthSignal.deltaThreshold + 1)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(justOver), .rising)

        let almost = series(count: 79, step: 8_388_608)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(almost), .insufficient)
    }

    func testListBadgeCopyAndIndependentRingStayPut() {
        XCTAssertEqual(MemoryGrowthListCopy.title, "上涨")
        XCTAssertEqual(MemoryGrowthListCopy.help, "近期内存持续上涨")
        XCTAssertNotEqual(MemoryGrowthListCopy.title, "近期驻留内存上涨")
        XCTAssertNotEqual(MemoryGrowthListCopy.help, "近期驻留内存上涨")
        XCTAssertNotEqual(MemoryGrowthListCopy.title, MemoryGrowthCopy.rising)

        let rising = series(count: 80, step: 1_048_576)
        let badge = MemoryGrowthList.badge(page: .memory, rowPid: 3, seriesByPid: [3: rising])
        XCTAssertEqual(badge, MemoryGrowthListBadge(title: "上涨", help: "近期内存持续上涨"))
        XCTAssertEqual(
            MemoryGrowthSidebar.slot(page: .memory, selectedPid: 9, detailSeries: rising)?.caption,
            MemoryGrowthCopy.rising
        )
        XCTAssertNil(MemoryGrowthList.badge(page: .memory, rowPid: 9, seriesByPid: [3: rising]))
        XCTAssertNil(MemoryGrowthList.badge(page: .cpu, rowPid: 3, seriesByPid: [3: rising]))
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 3,
                seriesByPid: [3: series(count: 79, step: 8_388_608)]
            )
        )
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 3,
                seriesByPid: [3: series(count: 90, step: 0)]
            )
        )
    }

    func testNewDetailCopyOmitsBannedWords() {
        var lines: [String] = []
        for page in DashboardPage.allCases {
            for total in [UInt64?.none, UInt64(0), 16 * gib] {
                let copy = MemoryDetailPresentation.field(page: page, part: 42, total: total)
                lines.append(copy.title)
                lines.append(copy.caption)
                lines.append(copy.help ?? "")
            }
        }
        lines.append(contentsOf: [
            MemoryGrowthCopy.title,
            MemoryGrowthCopy.rising,
            MemoryGrowthCopy.insufficient,
            MemoryGrowthCopy.basis,
            MemoryGrowthCopy.basis(for: .rising) ?? "",
            MemoryGrowthListCopy.title,
            MemoryGrowthListCopy.help,
        ])
        let blob = lines.joined(separator: "\n")
        let banned = [
            "泄漏", "泄露", "leak", "危险", "异常", "独占", "可释放",
            "活动监视器", "真实占用", "footprint", "分钟", "稳定", "正常", "每点都在涨",
        ]
        for word in banned {
            XCTAssertFalse(blob.localizedCaseInsensitiveContains(word), word)
        }
    }

    func testDisclosureTextIsExactAndAllowsOnlyItsNegation() {
        XCTAssertEqual(MemoryDetailSamplingWindow.summary, "采样窗口与判断依据")
        XCTAssertEqual(
            MemoryDetailSamplingWindow.body,
            "使用当前选中进程已有的采样序列，最多90点；曲线从有样本开始，无需收满。至少80点才判断上涨：首尾净增超过8 MiB，且至少60%的相邻采样间隔上涨；中间可以有下降。仅表示近期窗口，不判断异常或泄漏。"
        )
        XCTAssertFalse(MemoryDetailSamplingWindow.summary.contains("分钟"))
        XCTAssertFalse(MemoryDetailSamplingWindow.body.contains("分钟"))
        XCTAssertFalse(MemoryDetailSamplingWindow.body.contains("稳定"))
        XCTAssertFalse(MemoryDetailSamplingWindow.body.contains("正常"))
        XCTAssertFalse(MemoryDetailSamplingWindow.body.contains("每点都在涨"))
        XCTAssertTrue(MemoryDetailSamplingWindow.body.contains("不判断异常或泄漏"))
    }

    private func shareBands() -> [(UInt64, UInt64)] {
        [
            (1, 10_000),
            (999, 1_000_000),
            (1, 1_000),
            (1, 100),
            (25, 1_000),
            (5, 100),
            (9, 100),
            (99, 1_000),
            (10, 100),
            (50, 100),
            (100, 100),
        ]
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        let baseline = 200_000_000.0
        return line(values: (0..<count).map { baseline + Double($0) * step })
    }

    private func line(count: Int, net: Double) -> [ChartSample] {
        let baseline = 200_000_000.0
        let lastIndex = count - 1
        let values = (0..<count).map { index -> Double in
            if index == lastIndex { return baseline + net }
            return baseline + net * Double(index) / Double(lastIndex)
        }
        return line(values: values)
    }

    private func line(values: [Double]) -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return values.enumerated().map { index, value in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: value
            )
        }
    }
}
