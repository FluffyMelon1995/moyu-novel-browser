import Cocoa
import WebKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

// MARK: - 偏好设置

enum Prefs {
    static let d = UserDefaults.standard

    static func register() {
        d.register(defaults: [
            "lines": 1, "fontSize": 13, "textStyle": 1, "autoFlip": 0,
            "autoHide": true, "homeURL": "https://www.google.com",
            "hotZoneSize": 60, "hotZoneVisible": false, "sentenceBreak": true, "maxBoxWidth": 760,
            "pageTransition": 1, "transitionSpeed": 45,
            "autoBrowseClicks": false, "autoBrowseSpeed": 2, "rightClickBoss": true,
        ])
    }

    /// 换页动效：0 无，1 淡入淡出，2 上滑
    static var pageTransition: Int {
        get { d.integer(forKey: "pageTransition") }
        set { d.set(newValue, forKey: "pageTransition") }
    }
    /// 动效时长（百分之一秒）
    static var transitionSpeed: Int {
        get { max(10, d.integer(forKey: "transitionSpeed")) }
        set { d.set(newValue, forKey: "transitionSpeed") }
    }

    /// 地址栏最大宽度，0 = 不限
    static var maxBoxWidth: Int {
        get { d.integer(forKey: "maxBoxWidth") }
        set { d.set(newValue, forKey: "maxBoxWidth") }
    }

    /// 每页只在标点处结束，不把句子从中间截断
    static var sentenceBreak: Bool {
        get { d.bool(forKey: "sentenceBreak") }
        set { d.set(newValue, forKey: "sentenceBreak") }
    }

    static var lines: Int {
        get { min(6, max(1, d.integer(forKey: "lines"))) }
        set { d.set(newValue, forKey: "lines") }
    }
    static var fontSize: Int {
        get { min(24, max(9, d.integer(forKey: "fontSize"))) }
        set { d.set(newValue, forKey: "fontSize") }
    }
    /// 0 标准 1 柔和 2 很淡
    static var textStyle: Int {
        get { d.integer(forKey: "textStyle") }
        set { d.set(newValue, forKey: "textStyle") }
    }
    /// 自动翻页间隔（秒），0 = 关
    static var autoFlip: Int {
        get { d.integer(forKey: "autoFlip") }
        set { d.set(newValue, forKey: "autoFlip") }
    }
    /// 切到别的 App 时自动进入老板模式
    static var autoHide: Bool {
        get { d.bool(forKey: "autoHide") }
        set { d.set(newValue, forKey: "autoHide") }
    }
    static var homeURL: String {
        get { d.string(forKey: "homeURL") ?? "https://www.google.com" }
        set { d.set(newValue, forKey: "homeURL") }
    }
    static var lastURL: String? {
        get { d.string(forKey: "lastURL") }
        set { d.set(newValue, forKey: "lastURL") }
    }
    /// 自动浏览时会不会点击站内链接（默认只滚动，比较安全）
    static var autoBrowseClicks: Bool {
        get { d.bool(forKey: "autoBrowseClicks") }
        set { d.set(newValue, forKey: "autoBrowseClicks") }
    }
    /// 自动浏览速度：1 慢、2 适中、3 快
    static var autoBrowseSpeed: Int {
        get { d.integer(forKey: "autoBrowseSpeed") }
        set { d.set(newValue, forKey: "autoBrowseSpeed") }
    }
    /// 在网页上连点两下右键直接进入老板模式
    static var rightClickBoss: Bool {
        get { d.bool(forKey: "rightClickBoss") }
        set { d.set(newValue, forKey: "rightClickBoss") }
    }
    /// 上次打开的所有标签页，下次启动时恢复
    static var tabURLs: [String]? {
        get { d.stringArray(forKey: "tabURLs") }
        set { d.set(newValue, forKey: "tabURLs") }
    }
    static var selectedTab: Int {
        get { d.integer(forKey: "selectedTab") }
        set { d.set(newValue, forKey: "selectedTab") }
    }
    static var novelPath: String? {
        get { d.string(forKey: "novelPath") }
        set { d.set(newValue, forKey: "novelPath") }
    }
    static func offset(for path: String) -> Int {
        (d.dictionary(forKey: "offsets")?[path] as? Int) ?? 0
    }
    /// 断点续读：保存当前位置和“上一页”用的翻页记录，并立刻写盘
    static func saveProgress(_ offset: Int, history: [Int], for path: String) {
        var map = d.dictionary(forKey: "offsets") ?? [:]
        map[path] = offset
        d.set(map, forKey: "offsets")
        var hist = d.dictionary(forKey: "histories") ?? [:]
        hist[path] = Array(history.suffix(300))
        d.set(hist, forKey: "histories")
        d.synchronize()
    }
    static func history(for path: String) -> [Int] {
        (d.dictionary(forKey: "histories")?[path] as? [Int]) ?? []
    }

    /// 窗口左下/右下角的翻页热区边长，0 = 关
    static var hotZoneSize: Int {
        get { d.integer(forKey: "hotZoneSize") }
        set { d.set(newValue, forKey: "hotZoneSize") }
    }
    static var hotZoneVisible: Bool {
        get { d.bool(forKey: "hotZoneVisible") }
        set { d.set(newValue, forKey: "hotZoneVisible") }
    }
}

// MARK: - 小说

final class Novel {
    let path: String
    /// 去掉空行和缩进后的全文，段落之间用一个全角空格隔开
    let text: NSString
    let chapters: [(title: String, offset: Int)]

    private init(path: String, text: NSString, chapters: [(title: String, offset: Int)]) {
        self.path = path
        self.text = text
        self.chapters = chapters
    }

    static func load(path: String) throws -> Novel {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let raw = decode(data) else { throw CocoaError(.fileReadInapplicableStringEncoding) }

        let chapterRE = try! NSRegularExpression(pattern: "^第[0-9０-９零〇一二三四五六七八九十百千万两]+[章节回卷]")
        let out = NSMutableString(capacity: data.count)
        var chapters: [(title: String, offset: Int)] = []
        raw.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return }
            if out.length > 0 { out.append("　") }
            let len = (t as NSString).length
            if len < 60, chapterRE.firstMatch(in: t, range: NSRange(location: 0, length: len)) != nil {
                chapters.append((t, out.length))
            }
            out.append(t)
        }
        return Novel(path: path, text: out, chapters: chapters)
    }

    /// 依次尝试 UTF-8 / UTF-16 / GB18030 / Big5
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        for cf in [CFStringEncodings.GB_18030_2000, .big5_HKSCS_1999, .big5] {
            let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
            if let s = String(data: data, encoding: enc) { return s }
        }
        return nil
    }

    func chapterIndex(at offset: Int) -> Int? {
        var lo = 0, hi = chapters.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if chapters[mid].offset <= offset { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    static func chapterNumber(_ title: String) -> Int? {
        let digits = title.dropFirst().prefix { $0.isNumber && $0.isASCII }
        return Int(digits)
    }
}

// MARK: - 快捷键

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var mods: UInt   // NSEvent.ModifierFlags 里的 ⌘⌥⌃⇧
    var label: String

    static let modMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: Int, mods: NSEvent.ModifierFlags, label: String) {
        self.keyCode = keyCode
        self.mods = mods.intersection(Shortcut.modMask).rawValue
        self.label = label
    }

    init(event e: NSEvent) {
        let flags = e.modifierFlags.intersection(Shortcut.modMask)
        self.init(keyCode: Int(e.keyCode), mods: flags, label: Shortcut.describe(keyCode: Int(e.keyCode), flags: flags, event: e))
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: mods) }

    func matches(_ e: NSEvent) -> Bool {
        Int(e.keyCode) == keyCode && e.modifierFlags.intersection(Shortcut.modMask) == flags
    }

    func sameKeys(_ other: Shortcut) -> Bool { keyCode == other.keyCode && mods == other.mods }

    var carbonModifiers: Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    private static let keyNames: [Int: String] = [
        kVK_Escape: "Esc", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func describe(keyCode: Int, flags: NSEvent.ModifierFlags, event: NSEvent?) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let key = keyNames[keyCode] ?? event?.charactersIgnoringModifiers?.uppercased() ?? "#\(keyCode)"
        return s + key
    }
}

enum ShortcutAction: String, CaseIterable {
    case nextPage, prevPage, boss, globalBoss, autoBrowse

    var title: String {
        switch self {
        case .nextPage: return "下一页"
        case .prevPage: return "上一页"
        case .boss: return "老板键"
        case .globalBoss: return "全局老板键"
        case .autoBrowse: return "自动浏览开关"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .nextPage: return Shortcut(keyCode: kVK_ANSI_C, mods: .command, label: "⌘C")
        case .prevPage: return Shortcut(keyCode: kVK_ANSI_V, mods: .command, label: "⌘V")
        case .boss: return Shortcut(keyCode: kVK_Escape, mods: [], label: "Esc")
        case .globalBoss: return Shortcut(keyCode: kVK_ANSI_Grave, mods: .option, label: "⌥`")
        case .autoBrowse: return Shortcut(keyCode: kVK_ANSI_A, mods: [.command, .option], label: "⌥⌘A")
        }
    }

    private var key: String { "shortcut.\(rawValue)" }

    /// nil = 已清除（不用快捷键）
    var shortcut: Shortcut? {
        guard let data = Prefs.d.data(forKey: key) else { return defaultShortcut }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    func set(_ s: Shortcut?) {
        let data = s.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        Prefs.d.set(data, forKey: key)
    }

    func reset() { Prefs.d.removeObject(forKey: key) }

    var label: String { shortcut?.label ?? "无" }

    static let didChange = Notification.Name("ShortcutsDidChange")
}

// MARK: - 全局快捷键（Carbon，不需要辅助功能权限）

enum HotKey {
    static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?
    private static var installed = false

    static func register(_ shortcut: Shortcut?) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKey.handler?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        unregister()
        guard let s = shortcut else { return }
        let id = EventHotKeyID(signature: OSType(0x4E56_4C42), id: 1)
        RegisterEventHotKey(UInt32(s.keyCode), UInt32(s.carbonModifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    static func unregister() {
        if let r = ref { UnregisterEventHotKey(r) }
        ref = nil
    }
}

// MARK: - 快捷键设置窗口

final class ShortcutRecorder: NSButton {
    static var isRecording = false
    let shortcutAction: ShortcutAction
    var onRecorded: ((Shortcut) -> Void)?
    private var monitor: Any?

    init(action: ShortcutAction) {
        shortcutAction = action
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        self.action = #selector(toggleRecording)
        refresh()
        widthAnchor.constraint(equalToConstant: 170).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() { title = monitor == nil ? shortcutAction.label : "请按下新快捷键…" }

    @objc private func toggleRecording() {
        monitor == nil ? start() : stop()
    }

    private func start() {
        ShortcutRecorder.isRecording = true
        HotKey.unregister()   // 录制时先放开全局快捷键，不然按不进来
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            self.stop()
            self.onRecorded?(Shortcut(event: e))
            return nil
        }
        refresh()
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        ShortcutRecorder.isRecording = false
        HotKey.register(ShortcutAction.globalBoss.shortcut)
        refresh()
    }
}

final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    private var recorders: [ShortcutRecorder] = []
    private let status = NSTextField(labelWithString: "")

    init() {
        let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "快捷键设置"
        super.init(window: win)
        win.delegate = self

        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        for action in ShortcutAction.allCases {
            let rec = ShortcutRecorder(action: action)
            rec.onRecorded = { [weak self] s in self?.apply(s, to: action) }
            recorders.append(rec)
            let clear = NSButton(title: "清除", target: self, action: #selector(clearRow(_:)))
            let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetRow(_:)))
            clear.tag = recorders.count - 1
            reset.tag = recorders.count - 1
            grid.addRow(with: [NSTextField(labelWithString: action.title), rec, clear, reset])
        }
        grid.column(at: 0).xPlacement = .trailing

        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = 480
        let note = NSTextField(wrappingLabelWithString:
            "点击按钮后按下新的组合键。“全局老板键”在 App 处于后台时也能用，必须带 ⌘、⌥ 或 ⌃。不带修饰键的普通字母会影响在网页里打字。")
        note.textColor = .tertiaryLabelColor
        note.font = .systemFont(ofSize: 11)
        let resetAll = NSButton(title: "全部恢复默认", target: self, action: #selector(resetAll))

        let stack = NSStackView(views: [grid, status, note, resetAll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 480).isActive = true
        win.contentView = stack
        win.setContentSize(stack.fittingSize)
        win.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func apply(_ s: Shortcut, to action: ShortcutAction) {
        if action == .globalBoss, s.flags.intersection([.command, .option, .control]).isEmpty {
            return fail("全局老板键至少要带 ⌘、⌥ 或 ⌃，不然会影响所有 App 的打字。")
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && $0.shortcut.map(s.sameKeys) == true }) {
            return fail("\(s.label) 已经被「\(other.title)」占用了。")
        }
        action.set(s)
        changed("「\(action.title)」改成了 \(s.label)")
    }

    private func fail(_ msg: String) {
        NSSound.beep()
        status.textColor = .systemRed
        status.stringValue = msg
    }

    private func changed(_ msg: String) {
        status.textColor = .secondaryLabelColor
        status.stringValue = msg
        recorders.forEach { $0.refresh() }
        HotKey.register(ShortcutAction.globalBoss.shortcut)
        NotificationCenter.default.post(name: ShortcutAction.didChange, object: nil)
    }

    @objc private func clearRow(_ sender: NSButton) {
        let a = recorders[sender.tag].shortcutAction
        a.set(nil)
        changed("已清除「\(a.title)」的快捷键")
    }

    @objc private func resetRow(_ sender: NSButton) {
        let a = recorders[sender.tag].shortcutAction
        if let other = ShortcutAction.allCases.first(where: { $0 != a && $0.shortcut.map(a.defaultShortcut.sameKeys) == true }) {
            return fail("默认的 \(a.defaultShortcut.label) 已经被「\(other.title)」占用了，请先改掉那一项。")
        }
        a.reset()
        changed("「\(a.title)」恢复为 \(a.label)")
    }

    @objc private func resetAll() {
        ShortcutAction.allCases.forEach { $0.reset() }
        changed("所有快捷键都恢复默认了")
    }

    func windowWillClose(_ notification: Notification) {
        recorders.forEach { $0.stop() }
    }
}

// MARK: - 视图

final class RootView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class TopBar: NSVisualEffectView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// 窗口角落的隐形翻页按钮；老板模式下不拦截点击，网页照常可点
final class HotZone: NSView {
    var onClick: (() -> Void)?
    var isActive = true
    var showsOutline = false { didSet { needsDisplay = true } }
    var symbol = "chevron.right"
    weak var scrollTarget: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? { isActive ? super.hitTest(point) : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func scrollWheel(with event: NSEvent) { scrollTarget?.scrollWheel(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        guard showsOutline else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: min(28, bounds.width / 3), weight: .semibold)
                .applying(.init(paletteColors: [.controlAccentColor]))) else { return }
        let s = img.size
        img.draw(in: NSRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2,
                            width: s.width, height: s.height))
    }
}

/// 地址栏：平时显示小说，老板模式显示网址，点击后变成网址输入框
final class AddressBox: NSView, NSTextFieldDelegate {
    enum Style { case novel, url, hint }

    var lines = 1
    var font = NSFont.systemFont(ofSize: 13)
    var novelColor = NSColor.secondaryLabelColor
    var isBoss = false
    var urlString = ""
    var progress: Double = 0 { didSet { needsLayout = true; progressBar.isHidden = progress <= 0 || progress >= 1 } }

    var onSubmit: ((String) -> Void)?
    var onPage: ((Int) -> Void)?
    var onEditingChanged: (() -> Void)?
    var onReload: (() -> Void)?

    private(set) var isEditing = false

    let icon = NSImageView()
    let reloadButton = NSButton()
    let field = NSTextField()
    private let textView: NSTextView
    private let progressBar = NSView()

    // 用于计算一页能放多少字（和 textView 用同一套 TextKit 1 排版）
    private let mStorage = NSTextStorage()
    private let mLayout = NSLayoutManager()
    private let mContainer = NSTextContainer()

    private var scrollAccum: CGFloat = 0
    private var scrollFired = false

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = NSTextView(frame: .zero, textContainer: container)
        super.init(frame: frame)

        mStorage.addLayoutManager(mLayout)
        mContainer.lineFragmentPadding = 0
        mLayout.addTextContainer(mContainer)

        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.wantsLayer = true
        textView.layer?.masksToBounds = true
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        addSubview(textView)

        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)

        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "重新载入")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        reloadButton.isBordered = false
        reloadButton.contentTintColor = .secondaryLabelColor
        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked)
        addSubview(reloadButton)

        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.placeholderString = "Search or enter website name"
        field.delegate = self
        field.isHidden = true
        addSubview(field)

        progressBar.wantsLayer = true
        progressBar.isHidden = true
        addSubview(progressBar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.09)
                                           : NSColor.black.withAlphaComponent(0.055)).cgColor
            progressBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }

    var lineHeight: CGFloat { ceil(mLayout.defaultLineHeight(for: font)) }
    var displayLines: Int { (isBoss || isEditing) ? 1 : lines }
    var textWidth: CGFloat { max(20, bounds.width - 28 - 30) }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 10, y: (h - 14) / 2, width: 14, height: 14)
        reloadButton.frame = NSRect(x: bounds.width - 26, y: (h - 20) / 2, width: 20, height: 20)
        let th = CGFloat(displayLines) * lineHeight
        textView.frame = NSRect(x: 28, y: floor((h - th) / 2), width: textWidth, height: th)
        field.frame = NSRect(x: 28, y: floor((h - 20) / 2), width: textWidth, height: 20)
        progressBar.frame = NSRect(x: 0, y: h - 2.5, width: bounds.width * CGFloat(progress), height: 2.5)
    }

    private func attributes(_ style: Style) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        switch style {
        case .novel:
            ps.alignment = .natural
            ps.lineBreakMode = .byWordWrapping
            return [.font: font, .foregroundColor: novelColor, .paragraphStyle: ps]
        case .url, .hint:
            ps.alignment = .center
            ps.lineBreakMode = .byTruncatingTail
            return [.font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: style == .url ? NSColor.labelColor : NSColor.placeholderTextColor,
                    .paragraphStyle: ps]
        }
    }

    /// direction：0 不加动效，1 下一页，-1 上一页
    func display(_ text: String, style: Style, direction: Int = 0) {
        if direction != 0, Prefs.pageTransition != 0, let layer = textView.layer {
            let t = CATransition()
            t.duration = Double(Prefs.transitionSpeed) / 100
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if Prefs.pageTransition == 2 {
                // 新文字从下方推上来，像滚动一样
                t.type = .push
                t.subtype = direction > 0 ? .fromBottom : .fromTop
            } else {
                t.type = .fade
            }
            layer.add(t, forKey: "page")
        }
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes(style)))
    }

    /// 从 from 开始，正好放满 lines 行的字符数
    func fitLength(_ text: NSString, from: Int) -> Int {
        let remain = text.length - from
        guard remain > 0 else { return 0 }
        let chunk = text.substring(with: NSRange(location: from, length: min(remain, lines * 600)))
        mStorage.setAttributedString(NSAttributedString(string: chunk, attributes: attributes(.novel)))
        mContainer.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        let all = mLayout.glyphRange(for: mContainer)
        var count = 0, end = 0
        mLayout.enumerateLineFragments(forGlyphRange: all) { _, _, _, range, stop in
            count += 1
            end = NSMaxRange(range)
            if count >= self.lines { stop.pointee = true }
        }
        let chars = mLayout.characterRange(forGlyphRange: NSRange(location: 0, length: end), actualGlyphRange: nil).length
        return max(1, chars)
    }

    // MARK: 点击 → 输入网址

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isEditing { return super.hitTest(point) }
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        return reloadButton.frame.contains(p) ? reloadButton : self
    }

    override func mouseDown(with event: NSEvent) { beginEditing() }

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        textView.isHidden = true
        field.isHidden = false
        field.stringValue = urlString
        onEditingChanged?()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        field.isHidden = true
        textView.isHidden = false
        onEditingChanged?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let s = field.stringValue
            endEditing()
            onSubmit?(s)
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { endEditing() }

    @objc private func reloadClicked() { onReload?() }

    // MARK: 在地址栏上滚动 = 翻页

    override func scrollWheel(with e: NSEvent) {
        guard !isEditing, !isBoss else { return super.scrollWheel(with: e) }
        if !e.hasPreciseScrollingDeltas {
            if e.scrollingDeltaY < 0 { onPage?(1) } else if e.scrollingDeltaY > 0 { onPage?(-1) }
            return
        }
        if e.phase == .began { scrollAccum = 0; scrollFired = false }
        guard e.phase == .changed, !scrollFired else { return }
        scrollAccum += e.scrollingDeltaY
        if abs(scrollAccum) > 24 {
            scrollFired = true
            onPage?(scrollAccum < 0 ? 1 : -1)
        }
    }
}

// MARK: - 浏览器窗口

// MARK: - 自动浏览（假光标 + 自动滚动 + 点击站内链接）

/// 画在窗口最上层的假鼠标指针，不拦截任何点击
final class FakeCursor: NSImageView {
    private(set) var isHand = false

    init() {
        super.init(frame: .zero)
        imageScaling = .scaleNone
        setHand(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setHand(_ hand: Bool) {
        isHand = hand
        let c: NSCursor = hand ? .pointingHand : .arrow
        image = c.image
        setFrameSize(c.image.size)
    }

    /// 指针尖端所在的位置（父视图是翻转坐标）
    var tip: NSPoint {
        let hs = (isHand ? NSCursor.pointingHand : NSCursor.arrow).hotSpot
        return NSPoint(x: frame.minX + hs.x, y: frame.minY + hs.y)
    }

    func origin(forTip p: NSPoint) -> NSPoint {
        let hs = (isHand ? NSCursor.pointingHand : NSCursor.arrow).hotSpot
        return NSPoint(x: p.x - hs.x, y: p.y - hs.y)
    }
}

final class AutoBrowser {
    let cursor = FakeCursor()
    var webView: () -> WKWebView = { fatalError() }
    /// 后退按钮中心（root 坐标），走得太远时假光标会去点它
    var backButtonCenter: () -> NSPoint = { .zero }
    var goBack: () -> Void = {}

    private(set) var isRunning = false
    private var generation = 0
    private var hops = 0
    private var actionsSinceClick = 0
    private var nextClickAfter = 5
    /// 你在用鼠标时，假光标让开到这个时间点；之后从你的指针位置接回来
    private var takeoverUntil = Date.distantPast
    private var quietUntil = Date.distantPast
    private var lastMouse: NSPoint?
    private var moveAnchor: (point: NSPoint, time: Date)?
    /// 真鼠标现在的位置（root 坐标），不在网页上时为 nil
    var mouseLocation: () -> NSPoint? = { nil }
    /// 真鼠标是不是正停在这个窗口的网页上（没被别的窗口挡住，App 也在前台）
    var pointerOverWebView: () -> Bool = { false }
    private var realCursorHidden = false
    private var cursorTimer: Timer?

    private var speed: Double { [1.7, 1.0, 0.6][min(2, max(0, Prefs.autoBrowseSpeed - 1))] }
    private var isTakenOver: Bool { Date() < takeoverUntil }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        hops = 0
        actionsSinceClick = 0
        takeoverUntil = .distantPast
        showCursor(at: mouseLocation() ?? randomPoint())
        // 真指针一直藏着（不是“动一下就出现”的那种），只有你接管、或者指针离开网页时才显示
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateRealCursor() }
        updateRealCursor()
        step()   // 一开启就马上动起来
    }

    func stop() {
        isRunning = false
        generation += 1
        cursor.isHidden = true
        cursorTimer?.invalidate()
        cursorTimer = nil
        setRealCursorHidden(false)
    }

    private func updateRealCursor() {
        setRealCursorHidden(isRunning && !isTakenOver && NSApp.isActive && pointerOverWebView())
    }

    /// NSCursor.hide / unhide 要成对调用，这里记着状态，保证不会多藏或多放
    private func setRealCursorHidden(_ hidden: Bool) {
        guard hidden != realCursorHidden else { return }
        realCursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
    }

    /// 翻页之后的一小会儿不理会鼠标（宏鼠标按侧键翻页时手难免会带动鼠标）
    func ignoreMouseBriefly() { quietUntil = Date().addingTimeInterval(1.5) }

    /// 真鼠标在网页上移动了：大幅移动就交给你，停手 1.2 秒后假光标从你的指针位置接回去
    func mouseMoved(to p: NSPoint) {
        guard isRunning else { return }
        let now = Date()
        defer { lastMouse = p }
        if isTakenOver {
            // 接管期间只要还在动（超过手抖的幅度），就继续由你控制
            if let last = lastMouse, hypot(p.x - last.x, p.y - last.y) > 4 { takeoverUntil = now.addingTimeInterval(1.2) }
            return
        }
        if now >= quietUntil {
            // 1 秒内累计移动超过 80 点才算接管，手抖、按键带动的小位移不算
            if let a = moveAnchor, now.timeIntervalSince(a.time) < 1 {
                if hypot(p.x - a.point.x, p.y - a.point.y) > 80 { moveAnchor = nil; return takeOver(for: 1.2) }
            } else {
                moveAnchor = (p, now)
            }
        }
    }

    /// 真鼠标在网页上点击或滚动了：多让你一会儿
    func mouseClickedOrScrolled() {
        guard isRunning, Date() >= quietUntil else { return }
        takeOver(for: 3)
    }

    private func takeOver(for seconds: Double) {
        let wasTaken = isTakenOver
        takeoverUntil = max(takeoverUntil, Date().addingTimeInterval(seconds))
        cursor.isHidden = true
        setRealCursorHidden(false)   // 交给你：真指针立刻出现
        guard !wasTaken else { return }
        generation += 1   // 取消假光标手上正在做的动作
        waitForHandBack()
    }

    /// 等你停手，再在你的指针位置把假光标接回来，真指针同时藏起来，看上去就是同一个光标
    private func waitForHandBack() {
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isRunning, self.generation == g else { return }
            if self.isTakenOver { return self.waitForHandBack() }
            self.showCursor(at: self.mouseLocation() ?? self.randomPoint())
            self.updateRealCursor()
            self.schedule(after: 1.5)
        }
    }

    private func schedule(after seconds: Double) {
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds * speed) { [weak self] in
            guard let self, self.isRunning, self.generation == g else { return }
            self.step()
        }
    }

    private func step() {
        let wv = webView()
        if isTakenOver { return }   // waitForHandBack 会接着来
        if wv.isLoading || wv.window == nil { return schedule(after: 1) }
        if cursor.isHidden { showCursor(at: mouseLocation() ?? randomPoint()) }
        actionsSinceClick += 1
        if Prefs.autoBrowseClicks, actionsSinceClick >= nextClickAfter {
            return clickStep()
        }
        scrollStep()
    }

    // MARK: 滚动

    private static let scrollJS = """
    (function(dy){
      function scroller(){
        let el = document.elementFromPoint(innerWidth / 2, innerHeight / 2);
        while (el && el !== document.body && el !== document.documentElement) {
          const s = getComputedStyle(el);
          if (/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 20) return el;
          el = el.parentElement;
        }
        return document.scrollingElement || document.documentElement;
      }
      const el = scroller();
      const max = el.scrollHeight - el.clientHeight;
      if (dy === 0) { el.scrollTo({top: 0, behavior: 'smooth'}); return 'top'; }
      if (dy > 0 && el.scrollTop >= max - 5) return 'bottom';
      el.scrollBy({top: dy, behavior: 'smooth'});
      return 'ok';
    })(%d)
    """

    private func scrollStep() {
        // 大多数时候往下看，偶尔往回翻一点，像在回头确认内容
        let dy = Double.random(in: 0..<1) < 0.15 ? -Int.random(in: 120...260) : Int.random(in: 180...480)
        let g = generation
        moveCursor(to: randomPoint()) { [weak self] in
            guard let self, self.isRunning, self.generation == g else { return }
            self.webView().evaluateJavaScript(String(format: Self.scrollJS, dy)) { result, _ in
                if result as? String == "bottom" {
                    if Prefs.autoBrowseClicks {
                        self.actionsSinceClick = self.nextClickAfter   // 看到底了，下一步就点链接
                    } else {
                        self.webView().evaluateJavaScript(String(format: Self.scrollJS, 0))
                    }
                }
                self.schedule(after: Double.random(in: 2.5...6))
            }
        }
    }

    // MARK: 点击链接

    /// 只挑当前网站内、看得见的普通链接；带“删除/退出/审批/支付”之类字样的一律跳过
    private static let linksJS = """
    (function(){
      const bad = /(logout|log-out|signout|sign-out|sign_out|logoff|delete|remove|destroy|unsubscribe|approve|reject|decline|accept|confirm|submit|send|cancel|archive|purchase|checkout|order|pay|cart|download|admin|settings|\\.(pdf|zip|exe|dmg|pkg|msi)(\\?|$)|删除|退出|注销|登出|审批|批准|同意|拒绝|提交|发送|取消|购买|支付|下单|下载|设置)/i;
      const out = [];
      for (const a of document.querySelectorAll('a[href]')) {
        if (a.hasAttribute('download') || a.target === '_blank') continue;
        let u; try { u = new URL(a.href, location.href); } catch (e) { continue; }
        if (!/^https?:$/.test(u.protocol) || u.host !== location.host) continue;
        if (u.href.split('#')[0] === location.href.split('#')[0]) continue;
        if (bad.test(u.href) || bad.test(a.textContent || '') || bad.test(a.getAttribute('aria-label') || '')) continue;
        const r = a.getBoundingClientRect();
        if (r.width < 8 || r.height < 8 || r.top < 30 || r.bottom > innerHeight - 20 || r.left < 0 || r.right > innerWidth) continue;
        const st = getComputedStyle(a);
        if (st.visibility === 'hidden' || st.display === 'none' || Number(st.opacity) === 0) continue;
        out.push([u.href, r.left + r.width / 2, r.top + r.height / 2]);
        if (out.length >= 150) break;
      }
      return out;
    })()
    """

    private func clickStep() {
        actionsSinceClick = 0
        nextClickAfter = Int.random(in: 4...8)
        let wv = webView()
        let g = generation
        // 离起点走得太远了，就用假光标去点“后退”
        if hops >= 3, wv.canGoBack {
            moveCursor(to: backButtonCenter()) { [weak self] in
                guard let self, self.isRunning, self.generation == g else { return }
                self.pressThen { self.goBack(); self.hops -= 1; self.schedule(after: 3) }
            }
            return
        }
        wv.evaluateJavaScript(Self.linksJS) { [weak self] result, _ in
            guard let self, self.isRunning, self.generation == g else { return }
            guard let links = result as? [[Any]], let pick = links.randomElement(),
                  let href = pick[0] as? String, let url = URL(string: href),
                  let x = (pick[1] as? NSNumber)?.doubleValue, let y = (pick[2] as? NSNumber)?.doubleValue
            else { return self.scrollStep() }   // 这一屏没有合适的链接，接着滚
            let scale = wv.pageZoom * wv.magnification
            let p = NSPoint(x: wv.frame.minX + x * scale, y: wv.frame.minY + y * scale)
            self.moveCursor(to: p, endAsHand: true) {
                guard self.isRunning, self.generation == g, self.webView() === wv else { return }
                self.pressThen {
                    wv.load(URLRequest(url: url))
                    self.hops += 1
                    self.schedule(after: 3)
                }
            }
        }
    }

    // MARK: 假光标动画

    private func showCursor(at p: NSPoint) {
        cursor.setHand(false)
        cursor.setFrameOrigin(cursor.origin(forTip: p))
        cursor.isHidden = false
    }

    private func randomPoint() -> NSPoint {
        let f = webView().frame.insetBy(dx: 80, dy: 60)
        guard f.width > 0, f.height > 0 else { return NSPoint(x: webView().frame.midX, y: webView().frame.midY) }
        return NSPoint(x: .random(in: f.minX...f.maxX), y: .random(in: f.minY...f.maxY))
    }

    /// 先经过一个随机的中间点再到终点，走得像人手而不是一条直线
    private func moveCursor(to target: NSPoint, endAsHand: Bool = false, completion: @escaping () -> Void) {
        let start = cursor.tip
        let mid = NSPoint(x: (start.x + target.x) / 2 + .random(in: -60...60),
                          y: (start.y + target.y) / 2 + .random(in: -40...40))
        let dist = hypot(target.x - start.x, target.y - start.y)
        let total = min(1.4, max(0.35, Double(dist) / 700)) * speed
        cursor.setHand(false)
        animate(to: mid, duration: total * 0.45) { [weak self] in
            guard let self else { return }
            self.animate(to: target, duration: total * 0.55) {
                if endAsHand { self.cursor.setHand(true); self.cursor.setFrameOrigin(self.cursor.origin(forTip: target)) }
                completion()
            }
        }
    }

    private func animate(to p: NSPoint, duration: Double, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cursor.animator().setFrameOrigin(cursor.origin(forTip: p))
        }, completionHandler: completion)
    }

    /// 停顿一下再“按下去”，看起来像在确认要点的东西
    private func pressThen(_ action: @escaping () -> Void) {
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0.3...0.7)) { [weak self] in
            guard let self, self.isRunning, self.generation == g else { return }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.cursor.setHand(false) }
        }
    }
}

// MARK: - 标签栏（Safari 的“分开式”布局：工具栏下面一排等宽标签）

final class TabItem: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true; updateClose() } }
    private var hovering = false { didSet { needsDisplay = true; updateClose() } }
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; toolTip = newValue }
    }

    private func updateClose() {
        closeButton.isHidden = !hovering
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 26, y: (bounds.height - 16) / 2, width: max(0, bounds.width - 52), height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || hovering else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor = isSelected
            ? (dark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.85))
            : (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04))
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose?() } }   // 中键关闭
    @objc private func closeClicked() { onClose?() }
}

final class TabStrip: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    private var items: [TabItem] = []

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func reload(titles: [String], selected: Int) {
        while items.count < titles.count {
            let item = TabItem()
            addSubview(item)
            items.append(item)
        }
        while items.count > titles.count { items.removeLast().removeFromSuperview() }
        for (i, item) in items.enumerated() {
            item.title = titles[i]
            item.isSelected = i == selected
            item.onSelect = { [weak self] in self?.onSelect?(i) }
            item.onClose = { [weak self] in self?.onClose?(i) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let n = CGFloat(max(1, items.count)), gap: CGFloat = 4, pad: CGFloat = 10
        let w = (bounds.width - pad * 2 - gap * (n - 1)) / n
        for (i, item) in items.enumerated() {
            item.frame = NSRect(x: pad + CGFloat(i) * (w + gap), y: 1, width: w, height: bounds.height - 6)
        }
    }
}

final class BrowserController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKDownloadDelegate, NSMenuItemValidation {
    let root = RootView()
    let bar = TopBar()
    let separator = NSBox()
    let box = AddressBox()
    let tabStrip = TabStrip()
    /// 当前标签页的网页
    private(set) var webView: WKWebView
    private var tabs: [WKWebView] = []
    private let webConfig: WKWebViewConfiguration
    private var tabObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var closedTabs: [URL] = []
    let autoBrowser = AutoBrowser()
    private var pendingRightClick: NSEvent?
    private var rightClickTimer: DispatchWorkItem?
    let prevZone = HotZone()
    let nextZone = HotZone()
    private var sidebarButton: NSButton!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var shareButton: NSButton!
    private var newTabButton: NSButton!
    private var bossButton: NSButton!

    private var novel: Novel?
    private var offset = 0
    private var pageLength = 0
    private var history: [Int] = []
    private var lastTextWidth: CGFloat = 0
    private var boss = false
    private var flipTimer: Timer?
    private var observations: [NSKeyValueObservation] = []

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        webConfig = config
        webView = WKWebView(frame: .zero, configuration: config)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.minSize = NSSize(width: 640, height: 400)
        win.contentView = root
        win.center()
        super.init(window: win)
        win.delegate = self
        win.setFrameAutosaveName("MainWindow")
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func symbolButton(_ name: String, _ action: Selector, _ tip: String) -> NSButton {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: tip)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!
        let b = NSButton(image: image, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.showsBorderOnlyWhileMouseInside = true
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        return b
    }

    private func build() {
        root.onLayout = { [weak self] in self?.layoutAll() }
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .followsWindowActiveState
        separator.boxType = .separator
        root.addSubview(bar)
        root.addSubview(separator)
        prevZone.symbol = "chevron.left"
        prevZone.onClick = { [weak self] in self?.prevPage() }
        nextZone.onClick = { [weak self] in self?.nextPage() }
        for z in [prevZone, nextZone] { root.addSubview(z) }

        bar.addSubview(tabStrip)
        tabStrip.onSelect = { [weak self] i in self?.selectTab(i) }
        tabStrip.onClose = { [weak self] i in self?.closeTab(i) }

        // 外观上和 Safari 一样；“边栏”= 跳转章节，“所有标签页”= 老板键
        sidebarButton = symbolButton("sidebar.left", #selector(jumpChapter(_:)), "显示边栏")
        backButton = symbolButton("chevron.left", #selector(goBack(_:)), "后退")
        forwardButton = symbolButton("chevron.right", #selector(goForward(_:)), "前进")
        shareButton = symbolButton("square.and.arrow.up", #selector(copyURL(_:)), "共享")
        newTabButton = symbolButton("plus", #selector(newTab(_:)), "新建标签页")
        bossButton = symbolButton("square.on.square", #selector(toggleBossAction(_:)), "显示所有标签页")
        for b in [sidebarButton!, backButton!, forwardButton!, shareButton!, newTabButton!, bossButton!] {
            bar.addSubview(b)
        }
        bar.addSubview(box)

        box.onSubmit = { [weak self] text in self?.open(text) }
        box.onPage = { [weak self] d in d > 0 ? self?.nextPage() : self?.prevPage() }
        box.onReload = { [weak self] in self?.reload(nil) }
        box.onEditingChanged = { [weak self] in
            guard let self else { return }
            if !self.box.isEditing { self.render() }
            self.root.needsLayout = true
        }

        setUpTab(webView)
        tabs = [webView]
        showCurrentTab()
        applyTextPrefs()

        autoBrowser.cursor.isHidden = true
        root.addSubview(autoBrowser.cursor)   // 最后加，保证在所有视图上面
        autoBrowser.webView = { [unowned self] in self.webView }
        autoBrowser.backButtonCenter = { [unowned self] in
            self.bar.convert(NSPoint(x: self.backButton.frame.midX, y: self.backButton.frame.midY), to: self.root)
        }
        autoBrowser.goBack = { [weak self] in self?.webView.goBack() }
        autoBrowser.mouseLocation = { [unowned self] in
            guard let win = self.window else { return nil }
            let p = self.root.convert(win.mouseLocationOutsideOfEventStream, from: nil)
            return self.webView.frame.contains(p) ? p : nil
        }
        autoBrowser.pointerOverWebView = { [unowned self] in
            guard let win = self.window, let p = self.autoBrowser.mouseLocation() else { return false }
            // 在角落翻页按钮上时露出指针，方便瞄准
            if (!self.prevZone.isHidden && self.prevZone.frame.contains(p)) || (!self.nextZone.isHidden && self.nextZone.frame.contains(p)) { return false }
            // 指针所在位置最上面的窗口必须是这个窗口，不然就是被别的窗口挡住了
            return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == win.windowNumber
        }
    }

    // MARK: 标签页

    private var currentIndex: Int { tabs.firstIndex { $0 === webView } ?? 0 }

    private func setUpTab(_ wv: WKWebView) {
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        // 每个标签的标题和网址一变，就刷新标签栏、保存会话
        tabObservations[ObjectIdentifier(wv)] = [
            wv.observe(\.title) { [weak self] _, _ in self?.refreshTabs() },
            wv.observe(\.url) { [weak self] _, _ in self?.refreshTabs(); self?.saveSession() },
        ]
    }

    /// 把当前标签的网页放进窗口，并把地址栏、按钮绑定到它身上
    private func showCurrentTab() {
        for t in tabs where t !== webView { t.removeFromSuperview() }
        if webView.superview == nil { root.addSubview(webView, positioned: .below, relativeTo: bar) }
        prevZone.scrollTarget = webView
        nextZone.scrollTarget = webView
        observations = [
            webView.observe(\.url, options: .initial) { [weak self] _, _ in self?.urlChanged() },
            webView.observe(\.title, options: .initial) { [weak self] wv, _ in self?.window?.title = wv.title ?? "" },
            webView.observe(\.estimatedProgress, options: .initial) { [weak self] wv, _ in self?.box.progress = wv.estimatedProgress },
            webView.observe(\.canGoBack, options: .initial) { [weak self] wv, _ in self?.backButton.isEnabled = wv.canGoBack },
            webView.observe(\.canGoForward, options: .initial) { [weak self] wv, _ in self?.forwardButton.isEnabled = wv.canGoForward },
            webView.observe(\.isLoading, options: .initial) { [weak self] wv, _ in
                self?.box.reloadButton.image = NSImage(systemSymbolName: wv.isLoading ? "xmark" : "arrow.clockwise",
                                                       accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            },
        ]
        refreshTabs()
        root.needsLayout = true
    }

    private func refreshTabs() {
        let titles = tabs.map { t -> String in
            if let title = t.title, !title.isEmpty { return title }
            return t.url?.host ?? "新标签页"
        }
        let wasVisible = !tabStrip.isHidden
        tabStrip.isHidden = tabs.count < 2   // 和 Safari 一样，只有一个标签时不显示标签栏
        tabStrip.reload(titles: titles, selected: currentIndex)
        if wasVisible != !tabStrip.isHidden { root.needsLayout = true }
    }

    /// 新标签默认插在当前标签右边
    @discardableResult
    private func addTab(_ wv: WKWebView? = nil, select: Bool = true, at index: Int? = nil) -> WKWebView {
        let tab = wv ?? WKWebView(frame: .zero, configuration: webConfig)
        setUpTab(tab)
        let i = min(index ?? currentIndex + 1, tabs.count)
        tabs.insert(tab, at: i)
        if select { selectTab(i) } else { refreshTabs() }
        saveSession()
        return tab
    }

    func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        if box.isEditing { box.endEditing() }
        webView = tabs[i]
        showCurrentTab()
        window?.makeFirstResponder(webView)
        saveSession()
    }

    func closeTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        if tabs.count == 1 { window?.performClose(nil); return }
        let tab = tabs.remove(at: i)
        if let u = tab.url { closedTabs.append(u) }
        tabObservations[ObjectIdentifier(tab)] = nil
        tab.stopLoading()
        tab.removeFromSuperview()
        if tab === webView { webView = tabs[min(i, tabs.count - 1)] }
        showCurrentTab()
        window?.makeFirstResponder(webView)
        saveSession()
    }

    private func saveSession() {
        Prefs.tabURLs = tabs.map { $0.url?.absoluteString ?? "" }
        Prefs.selectedTab = currentIndex
    }

    private func restoreSession() {
        let urls = Prefs.tabURLs?.filter { !$0.isEmpty } ?? []
        guard !urls.isEmpty else { return open(Prefs.lastURL ?? Prefs.homeURL) }
        open(urls[0])
        for u in urls.dropFirst() {
            if let url = URL(string: u) { addTab(select: false, at: tabs.count).load(URLRequest(url: url)) }
        }
        selectTab(min(max(0, Prefs.selectedTab), tabs.count - 1))
    }

    @objc func newTab(_ sender: Any?) {
        addTab()
        open(Prefs.homeURL)
        box.beginEditing()   // 像 Safari 一样，新标签页直接可以输入网址
    }

    @objc func closeCurrentTab(_ sender: Any?) { closeTab(currentIndex) }
    @objc func closeWindow(_ sender: Any?) { window?.performClose(nil) }
    @objc func nextTab(_ sender: Any?) { selectTab((currentIndex + 1) % tabs.count) }
    @objc func previousTab(_ sender: Any?) { selectTab((currentIndex - 1 + tabs.count) % tabs.count) }

    @objc func reopenClosedTab(_ sender: Any?) {
        guard let u = closedTabs.popLast() else { return NSSound.beep() }
        addTab().load(URLRequest(url: u))
    }

    func start() {
        restoreSession()
        if let path = Prefs.novelPath { loadNovel(path) }
        restartFlipTimer()
        render()

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // 切走就隐藏；切回来不自动恢复，要再按 Esc
            guard let self, Prefs.autoHide, !self.boss else { return }
            self.setBoss(true)
        }

        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] e in
            guard let self, self.autoBrowser.isRunning, e.window === self.window else { return e }
            let p = self.root.convert(e.locationInWindow, from: nil)
            let inCorner = (!self.prevZone.isHidden && self.prevZone.frame.contains(p)) || (!self.nextZone.isHidden && self.nextZone.frame.contains(p))
            guard self.webView.frame.contains(p), !inCorner else { return e }
            if e.type == .mouseMoved { self.autoBrowser.mouseMoved(to: p) } else { self.autoBrowser.mouseClickedOrScrolled() }
            return e
        }

        // 双击右键 = 老板键（只进不出）。第一下先压住，短时间内没有第二下，再照常弹出右键菜单
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] e in
            guard let self, Prefs.rightClickBoss, !self.boss, e.window === self.window else { return e }
            let p = self.root.convert(e.locationInWindow, from: nil)
            guard self.webView.frame.contains(p) else { return e }
            if e.type == .rightMouseUp { return self.pendingRightClick == nil ? e : nil }
            if self.pendingRightClick != nil {
                self.rightClickTimer?.cancel()
                self.pendingRightClick = nil
                self.setBoss(true)
                return nil
            }
            self.pendingRightClick = e
            let work = DispatchWorkItem { [weak self] in
                guard let self, let first = self.pendingRightClick else { return }
                self.pendingRightClick = nil
                self.window?.sendEvent(first)   // 直接交给窗口，不再经过这个监听
            }
            self.rightClickTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.4), execute: work)
            return nil
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !ShortcutRecorder.isRecording, e.window === self.window else { return e }
            // 切换标签页：⌃⇥ / ⌃⇧⇥、⇧⌘] / ⇧⌘[、⌘1…⌘9（编辑地址栏时也能用）
            let tabFlags = e.modifierFlags.intersection(Shortcut.modMask)
            let code = Int(e.keyCode)
            if code == kVK_Tab, tabFlags == .control { self.nextTab(nil); return nil }
            if code == kVK_Tab, tabFlags == [.control, .shift] { self.previousTab(nil); return nil }
            if code == kVK_ANSI_RightBracket, tabFlags == [.command, .shift] { self.nextTab(nil); return nil }
            if code == kVK_ANSI_LeftBracket, tabFlags == [.command, .shift] { self.previousTab(nil); return nil }
            let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
            if tabFlags == .command, let n = digits.firstIndex(of: code) {
                self.selectTab(n == 8 ? self.tabs.count - 1 : n)   // ⌘9 = 最后一个标签
                return nil
            }
            guard !self.box.isEditing else { return e }
            if ShortcutAction.autoBrowse.shortcut?.matches(e) == true { self.toggleAutoBrowse(nil); return nil }
            if ShortcutAction.boss.shortcut?.matches(e) == true {
                self.toggleBoss()
                return nil   // 不能传给网页：WKWebView 会把没处理的按键再发回来，导致切换两次
            }
            // 翻页键只在显示小说时生效；老板模式下照常交给网页（比如 ⌘C 复制）
            if !self.boss, ShortcutAction.nextPage.shortcut?.matches(e) == true { self.nextPage(); return nil }
            if !self.boss, ShortcutAction.prevPage.shortcut?.matches(e) == true { self.prevPage(); return nil }
            // ⌘C / ⌘V 被拿去翻页时，用 ⌥⌘C / ⌥⌘V 复制粘贴
            let flags = e.modifierFlags.intersection(Shortcut.modMask)
            if flags == [.command, .option], e.keyCode == UInt16(kVK_ANSI_C) {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
                return nil
            }
            if flags == [.command, .option], e.keyCode == UInt16(kVK_ANSI_V) {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                return nil
            }
            return e
        }
    }

    // MARK: 布局

    private func layoutAll() {
        guard let win = window else { return }
        let W = root.bounds.width, H = root.bounds.height
        let boxH = max(30, CGFloat(box.displayLines) * box.lineHeight + 14)
        let toolbarH = max(52, boxH + 22)
        let tabsH: CGFloat = tabStrip.isHidden ? 0 : 32
        let barH = toolbarH + tabsH
        bar.frame = NSRect(x: 0, y: 0, width: W, height: barH)
        tabStrip.frame = NSRect(x: 0, y: toolbarH, width: W, height: tabsH)
        separator.frame = NSRect(x: 0, y: barH, width: W, height: 1)
        webView.frame = NSRect(x: 0, y: barH + 1, width: W, height: max(0, H - barH - 1))

        let z = CGFloat(Prefs.hotZoneSize)
        prevZone.frame = NSRect(x: 0, y: H - z, width: z, height: z)
        nextZone.frame = NSRect(x: W - z, y: H - z, width: z, height: z)
        for zone in [prevZone, nextZone] {
            zone.isHidden = z <= 0
            zone.showsOutline = Prefs.hotZoneVisible
        }

        let cy: CGFloat = 26
        var x: CGFloat = win.styleMask.contains(.fullScreen) ? 12 : 86
        for (b, gap) in [(sidebarButton!, 14.0), (backButton!, 2.0), (forwardButton!, 12.0)] {
            b.frame = NSRect(x: x, y: cy - 14, width: 30, height: 28)
            x += 30 + gap
        }
        var rx = W - 12
        for b in [bossButton!, newTabButton!, shareButton!] {
            rx -= 30
            b.frame = NSRect(x: rx, y: cy - 14, width: 30, height: 28)
            rx -= 8
        }
        // 窗口小时跟着缩放，大了就封顶并居中（和 Safari 一样不会无限拉长）
        let room = max(200, rx - 6 - x)
        let maxW = Prefs.maxBoxWidth > 0 ? CGFloat(Prefs.maxBoxWidth) : room
        let boxW = min(room, maxW)
        let boxX = min(max(x, (W - boxW) / 2), x + room - boxW)
        box.frame = NSRect(x: boxX, y: 11, width: boxW, height: boxH)

        if abs(box.textWidth - lastTextWidth) > 0.5 {
            lastTextWidth = box.textWidth
            render()
        }
        placeTrafficLights()
    }

    /// 让红绿灯和工具栏按钮垂直居中，像 Safari 一样
    private func placeTrafficLights() {
        guard let win = window, !win.styleMask.contains(.fullScreen),
              let close = win.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        let h: CGFloat = 52
        container.frame = NSRect(x: 0, y: win.frame.height - h, width: win.frame.width, height: h)
        titlebar.frame = container.bounds
        for (i, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = win.standardWindowButton(kind) else { continue }
            b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 20, y: (h - b.frame.height) / 2))
        }
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }
    func windowDidBecomeKey(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights(); root.needsLayout = true }
    func windowDidEnterFullScreen(_ notification: Notification) { root.needsLayout = true }

    // MARK: 小说显示

    private func render(direction: Int = 0) {
        box.isBoss = boss
        if boss || box.isEditing {
            box.toolTip = nil
            let host = displayHost()
            box.display(host.isEmpty ? "Search or enter website name" : host, style: host.isEmpty ? .hint : .url)
            return
        }
        guard let n = novel else {
            box.toolTip = nil
            box.display("File › Open File…（⌘O）打开 txt 小说", style: .hint)
            return
        }
        offset = min(max(0, offset), max(0, n.text.length - 1))
        pageLength = box.fitLength(n.text, from: offset)
        if Prefs.sentenceBreak { pageLength = sentenceCut(n.text, from: offset, length: pageLength) }
        let page = n.text.substring(with: NSRange(location: offset, length: pageLength))
        box.display(page.trimmingCharacters(in: .whitespaces), style: .novel, direction: direction)
        box.toolTip = positionDescription()
    }

    private static let breakChars = CharacterSet(charactersIn: "，。！？；：、…,.!?;:　")
    private static let closingChars = CharacterSet(charactersIn: "”’」』）)》】〕\"'")

    /// 把一页的结尾往回缩到最后一个标点（连同后面的右引号/右括号）；整页都没有标点就不缩
    private func sentenceCut(_ text: NSString, from: Int, length: Int) -> Int {
        let end = from + length
        guard end < text.length else { return length }
        func isBreak(_ i: Int) -> Bool { Self.breakChars.contains(UnicodeScalar(text.character(at: i)) ?? " ") }
        func isClosing(_ i: Int) -> Bool { Self.closingChars.contains(UnicodeScalar(text.character(at: i)) ?? "a") }
        var i = end - 1
        while i > from {
            if isBreak(i) || (isClosing(i) && isBreak(i - 1)) {
                var cut = i + 1
                while cut < end, isClosing(cut) { cut += 1 }
                // 右引号被挤到下一页就不算完整，继续往前找；省略号“……”也不拆开
                if cut == end, isClosing(cut) || (cut < text.length && isBreak(cut) && text.character(at: cut) == text.character(at: i)) {
                    i -= 1
                    continue
                }
                return cut - from
            }
            i -= 1
        }
        return length
    }

    private func positionDescription() -> String {
        guard let n = novel else { return "" }
        let pct = n.text.length > 0 ? Double(offset) / Double(n.text.length) * 100 : 0
        let chapter = n.chapterIndex(at: offset).map { n.chapters[$0].title } ?? ""
        return String(format: "%@  %.1f%%", chapter, pct)
    }

    private func displayHost() -> String {
        guard let host = webView.url?.host else { return webView.url?.absoluteString ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func applyTextPrefs() {
        box.lines = Prefs.lines
        box.font = .systemFont(ofSize: CGFloat(Prefs.fontSize))
        box.novelColor = [NSColor.labelColor, .secondaryLabelColor, .tertiaryLabelColor][min(2, max(0, Prefs.textStyle))]
        history.removeAll()
        lastTextWidth = 0
        root.needsLayout = true
        render()
    }

    func loadNovel(_ path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Novel.load(path: path) }
            DispatchQueue.main.async {
                switch result {
                case .success(let n):
                    self.novel = n
                    self.offset = Prefs.offset(for: path)
                    self.history = Prefs.history(for: path)
                    Prefs.novelPath = path
                    self.render()
                case .failure(let err):
                    let alert = NSAlert(error: err)
                    alert.beginSheetModal(for: self.window!)
                }
            }
        }
    }

    private func moveTo(_ newOffset: Int, remember: Bool = true, direction: Int = 0) {
        guard let n = novel else { return }
        if direction != 0 { autoBrowser.ignoreMouseBriefly() }
        if remember {
            history.append(offset)
            if history.count > 1000 { history.removeFirst() }
        }
        offset = min(max(0, newOffset), max(0, n.text.length - 1))
        saveProgress()
        render(direction: direction)
    }

    func saveProgress() {
        guard let n = novel else { return }
        Prefs.saveProgress(offset, history: history, for: n.path)
    }

    func nextPage() {
        guard !boss, let n = novel, offset + pageLength < n.text.length else { return }
        moveTo(offset + pageLength, direction: 1)
    }

    func prevPage() {
        guard !boss, novel != nil, offset > 0 else { return }
        moveTo(history.popLast() ?? max(0, offset - pageLength), remember: false, direction: -1)
    }

    // MARK: 老板模式

    func setBoss(_ on: Bool) {
        boss = on
        if on, box.isEditing { box.endEditing() }
        if on { saveProgress() }
        prevZone.isActive = !on
        nextZone.isActive = !on
        root.needsLayout = true
        render()
    }

    func toggleBoss() { setBoss(!boss) }

    // MARK: 菜单动作

    @objc func toggleBossAction(_ sender: Any?) { toggleBoss() }
    @objc func nextPageAction(_ sender: Any?) { nextPage() }
    @objc func prevPageAction(_ sender: Any?) { prevPage() }
    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }
    @objc func goHome(_ sender: Any?) { open(Prefs.homeURL) }
    @objc func reload(_ sender: Any?) {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }
    @objc func focusAddress(_ sender: Any?) { box.beginEditing() }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(3, webView.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(0.3, webView.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { webView.pageZoom = 1 }
    @objc func setAsHome(_ sender: Any?) { if let u = webView.url?.absoluteString { Prefs.homeURL = u } }

    @objc func copyURL(_ sender: Any?) {
        guard let u = webView.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u, forType: .string)
    }

    @objc func setLines(_ sender: NSMenuItem) { Prefs.lines = sender.tag; applyTextPrefs() }
    @objc func setFontSize(_ sender: NSMenuItem) { Prefs.fontSize = sender.tag; applyTextPrefs() }
    @objc func setTextStyle(_ sender: NSMenuItem) { Prefs.textStyle = sender.tag; applyTextPrefs() }
    @objc func toggleAutoHide(_ sender: Any?) { Prefs.autoHide.toggle() }
    @objc func toggleRightClickBoss(_ sender: Any?) { Prefs.rightClickBoss.toggle() }

    @objc func toggleAutoBrowse(_ sender: Any?) {
        if autoBrowser.isRunning {
            autoBrowser.stop()
            window?.acceptsMouseMovedEvents = false
        } else {
            window?.acceptsMouseMovedEvents = true   // 用来发现你自己动了鼠标
            autoBrowser.start()
        }
    }
    @objc func toggleAutoBrowseClicks(_ sender: Any?) { Prefs.autoBrowseClicks.toggle() }
    @objc func setAutoBrowseSpeed(_ sender: NSMenuItem) { Prefs.autoBrowseSpeed = sender.tag }
    @objc func setPageTransition(_ sender: NSMenuItem) { Prefs.pageTransition = sender.tag }
    @objc func setTransitionSpeed(_ sender: NSMenuItem) { Prefs.transitionSpeed = sender.tag }
    @objc func setMaxBoxWidth(_ sender: NSMenuItem) { Prefs.maxBoxWidth = sender.tag; history.removeAll(); root.needsLayout = true }
    @objc func toggleSentenceBreak(_ sender: Any?) { Prefs.sentenceBreak.toggle(); history.removeAll(); render() }
    @objc func toggleHotZoneVisible(_ sender: Any?) { Prefs.hotZoneVisible.toggle(); root.needsLayout = true }
    @objc func setHotZoneSize(_ sender: NSMenuItem) { Prefs.hotZoneSize = sender.tag; root.needsLayout = true }
    @objc func setAutoFlip(_ sender: NSMenuItem) { Prefs.autoFlip = sender.tag; restartFlipTimer() }

    private func restartFlipTimer() {
        flipTimer?.invalidate()
        flipTimer = nil
        let secs = Prefs.autoFlip
        guard secs > 0 else { return }
        flipTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: true) { [weak self] _ in
            guard let self, !self.boss, !self.box.isEditing else { return }
            self.nextPage()
        }
    }

    @objc func openNovel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window!) { resp in
            guard resp == .OK, let url = panel.url else { return }
            self.loadNovel(url.path)
        }
    }

    @objc func jumpChapter(_ sender: Any?) {
        guard let n = novel else { return openNovel(nil) }
        let alert = NSAlert()
        alert.messageText = "跳转"
        alert.informativeText = "当前：\(positionDescription())\n\n输入章节号（如 120）、章节名关键词，或百分比（如 50%）"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "跳转")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window!) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            let q = field.stringValue.trimmingCharacters(in: .whitespaces)
            if q.hasSuffix("%"), let p = Double(q.dropLast()) {
                self.moveTo(Int(Double(n.text.length) * min(100, max(0, p)) / 100))
            } else if let num = Int(q) {
                if let c = n.chapters.first(where: { Novel.chapterNumber($0.title) == num }) {
                    self.moveTo(c.offset)
                } else if num >= 1, num <= n.chapters.count {
                    self.moveTo(n.chapters[num - 1].offset)
                } else {
                    NSSound.beep()
                }
            } else if !q.isEmpty, let c = n.chapters.first(where: { $0.title.contains(q) }) {
                self.moveTo(c.offset)
            } else if !q.isEmpty {
                NSSound.beep()
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleAutoBrowse(_:)):
            item.state = autoBrowser.isRunning ? .on : .off
            item.title = "自动浏览（\(ShortcutAction.autoBrowse.label)）"
        case #selector(toggleRightClickBoss(_:)): item.state = Prefs.rightClickBoss ? .on : .off
        case #selector(toggleAutoBrowseClicks(_:)): item.state = Prefs.autoBrowseClicks ? .on : .off
        case #selector(setAutoBrowseSpeed(_:)): item.state = item.tag == Prefs.autoBrowseSpeed ? .on : .off
        case #selector(nextPageAction(_:)): item.title = "下一页（\(ShortcutAction.nextPage.label)）"
        case #selector(prevPageAction(_:)): item.title = "上一页（\(ShortcutAction.prevPage.label)）"
        case #selector(toggleBossAction(_:)):
            item.state = boss ? .on : .off
            item.title = "老板模式（\(ShortcutAction.boss.label) / 全局 \(ShortcutAction.globalBoss.label)）"
        case #selector(toggleAutoHide(_:)):
            item.state = Prefs.autoHide ? .on : .off
            item.title = "切到别的 App 时隐藏（按 \(ShortcutAction.boss.label) 恢复）"
        case #selector(setLines(_:)): item.state = item.tag == Prefs.lines ? .on : .off
        case #selector(setFontSize(_:)): item.state = item.tag == Prefs.fontSize ? .on : .off
        case #selector(setTextStyle(_:)): item.state = item.tag == Prefs.textStyle ? .on : .off
        case #selector(setAutoFlip(_:)): item.state = item.tag == Prefs.autoFlip ? .on : .off
        case #selector(setPageTransition(_:)): item.state = item.tag == Prefs.pageTransition ? .on : .off
        case #selector(setTransitionSpeed(_:)): item.state = item.tag == Prefs.transitionSpeed ? .on : .off
        case #selector(setMaxBoxWidth(_:)): item.state = item.tag == Prefs.maxBoxWidth ? .on : .off
        case #selector(toggleSentenceBreak(_:)): item.state = Prefs.sentenceBreak ? .on : .off
        case #selector(toggleHotZoneVisible(_:)): item.state = Prefs.hotZoneVisible ? .on : .off
        case #selector(setHotZoneSize(_:)): item.state = item.tag == Prefs.hotZoneSize ? .on : .off
        case #selector(goBack(_:)): return webView.canGoBack
        case #selector(goForward(_:)): return webView.canGoForward
        default: break
        }
        return true
    }

    // MARK: 网页

    func open(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var url: URL?
        if t.contains("://") {
            url = URL(string: t)
        } else if !t.contains(" "), t.contains(".") || t.hasPrefix("localhost") {
            url = URL(string: "https://" + t)
        }
        if url == nil {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: t)]
            url = c.url
        }
        if let url { webView.load(URLRequest(url: url)) }
        window?.makeFirstResponder(webView)
    }

    private func urlChanged() {
        let u = webView.url
        box.urlString = u?.absoluteString ?? ""
        let secure = u?.scheme == "https"
        box.icon.image = NSImage(systemSymbolName: secure ? "lock.fill" : "globe", accessibilityDescription: nil)
        if let s = u?.absoluteString, u?.scheme?.hasPrefix("http") == true { Prefs.lastURL = s }
        if boss { render() }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank 和 window.open 都在新标签页打开（必须用 WebKit 给的 configuration 创建）
        guard action.targetFrame == nil else { return nil }
        return addTab(WKWebView(frame: .zero, configuration: configuration))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var dest = dir.appendingPathComponent(suggestedFilename)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        completionHandler(dest)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.beginSheetModal(for: window!) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: window!) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: window!) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: BrowserController!
    private var shortcutSettings: ShortcutSettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        controller = BrowserController()
        NSApp.mainMenu = buildMenu()
        controller.showWindow(nil)
        controller.start()
        HotKey.handler = { [weak self] in
            guard !ShortcutRecorder.isRecording else { return }
            self?.controller.toggleBoss()
        }
        HotKey.register(ShortcutAction.globalBoss.shortcut)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showShortcutSettings(_ sender: Any?) {
        if shortcutSettings == nil { shortcutSettings = ShortcutSettingsController() }
        shortcutSettings?.showWindow(nil)
        shortcutSettings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { controller.saveProgress() }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let c = controller!
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Browser"

        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            item.submenu = m
            main.addItem(item)
            return m
        }
        @discardableResult
        func add(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
            let item = m.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            item.tag = tag
            return item
        }

        let app = submenu(name)
        add(app, "About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, "Settings…", #selector(showShortcutSettings(_:)), ",", target: self)
        app.addItem(.separator())
        add(app, "Hide \(name)", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit \(name)", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu("File")
        add(file, "New Tab", #selector(BrowserController.newTab(_:)), "t", target: c)
        add(file, "Open Location…", #selector(BrowserController.focusAddress(_:)), "l", target: c)
        add(file, "Open File…", #selector(BrowserController.openNovel(_:)), "o", target: c)
        file.addItem(.separator())
        add(file, "Close Tab", #selector(BrowserController.closeCurrentTab(_:)), "w", target: c)
        add(file, "Close Window", #selector(BrowserController.closeWindow(_:)), "w", [.command, .shift], target: c)
        add(file, "Reopen Closed Tab", #selector(BrowserController.reopenClosedTab(_:)), "t", [.command, .shift], target: c)

        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        // ⌘C / ⌘V 被拿去翻页了，复制粘贴改用 ⌥⌘C / ⌥⌘V
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        let view = submenu("View")
        add(view, "Reload Page", #selector(BrowserController.reload(_:)), "r", target: c)
        view.addItem(.separator())
        add(view, "Actual Size", #selector(BrowserController.zoomReset(_:)), "0", target: c)
        add(view, "Zoom In", #selector(BrowserController.zoomIn(_:)), "=", target: c)
        add(view, "Zoom Out", #selector(BrowserController.zoomOut(_:)), "-", target: c)
        view.addItem(.separator())
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let hist = submenu("History")
        add(hist, "Back", #selector(BrowserController.goBack(_:)), "[", target: c)
        add(hist, "Forward", #selector(BrowserController.goForward(_:)), "]", target: c)
        add(hist, "Home", #selector(BrowserController.goHome(_:)), "h", [.command, .shift], target: c)

        // 阅读相关的都藏在 Bookmarks 菜单里
        let bm = submenu("Bookmarks")
        add(bm, "下一页", #selector(BrowserController.nextPageAction(_:)), target: c)   // 快捷键写在标题里，不设 keyEquivalent，免得抢走地址栏里的 ⌘C
        add(bm, "上一页", #selector(BrowserController.prevPageAction(_:)), target: c)
        add(bm, "跳转章节…", #selector(BrowserController.jumpChapter(_:)), "j", target: c)
        bm.addItem(.separator())
        add(bm, "老板模式", #selector(BrowserController.toggleBossAction(_:)), target: c)
        add(bm, "在网页上双击右键进入老板模式", #selector(BrowserController.toggleRightClickBoss(_:)), target: c)
        add(bm, "快捷键设置…", #selector(showShortcutSettings(_:)), target: self)
        bm.addItem(.separator())
        add(bm, "自动浏览", #selector(BrowserController.toggleAutoBrowse(_:)), target: c)
        add(bm, "自动浏览时点击站内链接", #selector(BrowserController.toggleAutoBrowseClicks(_:)), target: c)
        choices("自动浏览速度", [("慢", 1), ("适中", 2), ("快", 3)], #selector(BrowserController.setAutoBrowseSpeed(_:)))
        add(bm, "切到别的 App 时隐藏（按 Esc 恢复）", #selector(BrowserController.toggleAutoHide(_:)), target: c)
        bm.addItem(.separator())

        func choices(_ title: String, _ items: [(String, Int)], _ action: Selector) {
            let m = NSMenu(title: title)
            for (t, tag) in items { add(m, t, action, target: c, tag: tag) }
            bm.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = m
        }
        add(bm, "只在标点处换页（不截断句子）", #selector(BrowserController.toggleSentenceBreak(_:)), target: c)
        choices("显示行数",(1...6).map { ("\($0) 行", $0) }, #selector(BrowserController.setLines(_:)))
        choices("地址栏最大宽度", [("窄 (600)", 600), ("标准 (760)", 760), ("宽 (950)", 950), ("很宽 (1200)", 1200), ("不限", 0)],
                #selector(BrowserController.setMaxBoxWidth(_:)))
        choices("换页动效", [("无", 0), ("淡入淡出", 1), ("上滑", 2)], #selector(BrowserController.setPageTransition(_:)))
        choices("动效速度", [("快", 25), ("适中", 45), ("慢", 80), ("很慢", 130)],
                #selector(BrowserController.setTransitionSpeed(_:)))
        choices("字号", [11, 12, 13, 14, 15, 16, 18, 20].map { ("\($0)", $0) }, #selector(BrowserController.setFontSize(_:)))
        choices("文字颜色", [("标准", 0), ("柔和", 1), ("很淡", 2)], #selector(BrowserController.setTextStyle(_:)))
        choices("自动翻页", [("关", 0)] + [3, 5, 8, 10, 15, 20, 30].map { ("每 \($0) 秒", $0) },
                #selector(BrowserController.setAutoFlip(_:)))
        choices("角落翻页按钮大小", [("关", 0), ("小 (40)", 40), ("中 (60)", 60), ("大 (90)", 90), ("特大 (130)", 130)],
                #selector(BrowserController.setHotZoneSize(_:)))
        add(bm, "显示角落翻页按钮", #selector(BrowserController.toggleHotZoneVisible(_:)), target: c)
        bm.addItem(.separator())
        add(bm, "把当前网页设为主页", #selector(BrowserController.setAsHome(_:)), target: c)

        let win = submenu("Window")
        add(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(win, "Zoom", #selector(NSWindow.performZoom(_:)))
        win.addItem(.separator())
        // 真正的切换在按键监听里处理（⌃⇥ 会被网页吃掉），这里只是显示快捷键
        add(win, "Show Previous Tab", #selector(BrowserController.previousTab(_:)), "\t", [.control, .shift], target: c)
        add(win, "Show Next Tab", #selector(BrowserController.nextTab(_:)), "\t", .control, target: c)
        NSApp.windowsMenu = win

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
