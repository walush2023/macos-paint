import AppKit

/// 自我測試：跑過所有工具的繪製路徑，匯出 PNG 供視覺檢驗。
/// 啟動參數 `--test <output.png>` 觸發。不顯示視窗。
enum SelfTest {
    static func run(outputPath: String) -> Bool {
        let size = NSSize(width: 800, height: 600)
        let canvas = CanvasView(size: size)
        canvas.setFrameSize(size)
        _ = canvas.frame   // ensure created

        // ---- Lay out a grid of demo tiles ----
        let cols: CGFloat = 4
        let rows: CGFloat = 4
        let pad: CGFloat = 16
        let tileW = (size.width - pad * (cols + 1)) / cols
        let tileH = (size.height - pad * (rows + 1)) / rows
        func tileRect(_ i: Int) -> NSRect {
            let c = CGFloat(i % Int(cols))
            let r = CGFloat(i / Int(cols))
            return NSRect(
                x: pad + c * (tileW + pad),
                y: size.height - pad - (r + 1) * tileH - r * pad,
                width: tileW, height: tileH
            )
        }

        canvas.drawInBitmap { _ in
            // tile borders + labels
            NSColor.lightGray.setStroke()
            for i in 0..<16 {
                let r = tileRect(i)
                NSBezierPath(rect: r).stroke()
            }
        }

        // 1) Pencil (red diagonal)
        do {
            let r = tileRect(0)
            canvas.drawInBitmap { _ in
                let p = NSBezierPath()
                p.move(to: NSPoint(x: r.minX + 10, y: r.minY + 10))
                p.line(to: NSPoint(x: r.maxX - 10, y: r.maxY - 10))
                p.lineWidth = 1
                NSColor.red.setStroke()
                p.stroke()
                drawLabel("Pencil", in: r)
            }
        }

        // 2) Brush — round
        do {
            let r = tileRect(1)
            canvas.drawInBitmap { _ in
                BrushRenderer.render(kind: .round,
                    from: NSPoint(x: r.minX + 10, y: r.midY),
                    to: NSPoint(x: r.maxX - 10, y: r.midY),
                    color: .blue, size: 8)
                drawLabel("Brush", in: r)
            }
        }

        // 3) Airbrush
        do {
            let r = tileRect(2)
            canvas.drawInBitmap { _ in
                BrushRenderer.render(kind: .airbrush,
                    from: NSPoint(x: r.minX + 10, y: r.midY),
                    to: NSPoint(x: r.maxX - 10, y: r.midY),
                    color: NSColor(red: 1, green: 0.5, blue: 0, alpha: 1), size: 8)
                drawLabel("Airbrush", in: r)
            }
        }

        // 4) Calligraphy 1
        do {
            let r = tileRect(3)
            canvas.drawInBitmap { _ in
                BrushRenderer.render(kind: .calligraphy1,
                    from: NSPoint(x: r.minX + 10, y: r.minY + 10),
                    to: NSPoint(x: r.maxX - 10, y: r.maxY - 10),
                    color: .purple, size: 6)
                drawLabel("Cal1", in: r)
            }
        }

        // 5) Rectangle outline+fill
        do {
            let r = tileRect(4).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .rect,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: .yellow,
                    outline: .solid, fillStyle: .solid, size: 3)
                drawLabel("Rect", in: tileRect(4))
            }
        }

        // 6) Ellipse fill only
        do {
            let r = tileRect(5).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .ellipse,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: .cyan,
                    outline: FillStyle.none, fillStyle: .solid, size: 3)
                drawLabel("Ellipse", in: tileRect(5))
            }
        }

        // 7) Triangle
        do {
            let r = tileRect(6).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .triangle,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: NSColor(red: 0, green: 0.7, blue: 0.3, alpha: 1),
                    outline: .solid, fillStyle: .solid, size: 3)
                drawLabel("Tri", in: tileRect(6))
            }
        }

        // 8) Star5
        do {
            let r = tileRect(7).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .star5,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .orange, fill: .yellow,
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Star", in: tileRect(7))
            }
        }

        // 9) Hexagon
        do {
            let r = tileRect(8).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .hexagon,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .magenta, fill: NSColor.systemPink,
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Hex", in: tileRect(8))
            }
        }

        // 10) Arrow right
        do {
            let r = tileRect(9).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .arrowRight,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1),
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Arrow", in: tileRect(9))
            }
        }

        // 11) Heart
        do {
            let r = tileRect(10).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .heart,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .red, fill: NSColor(red: 1, green: 0.5, blue: 0.5, alpha: 1),
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Heart", in: tileRect(10))
            }
        }

        // 12) Lightning
        do {
            let r = tileRect(11).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .lightning,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: .yellow,
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Bolt", in: tileRect(11))
            }
        }

        // 13) Cloud callout
        do {
            let r = tileRect(12).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .calloutCloud,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .gray, fill: .white,
                    outline: .solid, fillStyle: .solid, size: 1.5)
                drawLabel("Cloud", in: tileRect(12))
            }
        }

        // 14) Rounded rect (oil brush stroke pattern around)
        do {
            let r = tileRect(13).insetBy(dx: 12, dy: 18)
            canvas.drawInBitmap { _ in
                ShapeRenderer.draw(kind: .roundedRect,
                    from: r.origin, to: NSPoint(x: r.maxX, y: r.maxY),
                    stroke: .black, fill: NSColor.lightGray,
                    outline: .solid, fillStyle: .solid, size: 2)
                drawLabel("Round", in: tileRect(13))
            }
        }

        // 15) Crayon strokes
        do {
            let r = tileRect(14)
            canvas.drawInBitmap { _ in
                BrushRenderer.render(kind: .crayon,
                    from: NSPoint(x: r.minX + 10, y: r.minY + 10),
                    to: NSPoint(x: r.maxX - 10, y: r.maxY - 10),
                    color: .brown, size: 6)
                BrushRenderer.render(kind: .crayon,
                    from: NSPoint(x: r.minX + 10, y: r.maxY - 10),
                    to: NSPoint(x: r.maxX - 10, y: r.minY + 10),
                    color: NSColor(red: 0, green: 0.4, blue: 0, alpha: 1), size: 6)
                drawLabel("Crayon", in: r)
            }
        }

        // 16) Watercolour
        do {
            let r = tileRect(15)
            canvas.drawInBitmap { _ in
                BrushRenderer.render(kind: .watercolour,
                    from: NSPoint(x: r.minX + 10, y: r.midY),
                    to: NSPoint(x: r.maxX - 10, y: r.midY),
                    color: NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), size: 12)
                drawLabel("Water", in: r)
            }
        }

        // ---- Fill test: paint a region, then flood-fill it ----
        // (skipped to keep image readable)

        // ---- Export ----
        guard let data = canvas.exportData(fileType: .png) else {
            FileHandle.standardError.write("✗ 無法產生 PNG 資料\n".data(using: .utf8)!)
            return false
        }
        let url = URL(fileURLWithPath: outputPath)
        do {
            try data.write(to: url)
            print("✓ 已產出 \(outputPath) (\(data.count) bytes)")
            return true
        } catch {
            FileHandle.standardError.write("✗ 寫檔失敗: \(error)\n".data(using: .utf8)!)
            return false
        }
    }

    private static func drawLabel(_ s: String, in r: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(white: 0.3, alpha: 1)
        ]
        (s as NSString).draw(at: NSPoint(x: r.minX + 3, y: r.minY + 3), withAttributes: attrs)
    }
}
