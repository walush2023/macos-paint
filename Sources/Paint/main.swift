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
