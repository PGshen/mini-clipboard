import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var controller: AppController?
    var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
        NSApp.setActivationPolicy(.accessory)
        ensureAccessibilityPermission()
        setApplicationIconFromPublic()
        controller?.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let fm = FileManager.default
            if let base = Bundle.main.resourceURL {
                let png = base.appendingPathComponent("public/menubar.png")
                if fm.fileExists(atPath: png.path), let img = NSImage(contentsOf: png) {
                    let thickness = NSStatusBar.system.thickness
                    let target = NSSize(width: thickness - 4, height: thickness - 4)
                    img.size = target
                    img.isTemplate = true
                    button.image = img
                    button.imageScaling = .scaleProportionallyDown
                    button.imagePosition = .imageOnly
                    button.title = ""
                } else if let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil) {
                    symbol.isTemplate = true
                    button.image = symbol
                    button.title = ""
                } else {
                    button.title = "MiniClip"
                }
            } else if let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil) {
                symbol.isTemplate = true
                button.image = symbol
                button.title = ""
            } else {
                button.title = "MiniClip"
            }
        }
        item.menu = buildStatusMenu()
        statusItem = item
        observeLanguageChanges()
    }
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("panel.menu.panel"), action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("panel.menu.settings"), action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("panel.menu.quit"), action: #selector(quitApp), keyEquivalent: ""))
        return menu
    }
    private func observeLanguageChanges() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if let item = self.statusItem { item.menu = self.buildStatusMenu() }
            if let w = self.preferencesWindow { w.title = L("window.settings.title") }
        }
    }
    private func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = L("alert.accessibility.title")
            alert.informativeText = L("alert.accessibility.message")
            alert.addButton(withTitle: L("alert.accessibility.openSettings"))
            alert.addButton(withTitle: L("alert.accessibility.later"))
            let r = alert.runModal()
            if r == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    private func setApplicationIconFromPublic() {
        let fm = FileManager.default
        if let base = Bundle.main.resourceURL {
            let png = base.appendingPathComponent("public/logo.png")
            let icns = base.appendingPathComponent("public/logo.icns")
            if fm.fileExists(atPath: png.path), let img = NSImage(contentsOf: png) {
                NSApp.applicationIconImage = img
                return
            }
            if fm.fileExists(atPath: icns.path), let img = NSImage(contentsOf: icns) {
                NSApp.applicationIconImage = img
                return
            }
        }
    }
    @objc func openPanel() { controller?.panel.show() }
    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let handled = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        if !handled {
            if preferencesWindow == nil {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                w.title = L("window.settings.title")
                w.isReleasedWhenClosed = false
                w.delegate = self
                let hosting = NSHostingView(rootView: SettingsView())
                hosting.translatesAutoresizingMaskIntoConstraints = false
                let content = NSView()
                content.translatesAutoresizingMaskIntoConstraints = false
                w.contentView = content
                content.addSubview(hosting)
                NSLayoutConstraint.activate([
                    hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    hosting.topAnchor.constraint(equalTo: content.topAnchor),
                    hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
                ])
                preferencesWindow = w
            }
            preferencesWindow?.center()
            preferencesWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w == preferencesWindow {
            preferencesWindow = nil
        }
    }
}

struct AppTheme {
    // 主色调
    static let mainPurple = Color(hex: "8C7CF0")
    static let palePinkPurple = Color(hex: "C6B9FF")
    
    // 辅色调
    static let softGreen = Color(hex: "A0E8AF")
    static let softYellow = Color(hex: "FDE68A")
    static let paleOrange = Color(hex: "FDBA74")
    
    // 背景色
    static let background = Color(hex: "F9F9FB") // 浅灰白
    static let panelBackground = Color(hex: "F5F5F7") // 面板背景
    static let cardBackground = Color.white // 卡片背景
    static let sidebarBackground = Color(hex: "F0F0F5") // 侧边栏背景
    
    // 阴影
    static let shadowColor = Color.black.opacity(0.05)
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
    
    // 渐变
    static let highlightGradient = LinearGradient(
        colors: [mainPurple, palePinkPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 圆角
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 12
    
    // MARK: - 多彩主题支持
    struct Palette {
        let main: Color
        let secondary: Color
        let background: Color
    }
    
    static let purple = Palette(main: Color(hex: "8C7CF0"), secondary: Color(hex: "C6B9FF"), background: Color(hex: "F9F9FB"))
    static let blue = Palette(main: Color(hex: "60A5FA"), secondary: Color(hex: "93C5FD"), background: Color(hex: "EFF6FF"))
    static let green = Palette(main: Color(hex: "34D399"), secondary: Color(hex: "6EE7B7"), background: Color(hex: "ECFDF5"))
    static let orange = Palette(main: Color(hex: "FB923C"), secondary: Color(hex: "FDBA74"), background: Color(hex: "FFF7ED"))
    static let pink = Palette(main: Color(hex: "F472B6"), secondary: Color(hex: "FBCFE8"), background: Color(hex: "FDF2F8"))
    static let teal = Palette(main: Color(hex: "2DD4BF"), secondary: Color(hex: "5EEAD4"), background: Color(hex: "F0FDFA"))
    static let yellow = Palette(main: Color(hex: "FBBF24"), secondary: Color(hex: "FDE68A"), background: Color(hex: "FFFBEB"))
    static let red = Palette(main: Color(hex: "F87171"), secondary: Color(hex: "FCA5A5"), background: Color(hex: "FEF2F2"))
    
    static let allPalettes = [purple, blue, green, orange, pink, teal, yellow, red]
    
    // 缓存已计算的应用主题色
    private static var appColorCache: [String: Palette] = [:]
    
    static func palette(for bundleID: String) -> Palette {
        if let cached = appColorCache[bundleID] { return cached }
        
        // 尝试从应用图标提取颜色
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            let icon = NSWorkspace.shared.icon(forFile: path).resize(to: NSSize(width: 32, height: 32))
            if let dominant = icon.dominantColor() {
                // 寻找最接近的预设色板
                let best = allPalettes.min(by: { p1, p2 in
                    distance(from: dominant, to: NSColor(p1.main)) < distance(from: dominant, to: NSColor(p2.main))
                }) ?? purple
                appColorCache[bundleID] = best
                return best
            }
        }
        
        // 降级方案：Hash 映射
        let hash = abs(bundleID.hashValue)
        let p = allPalettes[hash % allPalettes.count]
        appColorCache[bundleID] = p
        return p
    }
    
    static func closestPalette(for color: Color) -> Palette {
        let nsColor = NSColor(color)
        return allPalettes.min(by: { p1, p2 in
            distance(from: nsColor, to: NSColor(p1.main)) < distance(from: nsColor, to: NSColor(p2.main))
        }) ?? purple
    }
    
    private static func distance(from c1: NSColor, to c2: NSColor) -> Double {
        // 确保颜色转换到 sRGB 颜色空间，避免 Catalog color 报错
        guard let s1 = c1.usingColorSpace(.sRGB),
              let s2 = c2.usingColorSpace(.sRGB) else {
            return Double.greatestFiniteMagnitude
        }
        let r1 = s1.redComponent, g1 = s1.greenComponent, b1 = s1.blueComponent
        let r2 = s2.redComponent, g2 = s2.greenComponent, b2 = s2.blueComponent
        return sqrt(pow(r1-r2, 2) + pow(g1-g2, 2) + pow(b1-b2, 2))
    }
}

extension NSImage {
    func resize(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    func dominantColor() -> NSColor? {
        // 缩放到 1x1 取平均色
        let onePixel = self.resize(to: NSSize(width: 1, height: 1))
        guard let tiff = onePixel.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.colorAt(x: 0, y: 0)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

