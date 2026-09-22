// Usage: webkit-runner <editor.html> <project.json> <test.js> <output-directory>
// Isolated WebKit storage; never loads or changes the running editor's session.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 5 else { fatalError("Expected editor, project, test, output paths") }
final class TestScheme: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
final class Runner: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var web: WKWebView!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.setURLSchemeHandler(TestScheme(), forURLScheme: "app")
        cfg.userContentController.add(self, name: "testResult")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), configuration: cfg)
        web.navigationDelegate = self
        window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.orderBack(nil)
        web.load(URLRequest(url: URL(string: "app://local/index.html")!))
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) { print("FAIL: WebKit test timeout"); exit(1) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        do {
            let project = try String(contentsOfFile: args[2], encoding: .utf8)
            let script = try String(contentsOfFile: args[3], encoding: .utf8)
            web.evaluateJavaScript("window.testProject = " + project + ";\n" + script + "\nvoid 0;") { _, error in
                if let error { print("FAIL: \(error)"); exit(1) }
            }
        } catch { print("FAIL: \(error)"); exit(1) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        if let name = value["file"] as? String, let b64 = value["base64"] as? String,
           let data = Data(base64Encoded: b64) {
            let url = URL(fileURLWithPath: args[4]).appendingPathComponent((name as NSString).lastPathComponent)
            do { try data.write(to: url); print("Saved \(url.path) (\(data.count) bytes)") }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        if let log = value["log"] as? String { print(log) }
        if let passed = value["passed"] as? Bool { exit(passed ? 0 : 1) }
    }
}
let app = NSApplication.shared
let runner = Runner()
app.delegate = runner
app.setActivationPolicy(.accessory)
app.run()
