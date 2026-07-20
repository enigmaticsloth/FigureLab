// FigureLab — native macOS shell around the single-file editor.
//
// The page is served over a custom app:// scheme rather than file://, because
// WebKit gives file:// pages an opaque origin where localStorage (the editor's
// autosave) is unavailable.

import AppKit
import WebKit
import UniformTypeIdentifiers

let appScheme = "app"
let appHost = "local"

final class PageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let name = url.path == "" || url.path == "/" ? "/index.html" : url.path
        let file = Bundle.main.resourceURL!.appendingPathComponent(String(name.dropFirst()))
        guard let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "FigureLab", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "找不到 \(name)"]))
            return
        }
        let mime = file.pathExtension == "html" ? "text/html" : "application/octet-stream"
        let resp = URLResponse(url: url, mimeType: mime,
                               expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class Controller: NSObject, NSApplicationDelegate, WKUIDelegate,
                        WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    private var pinchMonitor: Any?

    // MARK: launch

    func applicationDidFinishLaunching(_ note: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(PageSchemeHandler(), forURLScheme: appScheme)
        cfg.userContentController.add(self, name: "figurelab")
        cfg.websiteDataStore = .default()
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")

        web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.allowsMagnification = false

        let size = NSSize(width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "FigureLab"
        // A slim titlebar tinted like the app's own chrome: it stays draggable and
        // keeps the traffic lights clear of the page, without a second title.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(srgbRed: 0.122, green: 0.129, blue: 0.149, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = web
        window.delegate = self
        window.setFrameAutosaveName("FigureLabWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)

        buildMenu()
        installPinchZoom()
        web.load(URLRequest(url: URL(string: "\(appScheme)://\(appHost)/index.html")!))
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Trackpad pinch. Caught before the event reaches WebKit so the canvas
    /// zooms instead of the whole page, and so it can never fire twice.
    private func installPinchZoom() {
        pinchMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let p = self.web.convert(event.locationInWindow, from: nil)
            let x = p.x
            let y = self.web.bounds.height - p.y          // AppKit origin is bottom-left
            let factor = 1 + event.magnification
            self.js(String(format: "window.flZoom && flZoom(%.5f, %.1f, %.1f)", factor, x, y))
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    // MARK: menu

    /// Menu item routed to this controller (drives the web app).
    private func item(_ title: String, _ sel: Selector, _ key: String,
                      _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = self
        return it
    }

    /// Menu item left to the responder chain — required for the standard
    /// window and application commands to reach AppKit at all.
    private func std(_ title: String, _ sel: Selector, _ key: String,
                     _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        return it
    }

    /// Tool switches keep bare letters out of the menu: a modifier-less key
    /// equivalent would fire while the user is typing in the text tool.
    private func toolItem(_ title: String, _ letter: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: "\(title)　\(letter.uppercased())", action: sel, keyEquivalent: "")
        it.target = self
        return it
    }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("關於 FigureLab", #selector(about), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(std("隱藏 FigureLab", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(std("隱藏其他", #selector(NSApplication.hideOtherApplications(_:)),
                            "h", [.command, .option]))
        appMenu.addItem(std("顯示全部", #selector(NSApplication.unhideAllApplications(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(std("結束 FigureLab", #selector(NSApplication.terminate(_:)), "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "檔案")
        fileMenu.addItem(item("新檔案／新分頁…", #selector(cmdNew), "n"))
        fileMenu.addItem(item("新分頁…", #selector(cmdNew), "t"))
        fileMenu.addItem(item("匯入圖片／PSD／AI…", #selector(cmdImport), "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("開啟專案…", #selector(cmdOpen), "o"))
        fileMenu.addItem(item("儲存專案…", #selector(cmdSave), "s"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("匯出 PNG…", #selector(cmdPNG), "e"))
        fileMenu.addItem(item("匯出 JPEG…", #selector(cmdJPG), "e", [.command, .option]))
        fileMenu.addItem(item("匯出 TIFF…", #selector(cmdTIF), "e", [.command, .control]))
        fileMenu.addItem(item("匯出 SVG…", #selector(cmdSVG), "e", [.command, .shift]))
        fileMenu.addItem(item("匯出 PDF…", #selector(cmdPDF), "p", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("關閉分頁", #selector(cmdCloseTab), "w"))
        fileMenu.addItem(std("關閉視窗", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編輯")
        editMenu.addItem(item("復原", #selector(cmdUndo), "z"))
        editMenu.addItem(item("重做", #selector(cmdRedo), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("剪下", #selector(cmdCut), "x"))
        editMenu.addItem(item("複製", #selector(cmdCopy), "c"))
        editMenu.addItem(item("貼上", #selector(cmdPaste), "v"))
        editMenu.addItem(item("再製", #selector(cmdDuplicate), "d"))
        editMenu.addItem(item("刪除　⌫", #selector(cmdDelete), ""))
        editMenu.addItem(.separator())
        editMenu.addItem(item("全選", #selector(cmdSelectAll), "a"))
        editMenu.addItem(item("取消選取／結束編輯　esc", #selector(cmdCancel), ""))
        editMenu.addItem(.separator())
        editMenu.addItem(item("編輯節點", #selector(cmdNodes), "n", [.command, .shift]))
        editMenu.addItem(item("網格變形", #selector(cmdWarp), "d", [.command, .shift]))
        editMenu.addItem(item("裁切", #selector(cmdCropCanvas), "c", [.command, .option]))
        editMenu.addItem(item("裁掉留白", #selector(cmdTrim), "c", [.command, .option, .shift]))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let arrItem = NSMenuItem()
        let arrMenu = NSMenu(title: "排列")
        arrMenu.addItem(item("移至最前", #selector(cmdFront), "]", [.command, .shift]))
        arrMenu.addItem(item("上移一層", #selector(cmdUp), "]"))
        arrMenu.addItem(item("下移一層", #selector(cmdDown), "["))
        arrMenu.addItem(item("移至最後", #selector(cmdBack), "[", [.command, .shift]))
        arrMenu.addItem(.separator())
        let ctlCmd: NSEvent.ModifierFlags = [.command, .control]
        arrMenu.addItem(item("靠左對齊", #selector(cmdAlignL), "l", ctlCmd))
        arrMenu.addItem(item("水平置中", #selector(cmdAlignCX), "h", ctlCmd))
        arrMenu.addItem(item("靠右對齊", #selector(cmdAlignR), "r", ctlCmd))
        arrMenu.addItem(item("靠上對齊", #selector(cmdAlignT), "t", ctlCmd))
        arrMenu.addItem(item("垂直置中", #selector(cmdAlignCY), "m", ctlCmd))
        arrMenu.addItem(item("靠下對齊", #selector(cmdAlignB), "b", ctlCmd))
        arrItem.submenu = arrMenu
        main.addItem(arrItem)

        let toolItemRoot = NSMenuItem()
        let toolMenu = NSMenu(title: "工具")
        toolMenu.addItem(toolItem("選取", "v", #selector(toolSelect)))
        toolMenu.addItem(toolItem("直線", "l", #selector(toolLine)))
        toolMenu.addItem(toolItem("箭頭", "a", #selector(toolArrow)))
        toolMenu.addItem(toolItem("矩形", "r", #selector(toolRect)))
        toolMenu.addItem(toolItem("橢圓", "o", #selector(toolEllipse)))
        toolMenu.addItem(toolItem("曲線", "p", #selector(toolCurve)))
        toolMenu.addItem(toolItem("手繪", "b", #selector(toolPencil)))
        toolMenu.addItem(toolItem("文字", "t", #selector(toolText)))
        toolItemRoot.submenu = toolMenu
        main.addItem(toolItemRoot)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "檢視")
        viewMenu.addItem(item("放大", #selector(cmdZoomIn), "+"))
        // ⌘= types "=", ⌘⇧= types "+"; accept both without showing two rows.
        let zoomAlt = item("放大", #selector(cmdZoomIn), "=")
        zoomAlt.isHidden = true
        viewMenu.addItem(zoomAlt)
        viewMenu.addItem(item("縮小", #selector(cmdZoomOut), "-"))
        viewMenu.addItem(item("實際大小", #selector(cmdZoom100), "1"))
        viewMenu.addItem(item("適合視窗", #selector(cmdFit), "0"))
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "視窗")
        winMenu.addItem(item("下一個分頁", #selector(cmdNextTab), "\t", [.control]))
        winMenu.addItem(item("上一個分頁", #selector(cmdPrevTab), "\t", [.control, .shift]))
        winMenu.addItem(.separator())
        winMenu.addItem(std("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"))
        winMenu.addItem(std("縮放", #selector(NSWindow.performZoom(_:)), ""))
        // macOS supplies its own full-screen item (Fn+F) once one is present here.
        winMenu.addItem(std("進入全螢幕", #selector(NSWindow.toggleFullScreen(_:)),
                            "f", [.command, .control]))
        winMenu.addItem(.separator())
        winMenu.addItem(std("全部移至最前", #selector(NSApplication.arrangeInFront(_:)), ""))
        winItem.submenu = winMenu
        main.addItem(winItem)

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "說明")
        helpMenu.addItem(item("快速鍵與操作說明", #selector(cmdHelp), "/", [.command, .shift]))
        helpItem.submenu = helpMenu
        main.addItem(helpItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
        NSApp.helpMenu = helpMenu
    }


    private func js(_ code: String) { web.evaluateJavaScript(code, completionHandler: nil) }
    private func send(_ cmd: String) { js("window.flCommand && flCommand('\(cmd)')") }

    @objc func cmdNew() { send("new") }
    @objc func cmdImport() { send("import") }
    @objc func cmdOpen() { send("open") }
    @objc func cmdSave() { send("save") }
    @objc func cmdPNG() { send("png") }
    @objc func cmdSVG() { send("svg") }
    @objc func cmdUndo() { send("undo") }
    @objc func cmdRedo() { send("redo") }
    @objc func cmdDuplicate() { send("duplicate") }
    @objc func cmdDelete() { send("delete") }
    @objc func cmdSelectAll() { send("selectAll") }
    @objc func cmdFit() { send("fit") }
    @objc func cmdZoom100() { send("zoom100") }
    @objc func cmdZoomIn() { send("zoomIn") }
    @objc func cmdZoomOut() { send("zoomOut") }
    @objc func cmdHelp() { send("help") }
    @objc func cmdJPG() { send("jpeg") }
    @objc func cmdTIF() { send("tiff") }
    @objc func cmdPDF() { send("pdf") }
    @objc func cmdCloseTab() { send("closeTab") }
    @objc func cmdNextTab() { send("nextTab") }
    @objc func cmdPrevTab() { send("prevTab") }
    @objc func cmdCancel() { send("cancel") }
    @objc func cmdNodes() { send("nodes") }
    @objc func cmdWarp() { send("warp") }
    @objc func cmdCropCanvas() { send("cropCanvas") }
    @objc func cmdTrim() { send("trim") }
    @objc func cmdFront() { send("front") }
    @objc func cmdUp() { send("up") }
    @objc func cmdDown() { send("down") }
    @objc func cmdBack() { send("back") }
    @objc func cmdAlignL() { send("align-l") }
    @objc func cmdAlignCX() { send("align-cx") }
    @objc func cmdAlignR() { send("align-r") }
    @objc func cmdAlignT() { send("align-t") }
    @objc func cmdAlignCY() { send("align-cy") }
    @objc func cmdAlignB() { send("align-b") }
    @objc func toolSelect() { send("tool-select") }
    @objc func toolLine() { send("tool-line") }
    @objc func toolArrow() { send("tool-arrow") }
    @objc func toolRect() { send("tool-rect") }
    @objc func toolEllipse() { send("tool-ellipse") }
    @objc func toolCurve() { send("tool-curve") }
    @objc func toolPencil() { send("tool-pencil") }
    @objc func toolText() { send("tool-text") }

    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FigureLab",
            .init(rawValue: "Copyright"): "圖稿排版與標註工具　支援 PSD 圖層與 Illustrator 檔"
        ])
    }

    // MARK: clipboard

    @objc func cmdCopy() { copyOrCut(false) }
    @objc func cmdCut() { copyOrCut(true) }

    private func copyOrCut(_ cut: Bool) {
        web.evaluateJavaScript("window.flCopyPayload ? flCopyPayload(\(cut)) : null") { value, _ in
            if let text = value as? String, !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        }
    }

    @objc func cmdPaste() {
        let pb = NSPasteboard.general
        var imgArg = "null"
        if let data = imageDataFromPasteboard(pb) {
            imgArg = "'\(data.base64EncodedString())'"
        }
        var textArg = "null"
        if let s = pb.string(forType: .string) {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            textArg = "'\(escaped)'"
        }
        js("window.flPaste && flPaste(\(imgArg), \(textArg))")
    }

    private func imageDataFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return png }
        // A file copied in Finder arrives as a URL rather than pixels.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first,
           let img = NSImage(contentsOf: first),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return png }
        return nil
    }

    // MARK: JS → native

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }
        if cmd == "closeWindow" { window.performClose(nil); return }
        if cmd == "save" {
            let name = body["name"] as? String ?? "figure"
            let b64 = body["data"] as? String ?? ""
            guard let data = Data(base64Encoded: b64) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            if let ext = name.split(separator: ".").last,
               let type = UTType(filenameExtension: String(ext)) {
                panel.allowedContentTypes = [type]
            }
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, let url = panel.url else { return }
                do { try data.write(to: url) }
                catch { self.alert("儲存失敗", error.localizedDescription) }
            }
        }
    }

    private func alert(_ title: String, _ info: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window, completionHandler: nil)
    }

    // MARK: WKUIDelegate — without these, alert()/confirm() and file inputs do nothing

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "好")
        a.addButton(withTitle: "取消")
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { resp in
            completionHandler(resp == .OK ? panel.urls : nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = Controller()
app.delegate = controller
app.run()
