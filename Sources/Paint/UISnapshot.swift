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

    /// 放大渲染所有工具游標到 PNG，方便視覺檢驗。
    static func renderCursors(outputPath: String) -> Bool {
        _ = NSApplication.shared
        let tools: [(Tool, String)] = [
            (.pencil, "鉛筆"), (.brush, "筆刷"), (.fill, "油漆桶"),
            (.eraser, "橡皮擦"), (.picker, "滴管"), (.magnifier, "放大鏡"),
            (.selectRect, "選取"), (.shape, "形狀"),
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
            let cur = Cursors.cursor(for: item.0)
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
        // 走與真實拖放完全相同的回呼路徑
        wc.canvas.onDropImage?(img, URL(fileURLWithPath: imagePath))

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
