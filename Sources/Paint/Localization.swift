import Foundation

/// 多國語言。以繁體中文原字串為 key；依系統語言自動選擇。
/// 未涵蓋的語言或字串回退為繁體中文原文。
enum L10n {
    enum Lang: Hashable { case zhHant, zhHans, en, ja }

    /// 測試/預覽時可強制指定語言（正常執行為 nil → 依系統）。
    static var override: Lang? = nil
    static let detected: Lang = detect()
    static var current: Lang { override ?? detected }

    static func detect() -> Lang {
        let pref = (Locale.preferredLanguages.first ?? "en").lowercased()
        if pref.hasPrefix("zh-hant") || pref.hasPrefix("zh-tw")
            || pref.hasPrefix("zh-hk") || pref.hasPrefix("zh-mo") { return .zhHant }
        if pref.hasPrefix("zh") { return .zhHans }       // zh-Hans / zh-CN / zh-SG
        if pref.hasPrefix("ja") { return .ja }
        return .en                                       // 其他 → 英文
    }

    static func tr(_ zh: String) -> String {
        if current == .zhHant { return zh }
        return table[zh]?[current] ?? zh
    }

    /// 帶格式參數（key 內含 %@ / %d 等）。
    static func trf(_ zh: String, _ args: CVarArg...) -> String {
        String(format: tr(zh), arguments: args)
    }

    private static func e(_ en: String, _ hans: String, _ ja: String) -> [Lang: String] {
        [.en: en, .zhHans: hans, .ja: ja]
    }

    private static let table: [String: [Lang: String]] = [
        // App / 視窗 / 標題
        "小畫家":            e("Paint", "画图", "ペイント"),
        "小畫家 (macOS 版)":  e("Paint for macOS", "画图（macOS 版）", "ペイント（macOS 版）"),
        "未命名":            e("Untitled", "无标题", "無題"),
        "未命名.png":        e("Untitled.png", "无标题.png", "無題.png"),
        "關於小畫家":         e("About Paint", "关于画图", "ペイントについて"),
        "結束小畫家":         e("Quit Paint", "退出画图", "ペイントを終了"),
        "Windows 小畫家功能再現\n以原生 AppKit 實作\n\n© 2026":
            e("A re-creation of Microsoft Paint\nBuilt natively with AppKit\n\n© 2026",
              "微软画图功能再现\n以原生 AppKit 实现\n\n© 2026",
              "Microsoft ペイントの再現\nAppKit でネイティブ実装\n\n© 2026"),
        "您要儲存對 %@ 的變更嗎？":
            e("Do you want to save changes to %@?",
              "是否保存对 %@ 的更改？",
              "%@ への変更を保存しますか？"),
        "寬度: %d 像素\n高度: %d 像素\n解析度: 96 DPI":
            e("Width: %d pixels\nHeight: %d pixels\nResolution: 96 DPI",
              "宽度: %d 像素\n高度: %d 像素\n分辨率: 96 DPI",
              "幅: %d ピクセル\n高さ: %d ピクセル\n解像度: 96 DPI"),

        // Tabs / 選單列
        "檔案": e("File", "文件", "ファイル"),
        "常用": e("Home", "主页", "ホーム"),
        "檢視": e("View", "视图", "表示"),
        "編輯": e("Edit", "编辑", "編集"),

        // 群組
        "剪貼簿":     e("Clipboard", "剪贴板", "クリップボード"),
        "影像":       e("Image", "图像", "イメージ"),
        "工具":       e("Tools", "工具", "ツール"),
        "容許度":     e("Tolerance", "容差", "許容値"),
        "筆刷":       e("Brushes", "刷子", "ブラシ"),
        "圖案":       e("Shapes", "形状", "図形"),
        "大小":       e("Size", "大小", "サイズ"),
        "色彩":       e("Colors", "颜色", "色"),
        "顯示或隱藏": e("Show or hide", "显示或隐藏", "表示/非表示"),
        "縮放":       e("Zoom", "缩放", "ズーム"),
        "顯示":       e("Display", "显示", "表示"),

        // 剪貼簿 / 影像 按鈕
        "貼上":           e("Paste", "粘贴", "貼り付け"),
        "剪下":           e("Cut", "剪切", "切り取り"),
        "複製":           e("Copy", "复制", "コピー"),
        "選取 ▾":         e("Select ▾", "选择 ▾", "選択 ▾"),
        "裁剪":           e("Crop", "裁剪", "トリミング"),
        "重新調整大小":   e("Resize", "调整大小", "サイズ変更"),
        "重新調整大小…":  e("Resize…", "调整大小…", "サイズ変更…"),
        "旋轉 ▾":         e("Rotate ▾", "旋转 ▾", "回転 ▾"),

        // 工具 tooltip
        "鉛筆":           e("Pencil", "铅笔", "鉛筆"),
        "以色彩填滿":     e("Fill with color", "用颜色填充", "色で塗りつぶし"),
        "文字":           e("Text", "文本", "テキスト"),
        "橡皮擦":         e("Eraser", "橡皮擦", "消しゴム"),
        "色彩選擇工具":   e("Color picker", "颜色选取器", "スポイト"),
        "放大鏡":         e("Magnifier", "放大镜", "拡大鏡"),

        // 筆刷
        "筆刷 ▾":         e("Brushes ▾", "刷子 ▾", "ブラシ ▾"),
        "書法筆 1":       e("Calligraphy brush 1", "书法笔 1", "カリグラフィ 1"),
        "書法筆 2":       e("Calligraphy brush 2", "书法笔 2", "カリグラフィ 2"),
        "噴槍":           e("Airbrush", "喷枪", "エアブラシ"),
        "油畫筆刷":       e("Oil brush", "油画笔", "油彩ブラシ"),
        "蠟筆":           e("Crayon", "蜡笔", "クレヨン"),
        "麥克筆":         e("Marker", "记号笔", "マーカー"),
        "自然鉛筆":       e("Natural pencil", "自然铅笔", "ナチュラル鉛筆"),
        "水彩筆刷":       e("Watercolour brush", "水彩笔", "水彩ブラシ"),

        // 形狀 tooltip
        "線條":           e("Line", "直线", "直線"),
        "曲線":           e("Curve", "曲线", "曲線"),
        "橢圓形":         e("Ellipse", "椭圆", "楕円"),
        "矩形":           e("Rectangle", "矩形", "四角形"),
        "圓角矩形":       e("Rounded rectangle", "圆角矩形", "角丸四角形"),
        "多邊形":         e("Polygon", "多边形", "多角形"),
        "三角形":         e("Triangle", "三角形", "三角形"),
        "直角三角形":     e("Right triangle", "直角三角形", "直角三角形"),
        "菱形":           e("Diamond", "菱形", "ひし形"),
        "五邊形":         e("Pentagon", "五边形", "五角形"),
        "六邊形":         e("Hexagon", "六边形", "六角形"),
        "右箭頭":         e("Right arrow", "右箭头", "右矢印"),
        "左箭頭":         e("Left arrow", "左箭头", "左矢印"),
        "上箭頭":         e("Up arrow", "上箭头", "上矢印"),
        "下箭頭":         e("Down arrow", "下箭头", "下矢印"),
        "四角星":         e("4-point star", "四角星", "4 点星"),
        "五角星":         e("5-point star", "五角星", "5 点星"),
        "六角星":         e("6-point star", "六角星", "6 点星"),
        "矩形圖說文字":   e("Rectangular callout", "矩形标注", "四角形吹き出し"),
        "橢圓形圖說文字": e("Oval callout", "椭圆标注", "楕円吹き出し"),
        "雲朵圖說文字":   e("Cloud callout", "云形标注", "雲形吹き出し"),
        "愛心":           e("Heart", "心形", "ハート"),
        "閃電":           e("Lightning", "闪电", "稲妻"),

        // 外框 / 填滿
        "外框: 純色":     e("Outline: Solid", "轮廓: 纯色", "枠線: 単色"),
        "外框: 無外框":   e("Outline: None", "轮廓: 无", "枠線: なし"),
        "填滿: 無填滿":   e("Fill: None", "填充: 无", "塗りつぶし: なし"),
        "填滿: 純色":     e("Fill: Solid", "填充: 纯色", "塗りつぶし: 単色"),

        // 選取選單
        "矩形選取":       e("Rectangular selection", "矩形选择", "四角形選択"),
        "任意形狀選取":   e("Free-form selection", "任意形状选择", "自由選択"),
        "全選":           e("Select all", "全选", "すべて選択"),

        // 大小 / 色彩
        "大小 ▾":         e("Size ▾", "大小 ▾", "サイズ ▾"),
        "編輯色彩":       e("Edit colors", "编辑颜色", "色の編集"),
        "色彩 1":         e("Color 1", "颜色 1", "色 1"),
        "色彩 2":         e("Color 2", "颜色 2", "色 2"),

        // 檢視
        "放大":           e("Zoom in", "放大", "拡大"),
        "縮小":           e("Zoom out", "缩小", "縮小"),
        "全螢幕":         e("Full screen", "全屏", "フルスクリーン"),
        "尺規":           e("Rulers", "标尺", "ルーラー"),
        "格線":           e("Gridlines", "网格线", "グリッド線"),
        "狀態列":         e("Status bar", "状态栏", "ステータスバー"),

        // 檔案/編輯/影像 選單
        "新增":           e("New", "新建", "新規"),
        "開啟…":          e("Open…", "打开…", "開く…"),
        "儲存":           e("Save", "保存", "保存"),
        "另存新檔…":      e("Save As…", "另存为…", "名前を付けて保存…"),
        "列印…":          e("Print…", "打印…", "プリント…"),
        "內容…":          e("Properties…", "属性…", "プロパティ…"),
        "復原":           e("Undo", "撤销", "取り消す"),
        "取消復原":       e("Redo", "重做", "やり直す"),
        "刪除":           e("Delete", "删除", "削除"),
        "向右旋轉 90°":   e("Rotate right 90°", "向右旋转 90°", "右に 90° 回転"),
        "向左旋轉 90°":   e("Rotate left 90°", "向左旋转 90°", "左に 90° 回転"),
        "旋轉 180°":      e("Rotate 180°", "旋转 180°", "180° 回転"),
        "水平翻轉":       e("Flip horizontal", "水平翻转", "左右反転"),
        "垂直翻轉":       e("Flip vertical", "垂直翻转", "上下反転"),

        // 對話框
        "影像內容":       e("Image Properties", "图像属性", "イメージのプロパティ"),
        "寬度 (像素):":   e("Width (pixels):", "宽度（像素）:", "幅（ピクセル）:"),
        "高度 (像素):":   e("Height (pixels):", "高度（像素）:", "高さ（ピクセル）:"),
        "維持外觀比例":   e("Maintain aspect ratio", "保持纵横比", "縦横比を維持"),
        "確定":           e("OK", "确定", "OK"),
        "取消":           e("Cancel", "取消", "キャンセル"),
        "不要儲存":       e("Don't Save", "不保存", "保存しない"),

        // tooltip 說明
        "油漆桶容許度：越高，越多相近顏色會被一起填滿":
            e("Fill tolerance: higher fills more similar colors together",
              "填充容差：越高，越多相近颜色会被一起填充",
              "塗りつぶしの許容値：高いほど近い色をまとめて塗ります"),
        "透明色：以此繪圖會清成透明（PNG 會保留透明）":
            e("Transparent color: drawing with it clears to transparency (preserved in PNG)",
              "透明色：用它绘图会清成透明（PNG 会保留透明）",
              "透明色：これで描くと透明になります（PNG で保持されます）"),
    ]
}

/// 全域簡寫。
func tr(_ zh: String) -> String { L10n.tr(zh) }
func trf(_ zh: String, _ args: CVarArg...) -> String {
    String(format: L10n.tr(zh), arguments: args)
}
