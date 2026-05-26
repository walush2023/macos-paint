import AppKit

// MARK: - Color picker dialog

enum ColorPickerDialog {
    static func run(in parent: NSWindow, initial: NSColor, completion: @escaping (NSColor?) -> Void) {
        let panel = NSColorPanel.shared
        panel.color = initial
        panel.showsAlpha = false
        // Use a continuous observer
        let observer = ColorPanelObserver()
        observer.completion = completion
        observer.target = panel
        panel.setTarget(observer)
        panel.setAction(#selector(ColorPanelObserver.colorChanged(_:)))
        // Keep observer alive
        observer.attach()
        panel.orderFront(nil)
    }
}

private final class ColorPanelObserver: NSObject {
    var completion: ((NSColor?) -> Void)?
    weak var target: NSColorPanel?
    private static var current: ColorPanelObserver?

    func attach() { ColorPanelObserver.current = self }

    @objc func colorChanged(_ panel: NSColorPanel) {
        completion?(panel.color)
    }
}

// MARK: - Resize dialog

enum ResizeDialog {
    static func run(in parent: NSWindow, currentSize: NSSize, completion: @escaping (NSSize?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "重新調整大小"

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 120)

        let wFld = NSTextField(string: String(Int(currentSize.width)))
        wFld.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        let hFld = NSTextField(string: String(Int(currentSize.height)))
        hFld.frame = NSRect(x: 0, y: 0, width: 100, height: 22)

        let wRow = NSStackView()
        wRow.orientation = .horizontal
        wRow.spacing = 6
        wRow.addArrangedSubview(NSTextField(labelWithString: "寬度 (像素):"))
        wRow.addArrangedSubview(wFld)
        stack.addArrangedSubview(wRow)

        let hRow = NSStackView()
        hRow.orientation = .horizontal
        hRow.spacing = 6
        hRow.addArrangedSubview(NSTextField(labelWithString: "高度 (像素):"))
        hRow.addArrangedSubview(hFld)
        stack.addArrangedSubview(hRow)

        let aspect = NSButton(checkboxWithTitle: "維持外觀比例", target: nil, action: nil)
        aspect.state = .on
        stack.addArrangedSubview(aspect)

        alert.accessoryView = stack
        alert.addButton(withTitle: "確定")
        alert.addButton(withTitle: "取消")

        alert.beginSheetModal(for: parent) { resp in
            if resp == .alertFirstButtonReturn {
                let w = max(1, Int(wFld.stringValue) ?? Int(currentSize.width))
                let h = max(1, Int(hFld.stringValue) ?? Int(currentSize.height))
                completion(NSSize(width: w, height: h))
            } else {
                completion(nil)
            }
        }
    }
}
