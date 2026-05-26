import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        windowController = MainWindowController()
        windowController.showWindow(nil)
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
        fileMenu.addItem(NSMenuItem(title: "新增", action: #selector(MainWindowController.newDocument), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "開啟…", action: #selector(MainWindowController.openDocument), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "儲存", action: #selector(MainWindowController.saveDocument), keyEquivalent: "s"))
        let saveAs = NSMenuItem(title: "另存新檔…", action: #selector(MainWindowController.saveAsDocument), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "列印…", action: #selector(MainWindowController.printDocument), keyEquivalent: "p"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "內容…", action: #selector(MainWindowController.showProperties), keyEquivalent: "e"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編輯")
        editMenu.addItem(NSMenuItem(title: "復原", action: #selector(MainWindowController.undo), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "取消復原", action: #selector(MainWindowController.redo), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪下", action: #selector(MainWindowController.cut), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "複製", action: #selector(MainWindowController.copy), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "貼上", action: #selector(MainWindowController.paste), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全選", action: #selector(MainWindowController.selectAll), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem(title: "刪除", action: #selector(MainWindowController.deleteSelection), keyEquivalent: "\u{8}"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "檢視")
        viewMenu.addItem(NSMenuItem(title: "放大", action: #selector(MainWindowController.zoomIn), keyEquivalent: "+"))
        viewMenu.addItem(NSMenuItem(title: "縮小", action: #selector(MainWindowController.zoomOut), keyEquivalent: "-"))
        viewMenu.addItem(NSMenuItem(title: "100%", action: #selector(MainWindowController.zoom100), keyEquivalent: "0"))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(title: "格線", action: #selector(MainWindowController.toggleGridlines), keyEquivalent: "g"))
        viewMenu.addItem(NSMenuItem(title: "尺規", action: #selector(MainWindowController.toggleRulers), keyEquivalent: "r"))
        viewMenu.addItem(NSMenuItem(title: "狀態列", action: #selector(MainWindowController.toggleStatusBar), keyEquivalent: ""))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(title: "全螢幕", action: #selector(MainWindowController.toggleFullScreen), keyEquivalent: "f"))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Image menu
        let imageItem = NSMenuItem()
        let imageMenu = NSMenu(title: "影像")
        imageMenu.addItem(NSMenuItem(title: "裁剪", action: #selector(MainWindowController.cropImage), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "重新調整大小…", action: #selector(MainWindowController.resizeImage), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem.separator())
        imageMenu.addItem(NSMenuItem(title: "向右旋轉 90°", action: #selector(MainWindowController.rotateRight), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "向左旋轉 90°", action: #selector(MainWindowController.rotateLeft), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "旋轉 180°", action: #selector(MainWindowController.rotate180), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "水平翻轉", action: #selector(MainWindowController.flipHorizontal), keyEquivalent: ""))
        imageMenu.addItem(NSMenuItem(title: "垂直翻轉", action: #selector(MainWindowController.flipVertical), keyEquivalent: ""))
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
