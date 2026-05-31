import AppKit

/// 輸入文字時跳出的格式面板：字型、字級、粗體/斜體/底線、顏色。
/// 變更即時套用到正在編輯的 NSTextView。
final class TextFormatPanel: NSWindowController, NSComboBoxDelegate {
    static let shared = TextFormatPanel()

    private weak var target: NSTextView?
    private var onChange: (() -> Void)?

    private var fontPopup: NSPopUpButton!
    private var sizeCombo: NSComboBox!
    private var boldBtn: NSButton!
    private var italicBtn: NSButton!
    private var underlineBtn: NSButton!
    private var colorWell: ColorButton!

    private static let sizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 96]

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 46),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = tr("文字")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        buildControls()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildControls() {
        guard let content = window?.contentView else { return }
        var x: CGFloat = 10
        let y: CGFloat = 10

        // 字型
        fontPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: 160, height: 25))
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        fontPopup.addItems(withTitles: families)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        content.addSubview(fontPopup)
        x += 168

        // 字級（可編輯）
        sizeCombo = NSComboBox(frame: NSRect(x: x, y: y, width: 62, height: 25))
        sizeCombo.addItems(withObjectValues: TextFormatPanel.sizes.map { "\($0)" })
        sizeCombo.completes = false
        sizeCombo.delegate = self
        sizeCombo.target = self
        sizeCombo.action = #selector(sizeChanged)
        content.addSubview(sizeCombo)
        x += 70

        // 粗體 / 斜體 / 底線
        boldBtn = toggle("B", bold: true);      boldBtn.frame = NSRect(x: x, y: y, width: 30, height: 25); x += 33
        italicBtn = toggle("I", italic: true);  italicBtn.frame = NSRect(x: x, y: y, width: 30, height: 25); x += 33
        underlineBtn = toggle("U", underline: true); underlineBtn.frame = NSRect(x: x, y: y, width: 30, height: 25); x += 40
        boldBtn.action = #selector(traitChanged); italicBtn.action = #selector(traitChanged); underlineBtn.action = #selector(traitChanged)
        boldBtn.target = self; italicBtn.target = self; underlineBtn.target = self
        [boldBtn, italicBtn, underlineBtn].forEach { content.addSubview($0) }

        // 顏色
        let cl = NSTextField(labelWithString: tr("色彩"))
        cl.font = NSFont.systemFont(ofSize: 11); cl.frame = NSRect(x: x, y: y + 3, width: 34, height: 18); x += 36
        content.addSubview(cl)
        colorWell = ColorButton(frame: NSRect(x: x, y: y, width: 28, height: 25))
        colorWell.onClick = { [weak self] in self?.pickColor() }
        content.addSubview(colorWell)
    }

    private func toggle(_ title: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .rounded
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        var f = NSFont.systemFont(ofSize: 13)
        if bold { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
        if italic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
        let attrs: [NSAttributedString.Key: Any] = underline
            ? [.font: f, .underlineStyle: NSUnderlineStyle.single.rawValue]
            : [.font: f]
        b.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        return b
    }

    // MARK: - 顯示 / 隱藏

    func show(for tv: NSTextView, near screenPoint: NSPoint, onChange: @escaping () -> Void) {
        target = tv
        self.onChange = onChange
        syncControlsFromState()
        if let w = window {
            // 置於文字點上方，避免遮住輸入
            var p = NSPoint(x: screenPoint.x, y: screenPoint.y + 70)
            if let scr = NSScreen.main {
                p.x = min(p.x, scr.visibleFrame.maxX - w.frame.width - 10)
                p.x = max(p.x, scr.visibleFrame.minX + 10)
                p.y = min(p.y, scr.visibleFrame.maxY - 10)
            }
            w.setFrameTopLeftPoint(p)
        }
        showWindow(nil)
        apply()
    }
    func hide() {
        window?.orderOut(nil)
        target = nil
        onChange = nil
    }
    var isShowing: Bool { window?.isVisible ?? false }

    // MARK: - 控制項 → 狀態 → 套用

    private func syncControlsFromState() {
        let s = PaintState.shared
        if let i = fontPopup.itemTitles.firstIndex(where: { $0 == familyOf(s.textFontName) }) {
            fontPopup.selectItem(at: i)
        }
        sizeCombo.stringValue = "\(Int(s.textFontSize))"
        boldBtn.state = s.textBold ? .on : .off
        italicBtn.state = s.textItalic ? .on : .off
        underlineBtn.state = s.textUnderline ? .on : .off
        colorWell.color = s.color1
    }
    private func familyOf(_ fontName: String) -> String {
        NSFont(name: fontName, size: 12)?.familyName ?? fontName
    }

    @objc private func fontChanged() {
        if let fam = fontPopup.titleOfSelectedItem,
           let f = NSFontManager.shared.font(withFamily: fam, traits: [], weight: 5, size: PaintState.shared.textFontSize) {
            PaintState.shared.textFontName = f.fontName
        } else if let fam = fontPopup.titleOfSelectedItem {
            PaintState.shared.textFontName = fam
        }
        apply()
    }
    @objc private func sizeChanged() {
        let v = CGFloat(Int(sizeCombo.stringValue) ?? Int(PaintState.shared.textFontSize))
        PaintState.shared.textFontSize = max(4, min(400, v))
        apply()
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.sizeChanged() }
    }
    @objc private func traitChanged() {
        PaintState.shared.textBold = boldBtn.state == .on
        PaintState.shared.textItalic = italicBtn.state == .on
        PaintState.shared.textUnderline = underlineBtn.state == .on
        apply()
    }
    private func pickColor() {
        let cp = NSColorPanel.shared
        cp.color = PaintState.shared.color1
        cp.setTarget(self)
        cp.setAction(#selector(colorPicked(_:)))
        cp.orderFront(nil)
    }
    @objc private func colorPicked(_ panel: NSColorPanel) {
        PaintState.shared.color1 = panel.color
        colorWell.color = panel.color
        NotificationCenter.default.post(name: PaintState.colorChanged, object: nil)
        apply()
    }

    /// 套用目前設定到編輯中的文字。
    func apply() {
        guard let tv = target else { return }
        let font = PaintState.shared.currentTextFont()
        let color = PaintState.shared.color1
        let range = NSRange(location: 0, length: (tv.string as NSString).length)
        if let ts = tv.textStorage {
            ts.beginEditing()
            ts.addAttribute(.font, value: font, range: range)
            ts.addAttribute(.foregroundColor, value: color, range: range)
            if PaintState.shared.textUnderline {
                ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                ts.removeAttribute(.underlineStyle, range: range)
            }
            ts.endEditing()
        }
        tv.font = font
        tv.textColor = color
        var ta = tv.typingAttributes
        ta[.font] = font
        ta[.foregroundColor] = color
        ta[.underlineStyle] = PaintState.shared.textUnderline ? NSUnderlineStyle.single.rawValue : 0
        tv.typingAttributes = ta
        colorWell.color = color
        onChange?()
    }
}

/// 顯示色塊、可點擊的小按鈕。
final class ColorButton: NSView {
    var color: NSColor = .black { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        color.setFill(); NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)).fill()
        NSColor.darkGray.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)).stroke()
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
