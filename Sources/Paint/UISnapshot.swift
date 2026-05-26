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
}
