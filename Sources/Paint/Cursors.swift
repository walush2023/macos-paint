import AppKit

/// 各工具對應的滑鼠游標。以向量繪製、2x 點陣輸出（retina 清晰）並快取為 NSCursor。
/// 繪圖座標：左下原點（與 drawInBitmap 一致）；NSCursor.hotSpot：左上原點。
enum Cursors {
    private static var cache: [Tool: NSCursor] = [:]
    private static let sqrt2 = CGFloat(2).squareRoot()

    static func cursor(for tool: Tool) -> NSCursor {
        switch tool {
        case .text:
            return .iBeam
        case .selectRect, .selectFree, .shape:
            return cached(tool) { makeCrosshair() }
        case .brush:        return cached(.brush)     { makeBrushCursor() }
        case .pencil:       return cached(.pencil)    { makePencilCursor() }
        case .fill:         return cached(.fill)      { makeFillCursor() }
        case .eraser:       return cached(.eraser)    { makeEraserCursor() }
        case .picker:       return cached(.picker)    { makePickerCursor() }
        case .magnifier:    return cached(.magnifier) { makeMagnifierCursor() }
        }
    }

    private static func cached(_ tool: Tool, _ make: () -> NSCursor) -> NSCursor {
        if let c = cache[tool] { return c }
        let c = make(); cache[tool] = c; return c
    }

    // MARK: - 縮放 / 移動游標（選取把手用）

    /// 對角雙箭頭（↖↘）。
    static let resizeNWSE: NSCursor = makeDoubleArrow(angle: -.pi / 4, hot: NSPoint(x: 12, y: 12))
    /// 對角雙箭頭（↗↙）。
    static let resizeNESW: NSCursor = makeDoubleArrow(angle: .pi / 4, hot: NSPoint(x: 12, y: 12))
    /// 上下雙箭頭。
    static let resizeNS: NSCursor = makeDoubleArrow(angle: .pi / 2, hot: NSPoint(x: 12, y: 12))
    /// 左右雙箭頭。
    static let resizeEW: NSCursor = makeDoubleArrow(angle: 0, hot: NSPoint(x: 12, y: 12))
    /// 四向移動。
    static let moveAll: NSCursor = makeMoveCursor()

    private static func makeDoubleArrow(angle: CGFloat, hot: NSPoint) -> NSCursor {
        let img = image(24) {
            let c = NSPoint(x: 12, y: 12)
            let len: CGFloat = 8, head: CGFloat = 3.5
            let dx = cos(angle), dy = sin(angle)
            let a = NSPoint(x: c.x - dx*len, y: c.y - dy*len)
            let b = NSPoint(x: c.x + dx*len, y: c.y + dy*len)
            let shaft = NSBezierPath()
            shaft.move(to: a); shaft.line(to: b)
            // 箭頭
            func arrow(at p: NSPoint, dirX: CGFloat, dirY: CGFloat) {
                let perpX = -dirY, perpY = dirX
                shaft.move(to: p)
                shaft.line(to: NSPoint(x: p.x - dirX*head + perpX*head, y: p.y - dirY*head + perpY*head))
                shaft.move(to: p)
                shaft.line(to: NSPoint(x: p.x - dirX*head - perpX*head, y: p.y - dirY*head - perpY*head))
            }
            arrow(at: b, dirX: dx, dirY: dy)
            arrow(at: a, dirX: -dx, dirY: -dy)
            NSColor.white.setStroke(); shaft.lineWidth = 3.4; shaft.lineCapStyle = .round; shaft.stroke()
            NSColor.black.setStroke(); shaft.lineWidth = 1.5; shaft.stroke()
        }
        return NSCursor(image: img, hotSpot: hot)
    }

    private static func makeMoveCursor() -> NSCursor {
        let img = image(24) {
            let c = NSPoint(x: 12, y: 12)
            let p = NSBezierPath()
            for ang in stride(from: 0.0, to: 2 * .pi, by: .pi / 2) {
                let dx = cos(ang), dy = sin(ang)
                let tip = NSPoint(x: c.x + dx*9, y: c.y + dy*9)
                let base = NSPoint(x: c.x + dx*4.5, y: c.y + dy*4.5)
                let perpX = -dy, perpY = dx
                p.move(to: base); p.line(to: tip)
                p.move(to: tip); p.line(to: NSPoint(x: tip.x - dx*3.5 + perpX*3.5, y: tip.y - dy*3.5 + perpY*3.5))
                p.move(to: tip); p.line(to: NSPoint(x: tip.x - dx*3.5 - perpX*3.5, y: tip.y - dy*3.5 - perpY*3.5))
            }
            NSColor.white.setStroke(); p.lineWidth = 3.4; p.lineCapStyle = .round; p.stroke()
            NSColor.black.setStroke(); p.lineWidth = 1.5; p.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }

    /// 依把手位置回傳對應的縮放游標。
    static func resizeCursor(for handle: CanvasView.Handle) -> NSCursor {
        switch handle {
        case .nw, .se: return resizeNWSE
        case .ne, .sw: return resizeNESW
        case .n, .s:   return resizeNS
        case .e, .w:   return resizeEW
        }
    }

    // MARK: - 繪圖基礎

    /// 以 2x 點陣繪製 size×size 點的游標圖，回傳 retina-ready NSImage。
    private static func image(_ size: CGFloat = 24, scale: CGFloat = 2, _ draw: () -> Void) -> NSImage {
        let px = Int(size * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return NSImage(size: NSSize(width: size, height: size)) }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.cgContext.scaleBy(x: scale, y: scale)   // 在「點」座標系繪製
            ctx.shouldAntialias = true
            ctx.cgContext.setLineJoin(.round)
            ctx.cgContext.setLineCap(.round)
            draw()
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    /// 先描白色光暈再填色、最後細黑邊：任何背景都看得清。
    private static func paint(_ path: NSBezierPath, fill: NSColor, halo: CGFloat = 2.4, line: CGFloat = 0.9,
                             shadow: Bool = false) {
        if shadow {
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
            sh.shadowBlurRadius = 1.5
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.set()
        }
        NSColor.white.setStroke(); path.lineWidth = halo; path.stroke()
        if shadow { NSGraphicsContext.restoreGraphicsState() }
        fill.setFill(); path.fill()
        NSColor.black.withAlphaComponent(0.85).setStroke(); path.lineWidth = line; path.stroke()
    }

    private static func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
    }

    // MARK: - 十字準心 (選取 / 形狀)

    private static func makeCrosshair() -> NSCursor {
        // 清楚的十字準心：四臂明顯，中央以白圈包黑點精準標示「起點」。
        let size: CGFloat = 28
        let c: CGFloat = 14, arm: CGFloat = 12, gap: CGFloat = 3
        let img = image(size, scale: 2) {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c, y: c + gap)); p.line(to: NSPoint(x: c, y: c + arm))
            p.move(to: NSPoint(x: c, y: c - gap)); p.line(to: NSPoint(x: c, y: c - arm))
            p.move(to: NSPoint(x: c + gap, y: c)); p.line(to: NSPoint(x: c + arm, y: c))
            p.move(to: NSPoint(x: c - gap, y: c)); p.line(to: NSPoint(x: c - arm, y: c))
            NSColor.white.setStroke(); p.lineWidth = 4; p.lineCapStyle = .round; p.stroke()
            NSColor.black.setStroke(); p.lineWidth = 1.8; p.stroke()
            // 精準起點：白圈 + 實心黑點，正落在 hotSpot
            let ring = NSBezierPath(ovalIn: NSRect(x: c - 2.4, y: c - 2.4, width: 4.8, height: 4.8))
            NSColor.white.setFill(); ring.fill()
            NSColor.black.setStroke(); ring.lineWidth = 0.8; ring.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: c - 1.1, y: c - 1.1, width: 2.2, height: 2.2))
            NSColor.black.setFill(); dot.fill()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: c, y: size - c))
    }

    // MARK: - 筆刷（準心 + 筆觸點）

    private static func makeBrushCursor() -> NSCursor {
        let img = image(24) {
            let c: CGFloat = 12, arm: CGFloat = 8, gap: CGFloat = 3
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c, y: c + gap)); p.line(to: NSPoint(x: c, y: c + arm))
            p.move(to: NSPoint(x: c, y: c - gap)); p.line(to: NSPoint(x: c, y: c - arm))
            p.move(to: NSPoint(x: c + gap, y: c)); p.line(to: NSPoint(x: c + arm, y: c))
            p.move(to: NSPoint(x: c - gap, y: c)); p.line(to: NSPoint(x: c - arm, y: c))
            NSColor.white.setStroke(); p.lineWidth = 3; p.stroke()
            NSColor.black.setStroke(); p.lineWidth = 1.2; p.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: c - 1, y: c - 1, width: 2, height: 2))
            NSColor.white.setStroke(); dot.lineWidth = 1.5; dot.stroke()
            NSColor.black.setFill(); dot.fill()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }

    // MARK: - 鉛筆（尖端在左下，依段落上色）

    private static func makePencilCursor() -> NSCursor {
        let img = image(24) {
            let tip = NSPoint(x: 2.6, y: 2.6)
            let d = NSPoint(x: 1/sqrt2, y: 1/sqrt2)        // 軸向
            let pp = NSPoint(x: -1/sqrt2, y: 1/sqrt2)      // 法向
            let hw: CGFloat = 2.7
            func ax(_ s: CGFloat) -> NSPoint { NSPoint(x: tip.x + d.x*s, y: tip.y + d.y*s) }
            func corner(_ s: CGFloat, _ sign: CGFloat) -> NSPoint {
                let a = ax(s); return NSPoint(x: a.x + pp.x*hw*sign, y: a.y + pp.y*hw*sign)
            }
            func seg(_ s0: CGFloat, _ s1: CGFloat, _ c: NSColor) {
                let p = NSBezierPath()
                p.move(to: corner(s0, 1)); p.line(to: corner(s1, 1))
                p.line(to: corner(s1, -1)); p.line(to: corner(s0, -1)); p.close()
                c.setFill(); p.fill()
            }
            // 整體外形（白光暈 + 黑邊）
            let sil = NSBezierPath()
            sil.move(to: ax(0))                       // 尖點
            sil.line(to: corner(3.2, 1))
            sil.line(to: corner(23, 1))
            sil.line(to: corner(23, -1))
            sil.line(to: corner(3.2, -1))
            sil.close()
            NSColor.white.setStroke(); sil.lineWidth = 2.4; sil.stroke()

            // 各段填色
            // 石墨尖（三角）
            let graphite = NSBezierPath()
            graphite.move(to: ax(0)); graphite.line(to: corner(3.2, 1)); graphite.line(to: corner(3.2, -1)); graphite.close()
            col(60, 60, 64).setFill(); graphite.fill()
            seg(3.2, 6, col(225, 198, 150))     // 木質
            seg(6, 19, col(255, 205, 60))       // 黃色筆身
            seg(19, 21, col(210, 210, 215))     // 金屬箍
            seg(21, 23, col(245, 150, 165))     // 橡皮擦

            NSColor.black.withAlphaComponent(0.85).setStroke(); sil.lineWidth = 0.9; sil.stroke()
            // 金屬箍上的兩條紋
            let band = NSBezierPath()
            band.move(to: corner(19.7, 1)); band.line(to: corner(19.7, -1))
            band.move(to: corner(20.4, 1)); band.line(to: corner(20.4, -1))
            NSColor.black.withAlphaComponent(0.5).setStroke(); band.lineWidth = 0.6; band.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 2.6, y: 24 - 2.6))
    }

    // MARK: - 油漆桶（傾倒，滴落點在左下）

    private static func makeFillCursor() -> NSCursor {
        let img = image(24) {
            // 桶身（梯形，向左下傾倒）
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 9, y: 21))
            body.line(to: NSPoint(x: 21, y: 17))
            body.line(to: NSPoint(x: 17.5, y: 7.5))
            body.line(to: NSPoint(x: 6.5, y: 11))
            body.close()
            paint(body, fill: col(150, 152, 158), shadow: true)
            // 桶口橢圓（藍漆）
            let rim = NSBezierPath()
            rim.move(to: NSPoint(x: 9, y: 21))
            rim.curve(to: NSPoint(x: 21, y: 17),
                      controlPoint1: NSPoint(x: 13, y: 24.5), controlPoint2: NSPoint(x: 18.5, y: 20))
            rim.curve(to: NSPoint(x: 9, y: 21),
                      controlPoint1: NSPoint(x: 14.5, y: 18.5), controlPoint2: NSPoint(x: 11, y: 19.5))
            col(40, 110, 220).setFill(); rim.fill()
            NSColor.black.withAlphaComponent(0.6).setStroke(); rim.lineWidth = 0.8; rim.stroke()
            // 提把
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 9.5, y: 21))
            handle.curve(to: NSPoint(x: 20.5, y: 17),
                         controlPoint1: NSPoint(x: 14, y: 27), controlPoint2: NSPoint(x: 19, y: 23))
            NSColor.white.setStroke(); handle.lineWidth = 2.2; handle.stroke()
            col(90, 92, 98).setStroke(); handle.lineWidth = 1.1; handle.stroke()
            // 傾倒的漆流 + 滴 (落在左下 hotspot)
            let stream = NSBezierPath()
            stream.move(to: NSPoint(x: 6.8, y: 11.5))
            stream.curve(to: NSPoint(x: 3, y: 3),
                         controlPoint1: NSPoint(x: 4.5, y: 9), controlPoint2: NSPoint(x: 3.5, y: 6))
            NSColor.white.setStroke(); stream.lineWidth = 3.2; stream.stroke()
            col(40, 110, 220).setStroke(); stream.lineWidth = 1.8; stream.stroke()
            let drop = NSBezierPath(ovalIn: NSRect(x: 1.4, y: 1.0, width: 4.2, height: 5.2))
            paint(drop, fill: col(40, 120, 235), halo: 1.6, line: 0.7)
            // 高光
            let gloss = NSBezierPath(ovalIn: NSRect(x: 2.4, y: 3.4, width: 1.2, height: 1.6))
            col(190, 215, 255).setFill(); gloss.fill()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 3, y: 24 - 3))
    }

    // MARK: - 橡皮擦（3D 粉紅膠塊，含上斜面）

    private static func makeEraserCursor() -> NSCursor {
        let img = image(24) {
            // 前面
            let front = NSBezierPath()
            front.move(to: NSPoint(x: 6, y: 6))
            front.line(to: NSPoint(x: 16, y: 6))
            front.line(to: NSPoint(x: 16, y: 13))
            front.line(to: NSPoint(x: 6, y: 13))
            front.close()
            paint(front, fill: col(240, 130, 150), shadow: true)
            // 上斜面
            let top = NSBezierPath()
            top.move(to: NSPoint(x: 6, y: 13))
            top.line(to: NSPoint(x: 16, y: 13))
            top.line(to: NSPoint(x: 19, y: 17))
            top.line(to: NSPoint(x: 9, y: 17))
            top.close()
            col(255, 175, 190).setFill(); top.fill()
            NSColor.black.withAlphaComponent(0.7).setStroke(); top.lineWidth = 0.9; top.stroke()
            // 右側面
            let side = NSBezierPath()
            side.move(to: NSPoint(x: 16, y: 6))
            side.line(to: NSPoint(x: 19, y: 10))
            side.line(to: NSPoint(x: 19, y: 17))
            side.line(to: NSPoint(x: 16, y: 13))
            side.close()
            col(215, 105, 125).setFill(); side.fill()
            NSColor.black.withAlphaComponent(0.7).setStroke(); side.lineWidth = 0.9; side.stroke()
            // 白色擦痕帶
            let band = NSBezierPath(rect: NSRect(x: 6, y: 6, width: 10, height: 2.4))
            NSColor.white.setFill(); band.fill()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }

    // MARK: - 滴管（尖端在左下）

    private static func makePickerCursor() -> NSCursor {
        let img = image(24) {
            let tip = NSPoint(x: 2.6, y: 2.6)
            let d = NSPoint(x: 1/sqrt2, y: 1/sqrt2)
            let pp = NSPoint(x: -1/sqrt2, y: 1/sqrt2)
            func ax(_ s: CGFloat) -> NSPoint { NSPoint(x: tip.x + d.x*s, y: tip.y + d.y*s) }
            func corner(_ s: CGFloat, _ sign: CGFloat, _ hw: CGFloat) -> NSPoint {
                let a = ax(s); return NSPoint(x: a.x + pp.x*hw*sign, y: a.y + pp.y*hw*sign)
            }
            // 細針尖 (s 0..4) → 玻璃管 (4..14, 較寬)
            let sil = NSBezierPath()
            sil.move(to: ax(0))
            sil.line(to: corner(4, 1, 1.1))
            sil.line(to: corner(14, 1, 2.1))
            sil.line(to: corner(14, -1, 2.1))
            sil.line(to: corner(4, -1, 1.1))
            sil.close()
            // 玻璃管：固定淺藍（與黃色鉛筆明顯區隔）
            paint(sil, fill: col(175, 218, 248), halo: 2.2, line: 0.9, shadow: true)
            // 管中高光條
            let band = NSBezierPath()
            band.move(to: corner(5, 0.4, 1.0)); band.line(to: corner(13, 0.4, 1.8))
            NSColor.white.withAlphaComponent(0.8).setStroke(); band.lineWidth = 1.0; band.stroke()
            // 金屬接環
            let collar = NSBezierPath()
            collar.move(to: corner(13.5, 1, 2.1)); collar.line(to: corner(13.5, -1, 2.1))
            col(120, 122, 130).setStroke(); collar.lineWidth = 1.6; collar.stroke()
            // 橡膠頭（右上球）— 青綠色
            let bulbC = ax(17)
            let bulb = NSBezierPath(ovalIn: NSRect(x: bulbC.x - 4, y: bulbC.y - 4, width: 8, height: 8))
            paint(bulb, fill: col(60, 175, 165), halo: 2.0, line: 0.9)
            let gloss = NSBezierPath(ovalIn: NSRect(x: bulbC.x - 2.4, y: bulbC.y, width: 2, height: 2.4))
            col(190, 235, 228).setFill(); gloss.fill()
            // 尖端顯示目前選取色彩（小圓點）
            if let c1 = PaintState.shared.color1.usingColorSpace(.deviceRGB) {
                let tipDot = NSBezierPath(ovalIn: NSRect(x: tip.x - 1, y: tip.y - 1, width: 2.6, height: 2.6))
                c1.setFill(); tipDot.fill()
            }
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 2.6, y: 24 - 2.6))
    }

    // MARK: - 放大鏡（玻璃中心為 hotspot，含 + 號）

    private static func makeMagnifierCursor() -> NSCursor {
        let img = image(24) {
            let center = NSPoint(x: 10, y: 14)
            let r: CGFloat = 6.2
            // 手把（往左下）
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: center.x - r*0.7, y: center.y - r*0.7))
            handle.line(to: NSPoint(x: 2.5, y: 2.5))
            NSColor.white.setStroke(); handle.lineWidth = 4.2; handle.stroke()
            col(70, 72, 80).setStroke(); handle.lineWidth = 2.6; handle.stroke()
            // 鏡片
            let glass = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
            NSColor.white.setStroke(); glass.lineWidth = 3.4; glass.stroke()
            col(150, 205, 245, 0.55).setFill(); glass.fill()
            col(40, 70, 110).setStroke(); glass.lineWidth = 1.6; glass.stroke()
            // 高光弧
            let hi = NSBezierPath()
            hi.appendArc(withCenter: center, radius: r - 1.6,
                         startAngle: 110, endAngle: 170)
            NSColor.white.withAlphaComponent(0.85).setStroke(); hi.lineWidth = 1.3; hi.stroke()
            // + 號
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: center.x - 2.6, y: center.y)); plus.line(to: NSPoint(x: center.x + 2.6, y: center.y))
            plus.move(to: NSPoint(x: center.x, y: center.y - 2.6)); plus.line(to: NSPoint(x: center.x, y: center.y + 2.6))
            col(30, 60, 100).setStroke(); plus.lineWidth = 1.4; plus.stroke()
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 24 - 14))
    }
}
