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
        alert.messageText = tr("重新調整大小")

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
        wRow.addArrangedSubview(NSTextField(labelWithString: tr("寬度 (像素):")))
        wRow.addArrangedSubview(wFld)
        stack.addArrangedSubview(wRow)

        let hRow = NSStackView()
        hRow.orientation = .horizontal
        hRow.spacing = 6
        hRow.addArrangedSubview(NSTextField(labelWithString: tr("高度 (像素):")))
        hRow.addArrangedSubview(hFld)
        stack.addArrangedSubview(hRow)

        let aspect = NSButton(checkboxWithTitle: tr("維持外觀比例"), target: nil, action: nil)
        aspect.state = .on
        stack.addArrangedSubview(aspect)

        // 維持外觀比例：改寬自動算高、改高自動算寬（原本勾選框沒有作用）
        let linker = AspectLinker(original: currentSize, width: wFld, height: hFld, aspect: aspect)
        wFld.delegate = linker
        hFld.delegate = linker

        alert.accessoryView = stack
        alert.addButton(withTitle: tr("確定"))
        alert.addButton(withTitle: tr("取消"))

        alert.beginSheetModal(for: parent) { resp in
            withExtendedLifetime(linker) {}
            if resp == .alertFirstButtonReturn {
                let maxD = Int(CanvasView.maxDimension)
                let w = min(maxD, max(1, Int(wFld.stringValue) ?? Int(currentSize.width)))
                let h = min(maxD, max(1, Int(hFld.stringValue) ?? Int(currentSize.height)))
                completion(NSSize(width: w, height: h))
            } else {
                completion(nil)
            }
        }
    }
}

/// 重新調整大小對話框：寬高連動（維持外觀比例）。
final class AspectLinker: NSObject, NSTextFieldDelegate {
    let original: NSSize
    let width: NSTextField, height: NSTextField, aspect: NSButton
    init(original: NSSize, width: NSTextField, height: NSTextField, aspect: NSButton) {
        self.original = original; self.width = width; self.height = height; self.aspect = aspect
    }
    /// 純函式（方便測試）：依比例由一邊算另一邊。
    static func linked(_ v: Int, from: CGFloat, to: CGFloat) -> Int {
        guard from > 0 else { return v }
        return max(1, Int((CGFloat(v) * to / from).rounded()))
    }
    func controlTextDidChange(_ obj: Notification) {
        guard aspect.state == .on, let f = obj.object as? NSTextField, let v = Int(f.stringValue), v > 0 else { return }
        if f === width {
            height.stringValue = String(AspectLinker.linked(v, from: original.width, to: original.height))
        } else if f === height {
            width.stringValue = String(AspectLinker.linked(v, from: original.height, to: original.width))
        }
    }
}
