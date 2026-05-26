import AppKit

/// 形狀繪製。draw() 接收兩個對角點，自動建立 path 並依設定描邊/填滿。
enum ShapeRenderer {
    static func draw(kind: ShapeKind, from a: NSPoint, to b: NSPoint,
                     stroke: NSColor, fill: NSColor,
                     outline: FillStyle, fillStyle: FillStyle, size: CGFloat) {
        let rect = NSRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        )
        let path = pathFor(kind: kind, rect: rect, p0: a, p1: b)
        if fillStyle == .solid {
            fill.setFill()
            path.fill()
        }
        if outline == .solid {
            stroke.setStroke()
            path.lineWidth = size
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func pathFor(kind: ShapeKind, rect r: NSRect, p0: NSPoint, p1: NSPoint) -> NSBezierPath {
        switch kind {
        case .line:
            let p = NSBezierPath()
            p.move(to: p0); p.line(to: p1)
            return p
        case .curve:
            let p = NSBezierPath()
            p.move(to: p0); p.line(to: p1)
            return p
        case .ellipse:
            return NSBezierPath(ovalIn: r)
        case .rect:
            return NSBezierPath(rect: r)
        case .roundedRect:
            let radius = min(r.width, r.height) * 0.15
            return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        case .polygon:
            return NSBezierPath(rect: r)
        case .triangle:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: r.maxY))
            p.line(to: NSPoint(x: r.minX, y: r.minY))
            p.line(to: NSPoint(x: r.maxX, y: r.minY))
            p.close()
            return p
        case .rightTriangle:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.maxY))
            p.line(to: NSPoint(x: r.minX, y: r.minY))
            p.line(to: NSPoint(x: r.maxX, y: r.minY))
            p.close()
            return p
        case .diamond:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: r.maxY))
            p.line(to: NSPoint(x: r.maxX, y: r.midY))
            p.line(to: NSPoint(x: r.midX, y: r.minY))
            p.line(to: NSPoint(x: r.minX, y: r.midY))
            p.close()
            return p
        case .pentagon: return regularPolygon(in: r, sides: 5, rotation: .pi / 2)
        case .hexagon:  return regularPolygon(in: r, sides: 6, rotation: 0)
        case .arrowRight:  return arrowPath(r, direction: .right)
        case .arrowLeft:   return arrowPath(r, direction: .left)
        case .arrowUp:     return arrowPath(r, direction: .up)
        case .arrowDown:   return arrowPath(r, direction: .down)
        case .star4: return starPath(in: r, points: 4, innerRatio: 0.4)
        case .star5: return starPath(in: r, points: 5, innerRatio: 0.5)
        case .star6: return starPath(in: r, points: 6, innerRatio: 0.5)
        case .calloutRect:    return calloutRectPath(r)
        case .calloutEllipse: return calloutEllipsePath(r)
        case .calloutCloud:   return cloudPath(r)
        case .heart:     return heartPath(r)
        case .lightning: return lightningPath(r)
        }
    }

    private static func regularPolygon(in r: NSRect, sides n: Int, rotation: CGFloat) -> NSBezierPath {
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        let p = NSBezierPath()
        for i in 0..<n {
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(n)
            let x = cx + cos(a) * rx
            let y = cy + sin(a) * ry
            if i == 0 { p.move(to: NSPoint(x: x, y: y)) }
            else { p.line(to: NSPoint(x: x, y: y)) }
        }
        p.close()
        return p
    }

    enum ArrowDir { case right, left, up, down }

    private static func arrowPath(_ r: NSRect, direction: ArrowDir) -> NSBezierPath {
        let p = NSBezierPath()
        // Build a right-arrow in a unit rect, then transform.
        // Body 40% of height, head 40% of width
        let headW: CGFloat = 0.4
        let bodyH: CGFloat = 0.4
        let bodyOffY: CGFloat = (1 - bodyH) / 2
        let pts: [NSPoint] = [
            NSPoint(x: 0,             y: bodyOffY),
            NSPoint(x: 1 - headW,     y: bodyOffY),
            NSPoint(x: 1 - headW,     y: 0),
            NSPoint(x: 1,             y: 0.5),
            NSPoint(x: 1 - headW,     y: 1),
            NSPoint(x: 1 - headW,     y: 1 - bodyOffY),
            NSPoint(x: 0,             y: 1 - bodyOffY),
        ]
        let transformed = pts.map { unit -> NSPoint in
            var u = unit
            switch direction {
            case .right: break
            case .left:  u = NSPoint(x: 1 - u.x, y: u.y)
            case .up:    u = NSPoint(x: u.y, y: u.x)
            case .down:  u = NSPoint(x: 1 - u.y, y: 1 - u.x)
            }
            return NSPoint(x: r.minX + u.x * r.width, y: r.minY + u.y * r.height)
        }
        p.move(to: transformed[0])
        for q in transformed.dropFirst() { p.line(to: q) }
        p.close()
        return p
    }

    private static func starPath(in r: NSRect, points: Int, innerRatio: CGFloat) -> NSBezierPath {
        let cx = r.midX, cy = r.midY
        let outerX = r.width / 2, outerY = r.height / 2
        let p = NSBezierPath()
        let n = points * 2
        for i in 0..<n {
            let a = -.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let rx = (i % 2 == 0) ? outerX : outerX * innerRatio
            let ry = (i % 2 == 0) ? outerY : outerY * innerRatio
            let x = cx + cos(a) * rx
            let y = cy + sin(a) * ry
            if i == 0 { p.move(to: NSPoint(x: x, y: y)) }
            else { p.line(to: NSPoint(x: x, y: y)) }
        }
        p.close()
        return p
    }

    private static func calloutRectPath(_ r: NSRect) -> NSBezierPath {
        let bodyH = r.height * 0.75
        let body = NSRect(x: r.minX, y: r.minY + r.height - bodyH, width: r.width, height: bodyH)
        let radius = min(body.width, body.height) * 0.1
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        // tail
        let tail = NSBezierPath()
        let tx = r.minX + r.width * 0.25
        let tw = r.width * 0.1
        tail.move(to: NSPoint(x: tx, y: body.minY))
        tail.line(to: NSPoint(x: tx + tw / 2, y: r.minY))
        tail.line(to: NSPoint(x: tx + tw, y: body.minY))
        tail.close()
        path.append(tail)
        return path
    }
    private static func calloutEllipsePath(_ r: NSRect) -> NSBezierPath {
        let bodyH = r.height * 0.75
        let body = NSRect(x: r.minX, y: r.minY + r.height - bodyH, width: r.width, height: bodyH)
        let path = NSBezierPath(ovalIn: body)
        let tail = NSBezierPath()
        let tx = r.minX + r.width * 0.25
        let tw = r.width * 0.1
        tail.move(to: NSPoint(x: tx, y: body.minY + 4))
        tail.line(to: NSPoint(x: tx + tw / 2, y: r.minY))
        tail.line(to: NSPoint(x: tx + tw, y: body.minY + 4))
        tail.close()
        path.append(tail)
        return path
    }
    private static func cloudPath(_ r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        // string of bumps approximating a cloud
        let bumps: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.00, 0.30, 0.30, 0.50),
            (0.15, 0.55, 0.35, 0.45),
            (0.40, 0.65, 0.30, 0.35),
            (0.60, 0.55, 0.35, 0.45),
            (0.70, 0.30, 0.30, 0.45),
            (0.45, 0.10, 0.35, 0.40),
            (0.15, 0.10, 0.35, 0.40),
        ]
        for (i, b) in bumps.enumerated() {
            let rr = NSRect(
                x: r.minX + b.0 * r.width,
                y: r.minY + b.1 * r.height,
                width: b.2 * r.width,
                height: b.3 * r.height
            )
            let oval = NSBezierPath(ovalIn: rr)
            if i == 0 { p.append(oval) }
            else { p.append(oval) }
        }
        // tail
        let tail = NSBezierPath()
        let tx = r.minX + r.width * 0.2
        tail.move(to: NSPoint(x: tx, y: r.minY + r.height * 0.18))
        tail.line(to: NSPoint(x: tx + r.width * 0.05, y: r.minY))
        tail.line(to: NSPoint(x: tx + r.width * 0.12, y: r.minY + r.height * 0.15))
        tail.close()
        p.append(tail)
        return p
    }
    private static func heartPath(_ r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        let cx = r.midX
        let topY = r.maxY
        let botY = r.minY
        p.move(to: NSPoint(x: cx, y: topY - r.height * 0.25))
        p.curve(
            to: NSPoint(x: r.minX, y: topY - r.height * 0.3),
            controlPoint1: NSPoint(x: cx - r.width * 0.05, y: topY),
            controlPoint2: NSPoint(x: r.minX, y: topY)
        )
        p.curve(
            to: NSPoint(x: cx, y: botY),
            controlPoint1: NSPoint(x: r.minX, y: topY - r.height * 0.7),
            controlPoint2: NSPoint(x: cx - r.width * 0.2, y: botY + r.height * 0.2)
        )
        p.curve(
            to: NSPoint(x: r.maxX, y: topY - r.height * 0.3),
            controlPoint1: NSPoint(x: cx + r.width * 0.2, y: botY + r.height * 0.2),
            controlPoint2: NSPoint(x: r.maxX, y: topY - r.height * 0.7)
        )
        p.curve(
            to: NSPoint(x: cx, y: topY - r.height * 0.25),
            controlPoint1: NSPoint(x: r.maxX, y: topY),
            controlPoint2: NSPoint(x: cx + r.width * 0.05, y: topY)
        )
        p.close()
        return p
    }
    private static func lightningPath(_ r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        let pts: [(CGFloat, CGFloat)] = [
            (0.55, 1.00),
            (0.20, 0.50),
            (0.40, 0.50),
            (0.20, 0.00),
            (0.65, 0.55),
            (0.45, 0.55),
            (0.80, 1.00),
        ]
        for (i, t) in pts.enumerated() {
            let q = NSPoint(x: r.minX + t.0 * r.width, y: r.minY + t.1 * r.height)
            if i == 0 { p.move(to: q) } else { p.line(to: q) }
        }
        p.close()
        return p
    }
}
