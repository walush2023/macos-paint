import AppKit

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--test" {
    // Headless self-test mode：跑過所有繪製路徑，匯出 PNG
    let ok = SelfTest.run(outputPath: args[2])
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
