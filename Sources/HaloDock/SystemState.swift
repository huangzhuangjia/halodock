import AppKit
import Combine
import IOKit.ps
import IOKit.pwr_mgt
import Network

@MainActor
final class SystemState: ObservableObject {
    @Published private(set) var battery = "读取中…"
    @Published private(set) var memory = "读取中…"
    @Published private(set) var network = "检测中…"
    @Published private(set) var storage = "读取中…"
    @Published private(set) var memoryFraction: Double?
    @Published private(set) var storageFreeFraction: Double?
    let history: ClipboardHistory
    @Published private(set) var wakeEndsAt: Date?
    @Published private(set) var wakeRemaining = ""
    @Published private(set) var keepAwake = false
    @Published var actionError: String?
    private let defaults: UserDefaults
    private var assertion: IOPMAssertionID = 0
    private let monitor = NWPathMonitor()
    private let hostPort = mach_host_self()
    private var polling: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.history = defaults === UserDefaults.standard && pasteboard === NSPasteboard.general ? .shared : ClipboardHistory(board: pasteboard, defaults: defaults)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.network = connected ? "已连接" : "未连接"
            }
        }
        monitor.start(queue: DispatchQueue(label: "HaloDock.network"))
        refresh()
        if defaults.bool(forKey: "keepAwake") {
            let end = defaults.object(forKey: "wakeEndsAt") as? Date
            if let end, end <= Date() { defaults.set(false, forKey: "keepAwake"); defaults.removeObject(forKey: "wakeEndsAt") }
            else { setKeepAwake(true); wakeEndsAt = end; updateWakeCountdown() }
        }
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                self.history.capture()
                self.updateWakeCountdown()
            }
        }
    }

    func refresh() {
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            battery = "无电池"
            for source in sources {
                guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = data[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                battery = "\(Int((Double(current) / Double(maximum) * 100).rounded()))%"
            }
        } else { battery = "暂不可用" }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pages = UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
            let reclaimable = UInt64(stats.purgeable_count) + UInt64(stats.external_page_count)
            let used = (pages > reclaimable ? pages - reclaimable : 0) * UInt64(getpagesize())
            memoryFraction = min(1, max(0, Double(used) / Double(ProcessInfo.processInfo.physicalMemory)))
            memory = "\(Int(min(100, Double(used) / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded()))%"
        } else { memory = "暂不可用"; memoryFraction = nil }

        if let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
           let bytes = values.volumeAvailableCapacity {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .decimal
            formatter.allowedUnits = [.useGB, .useTB]
            storageFreeFraction = values.volumeTotalCapacity.flatMap { $0 > 0 ? min(1, max(0, Double(bytes) / Double($0))) : nil }
            storage = formatter.string(fromByteCount: Int64(bytes))
        } else { storage = "暂不可用"; storageFreeFraction = nil }
    }

    func startWake(minutes: Int) {
        setKeepAwake(true)
        guard keepAwake else { return }
        wakeEndsAt = minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil
        defaults.set(wakeEndsAt, forKey: "wakeEndsAt")
        updateWakeCountdown()
    }

    func updateWakeCountdown(now: Date = Date()) {
        guard keepAwake, let end = wakeEndsAt else { wakeRemaining = ""; return }
        guard end > now else { setKeepAwake(false); return }
        let seconds = Int(ceil(end.timeIntervalSince(now)))
        wakeRemaining = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func setKeepAwake(_ enabled: Bool) {
        if enabled && !keepAwake {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "HaloDock 保持唤醒" as CFString, &assertion)
            guard result == kIOReturnSuccess else { actionError = "无法开启保持唤醒"; return }
            keepAwake = true
            defaults.set(true, forKey: "keepAwake")
        } else if !enabled && keepAwake {
            guard IOPMAssertionRelease(assertion) == kIOReturnSuccess else { actionError = "无法关闭保持唤醒"; return }
            keepAwake = false
            defaults.set(false, forKey: "keepAwake")
            wakeEndsAt = nil
            wakeRemaining = ""
            defaults.removeObject(forKey: "wakeEndsAt")
        }
    }

    func shutdown() {
        polling?.cancel()
        monitor.cancel()
        if keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        }
    }

}
