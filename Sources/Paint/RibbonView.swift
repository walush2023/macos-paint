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

    private var currentTab: Tab = .home
    enum Tab { case home, view }

    // MARK: - Layout constants (統一對齊用)
    private let topPad: CGFloat = 6      // 內容區上緣
    private let bandH: CGFloat  = 72     // 內容區高度 (大按鈕高度)
    private var labelY: CGFloat { topPad + bandH + 4 }   // 群組標籤 y (=82)
    private var bandBottom: CGFloat { topPad + bandH }   // 內容區下緣 (=78)
    /// 在內容帶中，把高度 h 的元件垂直置中時的頂端 y。
    private func centeredY(_ h: CGFloat) -> CGFloat { topPad + (bandH - h) / 2 }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 110))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1).cgColor
        showHomeTab()
        observeState()
    }
    required init?(coder: NSCoder) { fatalError() }

    func showHomeTab() {
        currentTab = .home
        subviews.forEach { $0.removeFromSuperview() }
        toolButtons.removeAll(); shapeButtons.removeAll()
        brushButtons.removeAll(); sizeButtons.removeAll()
        paletteCells.removeAll()
        buildLayout()
        refreshHighlights()
        refreshColors()
    }

    func showViewTab() {
        currentTab = .view
        subviews.forEach { $0.removeFromSuperview() }
        toolButtons.removeAll(); shapeButtons.removeAll()
        brushButtons.removeAll(); sizeButtons.removeAll()
        paletteCells.removeAll()
        buildViewTabLayout()
    }

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

    private func buildViewTabLayout() {
        var x: CGFloat = 6
        x = buildZoomGroup(x: x); x = drawSeparator(x: x)
        x = buildShowHideGroup(x: x); x = drawSeparator(x: x)
        _ = buildDisplayGroup(x: x)
    }

    private func buildZoomGroup(x: CGFloat) -> CGFloat {
        let zoomIn = makeBigButton(title: "放大", icon: "🔍+", x: x) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.zoomIn(_:)), with: nil)
        }
        addSubview(zoomIn)
        let zoomOut = makeBigButton(title: "縮小", icon: "🔍−", x: x + 58) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.zoomOut(_:)), with: nil)
        }
        addSubview(zoomOut)
        let zoom100 = makeBigButton(title: "100%", icon: "💯", x: x + 116) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.zoom100(_:)), with: nil)
        }
        addSubview(zoom100)
        addGroupLabel("縮放", x: x, w: 170)
        return x + 174 + 4
    }

    private func buildShowHideGroup(x: CGFloat) -> CGFloat {
        let rowH: CGFloat = 24
        let topY = centeredY(rowH * 3)
        let rulers = NSButton(checkboxWithTitle: "尺規", target: self, action: #selector(toggleRulersBox(_:)))
        rulers.state = PaintState.shared.showRulers ? .on : .off
        rulers.frame = NSRect(x: x, y: topY, width: 110, height: 22)
        addSubview(rulers)
        let grid = NSButton(checkboxWithTitle: "格線", target: self, action: #selector(toggleGridBox(_:)))
        grid.state = PaintState.shared.showGridlines ? .on : .off
        grid.frame = NSRect(x: x, y: topY + rowH, width: 110, height: 22)
        addSubview(grid)
        let status = NSButton(checkboxWithTitle: "狀態列", target: self, action: #selector(toggleStatusBox(_:)))
        status.state = PaintState.shared.showStatusBar ? .on : .off
        status.frame = NSRect(x: x, y: topY + rowH * 2, width: 110, height: 22)
        addSubview(status)
        addGroupLabel("顯示或隱藏", x: x, w: 110)
        return x + 114
    }

    private func buildDisplayGroup(x: CGFloat) -> CGFloat {
        let fs = makeBigButton(title: "全螢幕", icon: "⛶", x: x) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.toggleFullScreen(_:)), with: nil)
        }
        addSubview(fs)
        addGroupLabel("顯示", x: x, w: 54)
        return x + 58
    }

    @objc private func toggleRulersBox(_ sender: NSButton) {
        PaintState.shared.showRulers = (sender.state == .on)
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc private func toggleGridBox(_ sender: NSButton) {
        PaintState.shared.showGridlines = (sender.state == .on)
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc private func toggleStatusBox(_ sender: NSButton) {
        PaintState.shared.showStatusBar = (sender.state == .on)
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }

    @discardableResult
    private func drawSeparator(x: CGFloat) -> CGFloat {
        let v = NSBox(frame: NSRect(x: x, y: topPad, width: 1, height: bandH + 4))
        v.boxType = .separator
        addSubview(v)
        return x + 8
    }

    // MARK: - Groups

    private func buildClipboardGroup(x: CGFloat) -> CGFloat {
        let startX = x
        var x = x
        let paste = makeBigButton(title: "貼上", icon: "📋", x: x) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(Selector("paste:"), with: nil)
        }
        addSubview(paste)
        x += 58
        // 剪下 / 複製：兩列垂直置中
        let rowH: CGFloat = 24, smallW: CGFloat = 70
        let topY = centeredY(rowH * 2)
        let cut = makeSmallButton(title: "剪下", icon: "✂", y: topY, width: smallW) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(Selector("cut:"), with: nil)
        }
        cut.frame.origin.x = x; addSubview(cut)
        let copy = makeSmallButton(title: "複製", icon: "📑", y: topY + rowH, width: smallW) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(Selector("copy:"), with: nil)
        }
        copy.frame.origin.x = x; addSubview(copy)
        x += smallW
        addGroupLabel("剪貼簿", x: startX, w: x - startX)
        return x + 4
    }

    private func buildImageGroup(x: CGFloat) -> CGFloat {
        let startX = x
        var x = x
        let sel = makeBigButton(title: "選取 ▾", icon: "▭", x: x) { [weak self] sender in
            self?.showSelectMenu(from: sender)
        }
        toolButtons[.selectRect] = sel
        toolButtons[.selectFree] = sel
        addSubview(sel)
        x += 58

        // 裁剪 / 重新調整大小 / 旋轉：三列垂直置中
        let rowH: CGFloat = 24, smallW: CGFloat = 124
        let topY = centeredY(rowH * 3)
        let crop = makeSmallButton(title: "裁剪", icon: "✂", y: topY, width: smallW) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.cropImage(_:)), with: nil)
        }; crop.frame.origin.x = x; addSubview(crop)
        let resize = makeSmallButton(title: "重新調整大小", icon: "⤢", y: topY + rowH, width: smallW) { [weak self] _ in
            self?.window?.windowController?.tryToPerform(#selector(MainWindowController.resizeImage(_:)), with: nil)
        }; resize.frame.origin.x = x; addSubview(resize)
        let rotate = makeSmallButton(title: "旋轉 ▾", icon: "⟳", y: topY + rowH * 2, width: smallW) { [weak self] sender in
            self?.showRotateMenu(from: sender)
        }; rotate.frame.origin.x = x; addSubview(rotate)
        x += smallW

        addGroupLabel("影像", x: startX, w: x - startX)
        return x + 4
    }

    private func buildToolsGroup(x: CGFloat) -> CGFloat {
        // 3 cols x 2 rows，整組垂直/水平置中
        let icons: [(Tool, String, String)] = [
            (.pencil,    "鉛筆", "✏️"),
            (.fill,      "以色彩填滿", "🪣"),
            (.text,      "文字", "𝐀"),
            (.eraser,    "橡皮擦", "🧽"),
            (.picker,    "色彩選擇工具", "💧"),
            (.magnifier, "放大鏡", "🔍"),
        ]
        let cell: CGFloat = 28, btnSize: CGFloat = 26
        let gridW = cell * 3
        let gridH = cell * 2
        let gridX = x
        let topY = centeredY(gridH)
        for (i, info) in icons.enumerated() {
            let col = i % 3, row = i / 3
            let btn = makeToolButton(icon: info.2, tooltip: info.1, tool: info.0)
            btn.frame = NSRect(
                x: gridX + CGFloat(col) * cell + (cell - btnSize) / 2,
                y: topY + CGFloat(row) * cell + (cell - btnSize) / 2,
                width: btnSize, height: btnSize
            )
            addSubview(btn)
            toolButtons[info.0] = btn
        }
        addGroupLabel("工具", x: gridX, w: gridW)
        return gridX + gridW + 4
    }

    private func buildBrushesGroup(x: CGFloat) -> CGFloat {
        let big = makeBigButton(title: "筆刷 ▾", icon: "🖌", x: x) { [weak self] sender in
            self?.showBrushMenu(from: sender)
        }
        addSubview(big)
        addGroupLabel("筆刷", x: x, w: 54)
        return x + 58
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
        let shapeCell: CGFloat = 23
        let gridW = shapeCell * CGFloat(cols)
        let gridH = shapeCell * 2
        let dropH: CGFloat = 22
        // 形狀格 + 兩個下拉，整體垂直置中
        let blockH = gridH + 4 + dropH
        let topY = centeredY(blockH)
        for (i, info) in kinds.enumerated() {
            let col = i % cols, row = i / cols
            let btn = NSButton(frame: NSRect(
                x: x + CGFloat(col) * shapeCell,
                y: topY + CGFloat(row) * shapeCell,
                width: shapeCell, height: shapeCell))
            btn.bezelStyle = .smallSquare
            btn.isBordered = false
            btn.title = info.2
            btn.font = NSFont.systemFont(ofSize: 12)
            btn.toolTip = info.1
            btn.target = self
            btn.action = #selector(shapeClicked(_:))
            btn.tag = i
            addSubview(btn)
            shapeButtons[info.0] = btn
        }

        // Outline / Fill dropdowns（並排於形狀格下方）
        let dropY = topY + gridH + 4
        let dropW = (gridW - 4) / 2
        outlineMenu = NSPopUpButton(frame: NSRect(x: x, y: dropY, width: dropW, height: dropH))
        outlineMenu.addItem(withTitle: "外框: 純色")
        outlineMenu.addItem(withTitle: "外框: 無外框")
        outlineMenu.target = self
        outlineMenu.action = #selector(outlineChanged(_:))
        addSubview(outlineMenu)

        fillMenu = NSPopUpButton(frame: NSRect(x: x + dropW + 4, y: dropY, width: dropW, height: dropH))
        fillMenu.addItem(withTitle: "填滿: 無填滿")
        fillMenu.addItem(withTitle: "填滿: 純色")
        fillMenu.target = self
        fillMenu.action = #selector(fillChanged(_:))
        addSubview(fillMenu)

        addGroupLabel("圖案", x: x, w: gridW)
        return x + gridW + 4
    }

    private func buildSizeGroup(x: CGFloat) -> CGFloat {
        let big = makeBigButton(title: "大小 ▾", icon: "≡", x: x) { [weak self] sender in
            self?.showSizeMenu(from: sender)
        }
        addSubview(big)
        addGroupLabel("大小", x: x, w: 54)
        return x + 58
    }

    private func buildColorsGroup(x: CGFloat) -> CGFloat {
        let startX = x
        var x = x
        // 色彩 1 / 色彩 2 swatches（垂直置中）
        let swatchH: CGFloat = 60
        let swatchY = centeredY(swatchH)
        color1Well = ColorSwatchView(label: "色彩 1", color: PaintState.shared.color1, isSecondary: false)
        color1Well.frame = NSRect(x: x, y: swatchY, width: 40, height: swatchH)
        color1Well.onClick = { [weak self] in self?.activateSwatch(secondary: false) }
        addSubview(color1Well)
        x += 44

        color2Well = ColorSwatchView(label: "色彩 2", color: PaintState.shared.color2, isSecondary: true)
        color2Well.frame = NSRect(x: x, y: swatchY, width: 40, height: swatchH)
        color2Well.onClick = { [weak self] in self?.activateSwatch(secondary: true) }
        addSubview(color2Well)
        x += 50

        // Palette 10x2（垂直置中）
        let cellSize: CGFloat = 16, cellGap: CGFloat = 1
        let cols = 10
        let paletteH = CGFloat(2) * cellSize + cellGap
        let paletteY = centeredY(paletteH)
        for (i, color) in Palette.standard.enumerated() {
            let col = i % cols, row = i / cols
            let cell = PaletteCellView(color: color)
            cell.frame = NSRect(
                x: x + CGFloat(col) * (cellSize + cellGap),
                y: paletteY + CGFloat(row) * (cellSize + cellGap),
                width: cellSize, height: cellSize)
            cell.onClick = { [weak self] secondary in
                if secondary { PaintState.shared.color2 = color } else { PaintState.shared.color1 = color }
                NotificationCenter.default.post(name: PaintState.colorChanged, object: nil)
            }
            paletteCells.append(cell)
            addSubview(cell)
        }
        x += CGFloat(cols) * (cellSize + cellGap) + 10

        // 編輯色彩大按鈕
        let editBtn = makeBigButton(title: "編輯色彩", icon: "🎨", x: x) { [weak self] _ in
            self?.openColorPicker()
        }
        addSubview(editBtn)
        x += 58

        addGroupLabel("色彩", x: startX, w: x - startX)
        return x + 4
    }

    // MARK: - Button factories

    private func makeBigButton(title: String, icon: String, x: CGFloat, action: @escaping (NSButton) -> Void) -> NSButton {
        let btn = ActionButton(frame: NSRect(x: x, y: topPad, width: 54, height: bandH))
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
        iconLbl.textColor = NSColor.black
        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font = NSFont.systemFont(ofSize: 11)
        titleLbl.alignment = .center
        titleLbl.isBordered = false
        titleLbl.drawsBackground = false
        titleLbl.isEditable = false
        titleLbl.textColor = NSColor.black
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

    private func makeSmallButton(title: String, icon: String, y: CGFloat, width: CGFloat = 110, action: @escaping (NSButton) -> Void) -> NSButton {
        let btn = ActionButton(frame: NSRect(x: 0, y: y, width: width, height: 22))
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.alignment = .left
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        btn.attributedTitle = NSAttributedString(
            string: "\(icon)  \(title)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
            ]
        )
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
        lbl.textColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        lbl.drawsBackground = false
        lbl.isBordered = false
        lbl.frame = NSRect(x: x, y: labelY, width: w, height: 14)
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
        m.addItem(withTitle: "向右旋轉 90°",  action: #selector(MainWindowController.rotateRight(_:)), keyEquivalent: "")
        m.addItem(withTitle: "向左旋轉 90°",  action: #selector(MainWindowController.rotateLeft(_:)),  keyEquivalent: "")
        m.addItem(withTitle: "旋轉 180°",     action: #selector(MainWindowController.rotate180(_:)),   keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "水平翻轉",      action: #selector(MainWindowController.flipHorizontal(_:)), keyEquivalent: "")
        m.addItem(withTitle: "垂直翻轉",      action: #selector(MainWindowController.flipVertical(_:)),   keyEquivalent: "")
        for item in m.items { item.target = window?.windowController }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }

    private func showSelectMenu(from sender: NSButton) {
        let m = NSMenu()
        m.addItem(withTitle: "矩形選取",   action: #selector(setSelectRect),  keyEquivalent: "")
        m.addItem(withTitle: "任意形狀選取", action: #selector(setSelectFree), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "全選",       action: Selector("selectAll:"), keyEquivalent: "")
        for item in m.items where item.action == Selector("selectAll:") {
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
            .foregroundColor: NSColor.black
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
