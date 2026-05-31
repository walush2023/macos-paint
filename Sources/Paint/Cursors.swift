import AppKit

/// 各工具對應的滑鼠游標。以向量繪製成小圖並快取為 NSCursor。
/// 座標：lockFocus 採左下原點繪製；NSCursor.hotSpot 採左上原點。
enum Cursors {
    private static var cache: [Tool: NSCursor] = [:]

    static func cursor(for tool: Tool) -> NSCursor {
        switch tool {
        case .text:
            return .iBeam
        case .selectRect, .selectFree:
            return .crosshair
        case .shape:
            return .crosshair
        case .brush:
            return cached(.brush) { makeBrushCursor() }
        case .pencil:
            return cached(.pencil) { makePencilCursor() }
        case .fill:
            return cached(.fill) { makeFillCursor() }
        case .eraser:
            return cached(.eraser) { makeEraserCursor() }
        case .picker:
            return cached(.picker) { makePickerCursor() }
        case .magnifier:
            return cached(.magnifier) { makeMagnifierCursor() }
        }
    }

    private static func cached(_ tool: Tool, _ make: () -> NSCursor) -> NSCursor {
        if let c = cache[tool] { return c }
        let c = make()
        cache[tool] = c
        return c
    }

    // MARK: - Drawing helpers

    private static func image(_ size: CGFloat = 24, _ draw: () -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        draw()
        img.unlockFocus()
        return img
    }

    /// 描白邊黑身，確保任何背景都看得到。
    private static func strokeOutlined(_ path: NSBezierPath, fill: NSColor = .black, lineWidth: CGFloat = 1) {
        NSColor.white.setStroke()
        path.lineWidth = lineWidth + 2
        path.stroke()
        fill.setFill()
        path.fill()
        NSColor.black.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    // MARK: - Individual cursors

    private static func makePencilCursor() -> NSCursor {
        let img = image(24) {
            // 鉛筆：右上到左下，尖端在左下 (2,2)（左下原點）
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 4, y: 4))
            body.line(to: NSPoint(x: 18, y: 18))
            body.line(to: NSPoint(x: 21, y: 15))
            body.line(to: NSPoint(x: 7, y: 1))
            body.close()
            NSColor.white.setStroke()
            body.lineWidth = 2.5; body.stroke()
            NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
            body.fill()
            NSColor.black.setStroke()
            body.lineWidth = 1; body.stroke()
            // 筆尖
            let tip = NSBezierPath()
            tip.move(to: NSPoint(x: 4, y: 4))
            tip.line(to: NSPoint(x: 1, y: 1))
            tip.line(to: NSPoint(x: 2.5, y: 5.5))
            tip.line(to: NSPoint(x: 5.5, y: 2.5))
            tip.close()
            NSColor.black.setFill()
            tip.fill()
        }
        // 尖端在左下 → 左上座標系 y = 24 - 1 = 23
        return NSCursor(image: img, hotSpot: NSPoint(x: 1, y: 23))
    }

    private static func makeBrushCursor() -> NSCursor {
        let img = image(24) {
            // 十字準心 + 筆刷點
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: 12, y: 4)); cross.line(to: NSPoint(x: 12, y: 20))
            cross.move(to: NSPoint(x: 4, y: 12)); cross.line(to: NSPoint(x: 20, y: 12))
            NSColor.white.setStroke(); cross.lineWidth = 3; cross.stroke()
            NSColor.black.setStroke(); cross.lineWidth = 1; cross.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }

    private static func makeFillCursor() -> NSCursor {
        let img = image(24) {
            // 油漆桶傾倒，倒出口在左下
            let bucket = NSBezierPath()
            bucket.move(to: NSPoint(x: 8, y: 20))
            bucket.line(to: NSPoint(x: 20, y: 16))
            bucket.line(to: NSPoint(x: 16, y: 6))
            bucket.line(to: NSPoint(x: 5, y: 10))
            bucket.close()
            strokeOutlined(bucket, fill: NSColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1))
            // 提把
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 8, y: 20))
            handle.curve(to: NSPoint(x: 20, y: 16),
                         controlPoint1: NSPoint(x: 12, y: 26),
                         controlPoint2: NSPoint(x: 18, y: 22))
            NSColor.black.setStroke(); handle.lineWidth = 1; handle.stroke()
            // 油漆滴
            let drop = NSBezierPath(ovalIn: NSRect(x: 3, y: 1, width: 5, height: 7))
            NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1).setFill()
            drop.fill()
            NSColor.white.setStroke(); drop.lineWidth = 1; drop.stroke()
        }
        // 滴落點在左下
        return NSCursor(image: img, hotSpot: NSPoint(x: 5, y: 22))
    }

    private static func makeEraserCursor() -> NSCursor {
        let img = image(24) {
            let r = NSBezierPath(rect: NSRect(x: 6, y: 6, width: 12, height: 12))
            NSColor.white.setFill(); r.fill()
            NSColor.black.setStroke(); r.lineWidth = 1.5; r.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }

    private static func makePickerCursor() -> NSCursor {
        let img = image(24) {
            // 滴管：右上到左下，尖端在左下
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 3, y: 3))
            body.line(to: NSPoint(x: 14, y: 14))
            body.line(to: NSPoint(x: 17, y: 11))
            body.line(to: NSPoint(x: 6, y: 0))
            body.close()
            strokeOutlined(body, fill: NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
            // 上方擠壓球
            let bulb = NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 8, height: 8))
            NSColor.white.setStroke(); bulb.lineWidth = 2.5; bulb.stroke()
            NSColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1).setFill(); bulb.fill()
            NSColor.black.setStroke(); bulb.lineWidth = 1; bulb.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 1, y: 23))
    }

    private static func makeMagnifierCursor() -> NSCursor {
        let img = image(24) {
            let circle = NSBezierPath(ovalIn: NSRect(x: 4, y: 8, width: 12, height: 12))
            NSColor.white.setStroke(); circle.lineWidth = 3.5; circle.stroke()
            NSColor.black.setStroke(); circle.lineWidth = 1.5; circle.stroke()
            NSColor(white: 1, alpha: 0.3).setFill(); circle.fill()
            // 手把
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 6, y: 8))
            handle.line(to: NSPoint(x: 1, y: 3))
            NSColor.white.setStroke(); handle.lineWidth = 4; handle.stroke()
            NSColor.black.setStroke(); handle.lineWidth = 2; handle.stroke()
        }
        // 放大鏡中心
        return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 10))
    }
}
