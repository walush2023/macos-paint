import AppKit

var args = CommandLine.arguments
// 測試/預覽用：--lang en|zh-Hans|zh-Hant|ja 強制介面語言
if let i = args.firstIndex(of: "--lang"), i + 1 < args.count {
    switch args[i + 1].lowercased() {
    case "en":               L10n.override = .en
    case "zh-hans", "hans":  L10n.override = .zhHans
    case "zh-hant", "hant":  L10n.override = .zhHant
    case "ja":               L10n.override = .ja
    default: break
    }
    args.removeSubrange(i...(i + 1))
}
// 預覽用：--tool fill 等，預先設定工具
if let i = args.firstIndex(of: "--tool"), i + 1 < args.count {
    if let t = Tool(rawValue: args[i + 1]) { PaintState.shared.tool = t }
    args.removeSubrange(i...(i + 1))
}
if args.count >= 3, args[1] == "--test" {
    // Headless self-test mode：跑過所有繪製路徑，匯出 PNG
    let ok = SelfTest.run(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 2, args[1] == "--unit-test" {
    let ok = UnitTests.runAll()
    exit(ok ? 0 : 1)
}
if args.count >= 3, args[1] == "--render-window" {
    // 建立完整視窗並離線渲染到 PNG，方便視覺驗證
    let ok = UISnapshot.run(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 3, args[1] == "--overlay-demo" {
    let ok = UISnapshot.renderOverlayDemo(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 3, args[1] == "--crop-demo" {
    let ok = UISnapshot.renderCropDemo(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 4, args[1] == "--make-icon" {
    let ok = IconMaker.makeRoundedIcon(input: args[2], output: args[3])
    exit(ok ? 0 : 1)
}
if args.count >= 3, args[1] == "--text-demo" {
    let ok = UISnapshot.renderTextDemo(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 2, args[1] == "--cursor-debug" {
    _ = NSApplication.shared
    let cur = Cursors.cursor(for: .selectRect)
    let img = cur.image
    print("image.size = \(img.size)")
    print("hotSpot = \(cur.hotSpot)")
    for r in img.representations {
        print("rep \(type(of: r)) pixels=\(r.pixelsWide)x\(r.pixelsHigh) size=\(r.size)")
    }
    // 以原生點大小渲染並數每個方向的黑色像素
    let S = Int(img.size.width)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: S, height: S))
    NSGraphicsContext.restoreGraphicsState()
    func dark(_ x: Int, _ y: Int) -> Bool {
        guard let c = rep.colorAt(x: max(0,min(S-1,x)), y: max(0,min(S-1,y))) else { return false }
        return c.alphaComponent > 0.3 && c.brightnessComponent < 0.5
    }
    let c = S/2
    var up=0, down=0, left=0, right=0
    for d in 3..<(S/2) {
        if dark(c, c-d) { up += 1 }      // 視覺上 y 小 = 上(top-left origin of bitmap data)
        if dark(c, c+d) { down += 1 }
        if dark(c-d, c) { left += 1 }
        if dark(c+d, c) { right += 1 }
    }
    print("arms(dark px) up=\(up) down=\(down) left=\(left) right=\(right)  (S=\(S))")
    // 匯出原生大小、8x 近鄰放大（看真實像素）
    let mag = 8
    let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S*mag, pixelsHigh: S*mag,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let bctx = NSGraphicsContext(bitmapImageRep: big)!
    NSGraphicsContext.current = bctx
    NSColor(white: 0.6, alpha: 1).setFill(); NSRect(x:0,y:0,width:S*mag,height:S*mag).fill()
    bctx.imageInterpolation = .none
    img.draw(in: NSRect(x: 0, y: 0, width: S*mag, height: S*mag))
    NSGraphicsContext.restoreGraphicsState()
    if args.count >= 3, let d = big.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: args[2]))
        print("✓ 原生像素放大圖: \(args[2])")
    }
    exit(0)
}
if args.count >= 3, args[1] == "--text-panel" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let p = TextFormatPanel.shared
    p.showWindow(nil)
    guard let cv = p.window?.contentView else { exit(1) }
    cv.layoutSubtreeIfNeeded()
    p.window?.display()
    if let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
        cv.cacheDisplay(in: cv.bounds, to: rep)
        if let d = rep.representation(using: .png, properties: [:]) {
            try? d.write(to: URL(fileURLWithPath: args[2]))
            print("✓ 已產出文字面板快照: \(args[2])")
        }
    }
    exit(0)
}
if args.count >= 4, args[1] == "--transparency-demo" {
    let ok = UISnapshot.renderTransparencyDemo(viewPath: args[2], pngPath: args[3])
    exit(ok ? 0 : 1)
}
if args.count >= 3, args[1] == "--cursor-preview" {
    let ok = UISnapshot.renderCursors(outputPath: args[2])
    exit(ok ? 0 : 1)
}
if args.count >= 4, args[1] == "--drop-test" {
    // 模擬拖放圖片載入：--drop-test <輸入圖片> <輸出快照>
    let ok = UISnapshot.runDrop(imagePath: args[2], outputPath: args[3])
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
