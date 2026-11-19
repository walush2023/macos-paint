import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    let canvas = CanvasView(size: NSSize(width: 800, height: 600))
    let ribbon = RibbonView()
    private let ribbonScroll = NSScrollView()
    let statusBar = StatusBarView()
    let scrollView = NSScrollView()
    let tabBar = TabBarView()
    let hRuler = CanvasRulerView(orientation: .horizontal)
    let vRuler = CanvasRulerView(orientation: .vertical)
    private let rulerThickness: CGFloat = 20
    var currentFileURL: URL?
    var isDirty: Bool = false

    private let tabBarHeight: CGFloat = 28
    private let ribbonHeight: CGFloat = 110
    private let statusBarHeight: CGFloat = 24

    // 畫布大小調整把手（右/下/右下角）
    private var rightHandle: CanvasResizeHandle?
    private var bottomHandle: CanvasResizeHandle?
    private var cornerHandle: CanvasResizeHandle?
    private var resizeBaseSize: NSSize = .zero
    private var resizeStartWin: NSPoint = .zero

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "\(tr("未命名")) - \(tr("小畫家"))"
        win.minSize = NSSize(width: 800, height: 500)
        // 強制使用淺色外觀以對齊 Windows 小畫家視覺、避免深色模式下標籤變白看不清
        win.appearance = NSAppearance(named: .aqua)
        super.init(window: win)
        win.delegate = self
        buildLayout()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleZoomChanged(_:)), name: PaintState.zoomChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleCanvasResized), name: PaintState.canvasResized, object: nil)
        nc.addObserver(self, selector: #selector(handleViewChanged), name: PaintState.viewChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleStatusUpdate(_:)), name: PaintState.statusUpdate, object: nil)
        nc.addObserver(self, selector: #selector(handleDocumentEdited(_:)), name: PaintState.documentEdited, object: canvas)
        nc.addObserver(self, selector: #selector(handleSelectionChanged(_:)), name: PaintState.selectionChanged, object: canvas)
        nc.addObserver(self, selector: #selector(handleScrolled), name: NSView.boundsDidChangeNotification,
                       object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        handleViewChanged()
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
        // ribbon 放在水平捲動檢視中：視窗比 ribbon 窄時可左右捲動（長語言字串也不會被裁掉）
        ribbonScroll.frame = NSRect(x: 0, y: h - tabBarHeight - ribbonHeight,
                                    width: content.bounds.width, height: ribbonHeight)
        ribbonScroll.autoresizingMask = [.width, .minYMargin]
        ribbonScroll.hasHorizontalScroller = true
        ribbonScroll.hasVerticalScroller = false
        ribbonScroll.autohidesScrollers = true
        ribbonScroll.scrollerStyle = .overlay
        ribbonScroll.drawsBackground = false
        ribbon.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: ribbonHeight)
        ribbonScroll.documentView = ribbon
        content.addSubview(ribbonScroll)
        ribbon.fitToScrollView()

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

        // 尺規（以畫布像素為單位，原點在畫布左上角）
        for r in [hRuler, vRuler] {
            r.canvas = canvas
            r.isHidden = true
            content.addSubview(r)
        }

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

        // 建立 3 個畫布大小調整把手
        let right = CanvasResizeHandle(pos: .right)
        let bottom = CanvasResizeHandle(pos: .bottom)
        let corner = CanvasResizeHandle(pos: .corner)
        for hv in [right, bottom, corner] {
            hv.onBegin = { [weak self] win in self?.beginCanvasResize(at: win) }
            hv.onDrag = { [weak self] win, pos in self?.dragCanvasResize(to: win, pos: pos) }
            hv.onEnd = { [weak self] in self?.endCanvasResize() }
            docView.addSubview(hv)
        }
        rightHandle = right; bottomHandle = bottom; cornerHandle = corner
        layoutResizeHandles()
    }

    // MARK: - 畫布大小拖拉

    private func beginCanvasResize(at win: NSPoint) {
        resizeBaseSize = PaintState.shared.canvasSize
        resizeStartWin = win
        canvas.beginCanvasResize()
    }
    private func dragCanvasResize(to win: NSPoint, pos: CanvasResizeHandle.Pos) {
        let zoom = PaintState.shared.zoom
        let dx = (win.x - resizeStartWin.x) / zoom    // 視窗 y 向上：往下拖 dy<0 → 變高
        let dy = (win.y - resizeStartWin.y) / zoom
        var newW = resizeBaseSize.width
        var newH = resizeBaseSize.height
        if pos == .right || pos == .corner { newW = resizeBaseSize.width + dx }
        if pos == .bottom || pos == .corner { newH = resizeBaseSize.height - dy }
        newW = max(1, newW.rounded())
        newH = max(1, newH.rounded())
        canvas.previewCanvasResize(to: NSSize(width: newW, height: newH))
        // canvasResized 通知會觸發 layoutDocument → 重新定位把手
    }
    private func endCanvasResize() {
        canvas.endCanvasResize()
        markDirty()
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
        menu.addItem(makeFileItem(tr("新增"),  Selector(("newDocument:"))))
        menu.addItem(makeFileItem(tr("開啟…"), Selector(("openDocument:"))))
        menu.addItem(makeFileItem(tr("儲存"),  Selector(("saveDocument:"))))
        menu.addItem(makeFileItem(tr("另存新檔…"), Selector(("saveAsDocument:"))))
        menu.addItem(.separator())
        menu.addItem(makeFileItem(tr("列印…"), Selector(("printDocument:"))))
        menu.addItem(.separator())
        menu.addItem(makeFileItem(tr("內容…"), Selector(("showProperties:"))))
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
        let base = currentFileURL?.lastPathComponent ?? tr("未命名")
        window?.title = "\(base)\(isDirty ? " *" : "") - \(tr("小畫家"))"
        window?.isDocumentEdited = isDirty
        window?.representedURL = currentFileURL
    }

    private let canvasMargin: CGFloat = 10
    private func layoutDocument() {
        guard let docView = scrollView.documentView else { return }
        let zoom = PaintState.shared.zoom
        let pxW = CGFloat(canvas.bitmap.pixelsWide)
        let pxH = CGFloat(canvas.bitmap.pixelsHigh)
        let w = pxW * zoom
        let h = pxH * zoom
        let cs = scrollView.contentSize
        let pad = canvasMargin + 24   // 右/下保留把手空間
        let dw = max(w + canvasMargin + pad, cs.width)
        let dh = max(h + canvasMargin + pad, cs.height)
        docView.frame = NSRect(x: 0, y: 0, width: dw, height: dh)
        // 左上對齊（docView 非翻轉，左下原點 → 內容靠頂端）
        let originY = dh - canvasMargin - h
        canvas.frame = NSRect(x: canvasMargin, y: originY, width: w, height: h)
        // bounds 保持原生像素尺寸：bitmap 視覺被自動縮放成 frame.size，
        // 滑鼠/選取/繪圖座標皆以像素為單位（與縮放無關）。
        canvas.setBoundsSize(NSSize(width: pxW, height: pxH))
        canvas.needsDisplay = true
        layoutResizeHandles()
        refreshRulers()
    }

    private func layoutResizeHandles() {
        let f = canvas.frame
        // 右(中)、下(中)、右下角
        rightHandle?.frame = NSRect(x: f.maxX - 1, y: f.midY - 4, width: 8, height: 8)
        bottomHandle?.frame = NSRect(x: f.midX - 4, y: f.minY - 7, width: 8, height: 8)
        cornerHandle?.frame = NSRect(x: f.maxX - 1, y: f.minY - 7, width: 8, height: 8)
    }

    @objc private func handleZoomChanged(_ n: Notification) {
        // 縮放前記住錨點（畫布像素）在畫面上的位置，縮放後維持在同一處
        let anchor = (n.userInfo?["anchor"] as? NSValue)?.pointValue
        var anchorInClip: NSPoint?
        if let a = anchor {
            let docPt = canvas.convert(a, to: scrollView.documentView)
            let origin = scrollView.contentView.bounds.origin
            anchorInClip = NSPoint(x: docPt.x - origin.x, y: docPt.y - origin.y)
        }
        layoutDocument()
        if let a = anchor, let inClip = anchorInClip, let doc = scrollView.documentView {
            let docPt = canvas.convert(a, to: doc)
            let clip = scrollView.contentView
            var o = NSPoint(x: docPt.x - inClip.x, y: docPt.y - inClip.y)
            o.x = max(0, min(doc.frame.width - clip.bounds.width, o.x))
            o.y = max(0, min(doc.frame.height - clip.bounds.height, o.y))
            clip.scroll(to: o)
            scrollView.reflectScrolledClipView(clip)
        }
        refreshRulers()
    }
    @objc private func handleCanvasResized() {
        layoutDocument()
        statusBar.updateCanvasSize(PaintState.shared.canvasSize)
    }
    @objc private func handleViewChanged() {
        statusBar.isHidden = !PaintState.shared.showStatusBar
        layoutWorkspace()
        canvas.needsDisplay = true   // 格線切換（ribbon 勾選框也走這條）
    }
    @objc private func handleScrolled() { refreshRulers() }
    private func refreshRulers() {
        hRuler.needsDisplay = true
        vRuler.needsDisplay = true
    }

    /// 依尺規/狀態列是否顯示，重新排列工作區（捲動區）大小。
    private func layoutWorkspace() {
        guard let content = window?.contentView else { return }
        let showR = PaintState.shared.showRulers
        let bottom: CGFloat = PaintState.shared.showStatusBar ? statusBarHeight : 0
        let top = content.bounds.height - tabBarHeight - ribbonHeight
        let t: CGFloat = showR ? rulerThickness : 0
        scrollView.frame = NSRect(x: t, y: bottom, width: content.bounds.width - t, height: top - bottom - t)
        hRuler.isHidden = !showR
        vRuler.isHidden = !showR
        hRuler.frame = NSRect(x: t, y: top - t, width: content.bounds.width - t, height: t)
        hRuler.autoresizingMask = [.width, .minYMargin]
        vRuler.frame = NSRect(x: 0, y: bottom, width: t, height: top - bottom - t)
        vRuler.autoresizingMask = [.height]
        layoutDocument()
        refreshRulers()
    }

    @objc private func handleDocumentEdited(_ n: Notification) { markDirty() }
    @objc private func handleSelectionChanged(_ n: Notification) {
        let info = n.userInfo
        if let w = info?["w"] as? Int, let h = info?["h"] as? Int {
            statusBar.updateSelection(NSSize(width: w, height: h))
        } else {
            statusBar.updateSelection(nil)
        }
    }
    @objc private func handleStatusUpdate(_ n: Notification) {
        if let info = n.userInfo, let x = info["x"] as? Int, let y = info["y"] as? Int {
            statusBar.update(x: x, y: y, canvasSize: PaintState.shared.canvasSize)
            hRuler.marker = CGFloat(x)
            vRuler.marker = CGFloat(y)
        }
    }

    // MARK: - File menu actions

    @objc func newDocument(_ sender: Any?) {
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.canvas.cancelPendingShape()
            self.canvas.commitText()
            self.canvas.resetCanvas(size: NSSize(width: 800, height: 600))
            self.currentFileURL = nil
            self.isDirty = false
            self.updateTitle()
            self.layoutDocument()
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
            if panel.runModal() == .OK, let url = panel.url {
                self.openImageFile(url)
            }
        }
    }

    /// 由 Finder 開檔 / 開啟方式 / 拖到 Dock，載入指定圖檔。
    func openImageFile(_ url: URL) {
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            guard let img = NSImage(contentsOf: url), img.isValid else {
                self.showError(trf("無法開啟「%@」：不是支援的影像格式。", url.lastPathComponent))
                RecentFiles.remove(url)
                return
            }
            self.canvas.cancelPendingShape()
            self.canvas.commitText()
            self.canvas.loadImage(img)
            self.currentFileURL = url
            self.isDirty = false
            self.updateTitle()
            self.layoutDocument()
            RecentFiles.add(url)
        }
    }

    @objc func saveDocument(_ sender: Any?) { _ = performSave() }

    /// 儲存；回傳是否真的存檔成功（另存視窗按取消 / 寫入失敗 → false）。
    @discardableResult
    func performSave() -> Bool {
        if let url = currentFileURL {
            return saveTo(url: url)
        }
        return performSaveAs()
    }

    private struct SaveFormat {
        let name: String
        let type: NSBitmapImageRep.FileType
        let ut: UTType
        let ext: String
    }
    private let saveFormats: [SaveFormat] = [
        SaveFormat(name: "PNG",  type: .png,  ut: .png,  ext: "png"),
        SaveFormat(name: "JPEG", type: .jpeg, ut: .jpeg, ext: "jpg"),
        SaveFormat(name: "BMP",  type: .bmp,  ut: .bmp,  ext: "bmp"),
        SaveFormat(name: "GIF",  type: .gif,  ut: .gif,  ext: "gif"),
        SaveFormat(name: "TIFF", type: .tiff, ut: .tiff, ext: "tiff"),
    ]

    @objc func saveAsDocument(_ sender: Any?) { _ = performSaveAs() }

    @discardableResult
    func performSaveAs() -> Bool {
        let panel = NSSavePanel()

        // 起始格式：沿用現有副檔名，否則 PNG
        let curExt = currentFileURL?.pathExtension.lowercased() ?? "png"
        let startIdx = saveFormats.firstIndex { $0.ext == curExt || ($0.ext == "jpg" && curExt == "jpeg") } ?? 0

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 170, height: 25))
        saveFormats.forEach { popup.addItem(withTitle: $0.name) }
        popup.selectItem(at: startIdx)

        let acc = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
        let label = NSTextField(labelWithString: tr("檔案格式:"))
        label.frame = NSRect(x: 14, y: 9, width: 100, height: 20)
        label.alignment = .right
        popup.frame = NSRect(x: 120, y: 6, width: 170, height: 25)
        acc.addSubview(label); acc.addSubview(popup)
        panel.accessoryView = acc

        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? tr("未命名")
        let applyFormat: () -> Void = { [weak panel] in
            guard let panel = panel else { return }
            let f = self.saveFormats[popup.indexOfSelectedItem]
            if #available(macOS 11.0, *) { panel.allowedContentTypes = [f.ut] }
            else { panel.allowedFileTypes = [f.ext] }
            panel.nameFieldStringValue = "\(baseName).\(f.ext)"
        }
        let handler = SavePanelFormatHandler(action: applyFormat)
        popup.target = handler
        popup.action = #selector(SavePanelFormatHandler.changed(_:))
        applyFormat()

        var ok = false
        if panel.runModal() == .OK, let url = panel.url {
            let f = saveFormats[popup.indexOfSelectedItem]
            if saveTo(url: url, type: f.type) {
                currentFileURL = url
                isDirty = false
                updateTitle()
                ok = true
            }
        }
        withExtendedLifetime(handler) {}   // 保活至 modal 結束
        return ok
    }

    @discardableResult
    private func saveTo(url: URL, type explicitType: NSBitmapImageRep.FileType? = nil) -> Bool {
        let type: NSBitmapImageRep.FileType
        if let t = explicitType {
            type = t
        } else {
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": type = .jpeg
            case "bmp":         type = .bmp
            case "gif":         type = .gif
            case "tiff":        type = .tiff
            default:            type = .png
            }
        }
        guard let data = canvas.exportData(fileType: type) else {
            showError(trf("無法儲存「%@」。", url.lastPathComponent))
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showError(trf("無法儲存「%@」。", url.lastPathComponent) + "\n" + error.localizedDescription)
            return false
        }
        isDirty = false
        updateTitle()
        RecentFiles.add(url)
        return true
    }

    private func showError(_ msg: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = msg
        alert.addButton(withTitle: tr("確定"))
        if let win = window, win.isVisible, win.attachedSheet == nil {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
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
        alert.messageText = tr("影像內容")
        alert.informativeText = trf("寬度: %d 像素\n高度: %d 像素\n解析度: 96 DPI", Int(s.width), Int(s.height))
        alert.addButton(withTitle: tr("確定"))
        alert.beginSheetModal(for: win, completionHandler: nil)
    }

    // MARK: - Edit actions (override NSResponder standard actions)

    @objc func undoAction(_ sender: Any?) {
        // 編輯文字中 → 復原文字輸入，而非畫布
        if canvas.isEditingText, let um = window?.firstResponder?.undoManager, um.canUndo { um.undo(); return }
        canvas.undo()
    }
    @objc func redoAction(_ sender: Any?) {
        if canvas.isEditingText, let um = window?.firstResponder?.undoManager, um.canRedo { um.redo(); return }
        canvas.redo()
    }

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
    }
    @objc func invertColors(_ sender: Any?) { canvas.invertColors() }
    @objc func clearImage(_ sender: Any?) { canvas.clearImage() }
    @objc func toggleTransparentSelection(_ sender: Any?) {
        PaintState.shared.transparentSelection.toggle()
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
    /// 目前可見範圍中心（畫布像素座標），縮放時以此為錨點。
    private func visibleCenterInCanvas() -> NSPoint {
        let clip = scrollView.contentView
        let c = NSPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        let p = canvas.convert(c, from: clip)
        return NSPoint(x: max(0, min(canvas.bounds.width, p.x)), y: max(0, min(canvas.bounds.height, p.y)))
    }
    @objc func zoomIn(_ sender: Any?) {
        let pct = StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: true)
        canvas.setZoom(CGFloat(pct / 100.0), anchor: visibleCenterInCanvas())
    }
    @objc func zoomOut(_ sender: Any?) {
        let pct = StatusBarView.nextZoomPct(from: Double(PaintState.shared.zoom * 100), up: false)
        canvas.setZoom(CGFloat(pct / 100.0), anchor: visibleCenterInCanvas())
    }
    @objc func zoom100(_ sender: Any?) {
        canvas.setZoom(1.0, anchor: visibleCenterInCanvas())
    }
    /// 符合視窗：讓整張畫布剛好放進可見區域。
    @objc func zoomToFit(_ sender: Any?) {
        let cs = scrollView.contentSize
        let pad = canvasMargin * 2 + 24
        let z = min((cs.width - pad) / CGFloat(canvas.bitmap.pixelsWide),
                    (cs.height - pad) / CGFloat(canvas.bitmap.pixelsHigh))
        canvas.setZoom(max(0.25, min(8.0, z)), anchor: nil)
        scrollView.contentView.scroll(to: .zero)
    }
    @objc func toggleGridlines(_ sender: Any?) {
        PaintState.shared.showGridlines.toggle()
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
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

    // MARK: - 關閉視窗前確認

    /// 視窗縮放（含放大到全螢幕／縮放鈕）後重新排版，畫布維持靠左上。
    func windowDidResize(_ notification: Notification) {
        ribbon.fitToScrollView()
        layoutDocument()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.isDirty = false
            self.window?.close()
        }
        return false
    }

    // MARK: - 選單狀態

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undoAction(_:)):
            return canvas.canUndo() || canvas.selectionImage != nil || canvas.isEditingText
        case #selector(redoAction(_:)):
            return canvas.canRedo() || canvas.isEditingText
        case #selector(cut(_:)), #selector(deleteSelection(_:)), #selector(cropImage(_:)):
            return canvas.selectionRect != nil
        case #selector(toggleGridlines(_:)):
            item.state = PaintState.shared.showGridlines ? .on : .off
        case #selector(toggleRulers(_:)):
            item.state = PaintState.shared.showRulers ? .on : .off
        case #selector(toggleStatusBar(_:)):
            item.state = PaintState.shared.showStatusBar ? .on : .off
        case #selector(toggleTransparentSelection(_:)):
            item.state = PaintState.shared.transparentSelection ? .on : .off
        default: break
        }
        return true
    }

    // MARK: - 最近開啟的檔案

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = RecentFiles.urls
        for url in urls {
            let it = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            it.representedObject = url
            it.target = self
            it.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            it.image = icon
            menu.addItem(it)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: tr("清除選單"), action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openImageFile(url)
    }
    @objc func clearRecent(_ sender: Any?) { RecentFiles.clear() }

    // MARK: - Helpers

    private func markDirty() {
        isDirty = true
        updateTitle()
        window?.isDocumentEdited = true
    }

    func confirmDiscardIfNeeded(_ completion: @escaping (Bool) -> Void) {
        canvas.commitText()
        guard isDirty, let win = window else { completion(true); return }
        if win.attachedSheet != nil { completion(false); return }   // 已有提示視窗
        let alert = NSAlert()
        alert.messageText = trf("您要儲存對 %@ 的變更嗎？", currentFileURL?.lastPathComponent ?? tr("未命名"))
        alert.addButton(withTitle: tr("儲存"))
        alert.addButton(withTitle: tr("不要儲存"))
        alert.addButton(withTitle: tr("取消"))
        alert.beginSheetModal(for: win) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                // 存檔失敗或另存視窗按取消 → 不要丟掉內容
                completion(self?.performSave() ?? false)
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
    private let selLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let zoomSlider = NSSlider(value: 100, minValue: zoomMin, maxValue: zoomMax, target: nil, action: nil)
    private let minusBtn = NSButton()
    private let plusBtn = NSButton()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.9, alpha: 1).cgColor
        for lbl in [posLabel, sizeLabel, selLabel, zoomLabel] {
            lbl.font = NSFont.systemFont(ofSize: 12)
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
        selLabel.frame = NSRect(x: 310, y: 4, width: 150, height: 18)
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

    /// 選取範圍大小（nil = 無選取）。
    func updateSelection(_ size: NSSize?) {
        if let s = size { selLabel.stringValue = "⬚ \(Int(s.width)) × \(Int(s.height)) px" }
        else { selLabel.stringValue = "" }
    }
    var selectionText: String { selLabel.stringValue }
    func updateCanvasSize(_ s: NSSize) {
        sizeLabel.stringValue = "⤢ \(Int(s.width)) × \(Int(s.height)) px"
    }

    func update(x: Int, y: Int, canvasSize: NSSize) {
        posLabel.stringValue = "📐 \(x), \(y) px"
        sizeLabel.stringValue = "⤢ \(Int(canvasSize.width)) × \(Int(canvasSize.height)) px"
        zoomLabel.stringValue = "\(Int(PaintState.shared.zoom * 100))%"
        zoomSlider.doubleValue = Double(PaintState.shared.zoom * 100)
    }

    @objc private func zoomChanged(_ sender: NSSlider) {
        applyZoomPct(sender.doubleValue)
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

// MARK: - 畫布大小調整把手

/// 畫布右/下/右下角的小白方塊，拖拉以調整畫布尺寸（不縮放內容）。
final class CanvasResizeHandle: NSView {
    enum Pos { case right, bottom, corner }
    let pos: Pos
    var onBegin: ((NSPoint) -> Void)?          // 視窗座標起點
    var onDrag: ((NSPoint, Pos) -> Void)?      // 目前視窗座標 + 位置
    var onEnd: (() -> Void)?

    init(pos: Pos) {
        self.pos = pos
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor(white: 0.35, alpha: 1).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch pos {
        case .right:  cursor = Cursors.resizeEW
        case .bottom: cursor = Cursors.resizeNS
        case .corner: cursor = Cursors.resizeNWSE
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        onBegin?(event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.locationInWindow, pos)
    }
    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}

// MARK: - 另存格式選單的 target

final class SavePanelFormatHandler: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func changed(_ sender: Any?) { action() }
}
