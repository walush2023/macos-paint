import AppKit

/// 各種筆刷的繪製演算法。所有方法都假設當前 graphics context 已設定好。
enum BrushRenderer {
    static func render(kind: BrushKind, from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        switch kind {
        case .round:         renderRound(from: a, to: b, color: color, size: size)
        case .calligraphy1:  renderCalligraphy(from: a, to: b, color: color, size: size, angle: -.pi / 4)
        case .calligraphy2:  renderCalligraphy(from: a, to: b, color: color, size: size, angle: .pi / 4)
        case .airbrush:      renderAirbrush(from: a, to: b, color: color, size: size)
        case .oil:           renderOil(from: a, to: b, color: color, size: size)
        case .crayon:        renderCrayon(from: a, to: b, color: color, size: size)
        case .marker:        renderMarker(from: a, to: b, color: color, size: size)
        case .naturalPencil: renderNaturalPencil(from: a, to: b, color: color, size: size)
        case .watercolour:   renderWatercolour(from: a, to: b, color: color, size: size)
        }
    }

    private static func renderRound(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let path = NSBezierPath()
        path.move(to: a); path.line(to: b)
        path.lineWidth = size
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func renderCalligraphy(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat, angle: CGFloat) {
        // Draw an oblique line by stamping rotated rectangles along the path.
        color.setFill()
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) * 2))
        let half = size
        let nibLen = size * 1.5
        let nibThick = size * 0.35
        let cosA = cos(angle), sinA = sin(angle)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cx = a.x + (b.x - a.x) * t
            let cy = a.y + (b.y - a.y) * t
            let p = NSBezierPath()
            let dx = cosA * nibLen / 2, dy = sinA * nibLen / 2
            let px = -sinA * nibThick / 2, py = cosA * nibThick / 2
            p.move(to: NSPoint(x: cx + dx + px, y: cy + dy + py))
            p.line(to: NSPoint(x: cx + dx - px, y: cy + dy - py))
            p.line(to: NSPoint(x: cx - dx - px, y: cy - dy - py))
            p.line(to: NSPoint(x: cx - dx + px, y: cy - dy + py))
            p.close()
            p.fill()
            _ = half
        }
    }

    private static func renderAirbrush(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let r = size * 2.2
        let count = 12 + Int(size)
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y)))
        color.withAlphaComponent(0.5).setFill()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cx = a.x + (b.x - a.x) * t
            let cy = a.y + (b.y - a.y) * t
            for _ in 0..<count {
                let theta = CGFloat.random(in: 0...(2 * .pi))
                let dist = CGFloat.random(in: 0...r)
                let px = cx + cos(theta) * dist
                let py = cy + sin(theta) * dist
                NSRect(x: px - 0.5, y: py - 0.5, width: 1.2, height: 1.2).fill()
            }
        }
    }

    private static func renderOil(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let path = NSBezierPath()
        path.move(to: a); path.line(to: b)
        path.lineWidth = size * 1.4
        path.lineCapStyle = .round
        color.withAlphaComponent(0.85).setStroke()
        path.stroke()
        // Streaks
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y)))
        color.withAlphaComponent(0.4).setStroke()
        for _ in 0..<3 {
            let p2 = NSBezierPath()
            let dx = CGFloat.random(in: -size...size) * 0.5
            let dy = CGFloat.random(in: -size...size) * 0.5
            p2.move(to: NSPoint(x: a.x + dx, y: a.y + dy))
            p2.line(to: NSPoint(x: b.x + dx, y: b.y + dy))
            p2.lineWidth = size * 0.4
            p2.lineCapStyle = .round
            p2.stroke()
            _ = steps
        }
    }

    private static func renderCrayon(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) * 1.5))
        color.withAlphaComponent(0.6).setFill()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cx = a.x + (b.x - a.x) * t
            let cy = a.y + (b.y - a.y) * t
            for _ in 0..<6 {
                let dx = CGFloat.random(in: -size...size)
                let dy = CGFloat.random(in: -size...size)
                NSRect(x: cx + dx - 0.5, y: cy + dy - 0.5, width: 1.2, height: 1.2).fill()
            }
        }
    }

    private static func renderMarker(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let path = NSBezierPath()
        path.move(to: a); path.line(to: b)
        path.lineWidth = size * 1.3
        path.lineCapStyle = .square
        color.withAlphaComponent(0.55).setStroke()
        path.stroke()
    }

    private static func renderNaturalPencil(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        let path = NSBezierPath()
        path.move(to: a); path.line(to: b)
        path.lineWidth = size * 0.9
        path.lineCapStyle = .round
        color.withAlphaComponent(0.7).setStroke()
        path.stroke()
        // graininess
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y)))
        color.withAlphaComponent(0.3).setFill()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cx = a.x + (b.x - a.x) * t
            let cy = a.y + (b.y - a.y) * t
            for _ in 0..<2 {
                let dx = CGFloat.random(in: -size/2...size/2)
                let dy = CGFloat.random(in: -size/2...size/2)
                NSRect(x: cx + dx - 0.4, y: cy + dy - 0.4, width: 0.8, height: 0.8).fill()
            }
        }
    }

    private static func renderWatercolour(from a: NSPoint, to b: NSPoint, color: NSColor, size: CGFloat) {
        // Multiple overlaid translucent strokes
        for _ in 0..<3 {
            let p = NSBezierPath()
            let dx = CGFloat.random(in: -size/2...size/2)
            let dy = CGFloat.random(in: -size/2...size/2)
            p.move(to: NSPoint(x: a.x + dx, y: a.y + dy))
            p.line(to: NSPoint(x: b.x + dx, y: b.y + dy))
            p.lineWidth = size * CGFloat.random(in: 1.0...1.5)
            p.lineCapStyle = .round
            color.withAlphaComponent(0.25).setStroke()
            p.stroke()
        }
    }
}
