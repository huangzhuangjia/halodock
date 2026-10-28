import AppKit
import Carbon
import Combine
import SwiftUI

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    // Require Command or Control or Option, with no unmodified/Shift-only global keys.
    var valid: Bool { keyCode < 128 && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 && modifiers & ~UInt32(cmdKey | controlKey | optionKey | shiftKey) == 0 && ![36, 48, 53, 123, 124, 125, 126].contains(keyCode) }
    var display: String {
        let prefix = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")].filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        let keys: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"空格",50:"`",65:"小数点",67:"×",69:"+",75:"÷",78:"−",81:"=",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9"]
        return prefix + (keys[keyCode] ?? "键 \(keyCode)")
    }
    static func from(_ event: NSEvent) -> Shortcut {
        var flags: UInt32 = 0
        for (flag, carbon): (NSEvent.ModifierFlags, Int) in [(.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { flags |= UInt32(carbon) }
        }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags)
    }
}

enum ShortcutAction: UInt32, CaseIterable, Identifiable {
    case panel = 1, screenshot, awake
    var id: UInt32 { rawValue }
    var title: String { switch self { case .panel: "打开菜单栏面板"; case .screenshot: "截取屏幕"; case .awake: "切换保持唤醒" } }
    var fallback: Shortcut {
        switch self {
        case .panel: Shortcut(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        case .screenshot: Shortcut(keyCode: 1, modifiers: UInt32(controlKey | optionKey))
        case .awake: Shortcut(keyCode: 0, modifiers: UInt32(controlKey | optionKey))
        }
    }
}

@MainActor
final class GlobalShortcuts: ObservableObject {
    static let shared = GlobalShortcuts()
    @Published private(set) var bindings: [ShortcutAction: Shortcut] = [:]
    @Published var message = "点击快捷键后按下新组合，Esc 取消；点击 × 可停用。"
    var onAction: ((ShortcutAction) -> Void)?
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var configured = false
    private let defaults: UserDefaults
    private let signature: OSType = 0x48414C4F

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in ShortcutAction.allCases {
            if let data = defaults.data(forKey: "shortcut.\(action.rawValue)"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data), saved.valid {
                bindings[action] = saved
            } else if !defaults.bool(forKey: "shortcut.disabled.\(action.rawValue)") { bindings[action] = action.fallback }
        }
    }
    func configure() {
        guard !configured else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x48414C4F, let action = ShortcutAction(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { message = "无法启用全局快捷键（\(status)）"; return }
        configured = true
        for action in ShortcutAction.allCases {
            if let shortcut = bindings[action], register(shortcut, for: action) != noErr { message = "\(action.title)快捷键被其他应用占用，请重新设置。" }
        }
    }
    private func register(_ shortcut: Shortcut, for action: ShortcutAction) -> OSStatus {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: signature, id: action.rawValue), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { references[action] = ref }
        return status
    }
    @discardableResult func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> Bool {
        if let shortcut {
            guard shortcut.valid else { message = "请使用含 ⌘、⌃ 或 ⌥ 的组合键。"; return false }
            guard !bindings.contains(where: { $0.key != action && $0.value == shortcut }) else { message = "该组合已用于其他操作。"; return false }
        }
        let previous = bindings[action]
        if let ref = references.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        if configured, let shortcut, register(shortcut, for: action) != noErr {
            if let previous { _ = register(previous, for: action) }
            message = "该快捷键被系统或其他应用占用，已保留原设置。"; return false
        }
        bindings[action] = shortcut
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: "shortcut.\(action.rawValue)")
        defaults.set(shortcut == nil, forKey: "shortcut.disabled.\(action.rawValue)")
        message = "已保存\(action.title)快捷键"
        return true
    }
    func pauseForRecording() {
        for ref in references.values { UnregisterEventHotKey(ref) }
        references.removeAll()
    }
    func resumeAfterRecording() {
        guard configured else { return }
        for action in ShortcutAction.allCases where references[action] == nil {
            if let binding = bindings[action], register(binding, for: action) != noErr { message = "\(action.title)快捷键被占用，请重新设置。" }
        }
    }
    func shutdown() {
        for ref in references.values { UnregisterEventHotKey(ref) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil; configured = false
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let value: Shortcut?
    let changed: (Shortcut) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcutTitle = value?.display ?? "未设置"
        button.changed = changed
        if !button.recording { button.title = button.shortcutTitle }
    }
}

@MainActor
final class RecorderButton: NSButton {
    var changed: ((Shortcut) -> Void)?
    var shortcutTitle = "未设置"
    private(set) var recording = false
    private var windowObservation: AnyCancellable?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self; action = #selector(beginRecording)
        setAccessibilityLabel("录制快捷键")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelRecording()
        windowObservation = NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.willCloseNotification))
            .sink { [weak self] notification in
                guard let self, let source = notification.object as? NSWindow, source === self.window else { return }
                self.cancelRecording()
            }
    }
    private func cancelRecording() {
        guard recording else { return }
        recording = false; title = shortcutTitle
        GlobalShortcuts.shared.resumeAfterRecording()
    }
    @objc private func beginRecording() { GlobalShortcuts.shared.pauseForRecording(); recording = true; title = "按下组合键…"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false; title = shortcutTitle
        if event.keyCode != 53 { changed?(Shortcut.from(event)) }
        GlobalShortcuts.shared.resumeAfterRecording()
    }
}
