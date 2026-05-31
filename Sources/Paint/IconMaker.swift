import AppKit

/// 把方形來源圖做成 macOS 風格的圓角（squircle）App 圖標：
/// 內容置於含邊距的圓角矩形內，四角圓潤，符合 Dock 顯示比例。
enum IconMaker {
    static func makeRoundedIcon(input: String, output: String) -> Bool {
        guard let src = NSImage(contentsOfFile: input) else {
            FileHandle.standardError.write("✗ 無法讀取 \(input)\n".data(using: .utf8)!)
            return false
        }
        let S = 1024                     // 輸出畫布
        let margin: CGFloat = 100        // 約 10% 邊距（對齊其他 App 的視覺大小）
        let content = CGFloat(S) - margin * 2          // 824
        let radius = content * 0.2237                  // macOS squircle 約 22.37%

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return false }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            // 透明邊距
            NSColor.clear.set()
            NSRect(x: 0, y: 0, width: S, height: S).fill()

            let rect = NSRect(x: margin, y: margin, width: content, height: content)
            let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            squircle.addClip()                 // 之後所有繪製都被圓角裁切

            // 不透明白底（保證四角為圓潤白色，而非透明/方形）
            NSColor.white.setFill()
            squircle.fill()
            // 來源圖縮放填入圓角區
            src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: output))
            // 回報角落 alpha（圓角外應為 0 透明）
            let a = rep.colorAt(x: 6, y: 6)?.alphaComponent ?? -1
            print("✓ 已產出圓角圖標 \(output)（角落 alpha=\(a)，應≈0）")
            return true
        } catch {
            FileHandle.standardError.write("✗ 寫檔失敗: \(error)\n".data(using: .utf8)!)
            return false
        }
    }
}
