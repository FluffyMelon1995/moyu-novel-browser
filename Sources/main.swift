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

// MARK: - 全局快捷键（Carbon，不需要辅助功能权限）

enum HotKey {
    static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(keyCode: Int, modifiers: Int) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4E56_4C42), id: 1)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
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

final class BrowserController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKDownloadDelegate, NSMenuItemValidation {
    let root = RootView()
    let bar = TopBar()
    let separator = NSBox()
    let box = AddressBox()
    let webView: WKWebView
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
        root.addSubview(webView)
        root.addSubview(bar)
        root.addSubview(separator)
        prevZone.symbol = "chevron.left"
        prevZone.onClick = { [weak self] in self?.prevPage() }
        nextZone.onClick = { [weak self] in self?.nextPage() }
        for z in [prevZone, nextZone] {
            z.scrollTarget = webView
            root.addSubview(z)
        }

        // 外观上和 Safari 一样；“边栏”= 跳转章节，“所有标签页”= 老板键
        sidebarButton = symbolButton("sidebar.left", #selector(jumpChapter(_:)), "显示边栏")
        backButton = symbolButton("chevron.left", #selector(goBack(_:)), "后退")
        forwardButton = symbolButton("chevron.right", #selector(goForward(_:)), "前进")
        shareButton = symbolButton("square.and.arrow.up", #selector(copyURL(_:)), "共享")
        newTabButton = symbolButton("plus", #selector(goHome(_:)), "新建标签页")
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

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        observations = [
            webView.observe(\.url) { [weak self] _, _ in self?.urlChanged() },
            webView.observe(\.title) { [weak self] wv, _ in self?.window?.title = wv.title ?? "" },
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in self?.box.progress = wv.estimatedProgress },
            webView.observe(\.canGoBack) { [weak self] wv, _ in self?.backButton.isEnabled = wv.canGoBack },
            webView.observe(\.canGoForward) { [weak self] wv, _ in self?.forwardButton.isEnabled = wv.canGoForward },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                self?.box.reloadButton.image = NSImage(systemSymbolName: wv.isLoading ? "xmark" : "arrow.clockwise",
                                                       accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            },
        ]
        backButton.isEnabled = false
        forwardButton.isEnabled = false
        applyTextPrefs()
    }

    func start() {
        open(Prefs.lastURL ?? Prefs.homeURL)
        if let path = Prefs.novelPath { loadNovel(path) }
        restartFlipTimer()
        render()

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // 切走就隐藏；切回来不自动恢复，要再按 Esc
            guard let self, Prefs.autoHide, !self.boss else { return }
            self.setBoss(true)
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !self.box.isEditing else { return e }
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if e.keyCode == UInt16(kVK_Escape), flags.isEmpty {
                self.toggleBoss()
                return nil   // 不能传给网页：WKWebView 会把没处理的按键再发回来，导致切换两次
            }
            // ⌘C 下一页、⌘V 上一页（编辑地址栏和老板模式时照常复制粘贴）
            if flags == .command, !self.boss, e.keyCode == UInt16(kVK_ANSI_C) { self.nextPage(); return nil }
            if flags == .command, !self.boss, e.keyCode == UInt16(kVK_ANSI_V) { self.prevPage(); return nil }
            return e
        }
    }

    // MARK: 布局

    private func layoutAll() {
        guard let win = window else { return }
        let W = root.bounds.width, H = root.bounds.height
        let boxH = max(30, CGFloat(box.displayLines) * box.lineHeight + 14)
        let barH = max(52, boxH + 22)
        bar.frame = NSRect(x: 0, y: 0, width: W, height: barH)
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
        case #selector(setLines(_:)): item.state = item.tag == Prefs.lines ? .on : .off
        case #selector(setFontSize(_:)): item.state = item.tag == Prefs.fontSize ? .on : .off
        case #selector(setTextStyle(_:)): item.state = item.tag == Prefs.textStyle ? .on : .off
        case #selector(setAutoFlip(_:)): item.state = item.tag == Prefs.autoFlip ? .on : .off
        case #selector(toggleAutoHide(_:)): item.state = Prefs.autoHide ? .on : .off
        case #selector(setPageTransition(_:)): item.state = item.tag == Prefs.pageTransition ? .on : .off
        case #selector(setTransitionSpeed(_:)): item.state = item.tag == Prefs.transitionSpeed ? .on : .off
        case #selector(setMaxBoxWidth(_:)): item.state = item.tag == Prefs.maxBoxWidth ? .on : .off
        case #selector(toggleSentenceBreak(_:)): item.state = Prefs.sentenceBreak ? .on : .off
        case #selector(toggleHotZoneVisible(_:)): item.state = Prefs.hotZoneVisible ? .on : .off
        case #selector(setHotZoneSize(_:)): item.state = item.tag == Prefs.hotZoneSize ? .on : .off
        case #selector(toggleBossAction(_:)): item.state = boss ? .on : .off
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
        // target=_blank 的链接在当前页打开
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        controller = BrowserController()
        NSApp.mainMenu = buildMenu()
        controller.showWindow(nil)
        controller.start()
        HotKey.handler = { [weak self] in self?.controller.toggleBoss() }
        HotKey.register(keyCode: kVK_ANSI_Grave, modifiers: optionKey)
        NSApp.activate(ignoringOtherApps: true)
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
        add(app, "Hide \(name)", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit \(name)", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu("File")
        add(file, "Open Location…", #selector(BrowserController.focusAddress(_:)), "l", target: c)
        add(file, "Open File…", #selector(BrowserController.openNovel(_:)), "o", target: c)
        file.addItem(.separator())
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        // ⌘C / ⌘V 被拿去翻页了，复制粘贴改用 ⌥⌘C / ⌥⌘V
        add(edit, "Copy", #selector(NSText.copy(_:)), "c", [.command, .option])
        add(edit, "Paste", #selector(NSText.paste(_:)), "v", [.command, .option])
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
        add(bm, "下一页", #selector(BrowserController.nextPageAction(_:)), "c", target: c)
        add(bm, "上一页", #selector(BrowserController.prevPageAction(_:)), "v", target: c)
        add(bm, "跳转章节…", #selector(BrowserController.jumpChapter(_:)), "j", target: c)
        bm.addItem(.separator())
        add(bm, "老板模式（Esc 或 ⌥`）", #selector(BrowserController.toggleBossAction(_:)), target: c)
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
        NSApp.windowsMenu = win

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
