import AppKit

/// 主畫布。底層是位元圖 (`bitmap`)，上層 (`overlay`) 用於形狀/選取預覽。
final class CanvasView: NSView, NSTextViewDelegate {
    private(set) var bitmap: NSBitmapImageRep!
    private var overlay: NSImage = NSImage()
    let history = History()

    // Mouse state
    private var isDrawing = false
    private var dragStart: NSPoint = .zero
    private var dragLast: NSPoint = .zero
    private var dragButton: Int = 0   // 0=left=color1, 1=right=color2
    private var curvePoints: [NSPoint] = []
    private var curvePhase: Int = 0    // 0: drawing line, 1: first bend, 2: second bend
    private var polygonPoints: [NSPoint] = []
    /// 形狀開始時按下的鍵：0=左鍵(外框 color1/填色 color2)，1=右鍵(兩色互換)。
    private var shapeButton: Int = 0

    // Selection state
    var selectionRect: NSRect? = nil
    var selectionImage: NSImage? = nil
    private var selectionStart: NSPoint = .zero
    private var selectionPath: NSBezierPath? = nil
    private var movingSelection = false
    private var moveOffset: NSPoint = .zero
    private var marchingPhase: CGFloat = 0
    private var marchingTimer: Timer?

    // Selection resize handles
    enum Handle { case nw, n, ne, e, se, s, sw, w }
    private var resizingHandle: Handle? = nil
    private var resizeStartRect: NSRect = .zero
    private var resizeStartPoint: NSPoint = .zero
    private let handleSize: CGFloat = 8

    // Text editing
    private var activeTextField: NSTextView?
    private var activeTextFont: NSFont = NSFont.systemFont(ofSize: 16)

    /// 拖放圖片進來時的回呼（由 MainWindowController 設定）。參數：圖片、來源 URL、放下點(畫布座標)。
    var onDropImage: ((NSImage, URL?, NSPoint) -> Void)?
    private var isDragHighlight = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        registerForDraggedTypes([.fileURL, .png, .tiff])
        resetCanvas(size: size, fill: .white)
        startMarchingAntsTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToolChanged),
            name: PaintState.toolChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleColorChangedForText),
            name: PaintState.colorChanged, object: nil
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { marchingTimer?.invalidate() }

    @objc private func handleToolChanged() {
        let t = PaintState.shared.tool
        // 切換到非文字工具時，合入正在編輯的文字
        if t != .text, activeTextField != nil { commitText() }
        // 切換工具時，完成進行中的曲線/多邊形（避免預覽殘留在 overlay）
        finishPendingShape()
        // 切換到非選取工具時，合入並結束目前的浮動選取
        if t != .selectRect, t != .selectFree, selectionRect != nil {
            commitSelection()
        }
        window?.invalidateCursorRects(for: self)
    }

    /// 編輯文字時 color1 改變 → 即時套用到文字。
    @objc private func handleColorChangedForText() {
        if activeTextField != nil { TextFormatPanel.shared.apply() }
    }

    /// ESC：取消進行中的形狀；合入並取消目前選取/文字狀態。
    override func cancelOperation(_ sender: Any?) {
        if activeTextField != nil { commitText(); return }
        if hasPendingShape { cancelPendingShape(); return }
        if selectionRect != nil || selectionPath != nil {
            commitSelection()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:   // ESC
            cancelOperation(nil); return
        case 36, 76:   // Return / Enter：完成多邊形/曲線
            if hasPendingShape { finishPendingShape(); return }
        case 51, 117:  // Delete / Forward Delete：刪除選取（以背景色填補）
            if selectionImage != nil { _ = cutSelection(); return }
        case 123, 124, 125, 126:   // 方向鍵：微移選取（Shift = 10 px）
            if var sel = selectionRect, selectionImage != nil {
                let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                switch event.keyCode {
                case 123: sel.origin.x -= step
                case 124: sel.origin.x += step
                case 125: sel.origin.y -= step
                default:  sel.origin.y += step
                }
                selectionRect = sel
                needsDisplay = true
                return
            }
        default: break
        }
        super.keyDown(with: event)
    }

    // MARK: - 進行中的多步驟形狀（曲線 / 多邊形）

    var hasPendingShape: Bool { !polygonPoints.isEmpty || curvePhase > 0 || (isDrawing && PaintState.shared.tool == .shape) }

    /// 放棄進行中的形狀（ESC）。
    func cancelPendingShape() {
        guard hasPendingShape else { return }
        polygonPoints.removeAll()
        curvePoints.removeAll()
        curvePhase = 0
        if PaintState.shared.tool == .shape { isDrawing = false }
        clearOverlay()
    }

    /// 完成進行中的形狀（Enter / 切換工具）：曲線以目前控制點畫出，多邊形至少 3 點才封閉。
    func finishPendingShape() {
        if curvePhase > 0, curvePoints.count >= 2 {
            finalizeCurve()
        } else if polygonPoints.count >= 3 {
            finalizePolygon()
        } else {
            cancelPendingShape()
        }
    }

    // MARK: - 縮放手勢（觸控板捏合 / ⌘+滾輪）

    override func magnify(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(PaintState.shared.zoom * (1 + event.magnification), anchor: anchor)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            let anchor = convert(event.locationInWindow, from: nil)
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? (1 + dy / 200) : (dy > 0 ? 1.25 : 0.8)
            setZoom(PaintState.shared.zoom * factor, anchor: anchor)
            return
        }
        super.scrollWheel(with: event)
    }

    /// 設定縮放（25%–800%），anchor 為要保持在畫面中央附近的畫布像素座標。
    func setZoom(_ z: CGFloat, anchor: NSPoint?) {
        let zoom = max(0.25, min(8.0, z))
        guard abs(zoom - PaintState.shared.zoom) > 0.0001 else { return }
        PaintState.shared.zoom = zoom
        var info: [String: Any] = [:]
        if let a = anchor { info["anchor"] = NSValue(point: a) }
        NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil, userInfo: info)
    }

    // 依當前工具設定游標
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: Cursors.cursor(for: PaintState.shared.tool))
    }

    // MARK: - Drag & drop (拖放圖片載入)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if canAcceptDrag(sender) {
            isDragHighlight = true
            needsDisplay = true
            return .copy
        }
        return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlight = false
        needsDisplay = true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptDrag(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlight = false
        needsDisplay = true
        let pb = sender.draggingPasteboard
        // 放下位置（畫布座標，左下原點）
        let dropPoint = clampToCanvas(convert(sender.draggingLocation, from: nil))

        // 1) 檔案 URL
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let url = urls.first, let img = NSImage(contentsOf: url) {
            onDropImage?(img, url, dropPoint)
            return true
        }
        // 2) 直接的影像資料
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first {
            onDropImage?(img, nil, dropPoint)
            return true
        }
        return false
    }
    private func canAcceptDrag(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        if let types = pb.types, types.contains(.fileURL) {
            return pb.canReadObject(forClasses: [NSURL.self],
                                    options: [.urlReadingContentsConformToTypes: ["public.image"]])
        }
        return false
    }

    // MARK: - Canvas management

    /// 建立指定尺寸、指定底色的空白點陣圖。
    private func makeBlankRep(size: NSSize, fill: NSColor) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(size.width.rounded())),
            pixelsHigh: max(1, Int(size.height.rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            fill.setFill()
            NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill(using: .copy)
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 安裝新的點陣圖為畫布內容，並同步畫面尺寸 / 狀態。
    /// `resetHistory` 為 true 時才清空復原歷史（僅「新增文件」用）。
    private func installBitmap(_ rep: NSBitmapImageRep, resetHistory: Bool) {
        bitmap = rep
        let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        setFrameSize(size)
        PaintState.shared.canvasSize = size
        clearOverlay()
        if resetHistory { history.reset(initial: copyBitmap(rep)) }
        needsDisplay = true
        NotificationCenter.default.post(name: PaintState.canvasResized, object: nil)
    }

    /// 新增空白文件：建立空白畫布並清空歷史。
    func resetCanvas(size: NSSize, fill: NSColor = .white) {
        discardSelection()   // 丟棄未合入的浮動圖片，避免新增後仍殘留
        guard let rep = makeBlankRep(size: size, fill: fill) else { return }
        installBitmap(rep, resetHistory: true)
    }

    private func copyBitmap(_ src: NSBitmapImageRep) -> NSBitmapImageRep {
        let copy = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: src.pixelsWide,
            pixelsHigh: src.pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: copy) {
            NSGraphicsContext.current = ctx
            src.draw(in: NSRect(x: 0, y: 0, width: src.pixelsWide, height: src.pixelsHigh))
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return copy
    }

    /// 從底圖**精確**複製一塊像素（視覺座標、左下原點）。直接搬記憶體：
    /// 不經 lockFocus → 不受螢幕色彩描述檔 / Retina 2x 影響，移動選取不會變色或變糊。
    private func copyPixels(in rect: NSRect) -> NSBitmapImageRep? {
        let x0 = Int(rect.minX.rounded()), w = Int(rect.width.rounded()), h = Int(rect.height.rounded())
        let top = bitmap.pixelsHigh - Int(rect.maxY.rounded())
        guard w > 0, h > 0, x0 >= 0, top >= 0,
              x0 + w <= bitmap.pixelsWide, top + h <= bitmap.pixelsHigh,
              let dst = makeBlankRep(size: NSSize(width: w, height: h), fill: .clear),
              let s = bitmap.bitmapData, let d = dst.bitmapData else { return nil }
        let spp = bitmap.samplesPerPixel
        for row in 0..<h {
            memcpy(d + row * dst.bytesPerRow,
                   s + (top + row) * bitmap.bytesPerRow + x0 * spp,
                   w * spp)
        }
        return dst
    }

    /// 把點陣包成 NSImage（點大小 = 像素大小）。
    private func image(from rep: NSBitmapImageRep) -> NSImage {
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        return img
    }

    /// 把任意 NSImage 轉成指定像素大小的畫布格式點陣（用於反轉色彩等需直接改像素的操作）。
    private func rep(of img: NSImage, size: NSSize) -> NSBitmapImageRep? {
        if let r = img.representations.first as? NSBitmapImageRep, img.representations.count == 1,
           r.pixelsWide == Int(size.width), r.pixelsHigh == Int(size.height),
           r.bitsPerSample == 8, r.samplesPerPixel == 4, !r.isPlanar,
           r.colorSpaceName == .deviceRGB, !r.bitmapFormat.contains(.alphaNonpremultiplied),
           !r.bitmapFormat.contains(.alphaFirst) {
            return r
        }
        guard let rep = makeBlankRep(size: size, fill: .clear) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            img.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 8-bit 預乘 RGBA（與底圖格式一致）。
    private func premultipliedBytes(_ c: NSColor) -> (UInt8, UInt8, UInt8, UInt8) {
        let conv = c.usingColorSpace(.deviceRGB) ?? c
        var rgba: [CGFloat] = [0, 0, 0, 0]
        conv.getComponents(&rgba)
        let a = rgba[3]
        func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (b(rgba[0] * a), b(rgba[1] * a), b(rgba[2] * a), b(a))
    }

    func pushHistory() {
        history.push(copyBitmap(bitmap))
        NotificationCenter.default.post(name: PaintState.documentEdited, object: self)
    }

    /// 通知狀態列目前選取大小。
    private func postSelectionChanged() {
        var info: [String: Int] = [:]
        if let r = selectionRect, r.width > 0, r.height > 0 {
            info = ["w": Int(r.width.rounded()), "h": Int(r.height.rounded())]
        }
        NotificationCenter.default.post(name: PaintState.selectionChanged, object: self, userInfo: info)
    }

    /// 丟棄目前的浮動選取（不合入底圖）。
    private func discardSelection() {
        selectionImage = nil
        selectionRect = nil
        selectionPath = nil
        resizingHandle = nil
        movingSelection = false
        postSelectionChanged()
    }

    func undo() {
        // 尚未合入的浮動插入圖片：復原 = 直接移除它，不動歷史
        if selectionImage != nil {
            discardSelection()
            needsDisplay = true
            return
        }
        cancelPendingShape()
        guard let snap = history.undo() else { return }
        discardSelection()
        installBitmap(copyBitmap(snap), resetHistory: false)
        NotificationCenter.default.post(name: PaintState.documentEdited, object: self)
    }
    func redo() {
        guard let snap = history.redo() else { return }
        discardSelection()
        installBitmap(copyBitmap(snap), resetHistory: false)
        NotificationCenter.default.post(name: PaintState.documentEdited, object: self)
    }
    func canUndo() -> Bool { history.canUndo() }
    func canRedo() -> Bool { history.canRedo() }

    // MARK: - Loading / saving images

    func loadImage(_ image: NSImage) {
        // 取真實像素尺寸（避免 DPI metadata 影響）。
        var pxW = Int(image.size.width.rounded())
        var pxH = Int(image.size.height.rounded())
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            pxW = rep.pixelsWide; pxH = rep.pixelsHigh
        }
        let size = NSSize(width: max(1, pxW), height: max(1, pxH))
        // 以「透明」為底，並用 .copy 原樣搬入像素 → 保留來源圖片的 alpha。
        guard let rep = makeBlankRep(size: size, fill: .clear) else { return }
        installBitmap(rep, resetHistory: false)
        drawInBitmap { ctx in
            ctx.compositingOperation = .copy
            image.draw(in: NSRect(origin: .zero, size: size),
                       from: .zero, operation: .copy, fraction: 1.0)
        }
        // 開啟檔案 = 新文件：以載入後的影像作為歷史起點（undo 不會清空成空白）
        history.reset(initial: copyBitmap(bitmap))
        needsDisplay = true
    }

    func exportData(fileType: NSBitmapImageRep.FileType) -> Data? {
        commitText()
        commitSelection()
        switch fileType {
        case .jpeg, .bmp:
            // 不支援透明的格式：先疊在白底上，否則透明處會變成黑色。
            guard let flat = makeBlankRep(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
                                          fill: .white) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: flat) {
                NSGraphicsContext.current = ctx
                bitmap.draw(in: NSRect(x: 0, y: 0, width: flat.pixelsWide, height: flat.pixelsHigh),
                            from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: false, hints: nil)
                ctx.flushGraphics()
            }
            NSGraphicsContext.restoreGraphicsState()
            let props: [NSBitmapImageRep.PropertyKey: Any] =
                fileType == .jpeg ? [.compressionFactor: 0.92] : [:]
            return flat.representation(using: fileType, properties: props)
        default:
            return bitmap.representation(using: fileType, properties: [:])
        }
    }

    /// 畫布尺寸上限（避免輸入過大數值造成記憶體爆掉）。
    static let maxDimension: CGFloat = 16384

    func scaleCanvas(toSize requested: NSSize) {
        commitSelection()
        let newSize = NSSize(width: min(CanvasView.maxDimension, max(1, requested.width.rounded())),
                             height: min(CanvasView.maxDimension, max(1, requested.height.rounded())))
        let oldImage = currentBitmapImage()
        guard let rep = makeBlankRep(size: newSize, fill: .clear) else { return }
        installBitmap(rep, resetHistory: false)
        drawInBitmap { _ in
            oldImage.draw(in: NSRect(origin: .zero, size: newSize))
        }
        pushHistory()
    }

    /// 把目前底圖包成 NSImage（不含浮動選取）。
    private func currentBitmapImage() -> NSImage {
        let img = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        img.addRepresentation(copyBitmap(bitmap))
        return img
    }

    /// 變更畫布尺寸但**不縮放內容**（延伸時補白底、縮小時裁切），內容左上對齊。
    /// 以拖拉開始時的原始內容為基準重繪，產生單一歷史步驟。
    func resizeCanvasKeepingContent(to newSize: NSSize) {
        beginCanvasResize()
        previewCanvasResize(to: newSize)
        endCanvasResize()
    }

    // MARK: - 畫布大小拖拉 session（內容不縮放，左上對齊）

    private var resizeBaseImage: NSImage?
    private var resizeBaseHeight: CGFloat = 0

    /// 開始一次畫布縮放：記住目前內容作為基準。
    func beginCanvasResize() {
        commitSelection()
        resizeBaseImage = currentBitmapImage()
        resizeBaseHeight = CGFloat(bitmap.pixelsHigh)
    }
    /// 拖拉中即時預覽新尺寸（不寫歷史）。內容以基準影像左上對齊重繪。
    func previewCanvasResize(to newSize: NSSize) {
        guard let base = resizeBaseImage else { return }
        let w = min(CanvasView.maxDimension, max(1, newSize.width.rounded()))
        let h = min(CanvasView.maxDimension, max(1, newSize.height.rounded()))
        guard let rep = makeBlankRep(size: NSSize(width: w, height: h), fill: .white) else { return }
        installBitmap(rep, resetHistory: false)
        drawInBitmap { _ in
            base.draw(at: NSPoint(x: 0, y: h - resizeBaseHeight),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }
    /// 結束縮放：寫入單一歷史步驟。
    func endCanvasResize() {
        guard resizeBaseImage != nil else { return }
        resizeBaseImage = nil
        pushHistory()
    }

    // MARK: - Drawing helpers

    func drawInBitmap(_ block: (NSGraphicsContext) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = ctx
            ctx.shouldAntialias = true
            block(ctx)
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        needsDisplay = true
    }

    func clearOverlay() {
        overlay = NSImage(size: bounds.size)
        needsDisplay = true
    }

    func drawInOverlay(_ block: (NSGraphicsContext) -> Void) {
        overlay = NSImage(size: bounds.size)
        overlay.lockFocus()
        if let ctx = NSGraphicsContext.current {
            block(ctx)
        }
        overlay.unlockFocus()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // 0) 透明棋盤底（透明像素會露出此圖樣）
        drawTransparencyCheckerboard(in: dirtyRect)

        // 1) base bitmap（明確 sourceOver：透明處露出棋盤，而非以 copy 覆寫掉棋盤）
        let src = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        bitmap.draw(in: bounds, from: src, operation: .sourceOver, fraction: 1.0,
                    respectFlipped: true, hints: nil)

        // 2) overlay (preview)
        overlay.draw(in: bounds)

        // 3) selection marquee
        if let sel = selectionRect {
            if let img = selectionImage {
                img.draw(in: sel)
            }
            let p = NSBezierPath(rect: sel)
            p.lineWidth = 1
            NSColor.black.setStroke()
            let dash: [CGFloat] = [4, 4]
            p.setLineDash(dash, count: 2, phase: marchingPhase)
            p.stroke()
            NSColor.white.setStroke()
            p.setLineDash(dash, count: 2, phase: marchingPhase + 4)
            p.stroke()
            // 8 個拖曳把手
            for (_, hr) in handleRects(for: sel) {
                NSColor.white.setFill()
                NSBezierPath(rect: hr).fill()
                NSColor.black.setStroke()
                let hp = NSBezierPath(rect: hr)
                hp.lineWidth = 1
                hp.stroke()
            }
        } else if let path = selectionPath {
            let dash: [CGFloat] = [4, 4]
            path.lineWidth = 1
            NSColor.black.setStroke()
            path.setLineDash(dash, count: 2, phase: marchingPhase)
            path.stroke()
        }

        // 3b) 文字框外框與把手
        drawTextBoxDecoration()

        // 4) gridlines at high zoom
        if PaintState.shared.showGridlines && PaintState.shared.zoom >= 4 {
            NSColor(white: 0.7, alpha: 1).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 0.5 / PaintState.shared.zoom
            for x in stride(from: 0, through: bounds.width, by: 1) {
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.height))
            }
            for y in stride(from: 0, through: bounds.height, by: 1) {
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.width, y: y))
            }
            path.stroke()
        }

        // 5) 拖放高亮
        if isDragHighlight {
            NSColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 0.15).setFill()
            bounds.fill()
            NSColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 0.9).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
            border.lineWidth = 4
            border.setLineDash([10, 6], count: 2, phase: 0)
            border.stroke()
        }
    }

    /// 畫透明棋盤底：白底 + 灰格，透明像素會露出此圖樣。
    /// dirtyRect 在 cacheDisplay 時可能是無限矩形，需與 bounds 取交集後再畫。
    private func drawTransparencyCheckerboard(in dirty: NSRect) {
        let rect = bounds.intersection(dirty.isInfinite ? bounds : dirty)
        guard !rect.isEmpty else { return }
        NSColor.white.setFill()
        rect.fill()
        let cell: CGFloat = 8
        NSColor(white: 0.78, alpha: 1).setFill()
        let x0 = (rect.minX / cell).rounded(.down) * cell
        let y0 = (rect.minY / cell).rounded(.down) * cell
        var y = y0
        while y < rect.maxY {
            var x = x0
            while x < rect.maxX {
                let gx = Int((x / cell).rounded(.down))
                let gy = Int((y / cell).rounded(.down))
                if (gx + gy) % 2 == 0 {
                    NSRect(x: x, y: y, width: cell, height: cell).intersection(rect).fill()
                }
                x += cell
            }
            y += cell
        }
    }

    private func startMarchingAntsTimer() {
        marchingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.selectionRect != nil || self.selectionPath != nil {
                self.marchingPhase = (self.marchingPhase + 1).truncatingRemainder(dividingBy: 8)
                self.needsDisplay = true
            }
        }
        RunLoop.current.add(marchingTimer!, forMode: .common)
    }

    // MARK: - Coordinate conversion (account for view-coordinate scaling)

    /// Convert window-level point to *bitmap-pixel* point (origin top-left of canvas).
    /// View is unflipped; bitmap origin is bottom-left in our drawing code already.
    private func canvasPoint(_ event: NSEvent) -> NSPoint {
        return convert(event.locationInWindow, from: nil)
    }

    private func clampToCanvas(_ p: NSPoint) -> NSPoint {
        NSPoint(
            x: max(0, min(bounds.width, p.x)),
            y: max(0, min(bounds.height, p.y))
        )
    }

    private func currentColor() -> NSColor {
        dragButton == 1 ? PaintState.shared.color2 : PaintState.shared.color1
    }
    private func altColor() -> NSColor {
        dragButton == 1 ? PaintState.shared.color1 : PaintState.shared.color2
    }

    // MARK: - Selection handle geometry

    private func handleRects(for sel: NSRect) -> [(Handle, NSRect)] {
        let s = handleSize
        let mx = sel.midX, my = sel.midY
        let l = sel.minX, r = sel.maxX, t = sel.maxY, b = sel.minY
        @inline(__always) func mk(_ cx: CGFloat, _ cy: CGFloat) -> NSRect {
            NSRect(x: cx - s/2, y: cy - s/2, width: s, height: s)
        }
        return [
            (.nw, mk(l, t)), (.n, mk(mx, t)), (.ne, mk(r, t)),
            (.e,  mk(r, my)),
            (.se, mk(r, b)), (.s, mk(mx, b)), (.sw, mk(l, b)),
            (.w,  mk(l, my)),
        ]
    }
    private func handleAt(_ p: NSPoint) -> Handle? {
        guard let sel = selectionRect else { return nil }
        for (h, hr) in handleRects(for: sel) {
            if hr.insetBy(dx: -2, dy: -2).contains(p) { return h }
        }
        return nil
    }
    /// 以把手 h 拖到 p 後的新矩形（對側固定），寬高至少 minSize。
    static func resized(_ r: NSRect, handle h: Handle, to p: NSPoint, minSize: CGFloat) -> NSRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch h {
        case .nw, .w, .sw: minX = min(p.x, maxX - minSize)
        case .ne, .e, .se: maxX = max(p.x, minX + minSize)
        default: break
        }
        switch h {
        case .nw, .n, .ne: maxY = max(p.y, minY + minSize)
        case .sw, .s, .se: minY = min(p.y, maxY - minSize)
        default: break
        }
        return NSRect(x: minX.rounded(), y: minY.rounded(),
                      width: (maxX - minX).rounded(), height: (maxY - minY).rounded())
    }

    private func applyResize(_ h: Handle, to p: NSPoint) {
        var r = resizeStartRect
        switch h {
        case .nw:
            r = NSRect(x: p.x, y: r.minY, width: r.maxX - p.x, height: p.y - r.minY)
        case .n:
            r = NSRect(x: r.minX, y: r.minY, width: r.width, height: p.y - r.minY)
        case .ne:
            r = NSRect(x: r.minX, y: r.minY, width: p.x - r.minX, height: p.y - r.minY)
        case .e:
            r = NSRect(x: r.minX, y: r.minY, width: p.x - r.minX, height: r.height)
        case .se:
            r = NSRect(x: r.minX, y: p.y, width: p.x - r.minX, height: r.maxY - p.y)
        case .s:
            r = NSRect(x: r.minX, y: p.y, width: r.width, height: r.maxY - p.y)
        case .sw:
            r = NSRect(x: p.x, y: p.y, width: r.maxX - p.x, height: r.maxY - p.y)
        case .w:
            r = NSRect(x: p.x, y: r.minY, width: r.maxX - p.x, height: r.height)
        }
        // 維持最小尺寸 (避免反折)
        if r.width < 4 { r.size.width = 4 }
        if r.height < 4 { r.size.height = 4 }
        selectionRect = NSRect(x: r.origin.x.rounded(), y: r.origin.y.rounded(),
                               width: r.width.rounded(), height: r.height.rounded())
        needsDisplay = true
        postSelectionChanged()
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        // Mac 慣例：Control+點按 等同右鍵（觸控板使用者也能用色彩 2 / 換色橡皮擦）
        dragButton = event.modifierFlags.contains(.control) ? 1 : 0
        handleMouseDown(canvasPoint(event), event: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        dragButton = 1
        handleMouseDown(canvasPoint(event), event: event)
    }
    override func mouseDragged(with event: NSEvent) { handleMouseDragged(canvasPoint(event), event: event) }
    override func rightMouseDragged(with event: NSEvent) { handleMouseDragged(canvasPoint(event), event: event) }
    override func mouseUp(with event: NSEvent) { handleMouseUp(canvasPoint(event), event: event) }
    override func rightMouseUp(with event: NSEvent) { handleMouseUp(canvasPoint(event), event: event) }

    override func mouseMoved(with event: NSEvent) {
        let raw = canvasPoint(event)
        let p = clampToCanvas(raw)
        let imgY = CGFloat(bitmap.pixelsHigh) - p.y
        NotificationCenter.default.post(
            name: PaintState.statusUpdate,
            object: nil,
            userInfo: ["x": Int(p.x), "y": Int(imgY)]
        )
        updateHoverCursor(at: raw)
        // 多邊形：滑鼠移動時預覽下一條邊
        if PaintState.shared.tool == .shape, PaintState.shared.shapeKind == .polygon, !polygonPoints.isEmpty {
            previewPolygon(currentEnd: p)
        }
    }

    /// 滑鼠停在選取上時，依把手/內部切換縮放或移動游標。
    private func updateHoverCursor(at p: NSPoint) {
        if let d = textBoxHit(p) {
            if case let .resize(h, _) = d { Cursors.resizeCursor(for: h).set() } else { Cursors.moveAll.set() }
            return
        }
        guard let sel = selectionRect else { return }   // 無選取 → 交給 cursorRect 的工具游標
        if let h = handleAt(p) {
            Cursors.resizeCursor(for: h).set()
        } else if sel.contains(p) {
            Cursors.moveAll.set()
        } else {
            Cursors.cursor(for: PaintState.shared.tool).set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
    }

    // MARK: - Tool dispatch

    private func handleMouseDown(_ p: NSPoint, event: NSEvent) {
        let tool = PaintState.shared.tool
        let pc = clampToCanvas(p)

        // 0) 文字編輯中：拖框線移動、拖把手縮放文字框
        if let d = textBoxHit(p) {
            textBoxDrag = d
            return
        }

        // 1) 若已有 selection，先檢查是否點到 resize 把手
        if let _ = selectionRect, let h = handleAt(p) {
            resizingHandle = h
            resizeStartRect = selectionRect!
            resizeStartPoint = p
            return
        }
        // 2) 點在 selection 內部 → 開始拖移
        if let sel = selectionRect, sel.contains(pc) {
            movingSelection = true
            moveOffset = NSPoint(x: pc.x - sel.origin.x, y: pc.y - sel.origin.y)
            return
        }
        // 3) 點到 selection 外面 → commit 並繼續處理當前工具
        if selectionRect != nil {
            commitSelection()
        }

        switch tool {
        case .pencil, .brush, .eraser:
            isDrawing = true
            dragStart = pc; dragLast = pc
            drawStroke(from: pc, to: pc, tool: tool)
        case .fill:
            floodFill(at: pc, with: currentColor())
            pushHistory()
        case .picker:
            pickColor(at: pc, intoSecondary: dragButton == 1)
        case .text:
            if activeTextField != nil { commitText() }   // 已在編輯 → 先合入再開新的
            beginText(at: pc)
        case .magnifier:
            // 左鍵放大、右鍵（或 Option）縮小，並以點擊處為中心
            let zoomOut = dragButton == 1 || event.modifierFlags.contains(.option)
            setZoom(PaintState.shared.zoom * (zoomOut ? 0.5 : 2.0), anchor: pc)
        case .shape:
            let kind = PaintState.shared.shapeKind
            if kind == .polygon {
                if polygonPoints.isEmpty {
                    shapeButton = dragButton
                    polygonPoints = [pc]
                } else if event.clickCount >= 2 {
                    finalizePolygon()   // 雙擊 → 封閉
                } else {
                    // 點回起點附近也封閉
                    let p0 = polygonPoints[0]
                    if polygonPoints.count >= 3, hypot(pc.x - p0.x, pc.y - p0.y) <= 4 {
                        finalizePolygon()
                    } else {
                        polygonPoints.append(snapped(from: polygonPoints.last!, to: pc, event: event, line: true))
                        previewPolygon(currentEnd: polygonPoints.last!)
                    }
                }
                isDrawing = false
            } else if kind == .curve {
                // 曲線三步驟：1) 拖出直線 2) 點/拖第一個彎曲點 3) 點/拖第二個彎曲點 → 完成
                if curvePhase == 0 {
                    shapeButton = dragButton
                    isDrawing = true
                    dragStart = pc
                    dragLast = pc
                    curvePoints = [pc, pc]
                } else {
                    isDrawing = true
                    curvePoints.append(pc)
                    previewCurve()
                }
            } else {
                shapeButton = dragButton
                isDrawing = true
                dragStart = pc; dragLast = pc
            }
        case .selectRect, .selectFree:
            beginSelection(at: pc)
        }
    }

    private func handleMouseDragged(_ p: NSPoint, event: NSEvent) {
        let pc = clampToCanvas(p)
        NotificationCenter.default.post(
            name: PaintState.statusUpdate, object: nil,
            userInfo: ["x": Int(pc.x), "y": Int(CGFloat(bitmap.pixelsHigh) - pc.y)]
        )
        if let d = textBoxDrag {
            dragTextBox(d, to: p)
            return
        }
        if let h = resizingHandle {
            applyResize(h, to: p)
            return
        }
        if movingSelection, var sel = selectionRect {
            sel.origin = NSPoint(x: (p.x - moveOffset.x).rounded(), y: (p.y - moveOffset.y).rounded())
            selectionRect = sel
            needsDisplay = true
            return
        }
        let tool = PaintState.shared.tool
        switch tool {
        case .pencil, .brush, .eraser:
            if isDrawing {
                drawStroke(from: dragLast, to: pc, tool: tool)
                dragLast = pc
            }
        case .shape:
            let kind = PaintState.shared.shapeKind
            if kind == .curve {
                if isDrawing, !curvePoints.isEmpty {
                    if curvePhase == 0 {
                        curvePoints[1] = snapped(from: curvePoints[0], to: pc, event: event, line: true)
                    } else {
                        curvePoints[curvePoints.count - 1] = pc   // 拖曳中即時彎曲
                    }
                    previewCurve()
                }
            } else if isDrawing && kind != .polygon {
                previewShape(from: dragStart, to: snapped(from: dragStart, to: pc, event: event, line: kind == .line))
            }
        case .selectRect, .selectFree:
            extendSelection(to: pc)
        default: break
        }
    }

    private func handleMouseUp(_ p: NSPoint, event: NSEvent) {
        let pc = clampToCanvas(p)
        if textBoxDrag != nil {
            textBoxDrag = nil
            if let tv = activeTextField { window?.makeFirstResponder(tv) }
            return
        }
        if resizingHandle != nil {
            resizingHandle = nil
            return
        }
        if movingSelection {
            movingSelection = false
            return
        }
        let tool = PaintState.shared.tool
        switch tool {
        case .pencil, .brush, .eraser:
            if isDrawing {
                drawStroke(from: dragLast, to: pc, tool: tool)
                isDrawing = false
                pushHistory()
            }
        case .shape:
            let kind = PaintState.shared.shapeKind
            if kind == .curve {
                if isDrawing, !curvePoints.isEmpty {
                    isDrawing = false
                    if curvePhase == 0 {
                        curvePoints[1] = snapped(from: curvePoints[0], to: pc, event: event, line: true)
                        // 太短（只是點一下）→ 取消
                        if hypot(curvePoints[1].x - curvePoints[0].x, curvePoints[1].y - curvePoints[0].y) < 1 {
                            cancelPendingShape()
                        } else {
                            curvePhase = 1
                        }
                    } else if curvePhase == 1 {
                        curvePoints[curvePoints.count - 1] = pc
                        curvePhase = 2
                        previewCurve()
                    } else {
                        curvePoints[curvePoints.count - 1] = pc
                        finalizeCurve()
                    }
                }
            } else if kind == .polygon {
                // no-op
            } else if isDrawing {
                clearOverlay()
                drawShape(from: dragStart, to: snapped(from: dragStart, to: pc, event: event, line: kind == .line))
                isDrawing = false
                pushHistory()
            }
        case .selectRect, .selectFree:
            endSelection(at: pc)
        default: break
        }
    }

    // MARK: - Pencil / Brush / Eraser

    private func drawStroke(from a: NSPoint, to b: NSPoint, tool: Tool) {
        // 橡皮擦右鍵：只把「色彩 1」的像素換成「色彩 2」（Windows 小畫家的換色橡皮擦）
        if tool == .eraser && dragButton == 1 {
            replaceColorStroke(from: a, to: b)
            return
        }
        let color = currentColor()
        let st = PaintState.shared
        let size = st.strokeSize
        // 橡皮擦一律用色彩 2（背景色）
        let activeColor = (tool == .eraser) ? st.color2 : color
        let transparent = activeColor.isPaintTransparent
        drawInBitmap { ctx in
            if transparent { ctx.compositingOperation = .clear }
            switch tool {
            case .pencil, .eraser:
                // 鉛筆：不反鋸齒、對齊像素的 n×n 方點；橡皮擦：n×n 方塊
                ctx.shouldAntialias = false
                activeColor.setFill()
                let n = tool == .pencil ? max(1, st.pencilSize.rounded()) : max(1, st.eraserSize.rounded())
                for p in CanvasView.pixelLine(from: a, to: b) {
                    CanvasView.squareRect(at: p, size: n).fill()
                }
            case .brush:
                BrushRenderer.render(kind: st.brushKind, from: a, to: b, color: color, size: size)
            default: break
            }
        }
    }

    /// a→b 之間逐像素的整數點（含兩端）。
    static func pixelLine(from a: NSPoint, to b: NSPoint) -> [NSPoint] {
        let ax = floor(a.x), ay = floor(a.y), bx = floor(b.x), by = floor(b.y)
        let steps = Int(max(abs(bx - ax), abs(by - ay)))
        return (0...max(0, steps)).map { i in
            let t = steps == 0 ? 0 : CGFloat(i) / CGFloat(steps)
            return NSPoint(x: (ax + (bx - ax) * t).rounded(), y: (ay + (by - ay) * t).rounded())
        }
    }
    /// 以像素 p 為中心、邊長 n 的整數方塊（n 為偶數時往左下偏半格）。
    static func squareRect(at p: NSPoint, size n: CGFloat) -> NSRect {
        let off = floor((n - 1) / 2)
        return NSRect(x: p.x - off, y: p.y - off, width: n, height: n)
    }

    /// 換色橡皮擦：筆跡範圍內，與色彩 1 完全相同的像素改成色彩 2（可為透明）。
    private func replaceColorStroke(from a: NSPoint, to b: NSPoint) {
        guard let data = bitmap.bitmapData else { return }
        let st = PaintState.shared
        let from = premultipliedBytes(st.color1)
        let to: (UInt8, UInt8, UInt8, UInt8) = st.color2.isPaintTransparent ? (0, 0, 0, 0) : premultipliedBytes(st.color2)
        let n = max(1, st.eraserSize.rounded())
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh, bpr = bitmap.bytesPerRow
        let spp = bitmap.samplesPerPixel
        for p in CanvasView.pixelLine(from: a, to: b) {
            let r = CanvasView.squareRect(at: p, size: n)
            let x0 = max(0, Int(r.minX)), x1 = min(w, Int(r.maxX))
            let y0 = max(0, Int(r.minY)), y1 = min(h, Int(r.maxY))
            guard x0 < x1, y0 < y1 else { continue }
            for vy in y0..<y1 {
                let row = (h - 1 - vy) * bpr       // 視覺座標 y（左下原點）→ 資料列（上到下）
                for x in x0..<x1 {
                    let o = row + x * spp
                    if data[o] == from.0 && data[o + 1] == from.1 && data[o + 2] == from.2 && data[o + 3] == from.3 {
                        data[o] = to.0; data[o + 1] = to.1; data[o + 2] = to.2; data[o + 3] = to.3
                    }
                }
            }
        }
        needsDisplay = true
    }

    // MARK: - Fill (flood fill)

    /// 給單元測試呼叫的版本（使用 *視覺座標*，原點左下）。
    func testFloodFill(at p: NSPoint, with color: NSColor) {
        floodFill(at: p, with: color)
    }

    /// 給單元測試：直接觸發筆畫繪製（鉛筆/筆刷/橡皮擦）。
    func testStroke(from a: NSPoint, to b: NSPoint, tool: Tool) {
        drawStroke(from: a, to: b, tool: tool)
    }

    /// 給單元測試用：模擬把手 hit-test。
    func testHandleAt(_ p: NSPoint) -> Handle? { handleAt(p) }

    /// 給單元測試用：模擬指定把手拖到某點。
    func testBeginResize(handle: Handle, startRect: NSRect, startPoint: NSPoint) {
        resizingHandle = handle
        resizeStartRect = startRect
        resizeStartPoint = startPoint
    }
    func testApplyResize(to p: NSPoint) {
        guard let h = resizingHandle else { return }
        applyResize(h, to: p)
    }
    func testEndResize() { resizingHandle = nil }

    /// 對外暴露的選取建立 helper（給測試模擬使用者拖選矩形）。
    func testSetRectangularSelection(_ rect: NSRect) {
        commitSelection()
        liftSelection(rect: rect)
    }

    private func floodFill(at p: NSPoint, with color: NSColor) {
        let x = Int(p.x), y = Int(CGFloat(bitmap.pixelsHigh) - p.y)
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh else { return }
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard let data = bitmap.bitmapData else { return }
        let bpr = bitmap.bytesPerRow
        let spp = bitmap.samplesPerPixel

        @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * bpr + x * spp }
        let seed = idx(x, y)
        let t0 = data[seed], t1 = data[seed + 1], t2 = data[seed + 2], t3 = data[seed + 3]
        var rgba: [CGFloat] = [0, 0, 0, 0]
        let conv = color.usingColorSpace(.deviceRGB) ?? color
        conv.getComponents(&rgba)
        let nr = UInt8(rgba[0] * 255), ng = UInt8(rgba[1] * 255), nb = UInt8(rgba[2] * 255), na = UInt8(rgba[3] * 255)

        // 容許度：0% → 僅完全相同色；100% → 任意色。以 RGBA 歐氏距離為基準。
        // 含 alpha：避免不透明黑(0,0,0,255) 與 透明(0,0,0,0) 因 RGB 相同而互相滲漏。
        let tol = PaintState.shared.fillTolerance / 100.0
        let maxDist = (255.0 * 255.0 * 4.0).squareRoot()
        let threshold = tol * maxDist

        if tol <= 0 && (t0, t1, t2, t3) == (nr, ng, nb, na) { return }

        // 與種子色的距離是否在容許度內（比 RGBA）。
        @inline(__always) func matchesSeed(_ i: Int) -> Bool {
            if threshold == 0 {
                return data[i] == t0 && data[i+1] == t1 && data[i+2] == t2 && data[i+3] == t3
            }
            let dr = Double(Int(data[i])   - Int(t0))
            let dg = Double(Int(data[i+1]) - Int(t1))
            let db = Double(Int(data[i+2]) - Int(t2))
            let da = Double(Int(data[i+3]) - Int(t3))
            return (dr*dr + dg*dg + db*db + da*da).squareRoot() <= threshold
        }

        // visited 陣列：容許度模式下，新填的色可能仍落在種子容許度內，
        // 若不標記已訪將造成重複掃描甚至無窮迴圈。
        var visited = [Bool](repeating: false, count: w * h)
        @inline(__always) func vIdx(_ x: Int, _ y: Int) -> Int { y * w + x }

        var stack: [(Int, Int)] = [(x, y)]
        while let (cx, cy) = stack.popLast() {
            if visited[vIdx(cx, cy)] { continue }
            if !matchesSeed(idx(cx, cy)) { continue }

            var lx = cx
            while lx >= 0, !visited[vIdx(lx, cy)], matchesSeed(idx(lx, cy)) { lx -= 1 }
            lx += 1
            var rx = cx
            while rx < w, !visited[vIdx(rx, cy)], matchesSeed(idx(rx, cy)) { rx += 1 }
            rx -= 1
            if lx > rx { continue }
            for xi in lx...rx {
                let i = idx(xi, cy)
                data[i] = nr; data[i+1] = ng; data[i+2] = nb; data[i+3] = na
                visited[vIdx(xi, cy)] = true
            }
            if cy > 0 {
                for xi in lx...rx where !visited[vIdx(xi, cy - 1)] && matchesSeed(idx(xi, cy - 1)) {
                    stack.append((xi, cy - 1))
                }
            }
            if cy < h - 1 {
                for xi in lx...rx where !visited[vIdx(xi, cy + 1)] && matchesSeed(idx(xi, cy + 1)) {
                    stack.append((xi, cy + 1))
                }
            }
        }
        needsDisplay = true
    }

    // MARK: - Color picker

    private func pickColor(at p: NSPoint, intoSecondary: Bool) {
        let x = max(0, min(bitmap.pixelsWide - 1, Int(p.x)))
        let y = max(0, min(bitmap.pixelsHigh - 1, Int(CGFloat(bitmap.pixelsHigh) - p.y)))
        guard let c = bitmap.colorAt(x: x, y: y) else { return }
        if intoSecondary { PaintState.shared.color2 = c }
        else { PaintState.shared.color1 = c }
        PaintState.shared.tool = PaintState.shared.previousDrawingTool
        NotificationCenter.default.post(name: PaintState.colorChanged, object: nil)
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
    }

    // MARK: - Shapes

    private var shapeStroke: NSColor { shapeButton == 1 ? PaintState.shared.color2 : PaintState.shared.color1 }
    private var shapeFill: NSColor { shapeButton == 1 ? PaintState.shared.color1 : PaintState.shared.color2 }

    /// Shift 約束：直線/多邊形邊/曲線端點鎖 45° 角；其他形狀鎖成正方形（正圓）。
    private func snapped(from a: NSPoint, to b: NSPoint, event: NSEvent?, line: Bool) -> NSPoint {
        guard let ev = event, ev.modifierFlags.contains(.shift) else { return b }
        return CanvasView.constrain(from: a, to: b, line: line)
    }

    /// 純函式（方便測試）：Shift 約束後的終點。
    static func constrain(from a: NSPoint, to b: NSPoint, line: Bool) -> NSPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        if line {
            let len = hypot(dx, dy)
            guard len > 0 else { return b }
            let step = CGFloat.pi / 4
            let ang = (atan2(dy, dx) / step).rounded() * step
            // 水平/垂直直接沿軸；45° 斜線取兩軸等長
            if abs(sin(ang)) < 0.01 { return NSPoint(x: b.x, y: a.y) }
            if abs(cos(ang)) < 0.01 { return NSPoint(x: a.x, y: b.y) }
            let d = max(abs(dx), abs(dy))
            return NSPoint(x: a.x + d * (cos(ang) > 0 ? 1 : -1), y: a.y + d * (sin(ang) > 0 ? 1 : -1))
        }
        let d = max(abs(dx), abs(dy))
        return NSPoint(x: a.x + (dx < 0 ? -d : d), y: a.y + (dy < 0 ? -d : d))
    }

    private func previewShape(from a: NSPoint, to b: NSPoint) {
        drawInOverlay { _ in
            ShapeRenderer.draw(
                kind: PaintState.shared.shapeKind,
                from: a, to: b,
                stroke: shapeStroke,
                fill: shapeFill,
                outline: PaintState.shared.outlineStyle,
                fillStyle: PaintState.shared.fillStyle,
                size: PaintState.shared.strokeSize
            )
        }
    }
    private func drawShape(from a: NSPoint, to b: NSPoint) {
        drawInBitmap { _ in
            ShapeRenderer.draw(
                kind: PaintState.shared.shapeKind,
                from: a, to: b,
                stroke: shapeStroke,
                fill: shapeFill,
                outline: PaintState.shared.outlineStyle,
                fillStyle: PaintState.shared.fillStyle,
                size: PaintState.shared.strokeSize
            )
        }
    }

    // MARK: - Polygon

    private func previewPolygon(currentEnd: NSPoint) {
        var pts = polygonPoints
        if pts.last != currentEnd { pts.append(currentEnd) }
        drawInOverlay { _ in
            let path = NSBezierPath()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.line(to: p) }
            shapeStroke.setStroke()
            path.lineWidth = PaintState.shared.strokeSize
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
    private func finalizePolygon() {
        guard polygonPoints.count >= 3 else { polygonPoints.removeAll(); clearOverlay(); return }
        let pts = polygonPoints
        drawInBitmap { _ in
            let path = NSBezierPath()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.line(to: p) }
            path.close()
            if PaintState.shared.fillStyle == .solid {
                shapeFill.setFill()
                path.fill()
            }
            if PaintState.shared.outlineStyle == .solid {
                shapeStroke.setStroke()
                path.lineWidth = PaintState.shared.strokeSize
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
        polygonPoints.removeAll()
        clearOverlay()
        pushHistory()
    }

    // Curve
    private func previewCurve() {
        let pts = curvePoints
        drawInOverlay { _ in
            let path = NSBezierPath()
            path.move(to: pts[0])
            if pts.count == 2 {
                path.line(to: pts[1])
            } else if pts.count == 3 {
                path.curve(to: pts[1], controlPoint1: pts[2], controlPoint2: pts[2])
            } else if pts.count >= 4 {
                path.curve(to: pts[1], controlPoint1: pts[2], controlPoint2: pts[3])
            }
            path.lineWidth = PaintState.shared.strokeSize
            path.lineCapStyle = .round
            shapeStroke.setStroke()
            path.stroke()
        }
    }
    private func finalizeCurve() {
        let pts = curvePoints
        drawInBitmap { _ in
            let path = NSBezierPath()
            path.move(to: pts[0])
            if pts.count >= 4 {
                path.curve(to: pts[1], controlPoint1: pts[2], controlPoint2: pts[3])
            } else if pts.count == 3 {
                path.curve(to: pts[1], controlPoint1: pts[2], controlPoint2: pts[2])
            } else {
                path.line(to: pts[1])
            }
            path.lineWidth = PaintState.shared.strokeSize
            shapeStroke.setStroke()
            path.lineCapStyle = .round
            path.stroke()
        }
        curvePoints.removeAll()
        curvePhase = 0
        clearOverlay()
        pushHistory()
    }

    // MARK: - Selection

    private func beginSelection(at p: NSPoint) {
        commitSelection()
        selectionStart = p
        if PaintState.shared.selectionShape == .rectangle {
            selectionRect = NSRect(origin: p, size: .zero)
        } else {
            let path = NSBezierPath()
            path.move(to: p)
            selectionPath = path
        }
    }
    private func extendSelection(to p: NSPoint) {
        if PaintState.shared.selectionShape == .rectangle {
            let minX = min(selectionStart.x, p.x)
            let minY = min(selectionStart.y, p.y)
            let w = abs(p.x - selectionStart.x)
            let h = abs(p.y - selectionStart.y)
            selectionRect = NSRect(x: minX, y: minY, width: w, height: h)
            needsDisplay = true
            postSelectionChanged()
        } else if let path = selectionPath {
            path.line(to: p)
            needsDisplay = true
        }
    }
    private func endSelection(at p: NSPoint) {
        if PaintState.shared.selectionShape == .rectangle {
            if let r = selectionRect, r.width >= 2 && r.height >= 2 {
                liftSelection(rect: r)
            } else {
                selectionRect = nil
            }
            needsDisplay = true
        } else if let path = selectionPath {
            path.close()
            let bb = path.bounds
            if bb.width >= 2 && bb.height >= 2 {
                liftSelectionFree(path: path)
                selectionPath = nil
            } else {
                selectionPath = nil
            }
            needsDisplay = true
        }
    }
    private func liftSelection(rect: NSRect) {
        let r = NSRect(
            x: floor(rect.origin.x), y: floor(rect.origin.y),
            width: ceil(rect.width), height: ceil(rect.height)
        ).intersection(bounds)
        guard r.width > 0 && r.height > 0, let px = copyPixels(in: r) else { selectionRect = nil; return }
        applyTransparentSelection(px)
        selectionImage = image(from: px)
        drawInBitmap { _ in
            PaintState.shared.color2.setFill()
            r.fill(using: .copy)   // copy：背景色為透明時會清成透明
        }
        selectionRect = r
        postSelectionChanged()
    }

    /// 「透明選取」：浮動選取中等於背景色(color2)的像素變透明（同 Windows 小畫家）。
    private func applyTransparentSelection(_ rep: NSBitmapImageRep) {
        guard PaintState.shared.transparentSelection, let d = rep.bitmapData else { return }
        let (r, g, b, a) = premultipliedBytes(PaintState.shared.color2)
        guard a > 0 else { return }
        let spp = rep.samplesPerPixel, bpr = rep.bytesPerRow
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let i = y * bpr + x * spp
                if d[i] == r && d[i+1] == g && d[i+2] == b && d[i+3] == a {
                    d[i] = 0; d[i+1] = 0; d[i+2] = 0; d[i+3] = 0
                }
            }
        }
    }
    private func liftSelectionFree(path: NSBezierPath) {
        let bb = path.bounds
        let r = NSRect(
            x: floor(bb.origin.x), y: floor(bb.origin.y),
            width: ceil(bb.width), height: ceil(bb.height)
        ).intersection(bounds)
        guard r.width > 0 && r.height > 0,
              let src = copyPixels(in: r),
              let px = makeBlankRep(size: r.size, fill: .clear) else { return }
        // 只保留路徑內的像素（同色彩空間點陣互畫，不經轉換）
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: px) {
            NSGraphicsContext.current = ctx
            if let shifted = path.copy() as? NSBezierPath {
                shifted.transform(using: AffineTransform(translationByX: -r.origin.x, byY: -r.origin.y))
                shifted.addClip()
            }
            src.draw(in: NSRect(origin: .zero, size: r.size), from: .zero, operation: .copy,
                     fraction: 1, respectFlipped: false, hints: nil)
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        applyTransparentSelection(px)
        selectionImage = image(from: px)
        drawInBitmap { ctx in
            ctx.compositingOperation = .copy   // 背景色為透明時也要清掉原處
            PaintState.shared.color2.setFill()
            path.fill()
        }
        selectionRect = r
        postSelectionChanged()
    }

    func commitSelection() {
        if let img = selectionImage, let r0 = selectionRect {
            // 對齊整數像素，避免縮放檢視下拖移產生小數座標 → 合入後變糊
            let r = NSRect(x: r0.origin.x.rounded(), y: r0.origin.y.rounded(),
                           width: max(1, r0.width.rounded()), height: max(1, r0.height.rounded()))
            drawInBitmap { _ in
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            }
            selectionImage = nil
            selectionRect = nil
            selectionPath = nil
            pushHistory()
            needsDisplay = true
            postSelectionChanged()
        } else if selectionRect != nil || selectionPath != nil {
            selectionRect = nil
            selectionPath = nil
            needsDisplay = true
            postSelectionChanged()
        }
    }
    func selectAll() {
        commitSelection()
        PaintState.shared.tool = .selectRect
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
        let r = NSRect(origin: .zero, size: bounds.size)
        liftSelection(rect: r)
        needsDisplay = true
    }

    func cutSelection() -> NSImage? {
        let img = selectionImage
        if img != nil {
            selectionImage = nil
            selectionRect = nil
            pushHistory()
            needsDisplay = true
            postSelectionChanged()
        }
        return img
    }
    func copySelection() -> NSImage? {
        if let img = selectionImage { return img }
        if let r = selectionRect, let px = copyPixels(in: r.intersection(bounds)) {
            return image(from: px)
        }
        return currentBitmapImage()
    }
    func pasteImage(_ img: NSImage) {
        commitSelection()
        PaintState.shared.tool = .selectRect
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
        let size = img.size
        selectionImage = img
        selectionRect = NSRect(origin: NSPoint(x: 0, y: (bounds.height - size.height).rounded()), size: size)
        needsDisplay = true
        postSelectionChanged()
    }

    /// 把圖片以「可移動的浮動選取」疊在現有內容上方（拖入第二張圖時用）。
    /// 放置在 `point` 為中心（畫布座標）；未指定則置中。可拖移、可用把手縮放，
    /// 點選取外即合入底圖。
    func overlayImage(_ img: NSImage, at point: NSPoint? = nil) {
        commitSelection()
        PaintState.shared.selectionShape = .rectangle
        PaintState.shared.tool = .selectRect
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
        let size = img.size
        var origin: NSPoint
        if let p = point {
            origin = NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2)
        } else {
            origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        }
        // 圖片放得進畫布時夾在範圍內；放不進就讓左上角對齊可見處。
        if size.width <= bounds.width {
            origin.x = max(0, min(bounds.width - size.width, origin.x))
        } else {
            origin.x = min(0, max(bounds.width - size.width, origin.x))
        }
        if size.height <= bounds.height {
            origin.y = max(0, min(bounds.height - size.height, origin.y))
        } else {
            origin.y = min(0, max(bounds.height - size.height, origin.y))
        }
        selectionImage = img
        selectionRect = NSRect(origin: NSPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
        needsDisplay = true
        postSelectionChanged()
    }

    // MARK: - 反轉色彩 / 清除

    /// 反轉色彩：有浮動選取時只反轉選取，否則整張畫布（保留 alpha）。
    func invertColors() {
        if let img = selectionImage, let r = selectionRect {
            guard let px = rep(of: img, size: NSSize(width: max(1, r.width.rounded()),
                                                     height: max(1, r.height.rounded()))),
                  let copy = copyRep(px) else { return }
            CanvasView.invertPremultiplied(copy)
            selectionImage = image(from: copy)
            needsDisplay = true
            NotificationCenter.default.post(name: PaintState.documentEdited, object: self)
            return
        }
        commitText()
        CanvasView.invertPremultiplied(bitmap)
        needsDisplay = true
        pushHistory()
    }

    private func copyRep(_ r: NSBitmapImageRep) -> NSBitmapImageRep? { r.copy() as? NSBitmapImageRep }

    /// 預乘 RGBA：反轉後 c' = a − c。
    static func invertPremultiplied(_ rep: NSBitmapImageRep) {
        guard let d = rep.bitmapData else { return }
        let spp = rep.samplesPerPixel, bpr = rep.bytesPerRow
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let i = y * bpr + x * spp
                let a = d[i + 3]
                d[i] = a &- min(a, d[i]); d[i+1] = a &- min(a, d[i+1]); d[i+2] = a &- min(a, d[i+2])
            }
        }
    }

    /// 清除影像：整張畫布填入背景色(color2)。
    func clearImage() {
        commitText()
        discardSelection()
        let c = PaintState.shared.color2
        drawInBitmap { _ in
            c.setFill()
            NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill(using: .copy)
        }
        pushHistory()
    }

    // MARK: - Crop / Rotate / Flip

    func cropToSelection() {
        guard let r0 = selectionRect else { return }
        let r = NSRect(x: r0.origin.x.rounded(), y: r0.origin.y.rounded(),
                       width: max(1, r0.width.rounded()), height: max(1, r0.height.rounded()))
        guard let img = selectionImage ?? copyPixels(in: r.intersection(bounds)).map({ image(from: $0) })
        else { return }
        selectionImage = nil
        selectionRect = nil
        postSelectionChanged()
        // 以「透明」為底並用 .copy 原樣搬入 → 保留裁剪區的透明背景（不再變白）
        guard let rep = makeBlankRep(size: r.size, fill: .clear) else { return }
        installBitmap(rep, resetHistory: false)
        drawInBitmap { ctx in
            ctx.compositingOperation = .copy
            img.draw(in: NSRect(origin: .zero, size: r.size),
                     from: .zero, operation: .copy, fraction: 1.0)
        }
        pushHistory()
    }

    func rotateCanvas(byDegrees deg: CGFloat) {
        commitSelection()
        let radians = deg * .pi / 180
        let s = bounds.size
        let newSize: NSSize
        if Int(deg.truncatingRemainder(dividingBy: 180)) == 0 {
            newSize = s
        } else {
            newSize = NSSize(width: s.height, height: s.width)
        }
        let oldImage = currentBitmapImage()
        guard let rep = makeBlankRep(size: newSize, fill: .clear) else { return }   // 透明為底 → 保留 alpha
        installBitmap(rep, resetHistory: false)
        drawInBitmap { _ in
            let tx = NSAffineTransform()
            tx.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
            tx.rotate(byRadians: radians)
            tx.translateX(by: -s.width / 2, yBy: -s.height / 2)
            tx.concat()
            oldImage.draw(in: NSRect(origin: .zero, size: s))
        }
        pushHistory()
    }

    func flipCanvas(horizontal: Bool) {
        commitSelection()
        let s = bounds.size
        let oldImage = currentBitmapImage()
        guard let rep = makeBlankRep(size: s, fill: .clear) else { return }   // 透明為底 → 保留 alpha
        installBitmap(rep, resetHistory: false)
        drawInBitmap { _ in
            let tx = NSAffineTransform()
            if horizontal {
                tx.translateX(by: s.width, yBy: 0)
                tx.scaleX(by: -1, yBy: 1)
            } else {
                tx.translateX(by: 0, yBy: s.height)
                tx.scaleX(by: 1, yBy: -1)
            }
            tx.concat()
            oldImage.draw(in: NSRect(origin: .zero, size: s))
        }
        pushHistory()
    }

    // MARK: - Text tool

    private var textAnchorTopLeft: NSPoint = .zero   // 文字框左上角（畫布座標）
    /// 使用者拖曳把手設定的固定寬度（nil = 依內容自動延展）與最小高度。
    private var textFixedWidth: CGFloat?
    private var textMinHeight: CGFloat = 0
    /// 正在拖曳文字框：移動或以把手縮放。
    private enum TextBoxDrag { case move(start: NSPoint, origin: NSPoint), resize(Handle, start: NSRect) }
    private var textBoxDrag: TextBoxDrag?

    private func beginText(at p: NSPoint) {
        let font = PaintState.shared.currentTextFont()
        textAnchorTopLeft = NSPoint(x: p.x.rounded(), y: p.y.rounded())
        textFixedWidth = nil
        textMinHeight = 0
        let h: CGFloat = max(40, font.pointSize * 1.8)
        let tv = NSTextView(frame: NSRect(x: textAnchorTopLeft.x, y: textAnchorTopLeft.y - h, width: 60, height: h))
        tv.isRichText = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = PaintState.shared.color1
        tv.font = font
        tv.typingAttributes[.font] = font
        tv.typingAttributes[.foregroundColor] = PaintState.shared.color1
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.delegate = self
        addSubview(tv)
        window?.makeFirstResponder(tv)
        activeTextField = tv
        fitTextView()

        // 顯示文字格式面板（字型/字級/粗體/斜體/底線/顏色）
        let winPt = convert(p, to: nil)
        let screenPt = window?.convertPoint(toScreen: winPt) ?? winPt
        TextFormatPanel.shared.show(for: tv, near: screenPt) { [weak self] in
            self?.fitTextView()
        }
    }

    func textDidChange(_ notification: Notification) { fitTextView() }

    /// 依內容/字型/使用者設定的寬高重算編輯框，左上角固定在 anchor。
    /// 自動模式：寬度隨內容延展（最多到畫布右緣）；固定寬度：在框內自動換行。
    private func fitTextView() {
        guard let tv = activeTextField, let tc = tv.textContainer, let lm = tv.layoutManager else { return }
        let wrapW = textFixedWidth ?? max(20, bounds.width - textAnchorTopLeft.x)
        tc.containerSize = NSSize(width: wrapW, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        // 以與合入時相同的方式量測文字實際範圍（usedRect 在重排後可能回報整個容器寬）
        var used = tv.attributedString().boundingRect(
            with: NSSize(width: wrapW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]).size
        if tv.string.hasSuffix("\n") { used.height += lm.defaultLineHeight(for: tv.font ?? PaintState.shared.currentTextFont()) }
        let lineH = lm.defaultLineHeight(for: tv.font ?? PaintState.shared.currentTextFont())
        let w = textFixedWidth ?? max(60, ceil(used.width) + 6)
        let h = max(textMinHeight, max(lineH, ceil(used.height)) + 4)
        tv.frame = NSRect(x: textAnchorTopLeft.x, y: textAnchorTopLeft.y - h, width: w, height: h)
        needsDisplay = true
    }

    /// 文字框外框（虛線＋8 把手）命中測試：把手 → 縮放；框線附近 → 移動。
    private func textBoxHit(_ p: NSPoint) -> TextBoxDrag? {
        guard let tv = activeTextField else { return nil }
        let f = tv.frame
        for (h, hr) in handleRects(for: f.insetBy(dx: -textBoxPad, dy: -textBoxPad))
            where hr.insetBy(dx: -2, dy: -2).contains(p) {
            return .resize(h, start: f)
        }
        let band = max(6, 6 / max(PaintState.shared.zoom, 0.01))
        if f.insetBy(dx: -band, dy: -band).contains(p) && !f.contains(p) {
            return .move(start: p, origin: textAnchorTopLeft)
        }
        return nil
    }
    private var textBoxPad: CGFloat { 3 }

    private func dragTextBox(_ d: TextBoxDrag, to p: NSPoint) {
        switch d {
        case let .move(start, origin):
            textAnchorTopLeft = NSPoint(x: (origin.x + p.x - start.x).rounded(),
                                        y: (origin.y + p.y - start.y).rounded())
        case let .resize(h, startRect):
            // 把手位於外框（文字區外擴 textBoxPad），換算回文字區
            let pad = textBoxPad
            let r = CanvasView.resized(startRect.insetBy(dx: -pad, dy: -pad), handle: h, to: p,
                                       minSize: 20 + 2 * pad).insetBy(dx: pad, dy: pad)
            textAnchorTopLeft = NSPoint(x: r.minX, y: r.maxY)
            textFixedWidth = r.width
            textMinHeight = r.height
        }
        fitTextView()
    }

    private func drawTextBoxDecoration() {
        guard let tv = activeTextField else { return }
        let box = tv.frame.insetBy(dx: -textBoxPad, dy: -textBoxPad)
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1 / max(PaintState.shared.zoom, 0.01)
        NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.9, alpha: 1).setStroke()
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.stroke()
        for (_, hr) in handleRects(for: box) {
            NSColor.white.setFill(); hr.fill()
            NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.9, alpha: 1).setStroke()
            let hp = NSBezierPath(rect: hr); hp.lineWidth = path.lineWidth; hp.stroke()
        }
    }

    func commitText() {
        guard let tv = activeTextField else { return }
        let attr = tv.attributedString()
        let frame = tv.frame
        TextFormatPanel.shared.hide()
        tv.removeFromSuperview()
        activeTextField = nil
        textBoxDrag = nil
        needsDisplay = true
        if attr.length > 0 {
            drawInBitmap { _ in
                attr.draw(with: frame, options: [.usesLineFragmentOrigin])
            }
            pushHistory()
        }
    }

    // 測試用存取
    var testTextFrame: NSRect? { activeTextField?.frame }
    func testBeginText(at p: NSPoint) { beginText(at: p) }
    func testTypeText(_ s: String) { activeTextField?.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0)); fitTextView() }

    var isEditingText: Bool { activeTextField != nil }

    /// 給單元測試：直接把文字（含字型/顏色/底線）繪入底圖。topLeft 為文字左上角（視覺座標）。
    func testCommitText(_ s: String, at topLeft: NSPoint, font: NSFont, color: NSColor, underline: Bool) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let attr = NSAttributedString(string: s, attributes: attrs)
        let size = attr.size()
        let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width + 4, height: size.height + 2)
        drawInBitmap { _ in attr.draw(in: frame) }
        pushHistory()
    }
}
