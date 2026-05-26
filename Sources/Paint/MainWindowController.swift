import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController {
    let canvas = CanvasView(size: NSSize(width: 800, height: 600))
    let ribbon = RibbonView()
    let statusBar = StatusBarView()
    let scrollView = NSScrollView()
    var currentFileURL: URL?
    var isDirty: Bool = false

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "未命名 - 小畫家"
        win.minSize = NSSize(width: 600, height: 400)
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

        ribbon.frame = NSRect(x: 0, y: content.bounds.height - 110, width: content.bounds.width, height: 110)
        ribbon.autoresizingMask = [.width, .minYMargin]
        content.addSubview(ribbon)

        statusBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: 24)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(statusBar)

        scrollView.frame = NSRect(
            x: 0, y: 24,
            width: content.bounds.width,
            height: content.bounds.height - 110 - 24
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = NSColor(calibratedRed: 0.6, green: 0.74, blue: 0.93, alpha: 1)
        scrollView.drawsBackground = true
        content.addSubview(scrollView)

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: max(800, scrollView.contentSize.width),
                                            height: max(600, scrollView.contentSize.height)))
        docView.wantsLayer = true
        scrollView.documentView = docView
        canvas.frame = NSRect(x: 20, y: 20, width: 800, height: 600)
        docView.addSubview(canvas)
    }

    private func updateTitle() {
        let base = currentFileURL?.lastPathComponent ?? "未命名"
        window?.title = "\(base)\(isDirty ? " *" : "") - 小畫家"
    }

    private func layoutDocument() {
        guard let docView = scrollView.documentView else { return }
        let zoom = PaintState.shared.zoom
        let w = CGFloat(canvas.bitmap.pixelsWide) * zoom
        let h = CGFloat(canvas.bitmap.pixelsHigh) * zoom
        let cs = scrollView.contentSize
        let dw = max(w + 40, cs.width)
        let dh = max(h + 40, cs.height)
        docView.frame = NSRect(x: 0, y: 0, width: dw, height: dh)
        canvas.frame = NSRect(
            x: (dw - w) / 2,
            y: (dh - h) / 2,
            width: w, height: h
        )
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

    @objc func newDocument() {
        confirmDiscardIfNeeded { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.canvas.resetCanvas(size: NSSize(width: 800, height: 600))
            self.currentFileURL = nil
            self.isDirty = false
            self.updateTitle()
        }
    }

    @objc func openDocument() {
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

    @objc func saveDocument() {
        if let url = currentFileURL {
            saveTo(url: url)
        } else {
            saveAsDocument()
        }
    }

    @objc func saveAsDocument() {
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

    @objc func printDocument() {
        canvas.commitSelection()
        let printInfo = NSPrintInfo.shared
        let op = NSPrintOperation(view: canvas, printInfo: printInfo)
        op.run()
    }

    @objc func showProperties() {
        guard let win = window else { return }
        let s = PaintState.shared.canvasSize
        let alert = NSAlert()
        alert.messageText = "影像內容"
        alert.informativeText = "寬度: \(Int(s.width)) 像素\n高度: \(Int(s.height)) 像素\n解析度: 96 DPI"
        alert.addButton(withTitle: "確定")
        alert.beginSheetModal(for: win, completionHandler: nil)
    }

    // MARK: - Edit actions

    @objc func undo() { canvas.undo(); markDirty() }
    @objc func redo() { canvas.redo(); markDirty() }
    @objc func cut() {
        if let img = canvas.cutSelection() {
            writeImageToPasteboard(img)
            markDirty()
        }
    }
    @objc func copy() {
        if let img = canvas.copySelection() {
            writeImageToPasteboard(img)
        }
    }
    @objc func paste() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let img = images.first {
            canvas.pasteImage(img)
            markDirty()
        }
    }
    @objc func selectAll() { canvas.selectAll() }
    @objc func deleteSelection() {
        _ = canvas.cutSelection()
        markDirty()
    }

    private func writeImageToPasteboard(_ img: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    // MARK: - Image actions

    @objc func cropImage() { canvas.cropToSelection(); markDirty() }
    @objc func resizeImage() {
        guard let win = window else { return }
        ResizeDialog.run(in: win, currentSize: PaintState.shared.canvasSize) { [weak self] result in
            guard let self = self, let r = result else { return }
            self.canvas.scaleCanvas(toSize: r)
            self.markDirty()
        }
    }
    @objc func rotateRight() { canvas.rotateCanvas(byDegrees: -90); markDirty() }
    @objc func rotateLeft()  { canvas.rotateCanvas(byDegrees: 90);  markDirty() }
    @objc func rotate180()   { canvas.rotateCanvas(byDegrees: 180); markDirty() }
    @objc func flipHorizontal() { canvas.flipCanvas(horizontal: true);  markDirty() }
    @objc func flipVertical()   { canvas.flipCanvas(horizontal: false); markDirty() }

    // MARK: - View

    @objc func zoomIn() {
        PaintState.shared.zoom = min(8.0, PaintState.shared.zoom * 1.5)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func zoomOut() {
        PaintState.shared.zoom = max(0.1, PaintState.shared.zoom / 1.5)
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func zoom100() {
        PaintState.shared.zoom = 1.0
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
    }
    @objc func toggleGridlines() {
        PaintState.shared.showGridlines.toggle()
        canvas.needsDisplay = true
    }
    @objc func toggleRulers() {
        PaintState.shared.showRulers.toggle()
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc func toggleStatusBar() {
        PaintState.shared.showStatusBar.toggle()
        NotificationCenter.default.post(name: PaintState.viewChanged, object: nil)
    }
    @objc func toggleFullScreen() {
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
                self?.saveDocument()
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
    private let posLabel = NSTextField(labelWithString: "📐 0, 0 px")
    private let sizeLabel = NSTextField(labelWithString: "⤢ 800 × 600 px")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let zoomSlider = NSSlider(value: 100, minValue: 10, maxValue: 800, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.9, alpha: 1).cgColor
        for lbl in [posLabel, sizeLabel, zoomLabel] {
            lbl.font = NSFont.systemFont(ofSize: 11)
            addSubview(lbl)
        }
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomChanged(_:))
        zoomSlider.controlSize = .small
        addSubview(zoomSlider)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        posLabel.frame = NSRect(x: 8, y: 4, width: 130, height: 18)
        sizeLabel.frame = NSRect(x: 150, y: 4, width: 150, height: 18)
        let rightW: CGFloat = 220
        zoomSlider.frame = NSRect(x: bounds.width - rightW, y: 4, width: 130, height: 18)
        zoomLabel.frame = NSRect(x: bounds.width - 80, y: 4, width: 60, height: 18)
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
}
