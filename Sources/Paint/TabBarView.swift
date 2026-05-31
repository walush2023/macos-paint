import AppKit

/// Ribbon 上方的 tab 列：檔案 / 常用 / 檢視
final class TabBarView: NSView {
    enum Tab { case file, home, view }
    var onTabSelected: ((Tab) -> Void)?
    var onFileMenu: (() -> Void)?

    private var current: Tab = .home
    private var fileBtn: NSButton!
    private var homeBtn: NSButton!
    private var viewBtn: NSButton!

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.815, green: 0.851, blue: 0.91, alpha: 1).cgColor

        fileBtn = makeFileTabBtn(title: tr("檔案"))
        fileBtn.target = self; fileBtn.action = #selector(fileTapped)
        addSubview(fileBtn)

        homeBtn = makeTabBtn(title: tr("常用"))
        homeBtn.target = self; homeBtn.action = #selector(homeTapped)
        addSubview(homeBtn)

        viewBtn = makeTabBtn(title: tr("檢視"))
        viewBtn.target = self; viewBtn.action = #selector(viewTapped)
        addSubview(viewBtn)

        updateHighlight()
    }
    required init?(coder: NSCoder) { fatalError() }

    var fileButtonOrigin: NSPoint { fileBtn.frame.origin }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        let h = bounds.height
        fileBtn.frame = NSRect(x: 0, y: 0, width: 64, height: h)
        homeBtn.frame = NSRect(x: 64, y: 0, width: 80, height: h)
        viewBtn.frame = NSRect(x: 144, y: 0, width: 64, height: h)
    }

    private func makeFileTabBtn(title: String) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .smallSquare
        b.isBordered = false
        b.title = title
        b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(calibratedRed: 0.176, green: 0.475, blue: 0.788, alpha: 1).cgColor
        b.contentTintColor = .white
        b.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        )
        return b
    }
    private func makeTabBtn(title: String) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .smallSquare
        b.isBordered = false
        b.title = title
        b.font = NSFont.systemFont(ofSize: 12)
        b.wantsLayer = true
        b.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.078, green: 0.259, blue: 0.545, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )
        return b
    }

    @objc private func fileTapped() { onFileMenu?() }
    @objc private func homeTapped() { current = .home; updateHighlight(); onTabSelected?(.home) }
    @objc private func viewTapped() { current = .view; updateHighlight(); onTabSelected?(.view) }

    private func updateHighlight() {
        homeBtn.layer?.backgroundColor = (current == .home)
            ? NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
            : NSColor.clear.cgColor
        viewBtn.layer?.backgroundColor = (current == .view)
            ? NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
            : NSColor.clear.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Bottom separator line
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: 0.5))
        p.line(to: NSPoint(x: bounds.width, y: 0.5))
        p.lineWidth = 1
        p.stroke()
    }
}
