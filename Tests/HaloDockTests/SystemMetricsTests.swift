import Foundation
import Testing
@testable import HaloDock

@Test func cpuUsageUsesIntervalDeltasAndHandlesCounterWrap() {
    let previous = CPUSample(user: 100, system: 50, idle: 700, nice: 10)
    let next = CPUSample(user: 130, system: 60, idle: 760, nice: 10)
    #expect(next.usage(since: previous) == 0.4)
    #expect(previous.usage(since: previous) == nil)
    let wrapped = CPUSample(user: 10, system: 0, idle: 20, nice: 0)
    let beforeWrap = CPUSample(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
    #expect(wrapped.usage(since: beforeWrap) == 0.5)
    #expect(CPUSample(user: 1, system: 0, idle: 1, nice: 0).usage(since: previous) == nil)
}

@Test func memoryPressureUsesSystemLevelsInsteadOfUsagePercentage() {
    #expect(MemoryPressureLevel(rawValue: 1)?.title == "正常")
    #expect(MemoryPressureLevel(rawValue: 2)?.title == "偏高")
    #expect(MemoryPressureLevel(rawValue: 4)?.title == "紧张")
    #expect(MemoryPressureLevel(rawValue: 0) == nil)
    #expect(MemoryPressureLevel(rawValue: 99) == nil)
}

@Test @MainActor func practicalStatusDefaultsAreAppliedOnceAndOptionalChoicesPersist() throws {
    let name = "HaloDock.StatusDefaults.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let panel = ScenePanel(defaults: defaults)
    #expect(panel.current.widgets.filter(\.visible).map(\.widget) == [.cpu, .pressure, .storage, .wake])
    panel.setVisible(.battery, true); panel.setVisible(.cpu, false)
    let restored = ScenePanel(defaults: defaults)
    #expect(restored.current.widgets.first { $0.widget == .battery }?.visible == true)
    #expect(restored.current.widgets.first { $0.widget == .cpu }?.visible == false)
}
