// zcode-pet v0.2: refined SVG cat (WKWebView render) + petdex sprite-sheet support.
// Logic layer identical to v0.1 (hooks bridge → state.json → state machine → gamification).
// Build: swiftc -O -swift-version 5 -o zcode-pet-bin main.swift

import AppKit
import Foundation
import WebKit

// MARK: - Paths

let petDir = NSHomeDirectory() + "/.zcode/pet"
let statePath = petDir + "/state.json"
let controlPath = petDir + "/control.json"
let prefsPath = petDir + "/prefs.json"
let savePath = petDir + "/save.json"
let pidPath = petDir + "/pet.pid"
let petsDir = petDir + "/pets"
let appDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let htmlPath = appDir + "/pet.html"
func petlog(_ s: String) {
    let p = "/tmp/pet_dbg2.log"
    if !FileManager.default.fileExists(atPath: p) {
        FileManager.default.createFile(atPath: p, contents: nil)
    }
    let fh = FileHandle(forWritingAtPath: p)
    _ = try? fh?.seekToEnd()
    _ = try? fh?.write(("\(Date()) [pet] \(s)\n").data(using: .utf8)!)
    try? fh?.close()
}

// MARK: - Models

struct BridgeState: Codable {
    var status: String = "idle"
    var tool: String?
    var note: String?
    var toolCallCount: Int?
    var sessionId: String?
    var ts: Double?
}

struct SaveData: Codable {
    var hunger: Double = 100
    var affinity: Double = 0
    var food: Int = 3
    var fedCount: Int = 0
    var petCount: Int = 0
    var tasksDone: Int = 0
    var birthday: Double = Date().timeIntervalSince1970
    var lastPetAt: Double = 0
    var lastHungerDecayAt: Double = Date().timeIntervalSince1970
}

struct Prefs: Codable {
    var x: Double?
    var y: Double?
    var notifyPermission: Bool = true
    var notifyDone: Bool = false
    var pet: String = "builtin"
}

struct GridInfo: Codable {
    var mode: String = "sheet"
    var path: String
    var frameW: Int
    var frameH: Int
    var cols: Int
    var rows: Int
    var fps: Int = 8
}

func loadJSON<T: Decodable>(_ path: String, as type: T.Type, fallback: T) -> T {
    guard let data = FileManager.default.contents(atPath: path) else { return fallback }
    return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
}

func loadGrid(_ path: String) -> GridInfo? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(GridInfo.self, from: data)
}

func saveJSON<T: Encodable>(_ obj: T, to path: String) {
    guard let data = try? JSONEncoder().encode(obj) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let windowW: CGFloat = 232
let windowH: CGFloat = 304


// MARK: - 宠物市场设置窗口（settings.html + JS 桥）

final class MarketController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = MarketController()
    var window: NSWindow?
    var webView: WKWebView?
    weak var petController: PetController?

    func eval(_ js: String) {
        open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func open() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "zcode-pet 宠物市场"
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "pet")
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 580), configuration: cfg)
        wv.navigationDelegate = self
        let html = (try? String(contentsOfFile: appDir + "/settings.html", encoding: .utf8)) ?? "<h1>settings.html missing</h1>"
        wv.loadHTMLString(html, baseURL: URL(fileURLWithPath: appDir))
        w.contentView = wv
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w; webView = wv
        petlog("market window opened")
    }

    private func reply(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__onHostMsg(\(s.jacksonEscaped))", completionHandler: nil)
        }
    }

    // JS -> Swift 消息分发
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "getManifest": fetchManifest()
        case "listInstalled": reply(["type": "installed", "pets": installedList(), "current": petController?.prefs.pet ?? "builtin"])
        case "dress":
            if let name = body["name"] as? String {
                DispatchQueue.main.async { self.petController?.dress(name) }
                reply(["type": "dressed", "ok": true, "name": name])
            }
        case "adopt": adopt(body)
        case "close": window?.performClose(nil)
        default: break
        }
    }

    // ---- manifest（磁盘缓存 5 分钟） ----
    private func fetchManifest() {
        let cachePath = petDir + "/manifest-v2.json"
        let fm = FileManager.default
        if let attr = try? fm.attributesOfItem(atPath: cachePath),
           let mtime = attr[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < 300,
           let cached = try? String(contentsOfFile: cachePath, encoding: .utf8) {
            reply(["type": "manifest", "json": cached])
            return
        }
        let url = URL(string: "https://assets.petdex.dev/manifests/petdex-v2.json")!
        URLSession.shared.dataTask(with: url) { data, resp, err in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data = data, let s = String(data: data, encoding: .utf8) else {
                self.reply(["type": "manifest", "json": NSNull(), "error": "网络错误: \(err?.localizedDescription ?? "?")"])
                return
            }
            try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
            self.reply(["type": "manifest", "json": s])
        }.resume()
    }

    // ---- 已安装列表 ----
    private func installedList() -> [[String: Any]] {
        var out: [[String: Any]] = []
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: petsDir) {
            for name in names.sorted() {
                let dir = petsDir + "/" + name
                guard fm.fileExists(atPath: dir + "/grid.json") else { continue }
                var item: [String: Any] = ["name": name]
                if let gd = try? Data(contentsOf: URL(fileURLWithPath: dir + "/grid.json")),
                   let g = try? JSONSerialization.jsonObject(with: gd) as? [String: Any] {
                    item["path"] = g["path"] ?? ""
                    item["rows"] = g["rows"] ?? 9
                }
                if let pd = try? Data(contentsOf: URL(fileURLWithPath: dir + "/pet.json")),
                   let p = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
                   let disp = p["displayName"] as? String { item["displayName"] = disp }
                out.append(item)
            }
        }
        return out
    }

    // ---- 领养：下载 pet.json + spritesheet,生成 grid.json,自动换装 ----
    private func adopt(_ body: [String: Any]) {
        guard let slug = body["slug"] as? String,
              let petJsonUrl = body["petJsonUrl"] as? String,
              let sheetUrl = body["spritesheetUrl"] as? String else {
            reply(["type": "adopted", "ok": false, "error": "参数缺失"]); return
        }
        let dir = petsDir + "/" + slug
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let group = DispatchGroup()
        var petOk = false, sheetOk = false
        group.enter()
        URLSession.shared.dataTask(with: URL(string: petJsonUrl)!) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                try? data.write(to: URL(fileURLWithPath: dir + "/pet.json"), options: .atomic); petOk = true
            }
            group.leave()
        }.resume()
        group.enter()
        URLSession.shared.dataTask(with: URL(string: sheetUrl)!) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                let ext = sheetUrl.hasSuffix(".png") ? "png" : "webp"
                try? data.write(to: URL(fileURLWithPath: dir + "/spritesheet.\(ext)"), options: .atomic)
                sheetOk = data.count > 100
            }
            group.leave()
        }.resume()
        group.notify(queue: .main) {
            guard petOk, sheetOk else {
                self.reply(["type": "adopted", "ok": false, "slug": slug, "error": "下载失败（网络或资源不可用）"])
                return
            }
            // 找到下载的精灵图 + 生成 grid.json（petdex 规范优先）
            var sheetPath: String?
            for ext in ["webp", "png"] {
                let p = dir + "/spritesheet.\(ext)"
                if fm.fileExists(atPath: p) { sheetPath = p; break }
            }
            guard let sp = sheetPath, let grid = Self.makeGrid(path: sp) else {
                self.reply(["type": "adopted", "ok": false, "slug": slug, "error": "无法识别精灵图尺寸"])
                return
            }
            saveJSON(grid, to: dir + "/grid.json")
            self.petController?.dress(slug)
            self.reply(["type": "adopted", "ok": true, "slug": slug])
            petlog("adopted \(slug): grid \(grid.cols)x\(grid.rows)")
        }
    }

    /// petdex 规范：8 列 × 192×208 帧整数倍；否则回退 8 列宽高比
    static func makeGrid(path: String) -> GridInfo? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        for k in [1, 2, 3, 4] {
            let fw = 192 * k, fh = 208 * k
            if w == fw * 8 && h % fh == 0 && 9 <= h / fh && h / fh <= 12 {
                return GridInfo(mode: "sheet", path: path, frameW: fw, frameH: fh, cols: 8, rows: h / fh, fps: 8)
            }
        }
        let fw = w / 8
        guard fw > 0 else { return nil }
        let rows = max(1, Int((Double(h) / Double(fw) * 208.0 / 208.0).rounded()))
        return GridInfo(mode: "sheet", path: path, frameW: fw, frameH: h / rows, cols: 8, rows: rows, fps: 8)
    }
}

extension String {
    /// JSON 字符串字面量安全嵌入 JS
    var jacksonEscaped: String {
        let esc: [String: String] = ["\\": "\\\\", "\"": "\\\"", "\n": "\\n", "\r": "", "<": "\\u003c"]
        var out = self
        for (k, v) in esc { out = out.replacingOccurrences(of: k, with: v) }
        return "\"" + out + "\""
    }
}

// MARK: - Host view (webview under, transparent event catcher on top)

final class PetHostView: NSView, WKNavigationDelegate {
    let webView: WKWebView
    var controller: PetController? = nil
    private var jsReady = false
    private var pendingJS: [String] = []

    init() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: windowW, height: windowH))
        super.init(frame: NSRect(x: 0, y: 0, width: windowW, height: windowH))
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // transparent
        petlog("html exists: \(FileManager.default.fileExists(atPath: htmlPath)) path=\(htmlPath)")
        petlog("webview frame=\(webView.frame) winScale")
        addSubview(webView)
        let html = (try? String(contentsOfFile: htmlPath, encoding: .utf8)) ?? "<h1>no html</h1>"
        webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: appDir))
    }

    required init?(coder: NSCoder) { fatalError() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        petlog("didFail: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        petlog("didFailProvisional: \(error.localizedDescription)")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        petlog("WebContentProcessDidTerminate!")
    }
    override func hitTest(_ point: NSPoint) -> NSView? { return self } // swallow webview events

    func js(_ script: String) {
        if jsReady { webView.evaluateJavaScript(script, completionHandler: nil) }
        else { pendingJS.append(script) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        petlog("didFinish navigation")
        jsReady = true
        let queued = pendingJS
        pendingJS.removeAll()
        queued.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
        controller?.renderAll()
    }

    // --- mouse: drag / click=pet / double=feed / right=menu ---
    private var dragStart: NSPoint? = nil
    private var moved = false
    private var lastClick: Date? = nil

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        moved = false
        if let last = lastClick, Date().timeIntervalSince(last) < 0.35 {
            controller?.feedTheCat(); lastClick = nil; dragStart = nil; return
        }
        lastClick = Date()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        if abs(now.x - start.x) + abs(now.y - start.y) > 4 { moved = true }
        guard let panel = window else { return }
        let o = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: o.x + now.x - start.x, y: o.y + now.y - start.y))
        dragStart = now
    }

    override func mouseUp(with event: NSEvent) {
        if moved { controller?.persistPosition() }
        else if let last = lastClick, Date().timeIntervalSince(last) < 0.3 {
            controller?.petTheCat()
        }
        dragStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.buildMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Controller

final class PetController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let host: PetHostView
    var save: SaveData
    var prefs: Prefs
    var bridge: BridgeState
    var lastStateTs: Double = 0
    var transientUntil: Date = .distantPast
    var transientStatus: String? = nil
    var attentionNotified = false
    var pushedSignature = ""
    var pollTick: Timer? = nil
    var customGrid: GridInfo? = nil

    init(panel: NSPanel, host: PetHostView) {
        self.panel = panel
        self.host = host
        self.save = loadJSON(savePath, as: SaveData.self, fallback: SaveData())
        self.prefs = loadJSON(prefsPath, as: Prefs.self, fallback: Prefs())
        self.bridge = loadJSON(statePath, as: BridgeState.self, fallback: BridgeState())
        super.init()
        panel.delegate = self
        if prefs.pet != "builtin", let g = loadGrid(petDir + "/pets/" + prefs.pet + "/grid.json") {
            customGrid = g
        }
        restoreWindowPosition()
    }

    private func restoreWindowPosition() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let x = prefs.x, let y = prefs.y {
            panel.setFrameOrigin(NSPoint(x: CGFloat(x), y: CGFloat(y)))
        } else {
            panel.setFrameOrigin(NSPoint(x: screenFrame.maxX - windowW - 24, y: screenFrame.minY + 140))
        }
    }

    func persistPosition() {
        let o = panel.frame.origin
        prefs.x = Double(o.x); prefs.y = Double(o.y)
        saveJSON(prefs, to: prefsPath)
    }

    // MARK: render pushes

    func renderAll() {
        if let g = customGrid {
            let payload = "{\"mode\":\"sheet\",\"path\":\"\(g.path)\",\"frameW\":\(g.frameW),\"frameH\":\(g.frameH),\"cols\":\(g.cols),\"rows\":\(g.rows),\"fps\":\(g.fps)}"
            host.js("setCustomPet(\(payload))")
        } else {
            host.js("setCustomPet(null)")
        }
        pushStatus(force: true)
        host.js("setTier(\(tier()))")
        host.js("setHungry(\(save.hunger < 30))")
    }

    func tier() -> Int {
        if save.affinity >= 100 { return 3 }
        if save.affinity >= 50 { return 2 }
        if save.affinity >= 10 { return 1 }
        return 0
    }

    func pushStatus(force: Bool = false) {
        let status = effectiveStatus()
        let tool = bridge.tool ?? ""
        let sig = status + "|" + tool
        if !force && sig == pushedSignature { return }
        pushedSignature = sig
        let toolArg = tool.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        host.js("setStatus('\(status)','\(toolArg)')")
    }

    func effectiveStatus() -> String {
        if let t = transientStatus {
            if Date() <= transientUntil { return t }
            transientStatus = nil
        }
        switch bridge.status {
        case "greet": return "greet"
        case "thinking": return "thinking"
        case "working": return "working"
        case "error": return "error"
        case "attention": return "attention"
        case "celebrate": return "celebrate"
        case "waiting", "idle": return "idle"
        default: return "idle"
        }
    }

    func bubble(_ text: String, seconds: Double = 4) {
        let safe = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        host.js("setBubble('\(safe)', \(seconds))")
    }

    // MARK: timers & state machine

    func start() {
        pollTick = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(pollTick!, forMode: .common)
    }

    func poll() {
        decayHunger()
        let fresh = loadJSON(statePath, as: BridgeState.self, fallback: bridge)
        if (fresh.ts ?? 0) != lastStateTs {
            lastStateTs = fresh.ts ?? 0
            bridge = fresh
            onStateChange()
        }
        consumeControl()
        // sleep after 5 min idle
        if transientStatus == nil {
            let last = Date(timeIntervalSince1970: lastStateTs)
            let idle = Date().timeIntervalSince(last)
            if idle > 300 && bridge.status != "sleep" {
                bridge.status = "sleep"
                pushStatus()
            } else if idle <= 300 && bridge.status == "sleep" {
                bridge.status = "idle"
                pushStatus()
            }
        }
        pushStatus()
    }

    private func onStateChange() {
        let status = bridge.status
        if status == "greet" {
            playTransient("greet", seconds: 2.0)
            bubble("喵！开工啦～", seconds: 2.5)
            return
        }
        if status == "thinking" {
            if let note = bridge.note, !note.isEmpty { bubble("思考中：\(note)") }
            return
        }
        if status == "working" {
            if let tool = bridge.tool { bubble("正在 \(tool) …", seconds: 2) }
            return
        }
        if status == "error" {
            bubble("呜…\(bridge.note ?? "工具出错了")", seconds: 4)
            return
        }
        if status == "attention" {
            if !attentionNotified {
                attentionNotified = true
                let tool = bridge.tool ?? "工具"
                bubble("猫在喊你确认 \(tool)！", seconds: 6)
                if prefs.notifyPermission {
                    notify(title: "ZCode 桌宠", body: "需要你的确认：\(tool)（猫在挥手）")
                }
            }
            return
        }
        if status == "celebrate" {
            let count = bridge.toolCallCount ?? 0
            let drop = min(3, 1 + count / 5)
            save.tasksDone += 1
            save.affinity = min(100, save.affinity + 1)
            let before = save.food
            save.food = min(9, save.food + drop)
            let gained = save.food - before
            persistSave()
            host.js("setTier(\(tier()))")
            playTransient("celebrate", seconds: 2.5)
            bubble(gained > 0 ? "任务完成！掉落 \(gained) 个猫粮 🐟" : "任务完成！猫粮已满", seconds: 4)
            if prefs.notifyDone {
                notify(title: "ZCode 桌宠", body: "任务完成（\(count) 次工具调用）")
            }
            attentionNotified = false
            return
        }
        if status == "waiting" {
            bubble("等你下一句话…", seconds: 3)
            attentionNotified = false
            return
        }
        attentionNotified = false
    }

    func playTransient(_ status: String, seconds: TimeInterval) {
        transientStatus = status
        transientUntil = Date().addingTimeInterval(seconds)
        pushStatus(force: true)
    }

    func decayHunger() {
        let now = Date().timeIntervalSince1970
        let hours = (now - save.lastHungerDecayAt) / 3600
        if hours > 0.05 {
            let wasHungry = save.hunger < 30
            save.hunger = max(0, save.hunger - hours * 2)
            save.lastHungerDecayAt = now
            persistSave()
            if wasHungry != (save.hunger < 30) { host.js("setHungry(\(save.hunger < 30))") }
        }
    }

    func persistSave() { saveJSON(save, to: savePath) }

    // MARK: interactions

    func petTheCat() {
        let now = Date().timeIntervalSince1970
        var message = "呼噜呼噜…"
        if now - save.lastPetAt > 60 {
            save.petCount += 1
            save.lastPetAt = now
            save.affinity = min(100, save.affinity + 1)
            persistSave()
            host.js("setTier(\(tier()))")
        } else {
            message = "刚摸过，猫要被摸秃了"
        }
        playTransient("petting", seconds: 1.6)
        bubble(message, seconds: 2.5)
    }

    func feedTheCat() {
        guard save.food > 0 else { bubble("猫粮没了！完成任务会掉落", seconds: 3); return }
        guard save.hunger < 95 else { bubble("还不饿，先干活吧喵", seconds: 3); return }
        save.food -= 1
        save.fedCount += 1
        save.hunger = min(100, save.hunger + 25)
        save.affinity = min(100, save.affinity + 2)
        persistSave()
        host.js("setTier(\(tier()))")
        host.js("setHungry(\(save.hunger < 30))")
        playTransient("eating", seconds: 2.5)
        bubble("开饭！剩 \(save.food) 个猫粮", seconds: 3)
    }

    // MARK: control file

    private func consumeControl() {
        guard FileManager.default.fileExists(atPath: controlPath),
              let data = FileManager.default.contents(atPath: controlPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else { return }
        try? FileManager.default.removeItem(atPath: controlPath)
        switch action {
        case "feed": feedTheCat()
        case "pet": petTheCat()
        case "show": panel.orderFrontRegardless()
        case "hide": panel.orderOut(nil)
        case "reload": renderAll()
        case "dress":
            if let name = obj["name"] as? String { dress(name) }
        case "market": openMarket()
        case "market-eval":
            if let js = obj["js"] as? String {
                MarketController.shared.eval(js)
            }
        case "status":
            let days = Int(Date().timeIntervalSince1970 - save.birthday) / 86400
            bubble("状态 \(bridge.status)｜饥饿 \(Int(save.hunger))｜亲密 \(Int(save.affinity))｜猫粮 \(save.food)｜养了 \(days) 天", seconds: 5)
        default: break
        }
    }

    // MARK: notifications

    func notify(title: String, body: String) {
        let esc = body.replacingOccurrences(of: "\"", with: "'")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(esc)\" with title \"\(title)\""]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // MARK: menu

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "摸摸猫（单击也能摸）", action: #selector(mPet(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: save.food > 0 ? "喂食（剩 \(save.food) 个猫粮）" : "喂食（没粮了）", action: #selector(mFeed(_:)), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "状态气泡", action: #selector(mStatus(_:)), keyEquivalent: "").target = self
        let perm = NSMenuItem(title: "通知：需要确认时喊我", action: #selector(mPerm(_:)), keyEquivalent: "")
        perm.target = self; perm.state = prefs.notifyPermission ? .on : .off; menu.addItem(perm)
        let done = NSMenuItem(title: "通知：任务完成时告诉我", action: #selector(mDone(_:)), keyEquivalent: "")
        done.target = self; done.state = prefs.notifyDone ? .on : .off; menu.addItem(done)
        // 换装子菜单
        let dress = NSMenuItem(title: "换装", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let builtin = NSMenuItem(title: "内置橘猫" + (prefs.pet == "builtin" ? " ✓" : ""), action: #selector(mDress(_:)), keyEquivalent: "")
        builtin.target = self; builtin.representedObject = "builtin"; sub.addItem(builtin)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: petsDir) {
            for name in names.sorted() where FileManager.default.fileExists(atPath: petsDir + "/" + name + "/grid.json") {
                let item = NSMenuItem(title: name + (prefs.pet == name ? " ✓" : ""), action: #selector(mDress(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = name; sub.addItem(item)
            }
        }
        dress.submenu = sub
        menu.addItem(dress)
        menu.addItem(withTitle: "宠物市场…（领养新宠物）", action: #selector(mMarket(_:)), keyEquivalent: "m").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "隐藏猫（/pet show 唤回）", action: #selector(mHide(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出桌宠", action: #selector(mQuit(_:)), keyEquivalent: "q").target = self
        return menu
    }

    @objc func mMarket(_ s: Any?) { openMarket() }
    @objc func mPet(_ s: Any?) { petTheCat() }
    @objc func mFeed(_ s: Any?) { feedTheCat() }
    @objc func mStatus(_ s: Any?) {
        let days = Int(Date().timeIntervalSince1970 - save.birthday) / 86400
        bubble("状态 \(bridge.status)｜饥饿 \(Int(save.hunger))｜亲密 \(Int(save.affinity))｜猫粮 \(save.food)｜养了 \(days) 天", seconds: 5)
    }
    @objc func mPerm(_ s: Any?) { prefs.notifyPermission.toggle(); saveJSON(prefs, to: prefsPath) }
    @objc func mDone(_ s: Any?) { prefs.notifyDone.toggle(); saveJSON(prefs, to: prefsPath) }
    @objc func mDress(_ s: NSMenuItem) {
        guard let name = s.representedObject as? String else { return }
        dress(name)
    }
    func openMarket() { MarketController.shared.open() }

    func dress(_ name: String) {
        prefs.pet = name
        saveJSON(prefs, to: prefsPath)
        if name == "builtin" { customGrid = nil }
        else if let g = loadGrid(petsDir + "/" + name + "/grid.json") { customGrid = g }
        renderAll()
        bubble(name == "builtin" ? "换回内置橘猫～" : "换上 \(name)！", seconds: 2.5)
    }
    @objc func mHide(_ s: Any?) { panel.orderOut(nil) }
    @objc func mQuit(_ s: Any?) {
        try? FileManager.default.removeItem(atPath: pidPath)
        NSApp.terminate(nil)
    }
}

// MARK: - Panel

final class PetPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
    }
}

// MARK: - main

func alreadyRunning() -> Bool {
    guard let text = try? String(contentsOfFile: pidPath, encoding: .utf8),
          let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return false }
    return kill(pid, 0) == 0
}

if alreadyRunning() { print("zcode-pet already running"); exit(0) }
try? FileManager.default.createDirectory(atPath: petDir, withIntermediateDirectories: true)
try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: windowW, height: windowH),
                     styleMask: [], backing: .buffered, defer: false)
let host = PetHostView()
panel.contentView = host
let controller = PetController(panel: panel, host: host)
host.controller = controller
MarketController.shared.petController = controller
petlog("app start, panel frame=\(panel.frame) htmlPath=\(htmlPath)")
panel.orderFrontRegardless()
controller.start()

app.run()
