import AppKit

/// 主畫布。底層是位元圖 (`bitmap`)，上層 (`overlay`) 用於形狀/選取預覽。
final class CanvasView: NSView {
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
    private var lastClickTime: TimeInterval = 0

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
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { marchingTimer?.invalidate() }

    @objc private func handleToolChanged() {
        window?.invalidateCursorRects(for: self)
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
            NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
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

    func pushHistory() {
        history.push(copyBitmap(bitmap))
    }

    /// 丟棄目前的浮動選取（不合入底圖）。
    private func discardSelection() {
        selectionImage = nil
        selectionRect = nil
        selectionPath = nil
        resizingHandle = nil
        movingSelection = false
    }

    func undo() {
        guard let snap = history.undo() else { return }
        discardSelection()
        installBitmap(copyBitmap(snap), resetHistory: false)
    }
    func redo() {
        guard let snap = history.redo() else { return }
        discardSelection()
        installBitmap(copyBitmap(snap), resetHistory: false)
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
        commitSelection()
        return bitmap.representation(using: fileType, properties: [:])
    }

    func scaleCanvas(toSize newSize: NSSize) {
        commitSelection()
        let oldImage = currentBitmapImage()
        guard let rep = makeBlankRep(size: newSize, fill: .white) else { return }
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
        let w = max(1, newSize.width.rounded()), h = max(1, newSize.height.rounded())
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
        selectionRect = r
        needsDisplay = true
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        dragButton = 0
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
    }

    /// 滑鼠停在選取上時，依把手/內部切換縮放或移動游標。
    private func updateHoverCursor(at p: NSPoint) {
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
            beginText(at: pc)
        case .magnifier:
            let factor: CGFloat = dragButton == 1 ? 0.5 : 2.0
            let zoom = max(0.1, min(8.0, PaintState.shared.zoom * factor))
            PaintState.shared.zoom = zoom
            NotificationCenter.default.post(name: PaintState.zoomChanged, object: nil)
        case .shape:
            let kind = PaintState.shared.shapeKind
            if kind == .polygon {
                let now = event.timestamp
                if polygonPoints.isEmpty {
                    polygonPoints = [pc]
                } else {
                    let isDouble = (now - lastClickTime) < 0.35
                    if isDouble {
                        finalizePolygon()
                    } else {
                        polygonPoints.append(pc)
                        previewPolygon(currentEnd: pc)
                    }
                }
                lastClickTime = now
                isDrawing = false
            } else if kind == .curve {
                if curvePhase == 0 {
                    isDrawing = true
                    dragStart = pc
                    dragLast = pc
                    curvePoints = [pc, pc]
                } else if curvePhase == 1 {
                    // adding first control point
                    curvePoints.append(pc)
                    previewCurve()
                } else if curvePhase == 2 {
                    // adding second control point; finalize
                    curvePoints.append(pc)
                    finalizeCurve()
                }
            } else {
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
        if let h = resizingHandle {
            applyResize(h, to: p)
            return
        }
        if movingSelection, var sel = selectionRect {
            sel.origin = NSPoint(x: pc.x - moveOffset.x, y: pc.y - moveOffset.y)
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
                if curvePhase == 0 && isDrawing {
                    curvePoints[1] = pc
                    previewCurve()
                }
            } else if isDrawing && kind != .polygon {
                previewShape(from: dragStart, to: pc)
            }
        case .selectRect, .selectFree:
            extendSelection(to: pc)
        default: break
        }
    }

    private func handleMouseUp(_ p: NSPoint, event: NSEvent) {
        let pc = clampToCanvas(p)
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
                if isDrawing && curvePhase == 0 {
                    curvePoints[1] = pc
                    curvePhase = 1
                    isDrawing = false
                }
            } else if kind == .polygon {
                // no-op
            } else if isDrawing {
                clearOverlay()
                drawShape(from: dragStart, to: pc)
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
        let color = currentColor()
        let bg = altColor()
        let size = PaintState.shared.strokeSize
        // 透明色：以 .clear 合成把覆蓋處清成透明。
        let activeColor = (tool == .eraser) ? bg : color
        let transparent = activeColor.isPaintTransparent
        drawInBitmap { ctx in
            if transparent { ctx.compositingOperation = .clear }
            switch tool {
            case .pencil:
                let path = NSBezierPath()
                path.lineWidth = 1
                path.lineCapStyle = .round
                path.move(to: a); path.line(to: b)
                color.setStroke()
                path.stroke()
            case .eraser:
                bg.setFill()
                let half = size / 2
                let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y)))
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let x = a.x + (b.x - a.x) * t
                    let y = a.y + (b.y - a.y) * t
                    NSRect(x: x - half, y: y - half, width: size, height: size).fill()
                }
            case .brush:
                BrushRenderer.render(
                    kind: PaintState.shared.brushKind,
                    from: a, to: b, color: color, size: size
                )
            default: break
            }
        }
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

    private func previewShape(from a: NSPoint, to b: NSPoint) {
        drawInOverlay { _ in
            ShapeRenderer.draw(
                kind: PaintState.shared.shapeKind,
                from: a, to: b,
                stroke: PaintState.shared.color1,
                fill: PaintState.shared.color2,
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
                stroke: PaintState.shared.color1,
                fill: PaintState.shared.color2,
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
            PaintState.shared.color1.setStroke()
            path.lineWidth = PaintState.shared.strokeSize
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
                PaintState.shared.color2.setFill()
                path.fill()
            }
            if PaintState.shared.outlineStyle == .solid {
                PaintState.shared.color1.setStroke()
                path.lineWidth = PaintState.shared.strokeSize
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
            PaintState.shared.color1.setStroke()
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
            } else {
                path.line(to: pts[1])
            }
            path.lineWidth = PaintState.shared.strokeSize
            PaintState.shared.color1.setStroke()
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
        guard r.width > 0 && r.height > 0 else { selectionRect = nil; return }
        let img = NSImage(size: r.size)
        img.lockFocus()
        bitmap.draw(in: NSRect(
            x: -r.origin.x, y: -r.origin.y,
            width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)
        ))
        img.unlockFocus()
        selectionImage = img
        drawInBitmap { _ in
            PaintState.shared.color2.setFill()
            r.fill()
        }
        selectionRect = r
    }
    private func liftSelectionFree(path: NSBezierPath) {
        let bb = path.bounds
        let r = NSRect(
            x: floor(bb.origin.x), y: floor(bb.origin.y),
            width: ceil(bb.width), height: ceil(bb.height)
        ).intersection(bounds)
        guard r.width > 0 && r.height > 0 else { return }
        let img = NSImage(size: r.size)
        img.lockFocus()
        if let shifted = path.copy() as? NSBezierPath {
            let tx = AffineTransform(translationByX: -r.origin.x, byY: -r.origin.y)
            shifted.transform(using: tx)
            shifted.addClip()
        }
        bitmap.draw(in: NSRect(
            x: -r.origin.x, y: -r.origin.y,
            width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)
        ))
        img.unlockFocus()
        selectionImage = img
        drawInBitmap { _ in
            PaintState.shared.color2.setFill()
            path.fill()
        }
        selectionRect = r
    }

    func commitSelection() {
        if let img = selectionImage, let r = selectionRect {
            drawInBitmap { _ in
                img.draw(in: r)
            }
            selectionImage = nil
            selectionRect = nil
            selectionPath = nil
            pushHistory()
            needsDisplay = true
        } else if selectionRect != nil || selectionPath != nil {
            selectionRect = nil
            selectionPath = nil
            needsDisplay = true
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
        }
        return img
    }
    func copySelection() -> NSImage? {
        if let img = selectionImage { return img }
        if let r = selectionRect {
            let img = NSImage(size: r.size)
            img.lockFocus()
            bitmap.draw(in: NSRect(
                x: -r.origin.x, y: -r.origin.y,
                width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)
            ))
            img.unlockFocus()
            return img
        }
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        bitmap.draw(in: bounds)
        img.unlockFocus()
        return img
    }
    func pasteImage(_ img: NSImage) {
        commitSelection()
        PaintState.shared.tool = .selectRect
        NotificationCenter.default.post(name: PaintState.toolChanged, object: nil)
        let size = img.size
        selectionImage = img
        selectionRect = NSRect(origin: NSPoint(x: 0, y: bounds.height - size.height), size: size)
        needsDisplay = true
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
        selectionRect = NSRect(origin: origin, size: size)
        needsDisplay = true
    }

    // MARK: - Crop / Rotate / Flip

    func cropToSelection() {
        guard let r = selectionRect else { return }
        let img = selectionImage ?? {
            let i = NSImage(size: r.size)
            i.lockFocus()
            bitmap.draw(in: NSRect(
                x: -r.origin.x, y: -r.origin.y,
                width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)
            ))
            i.unlockFocus()
            return i
        }()
        selectionImage = nil
        selectionRect = nil
        guard let rep = makeBlankRep(size: r.size, fill: .white) else { return }
        installBitmap(rep, resetHistory: false)
        drawInBitmap { _ in
            img.draw(in: NSRect(origin: .zero, size: r.size))
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
        guard let rep = makeBlankRep(size: newSize, fill: .white) else { return }
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
        guard let rep = makeBlankRep(size: s, fill: .white) else { return }
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

    private func beginText(at p: NSPoint) {
        let tv = NSTextView(frame: NSRect(x: p.x, y: p.y, width: 200, height: 40))
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = PaintState.shared.color1
        tv.font = activeTextFont
        addSubview(tv)
        window?.makeFirstResponder(tv)
        activeTextField = tv
    }
    func commitText() {
        guard let tv = activeTextField else { return }
        let text = tv.string
        let frame = tv.frame
        let font = tv.font ?? activeTextFont
        tv.removeFromSuperview()
        activeTextField = nil
        if !text.isEmpty {
            let color = PaintState.shared.color1
            drawInBitmap { _ in
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style
                ]
                let attr = NSAttributedString(string: text, attributes: attrs)
                attr.draw(in: frame)
            }
            pushHistory()
        }
    }
}
