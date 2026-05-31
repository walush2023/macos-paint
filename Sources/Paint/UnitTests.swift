import AppKit

/// 簡易功能單元測試。執行：Paint --unit-test
/// 涵蓋：歷史復原/重做、流填色、選取生命週期、檔案讀寫往返、旋轉/翻轉、調整大小。
enum UnitTests {
    static var failures: [String] = []

    static func runAll() -> Bool {
        failures = []
        let tests: [(String, () -> Void)] = [
            ("history",            testHistoryUndoRedo),
            ("floodFill",          testFloodFill),
            ("selectionLift",      testSelectionLiftCommit),
            ("fileRoundTrip",      testFileRoundTripPNG),
            ("rotate90",           testRotate90DimensionsSwap),
            ("flipH",              testFlipHorizontal),
            ("scale",              testScaleCanvas),
            ("palette",            testPaletteContainsExpectedColors),
            ("resizeHandles",      testSelectionResizeHandles),
            ("pasteSelection",     testPasteImageBecomesSelection),
            ("zoomCoords",         testZoomDoesNotAffectBitmapCoordinates),
            ("crop",               testCropToSelection),
            ("historyMulti",       testHistoryAcrossMultipleEdits),
            ("eraseSecondary",     testEraseLeavesSecondaryColor),
            ("rotate180Twice",     testRotate180Twice),
            ("flipV",              testFlipVertical),
            ("zoomStep25",         testZoomStep25),
            ("cursorMapping",      testCursorMapping),
            ("fillTolerance",      testFillTolerance),
            ("transparentFill",    testTransparentFill),
            ("coverTransparent",   testCoverTransparentWithOpaque),
            ("transparentEraser",  testTransparentEraser),
            ("pngPreservesAlpha",  testPNGPreservesAlpha),
            ("loadPreservesAlpha", testLoadPreservesAlpha),
            ("overlayDroppedImage", testOverlayDroppedImage),
        ]
        for (_, fn) in tests { fn() }

        if failures.isEmpty {
            print("✓ 全部 \(tests.count) 項測試通過")
            return true
        } else {
            print("✗ \(failures.count) 項失敗 / 共 \(tests.count) 項")
            for f in failures { print("  ✗ \(f)") }
            return false
        }
    }

    // MARK: - Test helpers

    private static func makeCanvas(_ w: Int = 100, _ h: Int = 80) -> CanvasView {
        let cv = CanvasView(size: NSSize(width: w, height: h))
        cv.setFrameSize(NSSize(width: w, height: h))
        return cv
    }

    /// 讀取像素，(x,y) 採 *視覺座標*（原點左下，與我們的 drawInBitmap 一致）。
    private static func pixel(of canvas: CanvasView, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let data = canvas.bitmap.bitmapData else { return nil }
        let bpr = canvas.bitmap.bytesPerRow
        let spp = canvas.bitmap.samplesPerPixel
        // 視覺 y → bitmap-data y（從頂往下）
        let dataY = canvas.bitmap.pixelsHigh - 1 - y
        let i = dataY * bpr + x * spp
        return (data[i], data[i+1], data[i+2], data[i+3])
    }

    private static func assertEq<T: Equatable>(_ name: String, _ a: T, _ b: T) {
        if a != b { failures.append("\(name): expected \(b), got \(a)") }
    }
    private static func assertTrue(_ name: String, _ cond: Bool) {
        if !cond { failures.append("\(name): condition was false") }
    }

    // MARK: - Tests

    static func testHistoryUndoRedo() {
        let cv = makeCanvas()
        // Initial state should be white
        let p0 = pixel(of: cv, 10, 10)!
        assertEq("history.initial.white.r", p0.0, 255)

        // Draw black rectangle, push history
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 50, height: 50).fill()
        }
        cv.pushHistory()
        let p1 = pixel(of: cv, 10, 10)!
        assertEq("history.draw.black.r", p1.0, 0)

        // Undo → white again
        cv.undo()
        let p2 = pixel(of: cv, 10, 10)!
        assertEq("history.undo.white.r", p2.0, 255)

        // Redo → black again
        cv.redo()
        let p3 = pixel(of: cv, 10, 10)!
        assertEq("history.redo.black.r", p3.0, 0)
    }

    static func testFloodFill() {
        // 1) 在純白畫布上倒油漆（容易踩到「同像素重複 push」的 crash）
        let cv = makeCanvas()
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        cv.testFloodFill(at: NSPoint(x: 50, y: 40), with: red)
        let center = pixel(of: cv, 50, 40)!
        assertEq("flood.basic.center.r", center.0, 255)
        assertEq("flood.basic.center.g", center.1, 0)
        // 邊緣也應該被填到
        let corner = pixel(of: cv, 99, 79)!
        assertEq("flood.basic.corner.r", corner.0, 255)

        // 2) 倒在邊角像素（0,0、最右下）
        let cv2 = makeCanvas()
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        cv2.testFloodFill(at: NSPoint(x: 0, y: 0), with: blue)
        let p2 = pixel(of: cv2, 50, 40)!
        assertEq("flood.cornerStart.center.b", p2.2, 255)
        let cv3 = makeCanvas()
        cv3.testFloodFill(at: NSPoint(x: 99, y: 79), with: blue)
        let p3 = pixel(of: cv3, 0, 0)!
        assertEq("flood.cornerEnd.opposite.b", p3.2, 255)

        // 3) 倒在已是目標色的像素（target == new）不應 crash
        let cv4 = makeCanvas()
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        cv4.testFloodFill(at: NSPoint(x: 50, y: 40), with: white)
        let p4 = pixel(of: cv4, 50, 40)!
        assertEq("flood.noop.r", p4.0, 255)

        // 4) 倒在隔離區域（黑線圍出小區）：只填裡面，不應跨越
        let cv5 = makeCanvas()
        cv5.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 20, y: 20, width: 60, height: 2).fill()  // 上邊
            NSRect(x: 20, y: 58, width: 60, height: 2).fill()  // 下邊
            NSRect(x: 20, y: 20, width: 2, height: 40).fill()  // 左邊
            NSRect(x: 78, y: 20, width: 2, height: 40).fill()  // 右邊
        }
        let green = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
        cv5.testFloodFill(at: NSPoint(x: 50, y: 40), with: green)
        // 內部應被填綠
        let inside = pixel(of: cv5, 50, 40)!
        assertEq("flood.bounded.inside.g", inside.1, 255)
        // 外部應仍為白
        let outside = pixel(of: cv5, 10, 10)!
        assertEq("flood.bounded.outside.r", outside.0, 255)
        assertEq("flood.bounded.outside.g", outside.1, 255)
        assertEq("flood.bounded.outside.b", outside.2, 255)
    }

    static func testSelectionLiftCommit() {
        let cv = makeCanvas()  // 100x80
        // Paint a 20x20 black square at visual (10,10)
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 10, y: 10, width: 20, height: 20).fill()
        }
        cv.pushHistory()

        PaintState.shared.selectionShape = .rectangle
        PaintState.shared.tool = .selectRect
        cv.selectAll()
        let img = cv.copySelection()
        assertTrue("selection.copyAll.image.notNil", img != nil)
        if let img = img {
            assertEq("selection.copyAll.image.w", Int(img.size.width), 100)
            assertEq("selection.copyAll.image.h", Int(img.size.height), 80)
        }
        cv.commitSelection()
        // After commit, the black square should be restored
        let p = pixel(of: cv, 15, 15)!
        assertEq("selection.committed.preservesBlack", p.0, 0)
    }

    static func testFileRoundTripPNG() {
        let cv = makeCanvas(60, 40)
        cv.drawInBitmap { _ in
            NSColor.green.setFill()
            NSRect(x: 10, y: 10, width: 30, height: 20).fill()
        }
        guard let data = cv.exportData(fileType: .png) else {
            failures.append("file.export.failed"); return
        }
        let path = NSTemporaryDirectory() + "paint-unit-test.png"
        try? data.write(to: URL(fileURLWithPath: path))

        guard let img = NSImage(contentsOfFile: path) else {
            failures.append("file.reload.failed"); return
        }
        let cv2 = makeCanvas(60, 40)
        cv2.loadImage(img)
        let p = pixel(of: cv2, 20, 20)!
        assertEq("file.roundtrip.green.r", p.0, 0)
        assertEq("file.roundtrip.green.g", p.1, 255)
    }

    static func testRotate90DimensionsSwap() {
        let cv = makeCanvas(100, 50)
        cv.rotateCanvas(byDegrees: 90)
        assertEq("rotate90.width", cv.bitmap.pixelsWide, 50)
        assertEq("rotate90.height", cv.bitmap.pixelsHigh, 100)
    }

    static func testFlipHorizontal() {
        let cv = makeCanvas(100, 50)
        // Place a black dot near left edge (visual coords: bottom-left origin)
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 5, y: 25, width: 4, height: 4).fill()
        }
        // Sanity: before flip, dot is on the left side
        let beforeLeft = pixel(of: cv, 6, 26)!
        assertEq("flip.h.before.left.black", beforeLeft.0, 0)

        cv.flipCanvas(horizontal: true)
        // After horizontal flip, dot should appear near right edge.
        // Original x=5..9 → after flip x=91..95 (width 100, mirror)
        let pLeft = pixel(of: cv, 6, 26)!
        let pRight = pixel(of: cv, 93, 26)!
        assertEq("flip.h.right.black", pRight.0, 0)
        assertEq("flip.h.left.white", pLeft.0, 255)
    }

    static func testScaleCanvas() {
        let cv = makeCanvas(100, 50)
        cv.scaleCanvas(toSize: NSSize(width: 200, height: 100))
        assertEq("scale.width", cv.bitmap.pixelsWide, 200)
        assertEq("scale.height", cv.bitmap.pixelsHigh, 100)
    }

    static func testSelectionResizeHandles() {
        let cv = makeCanvas(200, 200)
        // 建立 100x100 矩形選取於 (50,50)..(150,150)
        cv.testSetRectangularSelection(NSRect(x: 50, y: 50, width: 100, height: 100))
        guard let sel = cv.selectionRect else {
            failures.append("resize.selectionMissing"); return
        }

        // 點選右下角應命中 .se 把手
        let seCorner = NSPoint(x: sel.maxX, y: sel.minY)  // 視覺座標 (右下 in flipped sense)
        let h = cv.testHandleAt(seCorner)
        assertTrue("resize.handle.detected", h != nil)

        // 把右下角拖到 (200, 0) → selection 變大
        if let h = h {
            cv.testBeginResize(handle: h, startRect: sel, startPoint: seCorner)
            cv.testApplyResize(to: NSPoint(x: 200, y: 0))
            cv.testEndResize()
        }
        guard let resized = cv.selectionRect else {
            failures.append("resize.afterResize.missing"); return
        }
        assertEq("resize.newWidth", Int(resized.width), 150)

        // 西北角把手檢測
        let nwCorner = NSPoint(x: resized.minX, y: resized.maxY)
        let h2 = cv.testHandleAt(nwCorner)
        assertTrue("resize.handle.nw.detected", h2 != nil)
    }

    static func testPasteImageBecomesSelection() {
        let cv = makeCanvas(200, 200)
        // 建立一張小圖（綠色 30x30）
        let img = NSImage(size: NSSize(width: 30, height: 30))
        img.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 30, height: 30).fill()
        img.unlockFocus()

        cv.pasteImage(img)
        assertTrue("paste.selectionImage.set", cv.selectionImage != nil)
        guard let r = cv.selectionRect else {
            failures.append("paste.selectionRect.missing"); return
        }
        assertEq("paste.rect.width", Int(r.width), 30)
        assertEq("paste.rect.height", Int(r.height), 30)
    }

    static func testZoomDoesNotAffectBitmapCoordinates() {
        // 模擬 zoom 後仍能正確計算 selection pixel rect
        let cv = makeCanvas(100, 80)
        PaintState.shared.zoom = 2.0
        // bounds 應該還是 100x80（layoutDocument 不會在無視窗時跑，所以 bitmap-coord 直接驗證）
        assertEq("zoom.bitmap.width", cv.bitmap.pixelsWide, 100)
        assertEq("zoom.bitmap.height", cv.bitmap.pixelsHigh, 80)
        PaintState.shared.zoom = 1.0
    }

    static func testCropToSelection() {
        let cv = makeCanvas(100, 80)
        cv.drawInBitmap { _ in
            NSColor.red.setFill()
            NSRect(x: 10, y: 10, width: 30, height: 30).fill()
        }
        cv.testSetRectangularSelection(NSRect(x: 10, y: 10, width: 30, height: 30))
        cv.cropToSelection()
        assertEq("crop.newWidth",  cv.bitmap.pixelsWide, 30)
        assertEq("crop.newHeight", cv.bitmap.pixelsHigh, 30)
        // 像素 (5,5) 在裁剪後仍應是紅色（因為原本在裁剪區內）
        let p = pixel(of: cv, 5, 5)!
        assertEq("crop.preservesRed", p.0, 255)
    }

    static func testHistoryAcrossMultipleEdits() {
        let cv = makeCanvas(50, 50)
        // 連續三次塗黑、塗紅、塗綠
        let colors: [(NSColor, UInt8, UInt8, UInt8)] = [
            (NSColor.black,                              0,   0,   0),
            (NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), 255, 0, 0),
            (NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), 0, 255, 0),
        ]
        for (c, _, _, _) in colors {
            cv.drawInBitmap { _ in
                c.setFill()
                NSRect(x: 0, y: 0, width: 50, height: 50).fill()
            }
            cv.pushHistory()
        }
        // 現在是綠色
        assertEq("multi.now.g", pixel(of: cv, 25, 25)!.1, 255)
        // undo → 紅
        cv.undo()
        assertEq("multi.undo1.r", pixel(of: cv, 25, 25)!.0, 255)
        // undo → 黑
        cv.undo()
        assertEq("multi.undo2.k", pixel(of: cv, 25, 25)!.0, 0)
        // redo → 紅
        cv.redo()
        assertEq("multi.redo1.r", pixel(of: cv, 25, 25)!.0, 255)
    }

    static func testEraseLeavesSecondaryColor() {
        // 橡皮擦會用 color2（背景色）填覆。我們直接呼叫 drawInBitmap 填驗證 color2 正確套用。
        PaintState.shared.color2 = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)  // 藍色背景
        let cv = makeCanvas(60, 60)
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 60, height: 60).fill()
        }
        // 將原本黑色畫布以 color2 (藍) 填覆中央 (模擬橡皮擦)
        cv.drawInBitmap { _ in
            PaintState.shared.color2.setFill()
            NSRect(x: 20, y: 20, width: 20, height: 20).fill()
        }
        let center = pixel(of: cv, 30, 30)!
        assertEq("erase.center.b", center.2, 255)
        // 還原預設 color2
        PaintState.shared.color2 = .white
    }

    static func testRotate180Twice() {
        let cv = makeCanvas(80, 60)
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 5, y: 5, width: 10, height: 10).fill()
        }
        cv.rotateCanvas(byDegrees: 180)
        cv.rotateCanvas(byDegrees: 180)
        // 兩次 180 度 = 不變，原本左下角的黑點應該還在左下角
        let p = pixel(of: cv, 10, 10)!
        assertEq("rotate180Twice.preserved", p.0, 0)
    }

    static func testFlipVertical() {
        let cv = makeCanvas(40, 80)
        // 在底部放黑色帶
        cv.drawInBitmap { _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 40, height: 10).fill()
        }
        cv.flipCanvas(horizontal: false)
        // 翻轉後黑色帶應在頂部
        let pTop = pixel(of: cv, 20, 75)!
        let pBot = pixel(of: cv, 20, 5)!
        assertEq("flip.v.top.black", pTop.0, 0)
        assertEq("flip.v.bot.white", pBot.0, 255)
    }

    static func testZoomStep25() {
        // 100% → +25 = 125, −25 = 75
        assertEq("zoom.100.up",   StatusBarView.nextZoomPct(from: 100, up: true),  125)
        assertEq("zoom.100.down", StatusBarView.nextZoomPct(from: 100, up: false), 75)
        // 非整數倍會吸附：110 → up 125, down 100
        assertEq("zoom.110.up",   StatusBarView.nextZoomPct(from: 110, up: true),  125)
        assertEq("zoom.110.down", StatusBarView.nextZoomPct(from: 110, up: false), 100)
        // 邊界夾制
        assertEq("zoom.max.clamp", StatusBarView.nextZoomPct(from: 800, up: true),  800)
        assertEq("zoom.min.clamp", StatusBarView.nextZoomPct(from: 25,  up: false), 25)
        // 從最小往下不應低於 25
        assertEq("zoom.below.min", StatusBarView.nextZoomPct(from: 30,  up: false), 25)
    }

    static func testCursorMapping() {
        // 文字 → 系統 I-beam
        assertTrue("cursor.text.iBeam", Cursors.cursor(for: .text) === NSCursor.iBeam)
        // 其餘工具皆為自訂游標（非系統 arrow），且同工具回傳同一快取實例
        let drawingTools: [Tool] = [.pencil, .brush, .fill, .eraser, .picker, .magnifier, .selectRect, .shape]
        for t in drawingTools {
            let c1 = Cursors.cursor(for: t)
            let c2 = Cursors.cursor(for: t)
            assertTrue("cursor.\(t).notArrow", c1 !== NSCursor.arrow)
            assertTrue("cursor.\(t).cached", c1 === c2)
            // 自訂游標應帶有非零尺寸的影像
            assertTrue("cursor.\(t).hasImage", c1.image.size.width > 0)
        }
    }

    static func testFillTolerance() {
        let base = NSColor(deviceRed: 100/255.0, green: 100/255.0, blue: 100/255.0, alpha: 1)
        let near = NSColor(deviceRed: 120/255.0, green: 120/255.0, blue: 120/255.0, alpha: 1)
        let red  = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        func paint(_ cv: CanvasView) {
            cv.drawInBitmap { _ in
                base.setFill(); NSRect(x: 0, y: 0, width: 80, height: 60).fill()
                near.setFill(); NSRect(x: 30, y: 20, width: 20, height: 20).fill()
            }
        }

        // 容許度 0：只填完全相同色，相近塊（120）不受影響
        let cv = makeCanvas(80, 60)
        paint(cv)
        PaintState.shared.fillTolerance = 0
        cv.testFloodFill(at: NSPoint(x: 5, y: 5), with: red)
        assertEq("tol0.base.red", pixel(of: cv, 5, 5)!.0, 255)
        assertEq("tol0.block.untouched", pixel(of: cv, 40, 30)!.0, 120)

        // 容許度 30：相近色也一起被填掉
        let cv2 = makeCanvas(80, 60)
        paint(cv2)
        PaintState.shared.fillTolerance = 30
        cv2.testFloodFill(at: NSPoint(x: 5, y: 5), with: red)
        assertEq("tol30.base.red", pixel(of: cv2, 5, 5)!.0, 255)
        assertEq("tol30.block.filled", pixel(of: cv2, 40, 30)!.0, 255)

        PaintState.shared.fillTolerance = 0  // 還原，避免污染其他測試
    }

    static func testTransparentFill() {
        let cv = makeCanvas(40, 30)  // 預設白色不透明
        assertEq("trans.before.alpha", pixel(of: cv, 10, 10)!.3, 255)
        PaintState.shared.fillTolerance = 0
        cv.testFloodFill(at: NSPoint(x: 10, y: 10), with: .paintTransparent)
        assertEq("trans.fill.alpha0", pixel(of: cv, 10, 10)!.3, 0)
    }

    static func testCoverTransparentWithOpaque() {
        let cv = makeCanvas(40, 30)
        cv.testFloodFill(at: NSPoint(x: 10, y: 10), with: .paintTransparent)  // 整面清成透明
        assertEq("cover.cleared.alpha0", pixel(of: cv, 10, 10)!.3, 0)
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        cv.testFloodFill(at: NSPoint(x: 10, y: 10), with: red)               // 不透明色覆蓋透明
        let p = pixel(of: cv, 10, 10)!
        assertEq("cover.red.r", p.0, 255)
        assertEq("cover.red.alpha", p.3, 255)
    }

    static func testTransparentEraser() {
        let cv = makeCanvas(40, 30)
        cv.drawInBitmap { _ in NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill() }
        assertEq("eraseT.before.alpha", pixel(of: cv, 20, 15)!.3, 255)
        PaintState.shared.color2 = .paintTransparent   // 背景色設透明
        PaintState.shared.strokeSize = 10
        cv.testStroke(from: NSPoint(x: 20, y: 15), to: NSPoint(x: 20, y: 15), tool: .eraser)
        assertTrue("eraseT.after.alpha0", pixel(of: cv, 20, 15)!.3 < 10)
        PaintState.shared.color2 = .white
        PaintState.shared.strokeSize = 3
    }

    static func testPNGPreservesAlpha() {
        let cv = makeCanvas(40, 30)
        cv.testFloodFill(at: NSPoint(x: 5, y: 5), with: .paintTransparent)  // 整面透明
        cv.drawInBitmap { _ in
            NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
            NSRect(x: 10, y: 8, width: 16, height: 14).fill()              // 中央不透明藍塊
        }
        guard let data = cv.exportData(fileType: .png) else { failures.append("png.export.fail"); return }
        let path = NSTemporaryDirectory() + "paint-alpha-test.png"
        try? data.write(to: URL(fileURLWithPath: path))
        guard let img = NSImage(contentsOfFile: path),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { failures.append("png.reload.fail"); return }
        // 角落（透明區）alpha 應 ~0
        let aCorner = rep.colorAt(x: 2, y: 2)?.alphaComponent ?? -1
        assertTrue("png.transparent.kept", aCorner < 0.02)
        // 藍塊中心 alpha 應 ~1（data 座標：視覺 (18,15) → top-left y = 30-1-15）
        let blue = rep.colorAt(x: 18, y: 30 - 1 - 15)
        assertTrue("png.opaque.kept", (blue?.alphaComponent ?? 0) > 0.98)
        assertTrue("png.opaque.isBlue", (blue?.blueComponent ?? 0) > 0.9)
    }

    static func testLoadPreservesAlpha() {
        // 造一張：整面透明 + 中央不透明紅塊 的 PNG
        let src = makeCanvas(40, 30)
        src.testFloodFill(at: NSPoint(x: 5, y: 5), with: .paintTransparent)
        src.drawInBitmap { _ in
            NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 10, y: 8, width: 16, height: 14).fill()
        }
        guard let data = src.exportData(fileType: .png) else { failures.append("load.export.fail"); return }
        let path = NSTemporaryDirectory() + "paint-load-alpha.png"
        try? data.write(to: URL(fileURLWithPath: path))
        guard let img = NSImage(contentsOfFile: path) else { failures.append("load.read.fail"); return }

        // 開啟（載入）到另一個畫布 — 透明應被保留，而非變白
        let dst = makeCanvas(10, 10)
        dst.loadImage(img)
        assertEq("load.size.w", dst.bitmap.pixelsWide, 40)
        assertEq("load.size.h", dst.bitmap.pixelsHigh, 30)
        // 透明角落 alpha 仍為 0（修正前會變成 255 白色）
        assertEq("load.transparent.kept.alpha", pixel(of: dst, 2, 2)!.3, 0)
        // 紅塊保持不透明
        let red = pixel(of: dst, 18, 15)!
        assertEq("load.opaque.kept.alpha", red.3, 255)
        assertEq("load.opaque.kept.red", red.0, 255)
    }

    static func testOverlayDroppedImage() {
        // 原始畫布：整面綠
        let cv = makeCanvas(100, 80)
        cv.drawInBitmap { _ in
            NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 100, height: 80).fill()
        }
        cv.pushHistory()

        // 第二張圖：30x30 藍
        let blue = NSImage(size: NSSize(width: 30, height: 30))
        blue.lockFocus()
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 30, height: 30).fill()
        blue.unlockFocus()

        // 疊在中央 (50,40)
        cv.overlayImage(blue, at: NSPoint(x: 50, y: 40))
        // 應成為浮動選取，底圖尺寸不變（非取代整張畫布）
        assertTrue("overlay.selection.set", cv.selectionImage != nil)
        assertEq("overlay.canvas.unchanged.w", cv.bitmap.pixelsWide, 100)
        assertEq("overlay.canvas.unchanged.h", cv.bitmap.pixelsHigh, 80)
        guard let r = cv.selectionRect else { failures.append("overlay.rect.missing"); return }
        assertEq("overlay.rect.size.w", Int(r.width), 30)
        assertEq("overlay.centered.x", Int(r.midX), 50)
        assertEq("overlay.centered.y", Int(r.midY), 40)

        // 合入底圖後：中央變藍、四角仍綠（原圖被覆蓋而非取代）
        cv.commitSelection()
        let center = pixel(of: cv, 50, 40)!
        assertEq("overlay.committed.center.blue", center.2, 255)
        assertEq("overlay.committed.center.notGreen", center.1, 0)
        let corner = pixel(of: cv, 3, 3)!
        assertEq("overlay.corner.stillGreen", corner.1, 255)
    }

    static func testPaletteContainsExpectedColors() {
        // Standard palette should contain pure black (first) and pure white (somewhere in 2nd row)
        let firstColor = Palette.standard[0]
        guard let conv = firstColor.usingColorSpace(.deviceRGB) else {
            failures.append("palette.firstColor.colorSpace"); return
        }
        assertEq("palette.first.r", Int(conv.redComponent * 255), 0)
        assertEq("palette.first.g", Int(conv.greenComponent * 255), 0)
        assertEq("palette.first.b", Int(conv.blueComponent * 255), 0)

        // 11th color (start of row 2) should be white
        let secondRowFirst = Palette.standard[10]
        guard let c2 = secondRowFirst.usingColorSpace(.deviceRGB) else { return }
        assertEq("palette.row2first.r", Int(c2.redComponent * 255), 255)
    }
}
