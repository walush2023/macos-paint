import AppKit

// MARK: - 最近開啟的檔案

/// 以 UserDefaults 保存的「最近開啟」清單（最多 10 筆，最新在前）。
enum RecentFiles {
    static let key = "paint.recentFiles"
    static let maxCount = 10
    static var defaults: UserDefaults = .standard

    static var urls: [URL] {
        (defaults.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func add(_ url: URL) {
        var list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        list.insert(url.path, at: 0)
        defaults.set(Array(list.prefix(maxCount)), forKey: key)
    }
    static func remove(_ url: URL) {
        let list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        defaults.set(list, forKey: key)
    }
    static func clear() { defaults.removeObject(forKey: key) }
}

// MARK: - 尺規

/// 畫布尺規：單位為畫布像素，0 在畫布左上角；隨縮放與捲動更新，並標示滑鼠位置。
final class CanvasRulerView: NSView {
    enum Orientation { case horizontal, vertical }
    let orientation: Orientation
    weak var canvas: CanvasView?
    /// 滑鼠所在像素（畫布座標，y 由上往下）。
    var marker: CGFloat? { didSet { if !isHidden { needsDisplay = true } } }

    init(orientation: Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 依縮放挑選主刻度間距（像素），讓主刻度在螢幕上至少相隔約 50pt。
    static func majorStep(forZoom zoom: CGFloat) -> Int {
        let candidates = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
        for c in candidates where CGFloat(c) * zoom >= 50 { return c }
        return 10000
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
        if orientation == .horizontal {
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        } else {
            NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        }
        guard let canvas = canvas, canvas.superview != nil, let bm = canvas.bitmap else { return }
        let zoom = PaintState.shared.zoom
        let pxW = bm.pixelsWide, pxH = bm.pixelsHigh
        // 畫布左上角在本視圖中的位置
        let topLeft = convert(NSPoint(x: 0, y: CGFloat(pxH)), from: canvas)
        let major = CanvasRulerView.majorStep(forZoom: zoom)
        let minor = major >= 10 ? major / 10 : (major >= 5 ? 1 : 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
        ]
        NSColor(calibratedWhite: 0.45, alpha: 1).setFill()
        let length = orientation == .horizontal ? pxW : pxH
        let tickStep = minor > 0 ? minor : major
        // 只畫可見範圍
        let visLo: CGFloat, visHi: CGFloat
        if orientation == .horizontal {
            visLo = (dirtyRect.minX - topLeft.x) / zoom; visHi = (dirtyRect.maxX - topLeft.x) / zoom
        } else {
            visLo = (topLeft.y - dirtyRect.maxY) / zoom; visHi = (topLeft.y - dirtyRect.minY) / zoom
        }
        let start = max(0, Int(visLo) / tickStep * tickStep)
        let end = min(length, Int(visHi) + tickStep)
        guard start <= end else { return }
        for v in stride(from: start, through: end, by: tickStep) {
            let isMajor = v % major == 0
            let tick: CGFloat = isMajor ? 10 : 4
            if orientation == .horizontal {
                let x = (topLeft.x + CGFloat(v) * zoom).rounded() + 0.5
                NSRect(x: x - 0.5, y: 1, width: 1, height: tick).fill()
                if isMajor { ("\(v)" as NSString).draw(at: NSPoint(x: x + 2, y: 8), withAttributes: attrs) }
            } else {
                let y = (topLeft.y - CGFloat(v) * zoom).rounded() - 0.5
                NSRect(x: bounds.width - 1 - tick, y: y, width: tick, height: 1).fill()
                if isMajor {
                    var small = attrs
                    small[.font] = NSFont.systemFont(ofSize: v >= 1000 ? 8 : 9)
                    ("\(v)" as NSString).draw(at: NSPoint(x: 1, y: y - 11), withAttributes: small)
                }
            }
        }
        // 滑鼠位置標記
        if let m = marker {
            NSColor.systemRed.setFill()
            if orientation == .horizontal {
                NSRect(x: (topLeft.x + m * zoom).rounded(), y: 0, width: 1, height: bounds.height).fill()
            } else {
                NSRect(x: 0, y: (topLeft.y - m * zoom).rounded(), width: bounds.width, height: 1).fill()
            }
        }
    }
}
