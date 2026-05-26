import AppKit

/// Ribbon (頂部工具列)。模仿 Windows 7/10 Paint 的 ribbon。
final class RibbonView: NSView {

    // Outlets we need to keep
    private var color1Well: ColorSwatchView!
    private var color2Well: ColorSwatchView!
    private var paletteCells: [PaletteCellView] = []
    private var toolButtons: [Tool: NSButton] = [:]
    private var shapeButtons: [ShapeKind: NSButton] = [:]
    private var brushButtons: [BrushKind: NSButton] = [:]
    private var sizeButtons: [CGFloat: NSButton] = [:]
    private var outlineMenu: NSPopUpButton!
    private var fillMenu: NSPopUpButton!
    private var selectionShapeMenu: NSPopUpButton!

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 110))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1).cgColor
        buildLayout()
        observeState()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func observeState() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refreshHighlights), name: PaintState.toolChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshColors), name: PaintState.colorChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshHighlights), name: PaintState.shapeChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshHighlights), name: PaintState.brushChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshHighlights), name: PaintState.sizeChanged, object: nil)
    }

    private func buildLayout() {
        var x: CGFloat = 6

        x = buildClipboardGroup(x: x); x = drawSeparator(x: x)
        x = buildImageGroup(x: x); x = drawSeparator(x: x)
        x = buildToolsGroup(x: x); x = drawSeparator(x: x)
        x = buildBrushesGroup(x: x); x = drawSeparator(x: x)
        x = buildShapesGroup(x: x); x = drawSeparator(x: x)
        x = buildSizeGroup(x: x); x = drawSeparator(x: x)
        x = buildColorsGroup(x: x)

        let needed = x + 12
        if needed > frame.width {
            setFrameSize(NSSize(width: needed, height: frame.height))
        }
    }

    @discardableResult
    private func drawSeparator(x: CGFloat) -> CGFloat {
        let v = NSBox(frame: NSRect(x: x, y: 4, width: 1, height: 92))
        v.boxType = .separator
        addSubview(v)
        return x + 6
    }

    // MARK: - Groups

    private func buildClipboardGroup(x: CGFloat) -> CGFloat {
        var x = x
        let paste = makeBigButton(title: "貼上", icon: "📋", x: x) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.paste), with: nil)
        }
        addSubview(paste)
        x += 56
        let cut = makeSmallButton(title: "剪下", icon: "✂", y: 4) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.cut), with: nil)
        }
        cut.frame.origin.x = x
        addSubview(cut)
        let copy = makeSmallButton(title: "複製", icon: "📑", y: 28) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.copy), with: nil)
        }
        copy.frame.origin.x = x
        addSubview(copy)
        addGroupLabel("剪貼簿", x: x - 56, w: 120)
        return x + 70
    }

    private func buildImageGroup(x: CGFloat) -> CGFloat {
        var x = x
        // Select dropdown big button
        let sel = makeBigButton(title: "選取 ▾", icon: "▭", x: x) { [weak self] sender in
            self?.showSelectMenu(from: sender)
        }
        toolButtons[.selectRect] = sel
        toolButtons[.selectFree] = sel
        addSubview(sel)
        x += 56

        let crop = makeSmallButton(title: "裁剪", icon: "✂", y: 4) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.cropImage), with: nil)
        }; crop.frame.origin.x = x; addSubview(crop)

        let resize = makeSmallButton(title: "重新調整大小", icon: "⤢", y: 28) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.resizeImage), with: nil)
        }; resize.frame.origin.x = x; addSubview(resize)

        let rotate = makeSmallButton(title: "旋轉 ▾", icon: "⟳", y: 52) { [weak self] sender in
            self?.showRotateMenu(from: sender)
        }; rotate.frame.origin.x = x; addSubview(rotate)

        addGroupLabel("影像", x: x - 56, w: 200)
        return x + 130
    }

    private func buildToolsGroup(x: CGFloat) -> CGFloat {
        // 3 cols x 2 rows of small tool buttons
        let icons: [(Tool, String, String)] = [
            (.pencil,    "鉛筆", "✏️"),
            (.fill,      "以色彩填滿", "🪣"),
            (.text,      "文字", "𝐀"),
            (.eraser,    "橡皮擦", "🧽"),
            (.picker,    "色彩選擇工具", "💧"),
            (.magnifier, "放大鏡", "🔍"),
        ]
        let gridX = x
        for (i, info) in icons.enumerated() {
            let col = i % 3, row = i / 3
            let btn = makeToolButton(icon: info.2, tooltip: info.1, tool: info.0)
            btn.frame = NSRect(x: gridX + CGFloat(col) * 28, y: 6 + CGFloat(row) * 28, width: 26, height: 26)
            addSubview(btn)
            toolButtons[info.0] = btn
        }
        addGroupLabel("工具", x: gridX, w: 90)
        return gridX + 86
    }

    private func buildBrushesGroup(x: CGFloat) -> CGFloat {
        let big = makeBigButton(title: "筆刷 ▾", icon: "🖌", x: x) { [weak self] sender in
            self?.showBrushMenu(from: sender)
        }
        addSubview(big)
        addGroupLabel("筆刷", x: x, w: 56)
        return x + 60
    }

    private func buildShapesGroup(x: CGFloat) -> CGFloat {
        // Shapes grid (12 cols, 2 rows) of 22x22 buttons
        let kinds: [(ShapeKind, String, String)] = [
            (.line, "線條", "╱"), (.curve, "曲線", "∿"),
            (.ellipse, "橢圓形", "◯"), (.rect, "矩形", "▭"),
            (.roundedRect, "圓角矩形", "▢"), (.polygon, "多邊形", "⬠"),
            (.triangle, "三角形", "△"), (.rightTriangle, "直角三角形", "◣"),
            (.diamond, "菱形", "◇"), (.pentagon, "五邊形", "⬠"),
            (.hexagon, "六邊形", "⬡"),
            (.arrowRight, "右箭頭", "→"), (.arrowLeft, "左箭頭", "←"),
            (.arrowUp, "上箭頭", "↑"), (.arrowDown, "下箭頭", "↓"),
            (.star4, "四角星", "✦"), (.star5, "五角星", "★"), (.star6, "六角星", "✶"),
            (.calloutRect, "矩形圖說文字", "💬"), (.calloutEllipse, "橢圓形圖說文字", "🗨"),
            (.calloutCloud, "雲朵圖說文字", "☁"),
            (.heart, "愛心", "♥"), (.lightning, "閃電", "⚡"),
        ]
        let cols = 12
        for (i, info) in kinds.enumerated() {
            let col = i % cols, row = i / cols
            let btn = NSButton(frame: NSRect(x: x + CGFloat(col) * 22, y: 4 + CGFloat(row) * 22, width: 22, height: 22))
            btn.bezelStyle = .smallSquare
            btn.isBordered = false
            btn.title = info.2
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.toolTip = info.1
            btn.target = self
            btn.action = #selector(shapeClicked(_:))
            btn.tag = i
            addSubview(btn)
            shapeButtons[info.0] = btn
        }

        // Outline / Fill dropdowns
        outlineMenu = NSPopUpButton(frame: NSRect(x: x, y: 50, width: 100, height: 22))
        outlineMenu.addItem(withTitle: "外框: 純色")
        outlineMenu.addItem(withTitle: "外框: 無外框")
        outlineMenu.target = self
        outlineMenu.action = #selector(outlineChanged(_:))
        addSubview(outlineMenu)

        fillMenu = NSPopUpButton(frame: NSRect(x: x + 104, y: 50, width: 100, height: 22))
        fillMenu.addItem(withTitle: "填滿: 無填滿")
        fillMenu.addItem(withTitle: "填滿: 純色")
        fillMenu.target = self
        fillMenu.action = #selector(fillChanged(_:))
        addSubview(fillMenu)

        addGroupLabel("圖案", x: x, w: 264)
        return x + 268
    }

    private func buildSizeGroup(x: CGFloat) -> CGFloat {
        let big = makeBigButton(title: "大小 ▾", icon: "≡", x: x) { [weak self] sender in
            self?.showSizeMenu(from: sender)
        }
        addSubview(big)
        addGroupLabel("大小", x: x, w: 56)
        return x + 60
    }

    private func buildColorsGroup(x: CGFloat) -> CGFloat {
        // Color 1 & Color 2 swatches
        var x = x
        color1Well = ColorSwatchView(label: "色彩 1", color: PaintState.shared.color1, isSecondary: false)
        color1Well.frame = NSRect(x: x, y: 4, width: 40, height: 60)
        color1Well.onClick = { [weak self] in self?.activateSwatch(secondary: false) }
        addSubview(color1Well)
        x += 42

        color2Well = ColorSwatchView(label: "色彩 2", color: PaintState.shared.color2, isSecondary: true)
        color2Well.frame = NSRect(x: x, y: 4, width: 40, height: 60)
        color2Well.onClick = { [weak self] in self?.activateSwatch(secondary: true) }
        addSubview(color2Well)
        x += 50

        // Palette 10x2
        let cellSize: CGFloat = 16
        let cols = 10
        for (i, color) in Palette.standard.enumerated() {
            let col = i % cols, row = i / cols
            let cell = PaletteCellView(color: color)
            cell.frame = NSRect(x: x + CGFloat(col) * (cellSize + 1), y: 4 + CGFloat(row) * (cellSize + 1), width: cellSize, height: cellSize)
            cell.onClick = { [weak self] secondary in
                if secondary { PaintState.shared.color2 = color } else { PaintState.shared.color1 = color }
                NotificationCenter.default.post(name: PaintState.colorChanged, object: nil)
            }
            paletteCells.append(cell)
            addSubview(cell)
        }
        x += CGFloat(cols) * (cellSize + 1) + 8

        // Edit colors big button
        let editBtn = makeBigButton(title: "編輯色彩", icon: "🎨", x: x) { [weak self] _ in
            self?.openColorPicker()
        }
        addSubview(editBtn)
        x += 56

        addGroupLabel("色彩", x: x - 250, w: 250)
        return x + 6
    }

    // MARK: - Button factories

    private func makeBigButton(title: String, icon: String, x: CGFloat, action: @escaping (NSButton) -> Void) -> NSButton {
        let btn = ActionButton(frame: NSRect(x: x, y: 4, width: 54, height: 72))
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.title = ""
        btn.action = #selector(ActionButton.fire(_:))
        btn.target = btn
        btn.handler = action
        // We'll render content via a custom view
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        let iconLbl = NSTextField(labelWithString: icon)
        iconLbl.font = NSFont.systemFont(ofSize: 26)
        iconLbl.alignment = .center
        iconLbl.isBordered = false
        iconLbl.drawsBackground = false
        iconLbl.isEditable = false
        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font = NSFont.systemFont(ofSize: 10)
        titleLbl.alignment = .center
        titleLbl.isBordered = false
        titleLbl.drawsBackground = false
        titleLbl.isEditable = false
        stack.addArrangedSubview(iconLbl)
        stack.addArrangedSubview(titleLbl)
        stack.frame = btn.bounds
        stack.translatesAutoresizingMaskIntoConstraints = false
        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: btn.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: btn.trailingAnchor),
            stack.topAnchor.constraint(equalTo: btn.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: btn.bottomAnchor, constant: -4),
        ])
        return btn
    }

    private func makeSmallButton(title: String, icon: String, y: CGFloat, action: @escaping (NSButton) -> Void) -> NSButton {
        let btn = ActionButton(frame: NSRect(x: 0, y: y, width: 110, height: 22))
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.title = "\(icon)  \(title)"
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.alignment = .left
        btn.target = btn
        btn.action = #selector(ActionButton.fire(_:))
        btn.handler = action
        return btn
    }

    private func makeToolButton(icon: String, tooltip: String, tool: Tool) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.title = icon
        btn.font = NSFont.systemFont(ofSize: 14)
        btn.toolTip = tooltip
        btn.target = self
        btn.action = #selector(toolClicked(_:))
        btn.tag = Tool.allCases.firstIndex(of: tool) ?? 0
        return btn
    }

    private func addGroupLabel(_ s: String, x: CGFloat, w: CGFloat) {
        let lbl = NSTextField(labelWithString: s)
        lbl.font = NSFont.systemFont(ofSize: 10)
        lbl.alignment = .center
        lbl.textColor = .secondaryLabelColor
        lbl.frame = NSRect(x: x, y: 90, width: w, height: 16)
        addSubview(lbl)
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        let tool = Tool.allCases[sender.tag]
        PaintState.shared.tool = tool
        if tool != .text && tool != .picker && tool != .magnifier
            && tool != .selectRect && tool != .selectFree {
            PaintState.shared.previousDrawingTool = tool
        }
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }

    @objc private func shapeClicked(_ sender: NSButton) {
        let kinds: [ShapeKind] = [
            .line, .curve, .ellipse, .rect, .roundedRect, .polygon,
            .triangle, .rightTriangle, .diamond, .pentagon, .hexagon,
            .arrowRight, .arrowLeft, .arrowUp, .arrowDown,
            .star4, .star5, .star6,
            .calloutRect, .calloutEllipse, .calloutCloud,
            .heart, .lightning
        ]
        guard sender.tag < kinds.count else { return }
        PaintState.shared.shapeKind = kinds[sender.tag]
        PaintState.shared.tool = .shape
        NotificationCenter.default.post(name: PaintState.shapeChanged, object: nil)
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }

    @objc private func outlineChanged(_ sender: NSPopUpButton) {
        PaintState.shared.outlineStyle = sender.indexOfSelectedItem == 0 ? .solid : FillStyle.none
    }
    @objc private func fillChanged(_ sender: NSPopUpButton) {
        PaintState.shared.fillStyle = sender.indexOfSelectedItem == 0 ? FillStyle.none : .solid
    }

    private func showRotateMenu(from sender: NSButton) {
        let m = NSMenu()
        m.addItem(withTitle: "向右旋轉 90°",  action: #selector(MainWindowController.rotateRight), keyEquivalent: "")
        m.addItem(withTitle: "向左旋轉 90°",  action: #selector(MainWindowController.rotateLeft),  keyEquivalent: "")
        m.addItem(withTitle: "旋轉 180°",     action: #selector(MainWindowController.rotate180),   keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "水平翻轉",      action: #selector(MainWindowController.flipHorizontal), keyEquivalent: "")
        m.addItem(withTitle: "垂直翻轉",      action: #selector(MainWindowController.flipVertical),   keyEquivalent: "")
        for item in m.items { item.target = window?.windowController }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }

    private func showSelectMenu(from sender: NSButton) {
        let m = NSMenu()
        m.addItem(withTitle: "矩形選取",   action: #selector(setSelectRect),  keyEquivalent: "")
        m.addItem(withTitle: "任意形狀選取", action: #selector(setSelectFree), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "全選",       action: #selector(MainWindowController.selectAll), keyEquivalent: "")
        for item in m.items where item.action == #selector(MainWindowController.selectAll) {
            item.target = window?.windowController
        }
        for item in m.items where item.target == nil { item.target = self }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }
    @objc private func setSelectRect() {
        PaintState.shared.selectionShape = .rectangle
        PaintState.shared.tool = .selectRect
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }
    @objc private func setSelectFree() {
        PaintState.shared.selectionShape = .freeform
        PaintState.shared.tool = .selectFree
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }

    private func showBrushMenu(from sender: NSButton) {
        let m = NSMenu()
        let names: [(BrushKind, String)] = [
            (.round, "筆刷"), (.calligraphy1, "書法筆 1"), (.calligraphy2, "書法筆 2"),
            (.airbrush, "噴槍"), (.oil, "油畫筆刷"), (.crayon, "蠟筆"),
            (.marker, "麥克筆"), (.naturalPencil, "自然鉛筆"), (.watercolour, "水彩筆刷")
        ]
        for (kind, title) in names {
            let item = NSMenuItem(title: title, action: #selector(brushChosen(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.target = self
            m.addItem(item)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }
    @objc private func brushChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let k = BrushKind(rawValue: raw) else { return }
        PaintState.shared.brushKind = k
        PaintState.shared.tool = .brush
        PaintState.shared.previousDrawingTool = .brush
        NotificationCenter.default.post(name: PaintState.brushChanged, object: nil)
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }

    private func showSizeMenu(from sender: NSButton) {
        let m = NSMenu()
        for (i, s) in [CGFloat(1), 3, 5, 8].enumerated() {
            let item = NSMenuItem(title: String(repeating: "▬", count: i + 1), action: #selector(sizeChosen(_:)), keyEquivalent: "")
            item.tag = Int(s)
            item.target = self
            m.addItem(item)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }
    @objc private func sizeChosen(_ sender: NSMenuItem) {
        PaintState.shared.strokeSize = CGFloat(sender.tag)
        NotificationCenter.default.post(name: PaintState.sizeChanged, object: nil)
    }

    private func activateSwatch(secondary: Bool) {
        color1Well.isActive = !secondary
        color2Well.isActive = secondary
        color1Well.needsDisplay = true
        color2Well.needsDisplay = true
    }

    private func openColorPicker() {
        guard let win = window else { return }
        ColorPickerDialog.run(in: win, initial: PaintState.shared.color1) { color in
            guard let color = color else { return }
            PaintState.shared.color1 = color
            if !PaintState.shared.customPalette.contains(where: { $0.isEqualRGB(color) }) {
                PaintState.shared.customPalette.append(color)
            }
            NotificationCenter.default.post(name: PaintState.colorChanged, object: nil)
        }
    }

    // MARK: - Refresh

    @objc private func refreshHighlights() {
        for (tool, btn) in toolButtons {
            let on = PaintState.shared.tool == tool
                || (tool == .selectRect && (PaintState.shared.tool == .selectFree))
            btn.layer?.backgroundColor = on
                ? NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1).cgColor
                : NSColor.clear.cgColor
            btn.wantsLayer = true
        }
        for (kind, btn) in shapeButtons {
            let on = (PaintState.shared.tool == .shape && PaintState.shared.shapeKind == kind)
            btn.layer?.backgroundColor = on
                ? NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1).cgColor
                : NSColor.clear.cgColor
            btn.wantsLayer = true
        }
    }

    @objc private func refreshColors() {
        color1Well.color = PaintState.shared.color1
        color2Well.color = PaintState.shared.color2
        color1Well.needsDisplay = true
        color2Well.needsDisplay = true
    }
}

// MARK: - Buttons & swatches

final class ActionButton: NSButton {
    var handler: ((NSButton) -> Void)?
    @objc func fire(_ sender: Any?) { handler?(self) }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || isMouseOver {
            NSColor(red: 1, green: 0.9, blue: 0.6, alpha: 0.6).setFill()
            NSBezierPath(rect: bounds).fill()
        }
        super.draw(dirtyRect)
    }

    private var isMouseOver = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(ta)
    }
    override func mouseEntered(with event: NSEvent) { isMouseOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isMouseOver = false; needsDisplay = true }
}

final class ColorSwatchView: NSView {
    var color: NSColor
    var isActive: Bool
    let label: String
    let isSecondary: Bool
    var onClick: (() -> Void)?

    init(label: String, color: NSColor, isSecondary: Bool) {
        self.color = color
        self.label = label
        self.isSecondary = isSecondary
        self.isActive = !isSecondary
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1).setFill()
            NSBezierPath(rect: bounds).fill()
        }
        let swatch = NSRect(x: bounds.midX - 14, y: bounds.maxY - 28, width: 28, height: 18)
        color.setFill()
        NSBezierPath(rect: swatch).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: swatch).stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor
        ]
        (label as NSString).draw(at: NSPoint(x: 4, y: 2), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

final class PaletteCellView: NSView {
    var color: NSColor
    var onClick: ((Bool) -> Void)?
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor.darkGray.setStroke()
        NSBezierPath(rect: bounds).stroke()
    }
    override func mouseDown(with event: NSEvent)       { onClick?(false) }
    override func rightMouseDown(with event: NSEvent)  { onClick?(true) }
}

// MARK: - NSColor RGB compare

extension NSColor {
    func isEqualRGB(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.deviceRGB), let b = other.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
