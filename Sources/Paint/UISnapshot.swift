import AppKit

/// 離線渲染 main window 內容到 PNG。讓我們在無視窗存取時也能視覺檢驗 UI。
enum UISnapshot {
    static func run(outputPath: String) -> Bool {
        // 需要一個 NSApplication 才能建立視窗
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // hidden / non-activating

        let wc = MainWindowController()
        guard let win = wc.window, let content = win.contentView else {
            FileHandle.standardError.write("✗ 視窗或 contentView 為 nil\n".data(using: .utf8)!)
            return false
        }
        // Force layout
        content.layoutSubtreeIfNeeded()
        win.display()

        // Debug: dump immediate children
        print("contentView bounds: \(content.bounds)")
        for v in content.subviews {
            print("  - \(type(of: v)) frame=\(v.frame) hidden=\(v.isHidden)")
        }

        // 渲染整個 contentView
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            FileHandle.standardError.write("✗ bitmapImageRepForCachingDisplay 回 nil\n".data(using: .utf8)!)
            return false
        }
        content.cacheDisplay(in: content.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("✗ PNG 編碼失敗\n".data(using: .utf8)!)
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("✓ 已產出 UI 快照: \(outputPath) (\(data.count) bytes, \(rep.pixelsWide)×\(rep.pixelsHigh))")
            return true
        } catch {
            FileHandle.standardError.write("✗ 寫檔失敗: \(error)\n".data(using: .utf8)!)
            return false
        }
    }

    /// 文字示範：在畫布上以不同字型/樣式繪製文字，渲染結果。
    static func renderTextDemo(outputPath: String) -> Bool {
        _ = NSApplication.shared
        let cv = CanvasView(size: NSSize(width: 420, height: 220))
        cv.setFrameSize(NSSize(width: 420, height: 220))
        let fm = NSFontManager.shared
        var f1 = NSFont(name: "Helvetica", size: 34) ?? NSFont.systemFont(ofSize: 34)
        f1 = fm.convert(f1, toHaveTrait: .boldFontMask)
        cv.testCommitText("Paint for macOS", at: NSPoint(x: 20, y: 190),
                          font: f1, color: NSColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1), underline: false)
        var f2 = NSFont(name: "Times New Roman", size: 30) ?? NSFont.systemFont(ofSize: 30)
        f2 = fm.convert(f2, toHaveTrait: .italicFontMask)
        cv.testCommitText("Italic text", at: NSPoint(x: 20, y: 135),
                          font: f2, color: NSColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1), underline: false)
        cv.testCommitText("Underlined 文字", at: NSPoint(x: 20, y: 85),
                          font: NSFont.systemFont(ofSize: 28),
                          color: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1), underline: true)
        if let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: outputPath))
                print("✓ 已產出文字示範: \(outputPath)")
                return true
            }
        }
        return false
    }

    /// 裁剪保留透明示範：透明底 + 紅圓 → 選取裁剪 → 渲染畫布（透明區應露出棋盤，而非白）。
    static func renderCropDemo(outputPath: String) -> Bool {
        _ = NSApplication.shared
        let cv = CanvasView(size: NSSize(width: 260, height: 200))
        cv.setFrameSize(NSSize(width: 260, height: 200))
        cv.testFloodFill(at: NSPoint(x: 5, y: 5), with: .paintTransparent)   // 整面透明
        cv.drawInBitmap { _ in
            NSColor(srgbRed: 0.9, green: 0.25, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 70, y: 50, width: 110, height: 100)).fill()
        }
        cv.pushHistory()
        cv.testSetRectangularSelection(NSRect(x: 50, y: 35, width: 160, height: 130))
        cv.cropToSelection()
        let a = cv.bitmap.colorAt(x: 3, y: 3)?.alphaComponent ?? 1   // 角落應透明
        print("裁剪後尺寸: \(cv.bitmap.pixelsWide)×\(cv.bitmap.pixelsHigh)，角落 alpha=\(a)")
        if let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: outputPath))
            }
        }
        let ok = a < 0.02
        print(ok ? "✓ 裁剪保留透明" : "✗ 裁剪變不透明")
        return ok
    }

    /// 疊圖示範：先「開啟」一張底圖，再拖入第二張 → 第二張以浮動選取疊在上方，渲染整個視窗。
    static func renderOverlayDemo(outputPath: String) -> Bool {
        _ = NSApplication.shared
        let wc = MainWindowController()
        guard let win = wc.window, let content = win.contentView else { return false }

        // 底圖：橘色 + 對角線（模擬已開啟的圖片）
        let base = NSImage(size: NSSize(width: 360, height: 260))
        base.lockFocus()
        NSColor(srgbRed: 0.95, green: 0.6, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 360, height: 260).fill()
        NSColor.white.setStroke()
        let ln = NSBezierPath(); ln.lineWidth = 6
        ln.move(to: .zero); ln.line(to: NSPoint(x: 360, y: 260)); ln.stroke()
        base.unlockFocus()
        wc.canvas.loadImage(base)
        wc.currentFileURL = URL(fileURLWithPath: "/tmp/base.png")  // 視為「已開啟」

        // 第二張圖：半透明藍圓
        let overlay = NSImage(size: NSSize(width: 140, height: 140))
        overlay.lockFocus()
        NSColor(srgbRed: 0.15, green: 0.4, blue: 0.95, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 130, height: 130)).fill()
        overlay.unlockFocus()

        // 透過真實回呼路徑拖入（currentFileURL 非 nil → 疊加）
        wc.canvas.onDropImage?(overlay, nil, NSPoint(x: 230, y: 110))

        content.layoutSubtreeIfNeeded()
        win.display()
        let overlayActive = wc.canvas.selectionImage != nil
        print("疊加為浮動選取: \(overlayActive)，底圖尺寸: \(wc.canvas.bitmap.pixelsWide)×\(wc.canvas.bitmap.pixelsHigh)")

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return false }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        try? data.write(to: URL(fileURLWithPath: outputPath))
        print(overlayActive ? "✓ 疊圖示範完成" : "✗ 疊圖未生效")
        return overlayActive
    }

    /// 透明示範：紅底挖透明洞 + 不透明藍圓，渲染畫布（洞露出棋盤）並另存實際 PNG。
    static func renderTransparencyDemo(viewPath: String, pngPath: String) -> Bool {
        _ = NSApplication.shared
        let cv = CanvasView(size: NSSize(width: 360, height: 260))
        cv.setFrameSize(NSSize(width: 360, height: 260))
        cv.drawInBitmap { _ in
            NSColor(srgbRed: 0.93, green: 0.30, blue: 0.24, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 360, height: 260).fill()
        }
        // 用透明挖一個圓洞
        cv.drawInBitmap { ctx in
            ctx.compositingOperation = .clear
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 90, y: 60, width: 180, height: 140)).fill()
        }
        // 不透明藍圓覆蓋在洞中（示範「覆蓋透明元素」）
        cv.drawInBitmap { _ in
            NSColor(srgbRed: 0.15, green: 0.45, blue: 0.9, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 150, y: 95, width: 70, height: 70)).fill()
        }
        // 渲染畫布視圖（洞露出棋盤）
        if let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: viewPath))
            }
        }
        // 實際匯出 PNG（保留透明）
        var ok = false
        if let d = cv.exportData(fileType: .png) {
            try? d.write(to: URL(fileURLWithPath: pngPath))
            // 驗證透明區 alpha 0：取挖洞圓內、藍圓外的點（視覺 (110,130) → top-left y=260-1-130）
            if let rep = NSBitmapImageRep(data: d) {
                let a = rep.colorAt(x: 110, y: 260 - 1 - 130)?.alphaComponent ?? 1
                // 同時確認四角仍是不透明紅
                let corner = rep.colorAt(x: 5, y: 5)?.alphaComponent ?? 0
                ok = a < 0.02 && corner > 0.98
                print("透明洞 alpha=\(a)（應≈0）, 邊角 alpha=\(corner)（應≈1）")
            }
        }
        print(ok ? "✓ 透明示範完成，PNG 保留透明" : "✗ 透明示範失敗")
        return ok
    }

    /// 放大渲染所有工具游標到 PNG，方便視覺檢驗。
    static func renderCursors(outputPath: String) -> Bool {
        _ = NSApplication.shared
        let tools: [(NSCursor, String)] = [
            (Cursors.cursor(for: .pencil), tr("鉛筆")), (Cursors.cursor(for: .brush), tr("筆刷")),
            (Cursors.cursor(for: .fill), "油漆桶"), (Cursors.cursor(for: .eraser), tr("橡皮擦")),
            (Cursors.cursor(for: .picker), "滴管"), (Cursors.cursor(for: .magnifier), tr("放大鏡")),
            (Cursors.cursor(for: .selectRect), "選取"), (Cursors.cursor(for: .shape), "形狀"),
            // 調整插入圖片：移動 + 四向縮放
            (Cursors.moveAll, "移動"), (Cursors.resizeNWSE, "縮放↖↘"),
            (Cursors.resizeNESW, "縮放↗↙"), (Cursors.resizeNS, "縮放↕"),
            (Cursors.resizeEW, "縮放↔"),
        ]
        let cell = 200, cols = 4
        let rows = (tools.count + cols - 1) / cols
        let W = cols * cell, H = rows * cell
        let outImg = NSImage(size: NSSize(width: W, height: H))
        outImg.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        // 棋盤背景（看白光暈）+ 深色塊（看亮處）
        for gy in 0..<(H/12) { for gx in 0..<(W/12) {
            if (gx + gy) % 2 == 0 { NSColor(white: 0.85, alpha: 1).setFill()
                NSRect(x: gx*12, y: gy*12, width: 12, height: 12).fill() }
        }}
        for (i, item) in tools.enumerated() {
            let cx = (i % cols) * cell, cy = H - (i / cols + 1) * cell
            // 一半深色背景測試對比
            NSColor(white: 0.25, alpha: 1).setFill()
            NSRect(x: cx, y: cy, width: cell, height: cell/2).fill()
            let cur = item.0
            let img = cur.image
            let drawn: CGFloat = 128
            let ix = CGFloat(cx) + (CGFloat(cell) - drawn)/2
            let iy = CGFloat(cy) + (CGFloat(cell) - drawn)/2 + 8
            img.draw(in: NSRect(x: ix, y: iy, width: drawn, height: drawn))
            // hotspot 紅點（換算到放大後座標）
            let scale = drawn / img.size.width
            let hsx = ix + cur.hotSpot.x * scale
            let hsy = iy + (img.size.height - cur.hotSpot.y) * scale  // hotSpot 左上原點
            NSColor.red.setFill()
            NSBezierPath(ovalIn: NSRect(x: hsx-2, y: hsy-2, width: 4, height: 4)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
            (item.1 as NSString).draw(at: NSPoint(x: CGFloat(cx)+8, y: CGFloat(cy)+6), withAttributes: attrs)
        }
        outImg.unlockFocus()
        guard let tiff = outImg.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        try? data.write(to: URL(fileURLWithPath: outputPath))
        print("✓ 已產出游標預覽: \(outputPath)")
        return true
    }

    /// 模擬把圖片檔拖入視窗：載入 imagePath、觸發拖放回呼、渲染結果。
    static func runDrop(imagePath: String, outputPath: String) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let wc = MainWindowController()
        guard let win = wc.window, let content = win.contentView else { return false }

        guard let img = NSImage(contentsOfFile: imagePath) else {
            FileHandle.standardError.write("✗ 無法讀取圖片: \(imagePath)\n".data(using: .utf8)!)
            return false
        }
        // 走與真實拖放完全相同的回呼路徑（空白畫布 → 載入為整張畫布）
        wc.canvas.onDropImage?(img, URL(fileURLWithPath: imagePath), .zero)

        content.layoutSubtreeIfNeeded()
        win.display()

        // 驗證畫布尺寸已變成圖片尺寸
        let cw = wc.canvas.bitmap.pixelsWide, ch = wc.canvas.bitmap.pixelsHigh
        print("拖放後畫布尺寸: \(cw)×\(ch) (圖片: \(Int(img.size.width))×\(Int(img.size.height)))")

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return false }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("✓ 已產出拖放測試快照: \(outputPath)")
            return cw == Int(img.size.width) && ch == Int(img.size.height)
        } catch { return false }
    }
}
