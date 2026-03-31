import Foundation

enum PerformanceMonitor {
    private static let environment = ProcessInfo.processInfo.environment
    private static let environmentEnabled = environment["LITRIX_PERF_LOG"] == "1"
    private static let environmentThresholdMS: Double? = {
        guard let raw = ProcessInfo.processInfo.environment["LITRIX_PERF_THRESHOLD_MS"],
              let value = Double(raw),
              value >= 0 else {
            return nil
        }
        return value
    }()
    private static let userDefaultsEnabledKey = "litrix.performance_logs_enabled"

    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static var isEnabled: Bool {
        environmentEnabled || UserDefaults.standard.bool(forKey: userDefaultsEnabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsEnabledKey)
    }

    static func logElapsed(
        _ name: String,
        from startNanoseconds: UInt64,
        thresholdMS: Double = 16,
        metadata: () -> String = { "" }
    ) {
        guard isEnabled else { return }

        let endNanoseconds = DispatchTime.now().uptimeNanoseconds
        let elapsedNanoseconds = endNanoseconds >= startNanoseconds
            ? endNanoseconds - startNanoseconds
            : 0
        let elapsedMS = Double(elapsedNanoseconds) / 1_000_000
        let resolvedThreshold = environmentThresholdMS ?? thresholdMS
        guard elapsedMS >= resolvedThreshold else { return }

        let details = metadata()
        if details.isEmpty {
            print("[Perf] \(name): \(formattedMilliseconds(elapsedMS))ms")
        } else {
            print("[Perf] \(name): \(formattedMilliseconds(elapsedMS))ms | \(details)")
        }
    }

    private static func formattedMilliseconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension SidebarSelection {
    var performanceLabel: String {
        switch self {
        case .library(let library):
            return "library.\(library.rawValue)"
        case .collection(let name):
            return "collection.\(name)"
        case .tag(let name):
            return "tag.\(name)"
        }
    }
}
