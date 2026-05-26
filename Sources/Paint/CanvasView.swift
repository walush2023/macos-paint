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

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        resetCanvas(size: size, fill: .white)
        startMarchingAntsTimer()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { marchingTimer?.invalidate() }

    // MARK: - Canvas management

    func resetCanvas(size: NSSize, fill: NSColor = .white) {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        bitmap = rep
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            fill.setFill()
            NSRect(origin: .zero, size: size).fill()
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        setFrameSize(size)
        history.reset(initial: copyBitmap(rep))
        clearOverlay()
        needsDisplay = true
        PaintState.shared.canvasSize = size
        NotificationCenter.default.post(name: PaintState.canvasResized, object: nil)
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

    func undo() {
        if let snap = history.undo() {
            commitSelectionWithoutHistory()
            bitmap = copyBitmap(snap)
            needsDisplay = true
        }
    }
    func redo() {
        if let snap = history.redo() {
            commitSelectionWithoutHistory()
            bitmap = copyBitmap(snap)
            needsDisplay = true
        }
    }

    // MARK: - Loading / saving images

    func loadImage(_ image: NSImage) {
        let size = image.size
        resetCanvas(size: size, fill: .white)
        drawInBitmap { _ in
            image.draw(in: NSRect(origin: .zero, size: size))
        }
        history.reset(initial: copyBitmap(bitmap))
        needsDisplay = true
    }

    func exportData(fileType: NSBitmapImageRep.FileType) -> Data? {
        commitSelection()
        return bitmap.representation(using: fileType, properties: [:])
    }

    func scaleCanvas(toSize newSize: NSSize) {
        commitSelection()
        let old = bitmap!
        let oldImage = NSImage(size: NSSize(width: old.pixelsWide, height: old.pixelsHigh))
        oldImage.addRepresentation(old)
        resetCanvas(size: newSize, fill: .white)
        drawInBitmap { _ in
            oldImage.draw(in: NSRect(origin: .zero, size: newSize))
        }
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
        // 1) base bitmap
        bitmap.draw(in: bounds)

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
        let p = clampToCanvas(canvasPoint(event))
        let imgY = CGFloat(bitmap.pixelsHigh) - p.y
        NotificationCenter.default.post(
            name: PaintState.statusUpdate,
            object: nil,
            userInfo: ["x": Int(p.x), "y": Int(imgY)]
        )
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
        drawInBitmap { _ in
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
        let t0 = data[idx(x, y)], t1 = data[idx(x, y) + 1], t2 = data[idx(x, y) + 2], t3 = data[idx(x, y) + 3]
        var rgba: [CGFloat] = [0, 0, 0, 0]
        let conv = color.usingColorSpace(.deviceRGB) ?? color
        conv.getComponents(&rgba)
        let nr = UInt8(rgba[0] * 255), ng = UInt8(rgba[1] * 255), nb = UInt8(rgba[2] * 255), na = UInt8(rgba[3] * 255)
        if (t0, t1, t2, t3) == (nr, ng, nb, na) { return }

        @inline(__always) func matches(_ i: Int) -> Bool {
            data[i] == t0 && data[i+1] == t1 && data[i+2] == t2 && data[i+3] == t3
        }

        var stack: [(Int, Int)] = [(x, y)]
        while let (cx, cy) = stack.popLast() {
            // 同一像素可能從不同列被 push 兩次；pop 時已被先前的 scan 填過
            // 此時起始像素不再 match，會讓 lx > rx 造成 Range crash，直接跳過。
            guard matches(idx(cx, cy)) else { continue }

            var lx = cx
            while lx >= 0, matches(idx(lx, cy)) { lx -= 1 }
            lx += 1
            var rx = cx
            while rx < w, matches(idx(rx, cy)) { rx += 1 }
            rx -= 1
            if lx > rx { continue }
            for xi in lx...rx {
                let i = idx(xi, cy)
                data[i] = nr; data[i+1] = ng; data[i+2] = nb; data[i+3] = na
            }
            if cy > 0 {
                for xi in lx...rx where matches(idx(xi, cy - 1)) {
                    stack.append((xi, cy - 1))
                }
            }
            if cy < h - 1 {
                for xi in lx...rx where matches(idx(xi, cy + 1)) {
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
    private func commitSelectionWithoutHistory() {
        if let img = selectionImage, let r = selectionRect {
            drawInBitmap { _ in
                img.draw(in: r)
            }
        }
        selectionImage = nil
        selectionRect = nil
        selectionPath = nil
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
        resetCanvas(size: r.size, fill: .white)
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
        let old = bitmap!
        let oldImage = NSImage(size: s)
        oldImage.addRepresentation(old)
        resetCanvas(size: newSize, fill: .white)
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
        let old = bitmap!
        let oldImage = NSImage(size: s)
        oldImage.addRepresentation(old)
        resetCanvas(size: s, fill: .white)
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
