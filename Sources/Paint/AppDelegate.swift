import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppIcon()
        setupMainMenu()
        windowController = MainWindowController()
        windowController.showWindow(nil)
    }

    /// 設定 Dock 圖標：優先用 bundle 內 AppIcon.icns，否則找執行檔旁的 icon.png。
    private func applyAppIcon() {
        if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: icns) {
            NSApplication.shared.applicationIconImage = img
            return
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        for candidate in ["icon.png", "../../../icon.png", "../../../../icon.png"] {
            let url = exeDir.appendingPathComponent(candidate).standardizedFileURL
            if let img = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = img
                return
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "關於小畫家", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "結束小畫家", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "檔案")
        fileMenu.addItem(NSMenuItem(title: "新增", action: #selector(MainWindowController.newDocument(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "開啟…", action: #selector(MainWindowController.openDocument(_:)), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "儲存", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s"))
        let saveAs = NSMenuItem(title: "另存新檔…", action: #selector(MainWindowController.saveAsDocument(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "列印…", action: #selector(MainWindowController.printDocument(_:)), keyEquivalent: "p"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "內容…", action: #selector(MainWindowController.showProperties(_:)), keyEquivalent: "e"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編輯")
        editMenu.addItem(NSMenuItem(title: "復原", action: #selector(MainWindowController.undoAction(_:)), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "取消復原", action: #selector(MainWindowController.redoAction(_:)), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪下", action: Selector("cut:"), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "複製", action: Selector("copy:"), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "貼上", action: Selector("paste:"), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全選", action: Selector("selectAll:"), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem(title: "刪除", action: #selector(MainWindowController.deleteSelection(_:)), keyEquivalent: "\u{8}"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "檢視")
        viewMenu.addItem(NSMenuItem(title: "放大", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+"))
        viewMenu.addItem(NSMenuItem(title: "縮小", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-"))
        viewMenu.addItem(NSMenuItem(title: "100%", action: #selector(MainWindowController.zoom100(_:)), keyEquivalent: "0"))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(title: "格線", action: #selector(MainWindowController.toggleGridlines(_:)), keyEquivalent: "g"))
        viewMenu.addItem(NSMenuItem(title: "尺規", action: #selector(MainWindowController.toggleRulers(_:)), keyEquivalent: "r"))
        viewMenu.addItem(NSMenuItem(title: "狀態列", action: #selector(MainWindowController.toggleStatusBar(_:)), keyEquivalent: ""))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(title: "全螢幕", action: #selector(MainWindowController.toggleFullScreen(_:)), keyEquivalent: "f"))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Image menu
        let imageItem = NSMenuItem()
        let imageMenu = NSMenu(title: "影像")
        imageMenu.addItem(NSMenuItem(title: "裁剪", action: #selector(MainWindowController.cropImage(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "重新調整大小…", action: #selector(MainWindowController.resizeImage(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem.separator())
        imageMenu.addItem(NSMenuItem(title: "向右旋轉 90°", action: #selector(MainWindowController.rotateRight(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "向左旋轉 90°", action: #selector(MainWindowController.rotateLeft(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "旋轉 180°", action: #selector(MainWindowController.rotate180(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "水平翻轉", action: #selector(MainWindowController.flipHorizontal(_:)), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "垂直翻轉", action: #selector(MainWindowController.flipVertical(_:)), keyEquivalent: ""))
        imageItem.submenu = imageMenu
        mainMenu.addItem(imageItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "小畫家 (macOS 版)"
        alert.informativeText = "Windows 小畫家功能再現\n以原生 AppKit 實作\n\n© 2026"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }
}
