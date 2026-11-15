import Foundation

extension AlertMetric {
    /// Filled in when the user picks this metric. Nil leaves the typed threshold alone.
    var defaultThreshold: Double? {
        switch self {
        case .gpuUtilization:
            return 85
        case .cpu, .memoryFootprint, .memoryPressure, .chipTemperature, .diskFree:
            return nil
        }
    }
}

enum AlertMetricForm {
    /// Choosing GPU utilization replaces the threshold with 85. Other metrics keep `current`.
    static func thresholdText(afterChoosing metric: AlertMetric, current: String) -> String {
        guard let threshold = metric.defaultThreshold else { return current }
        return metric.displayThreshold(threshold)
    }
}

enum AlertGPUReading {
    /// Utilization of the accelerator the GPU page would select. Nil is missing, not zero.
    static func percent(from nodes: [GPUAcceleratorNode]?) -> Double? {
        guard let nodes else { return nil }
        return GPUPageProjection.apply(
            nodes: nodes,
            frame: .succeeded,
            sampledAt: nil,
            current: .initial,
            transition: .stayed
        ).utilizationPercent
    }
}

extension CustomAlertRule {
    var notificationBody: String {
        switch metric {
        case .cpu:
            return "\(object.phrase) CPU 已持续超过 \(AlertThresholdText.percent(threshold))"
        case .memoryFootprint:
            let bytes = UInt64(max(threshold, 0))
            return "\(object.phrase)内存占用已持续超过 \(ByteFormat.memory(bytes))"
        case .memoryPressure:
            return "\(object.phrase)内存压力已持续偏高"
        case .chipTemperature:
            return "\(object.phrase)芯片温度已持续超过 \(AlertThresholdText.degrees(threshold))"
        case .diskFree:
            let bytes = UInt64(max(threshold, 0))
            return "\(object.phrase)磁盘剩余已持续低于 \(ByteFormat.memory(bytes))"
        case .gpuUtilization:
            return "\(object.phrase) GPU 使用率已持续超过 \(AlertThresholdText.percent(threshold))"
        }
    }

    func gpuMeasurement(_ frame: AlertFrame) -> AlertMeasurement {
        AlertMeasurement(
            breached: AlertComparison.breached(
                metric: .gpuUtilization,
                threshold: threshold,
                value: frame.gpuUtilizationPercent
            ),
            pid: nil
        )
    }
}

extension AlertFrame {
    /// Menu-bar code must not name the chip-temperature type. The caller passes an already gated Celsius.
    /// A present node list is the selected accelerator. Nil nodes keep the explicit percent.
    static func sampled(
        systemCpuPercent: Double?,
        usedMemoryBytes: UInt64?,
        memoryPressure: PressureLevel?,
        chipCelsius: Double?,
        diskFreeBytes: UInt64?,
        gpuNodes: [GPUAcceleratorNode]? = nil,
        gpuUtilizationPercent: Double? = nil,
        processes: [AlertProcessSample]
    ) -> AlertFrame {
        let percent: Double?
        if let gpuNodes {
            percent = AlertGPUReading.percent(from: gpuNodes)
        } else {
            percent = gpuUtilizationPercent
        }
        return AlertFrame(
            systemCpuPercent: systemCpuPercent,
            usedMemoryBytes: usedMemoryBytes,
            memoryPressure: memoryPressure,
            chipTemperatureCelsius: chipCelsius,
            diskFreeBytes: diskFreeBytes,
            gpuUtilizationPercent: percent,
            processes: processes
        )
    }
}
