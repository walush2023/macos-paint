import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController {
    let canvas = CanvasView(size: NSSize(width: 800, height: 600))
    let ribbon = RibbonView()
    let statusBar = StatusBarView()
    let scrollView = NSScrollView()
    let tabBar = TabBarView()
    var currentFileURL: URL?
    var isDirty: Bool = false

    private let tabBarHeight: CGFloat = 28
    private let ribbonHeight: CGFloat = 110
    private let statusBarHeight: CGFloat = 24

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "未命名 - 小畫家"
        win.minSize = NSSize(width: 800, height: 500)
        // 強制使用淺色外觀以對齊 Windows 小畫家視覺、避免深色模式下標籤變白看不清
        win.appearance = NSAppearance(named: .aqua)
        super.init(window: win)
        buildLayout()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleZoomChanged), name: PaintState.zoomChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleCanvasResized), name: PaintState.canvasResized, object: nil)
        nc.addObserver(self, selector: #selector(handleViewChanged), name: PaintState.viewChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleStatusUpdate(_:)), name: PaintState.statusUpdate, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        guard let win = window else { return }
        let content = NSView(frame: win.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        win.contentView = content

        let h = content.bounds.height

        // 上方 tab bar
        tabBar.frame = NSRect(x: 0, y: h - tabBarHeight, width: content.bounds.width, height: tabBarHeight)
        tabBar.autoresizingMask = [.width, .minYMargin]
        tabBar.onTabSelected = { [weak self] tab in self?.selectTab(tab) }
        tabBar.onFileMenu = { [weak self] in self?.showFileMenu() }
        content.addSubview(tabBar)

        // ribbon 位於 tab bar 下方
        ribbon.frame = NSRect(x: 0, y: h - tabBarHeight - ribbonHeight,
                              width: content.bounds.width, height: ribbonHeight)
        ribbon.autoresizingMask = [.width, .minYMargin]
        content.addSubview(ribbon)

        // 狀態列
        statusBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: statusBarHeight)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(statusBar)

        // 工作區
        scrollView.frame = NSRect(
            x: 0, y: statusBarHeight,
            width: content.bounds.width,
            height: h - tabBarHeight - ribbonHeight - statusBarHeight
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = NSColor(calibratedRed: 0.6, green: 0.74, blue: 0.93, alpha: 1)
        scrollView.drawsBackground = true
        content.addSubview(scrollView)

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: max(840, scrollView.contentSize.width),
                                            height: max(640, scrollView.contentSize.height)))
        docView.wantsLayer = true
        scrollView.documentView = docView
        canvas.frame = NSRect(x: 20, y: docView.bounds.height - 620, width: 800, height: 600)
        canvas.onDropImage = { [weak self] img, url, dropPoint in
            guard let self = self else { return }
            if self.currentFileURL != nil || self.isDirty {
                // 已開啟/編輯中：把新圖以可移動的浮動選取疊在原圖上方
                self.canvas.overlayImage(img, at: dropPoint)
                self.isDirty = true
                self.updateTitle()
            } else {
                // 空白畫布：直接載入為整張畫布
                self.canvas.loadImage(img)
                self.currentFileURL = url
                self.isDirty = (url == nil)
                self.updateTitle()
                self.layoutDocument()
            }
        }
        docView.addSubview(canvas)
    }

    private func selectTab(_ tab: TabBarView.Tab) {
        switch tab {
        case .home: ribbon.showHomeTab()
        case .view: ribbon.showViewTab()
        case .file: break  // handled by onFileMenu
        }
    }

    private func showFileMenu() {
        guard let win = window else { return }
        let menu = NSMenu()
        menu.addItem(makeFileItem("新增",  Selector(("newDocument:"))))
        menu.addItem(makeFileItem("開啟…", Selector(("openDocument:"))))
        menu.addItem(makeFileItem("儲存",  Selector(("saveDocument:"))))
        menu.addItem(makeFileItem("另存新檔…", Selector(("saveAsDocument:"))))
        menu.addItem(.separator())
        menu.addItem(makeFileItem("列印…", Selector(("printDocument:"))))
        menu.addItem(.separator())
        menu.addItem(makeFileItem("內容…", Selector(("showProperties:"))))
        let appOrigin = tabBar.fileButtonOrigin
        let p = tabBar.convert(NSPoint(x: appOrigin.x, y: 0), to: nil)
        let screenPt = win.convertPoint(toScreen: p)
        menu.popUp(positioning: nil, at: screenPt, in: nil)
    }
    private func makeFileItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    private func updateTitle() {
        let base = currentFileURL?.lastPathComponent ?? "未命名"
        window?.title = "\(base)\(isDirty ? " *" : "") - 小畫家"
    }

    private func layoutDocument() {
        guard let docView = scrollView.documentView else { return }
        let zoom = PaintState.shared.zoom
        let pxW = CGFloat(canvas.bitmap.pixelsWide)
        let pxH = CGFloat(canvas.bitmap.pixelsHigh)
        let w = pxW * zoom
        let h = pxH * zoom
        let cs = scrollView.contentSize
        let dw = max(w + 40, cs.width)
        let dh = max(h + 40, cs.height)
        docView.frame = NSRect(x: 0, y: 0, width: dw, height: dh)
        canvas.frame = NSRect(
            x: (dw - w) / 2,
            y: (dh - h) / 2,
            width: w, height: h
        )
        // 保持 bounds 為原生像素尺寸：bitmap 視覺被自動縮放成 frame.size，
        // 而所有滑鼠事件、選取/繪圖座標都以像素為單位（與縮放無關）。
        canvas.setBoundsSize(NSSize(width: pxW, height: pxH))
        canvas.needsDisplay = true
    }

    @objc private func handleZoomChanged() { layoutDocument() }
    @objc private func handleCanvasResized() { layoutDocument() }
    @objc private func handleViewChanged() {
        statusBar.isHidden = !PaintState.shared.showStatusBar
    }
    @objc private func handleStatusUpdate(_ n: Notification) {
        if let info = n.userInfo, let x = info["x"] as? Int, let y = info["y"] as? Int {
            statusBar.update(x: x, y: y, canvasSize: PaintState.shared.canvasSize)
        }
    }

    // MARK: - File menu actions

    @objc func newDocument(_ sender: Any?) {
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.canvas.resetCanvas(size: NSSize(width: 800, height: 600))
            self.currentFileURL = nil
            self.isDirty = false
            self.updateTitle()
        }
    }

    @objc func openDocument(_ sender: Any?) {
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = [UTType.image]
            } else {
                panel.allowedFileTypes = ["png", "jpg", "jpeg", "bmp", "gif", "tiff"]
            }
            if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
                self.canvas.loadImage(img)
                self.currentFileURL = url
                self.isDirty = false
                self.updateTitle()
            }
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        if let url = currentFileURL {
            saveTo(url: url)
        } else {
            saveAsDocument(sender)
        }
    }

    @objc func saveAsDocument(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "未命名.png"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png, .jpeg, .bmp, .gif, .tiff]
        } else {
            panel.allowedFileTypes = ["png", "jpg", "jpeg", "bmp", "gif", "tiff"]
        }
        if panel.runModal() == .OK, let url = panel.url {
            saveTo(url: url)
            currentFileURL = url
            isDirty = false
            updateTitle()
        }
    }

    private func saveTo(url: URL) {
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType
        switch ext {
        case "jpg", "jpeg": type = .jpeg
        case "bmp":         type = .bmp
        case "gif":         type = .gif
        case "tiff":        type = .tiff
        default:            type = .png
        }
        if let data = canvas.exportData(fileType: type) {
            try? data.write(to: url)
            isDirty = false
            updateTitle()
        }
    }

    @objc func printDocument(_ sender: Any?) {
        canvas.commitSelection()
        let printInfo = NSPrintInfo.shared
        let op = NSPrintOperation(view: canvas, printInfo: printInfo)
        op.run()
    }

    @objc func showProperties(_ sender: Any?) {
        guard let win = window else { return }
        let s = PaintState.shared.canvasSize
        let alert = NSAlert()
        alert.messageText = "影像內容"
        alert.informativeText = "寬度: \(Int(s.width)) 像素\n高度: \(Int(s.height)) 像素\n解析度: 96 DPI"
        alert.addButton(withTitle: "確定")
        alert.beginSheetModal(for: win, completionHandler: nil)
    }

    // MARK: - Edit actions (override NSResponder standard actions)

    @objc func undoAction(_ sender: Any?) { canvas.undo(); markDirty() }
    @objc func redoAction(_ sender: Any?) { canvas.redo(); markDirty() }

    @objc func cut(_ sender: Any?) {
        if let img = canvas.cutSelection() {
            writeImageToPasteboard(img)
            markDirty()
        }
    }
    @objc func copy(_ sender: Any?) {
        if let img = canvas.copySelection() {
            writeImageToPasteboard(img)
        }
    }
    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let img = images.first {
            canvas.pasteImage(img)
            markDirty()
        }
    }
    @objc override func selectAll(_ sender: Any?) { canvas.selectAll() }
    @objc func deleteSelection(_ sender: Any?) {
        _ = canvas.cutSelection()
        markDirty()
    }

    private func writeImageToPasteboard(_ img: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    // MARK: - Image actions

    @objc func cropImage(_ sender: Any?) { canvas.cropToSelection(); markDirty() }
    @objc func resizeImage(_ sender: Any?) {
        guard let win = window else { return }
        ResizeDialog.run(in: win, currentSize: PaintState.shared.canvasSize) { [weak self] result in
            guard let self = self, let r = result else { return }
            self.canvas.scaleCanvas(toSize: r)
            self.markDirty()
        }
    }
    @objc func rotateRight(_ sender: Any?) { canvas.rotateCanvas(byDegrees: -90); markDirty() }
    @objc func rotateLeft(_ sender: Any?)  { canvas.rotateCanvas(byDegrees: 90);  markDirty() }
    @objc func rotate180(_ sender: Any?)   { canvas.rotateCanvas(byDegrees: 180); markDirty() }
    @objc func flipHorizontal(_ sender: Any?) { canvas.flipCanvas(horizontal: true);  markDirty() }
    @objc func flipVertical(_ sender: Any?)   { canvas.flipCanvas(horizontal: false); markDirty() }

    // MARK: - View

    // 檢視頁的放大/縮小 與 右下角 +/- 使用相同的 25% 步進邏輯
    @objc func zoomIn(_ sender: Any?) {
        let pct = StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: true)
        PaintState.shared.zoom = CGFloat(pct / 100.0)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func zoomOut(_ sender: Any?) {
        let pct = StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: false)
        PaintState.shared.zoom = CGFloat(pct / 100.0)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func zoom100(_ sender: Any?) {
        PaintState.shared.zoom = 1.0
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func toggleGridlines(_ sender: Any?) {
        PaintState.shared.showGridlines.toggle()
        canvas.needsDisplay = true
    }
    @objc func toggleRulers(_ sender: Any?) {
        PaintState.shared.showRulers.toggle()
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc func toggleStatusBar(_ sender: Any?) {
        PaintState.shared.showStatusBar.toggle()
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Helpers

    private func markDirty() {
        isDirty = true
        updateTitle()
    }

    private func confirmDiscardIfNeeded(_ completion: @escaping (Bool) -> Void) {
        guard isDirty, let win = window else { completion(true); return }
        let alert = NSAlert()
        alert.messageText = "您要儲存對\(currentFileURL?.lastPathComponent ?? "未命名")的變更嗎？"
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "不要儲存")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: win) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                self?.saveDocument(nil)
                completion(true)
            case .alertSecondButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }
}

// MARK: - Status bar

final class StatusBarView: NSView {
    static let zoomMin: Double = 25
    static let zoomMax: Double = 800
    static let zoomStep: Double = 25

    private let posLabel = NSTextField(labelWithString: "📐 0, 0 px")
    private let sizeLabel = NSTextField(labelWithString: "⤢ 800 × 600 px")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let zoomSlider = NSSlider(value: 100, minValue: zoomMin, maxValue: zoomMax, target: nil, action: nil)
    private let minusBtn = NSButton()
    private let plusBtn = NSButton()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.9, alpha: 1).cgColor
        for lbl in [posLabel, sizeLabel, zoomLabel] {
            lbl.font = NSFont.systemFont(ofSize: 11)
            lbl.textColor = NSColor.black
            lbl.drawsBackground = false
            lbl.isBordered = false
            addSubview(lbl)
        }
        zoomLabel.alignment = .right

        configureStepButton(minusBtn, symbol: "−")
        minusBtn.action = #selector(zoomMinus(_:))
        addSubview(minusBtn)

        configureStepButton(plusBtn, symbol: "+")
        plusBtn.action = #selector(zoomPlus(_:))
        addSubview(plusBtn)

        zoomSlider.target = self
        zoomSlider.action = #selector(zoomChanged(_:))
        zoomSlider.isContinuous = true
        zoomSlider.controlSize = .small
        addSubview(zoomSlider)

        // 聆聽 zoom 變化以即時更新百分比 (例如選單放大/縮小或滑桿拖曳)
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncFromState),
            name: PaintState.zoomChanged, object: nil
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configureStepButton(_ btn: NSButton, symbol: String) {
        btn.title = symbol
        btn.bezelStyle = .roundRect
        btn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        btn.target = self
        btn.setButtonType(.momentaryPushIn)
        btn.contentTintColor = .black
    }

    @objc private func syncFromState() {
        let pct = Int(PaintState.shared.zoom * 100)
        zoomLabel.stringValue = "\(pct)%"
        if Int(zoomSlider.doubleValue) != pct {
            zoomSlider.doubleValue = Double(pct)
        }
    }

    override func layout() {
        super.layout()
        posLabel.frame = NSRect(x: 8, y: 4, width: 130, height: 18)
        sizeLabel.frame = NSRect(x: 150, y: 4, width: 150, height: 18)
        // 右側：[−] [====slider====] [+]  100%
        let labelW: CGFloat = 52
        let btnW: CGFloat = 26
        let sliderW: CGFloat = 120
        let gap: CGFloat = 4
        var x = bounds.width - 8 - labelW
        zoomLabel.frame = NSRect(x: x, y: 4, width: labelW, height: 18)
        x -= gap + btnW
        plusBtn.frame = NSRect(x: x, y: 2, width: btnW, height: 20)
        x -= gap + sliderW
        zoomSlider.frame = NSRect(x: x, y: 4, width: sliderW, height: 18)
        x -= gap + btnW
        minusBtn.frame = NSRect(x: x, y: 2, width: btnW, height: 20)
    }

    func update(x: Int, y: Int, canvasSize: NSSize) {
        posLabel.stringValue = "📐 \(x), \(y) px"
        sizeLabel.stringValue = "⤢ \(Int(canvasSize.width)) × \(Int(canvasSize.height)) px"
        zoomLabel.stringValue = "\(Int(PaintState.shared.zoom * 100))%"
        zoomSlider.doubleValue = Double(PaintState.shared.zoom * 100)
    }

    @objc private func zoomChanged(_ sender: NSSlider) {
        PaintState.shared.zoom = CGFloat(sender.doubleValue / 100.0)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }

    /// 從目前百分比，以 25% 為單位跳到下一個整數倍（up=true 放大）。純函式，方便測試。
    static func nextZoomPct(from cur: Double, up: Bool) -> Double {
        if up {
            return min(zoomMax, (floor(cur / zoomStep) + 1) * zoomStep)
        } else {
            let stepped = (ceil(cur / zoomStep) - 1) * zoomStep
            return max(zoomMin, stepped)
        }
    }

    @objc private func zoomPlus(_ sender: Any?) {
        applyZoomPct(StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: true))
    }
    @objc private func zoomMinus(_ sender: Any?) {
        applyZoomPct(StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: false))
    }
    private func applyZoomPct(_ pct: Double) {
        PaintState.shared.zoom = CGFloat(pct / 100.0)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
}
