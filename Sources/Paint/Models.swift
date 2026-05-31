import AppKit

// MARK: - 透明色

extension NSColor {
    /// 「透明色」：alpha 0。用它繪圖會把像素清成透明。
    static let paintTransparent = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    /// 此色是否被視為透明（用於切換 .clear 合成模式）。
    var isPaintTransparent: Bool {
        (usingColorSpace(.deviceRGB)?.alphaComponent ?? alphaComponent) < 0.004
    }
}

// MARK: - Tools

enum Tool: String, CaseIterable {
    case pencil, brush, eraser, fill, picker, text, magnifier
    case selectRect, selectFree
    case shape
}

enum BrushKind: String, CaseIterable {
    case round         // 一般筆刷
    case calligraphy1  // 書法筆 1（左斜）
    case calligraphy2  // 書法筆 2（右斜）
    case airbrush      // 噴槍
    case oil           // 油畫筆刷
    case crayon        // 蠟筆
    case marker        // 麥克筆
    case naturalPencil // 自然鉛筆
    case watercolour   // 水彩
}

enum ShapeKind: String, CaseIterable {
    case line, curve, ellipse, rect, roundedRect, polygon
    case triangle, rightTriangle, diamond, pentagon, hexagon
    case arrowRight, arrowLeft, arrowUp, arrowDown
    case star4, star5, star6
    case calloutRect, calloutEllipse, calloutCloud
    case heart, lightning
}

enum FillStyle: String, CaseIterable {
    case none, solid
}

enum SelectionShape {
    case rectangle, freeform
}

// MARK: - State

final class PaintState {
    static let shared = PaintState()

    var tool: Tool = .pencil
    var previousDrawingTool: Tool = .pencil  // remembered when switching to text/picker etc
    var brushKind: BrushKind = .round
    var shapeKind: ShapeKind = .line
    var color1: NSColor = .black       // primary (left button)
    var color2: NSColor = .white       // secondary (right button)
    var strokeSize: CGFloat = 3
    var outlineStyle: FillStyle = .solid   // shape outline
    var fillStyle: FillStyle = .none       // shape fill
    var fillTolerance: Double = 0          // 油漆桶容許度 0–100%（0=完全相同色才填）
    var selectionShape: SelectionShape = .rectangle
    var transparentSelection: Bool = false
    var canvasSize: NSSize = NSSize(width: 800, height: 600)
    var zoom: CGFloat = 1.0
    var showGridlines: Bool = false
    var showRulers: Bool = false
    var showStatusBar: Bool = true

    var customPalette: [NSColor] = []  // user added custom colors

    // Notifications
    static let toolChanged   = Notification.Name("paint.toolChanged")
    static let colorChanged  = Notification.Name("paint.colorChanged")
    static let sizeChanged   = Notification.Name("paint.sizeChanged")
    static let brushChanged  = Notification.Name("paint.brushChanged")
    static let shapeChanged  = Notification.Name("paint.shapeChanged")
    static let zoomChanged   = Notification.Name("paint.zoomChanged")
    static let canvasResized = Notification.Name("paint.canvasResized")
    static let viewChanged   = Notification.Name("paint.viewChanged")
    static let statusUpdate  = Notification.Name("paint.statusUpdate")
    static let toleranceChanged = Notification.Name("paint.toleranceChanged")
}

// MARK: - Standard Palette (Windows Paint colors)

enum Palette {
    static let standard: [NSColor] = [
        // Row 1
        rgb(0,0,0), rgb(127,127,127), rgb(136,0,21), rgb(237,28,36),
        rgb(255,127,39), rgb(255,242,0), rgb(34,177,76), rgb(0,162,232),
        rgb(63,72,204), rgb(163,73,164),
        // Row 2
        rgb(255,255,255), rgb(195,195,195), rgb(185,122,87), rgb(255,174,201),
        rgb(255,201,14), rgb(239,228,176), rgb(181,230,29), rgb(153,217,234),
        rgb(112,146,190), rgb(200,191,231),
    ]
    static let basic: [NSColor] = [
        // Color picker dialog "basic colors" (Windows classic)
        rgb(255,128,128), rgb(255,255,128), rgb(128,255,128), rgb(0,255,128),
        rgb(128,255,255), rgb(0,128,255), rgb(255,128,192), rgb(255,128,255),
        rgb(255,0,0), rgb(255,255,0), rgb(128,255,0), rgb(0,255,64),
        rgb(0,255,255), rgb(0,128,192), rgb(128,128,192), rgb(255,0,255),
        rgb(128,64,64), rgb(255,128,64), rgb(0,255,0), rgb(0,128,128),
        rgb(0,64,128), rgb(128,128,255), rgb(128,0,64), rgb(255,0,128),
        rgb(128,0,0), rgb(255,128,0), rgb(0,128,0), rgb(0,128,64),
        rgb(0,0,255), rgb(0,0,160), rgb(128,0,128), rgb(128,0,255),
        rgb(64,0,0), rgb(128,64,0), rgb(0,64,0), rgb(0,64,64),
        rgb(0,0,128), rgb(0,0,64), rgb(64,0,64), rgb(64,0,128),
        rgb(0,0,0), rgb(128,128,0), rgb(128,128,64), rgb(128,128,128),
        rgb(64,128,128), rgb(192,192,192), rgb(64,0,64), rgb(255,255,255),
    ]
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        return NSColor(deviceRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
}

// MARK: - History (Undo / Redo)

final class History {
    static let maxSize = 50
    private var stack: [NSBitmapImageRep] = []
    private var head: Int = -1  // current snapshot index

    func push(_ snapshot: NSBitmapImageRep) {
        if head < stack.count - 1 {
            stack.removeSubrange((head + 1)...)
        }
        stack.append(snapshot)
        if stack.count > History.maxSize {
            stack.removeFirst()
        } else {
            head += 1
        }
        if head >= stack.count { head = stack.count - 1 }
    }

    func canUndo() -> Bool { head > 0 }
    func canRedo() -> Bool { head < stack.count - 1 }

    func undo() -> NSBitmapImageRep? {
        guard canUndo() else { return nil }
        head -= 1
        return stack[head]
    }
    func redo() -> NSBitmapImageRep? {
        guard canRedo() else { return nil }
        head += 1
        return stack[head]
    }
    func current() -> NSBitmapImageRep? {
        guard head >= 0 && head < stack.count else { return nil }
        return stack[head]
    }
    func reset(initial: NSBitmapImageRep) {
        stack = [initial]
        head = 0
    }
}
