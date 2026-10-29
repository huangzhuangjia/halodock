import Foundation
import Darwin

enum MemoryPressureLevel: Int {
    case normal = 1, warning = 2, critical = 4
    var title: String { switch self { case .normal: "正常"; case .warning: "偏高"; case .critical: "紧张" } }
    static func read() -> MemoryPressureLevel? {
        // XNU's sysctl handler exports dispatch pressure levels (1/2/4),
        // rather than the kernel's internal enum. Unknown/read failure stays unavailable.
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return nil }
        return .init(rawValue: Int(value))
    }
}

struct CPUSample {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
    func usage(since previous: CPUSample) -> Double? {
        let deltas = [user &- previous.user, system &- previous.system, idle &- previous.idle, nice &- previous.nice].map(UInt64.init)
        let total = deltas.reduce(0, +)
        guard total > 0, deltas.allSatisfy({ $0 < UInt64(UInt32.max) / 2 }) else { return nil }
        return min(1, max(0, Double(total - deltas[2]) / Double(total)))
    }
    static func read(host: host_t) -> CPUSample? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUSample(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }
}
