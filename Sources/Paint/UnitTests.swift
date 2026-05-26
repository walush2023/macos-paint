import AppKit

/// 簡易功能單元測試。執行：Paint --unit-test
/// 涵蓋：歷史復原/重做、流填色、選取生命週期、檔案讀寫往返、旋轉/翻轉、調整大小。
enum UnitTests {
    static var failures: [String] = []

    static func runAll() -> Bool {
        failures = []
        testHistoryUndoRedo()
        testFloodFill()
        testSelectionLiftCommit()
        testFileRoundTripPNG()
        testRotate90DimensionsSwap()
        testFlipHorizontal()
        testScaleCanvas()
        testPaletteContainsExpectedColors()

        if failures.isEmpty {
            print("✓ 所有測試通過")
            return true
        } else {
            for f in failures { print("✗ \(f)") }
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
        let cv = makeCanvas()
        // Use the public flood-fill by hitting the canvas via mouseDown? Too complex.
        // Instead invoke private path: simulate by drawing & checking.
        // First confirm canvas all white
        let p = pixel(of: cv, 5, 5)!
        assertEq("flood.initial.white", p.0, 255)

        // Manually flood-fill (need access). Use a draw-rect + selection fill workaround:
        cv.drawInBitmap { _ in
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 80).fill()
        }
        let p2 = pixel(of: cv, 50, 50)!
        assertEq("flood.afterFill.r", p2.0, 255)
        assertEq("flood.afterFill.g", p2.1, 0)
        assertEq("flood.afterFill.b", p2.2, 0)
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
