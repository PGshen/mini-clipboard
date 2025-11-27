import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import Carbon.HIToolbox

// 面板窗口控制器：创建半透明浮层窗口并处理显示/隐藏与定位
public final class PanelWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var window: NSWindow?
    private var rootView: AnyView?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var effectView: NSVisualEffectView?
    private var toastWindow: NSWindow?
    private var eventTap: CFMachPort?
    private var eventRunLoopSource: CFRunLoopSource?
    private var imeField: NSTextField?
    private var searchOverlayWindow: NSPanel?
    private var searchOverlayField: NSTextField?
    private var searchOverlayRect: CGRect?
    private var inputBuffer: String = ""
    public var previewService: PreviewService?
    public var onQueryUpdate: ((String) -> Void)?
    public var onSearchOverlayVisibleChanged: ((Bool) -> Void)?
    public var onShowSearchPopover: ((String?) -> Void)?
    public var onHideSearchPopover: (() -> Void)?
    public var onArrowLeft: (() -> Void)?
    public var onArrowRight: (() -> Void)?
    public var onArrowUp: (() -> Void)?
    public var onArrowDown: (() -> Void)?
    public var onEnter: (() -> Void)?
    public var onSpace: (() -> Void)?
    public var onShown: (() -> Void)?
    private var isSearchActive: Bool = false
    public func setSearchActive(_ active: Bool) { isSearchActive = active }
    public func updateSearchOverlayRect(_ rect: CGRect) { searchOverlayRect = rect }
    public override init() { super.init() }
    private func targetWidth() -> CGFloat {
        let s = activeScreen() ?? NSScreen.main
        guard let screen = s else { return 960 }
        return min(screen.visibleFrame.width * 0.8, 2048)
    }
    private func targetHeight() -> CGFloat {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        let style = HistoryLayoutStyle(rawValue: raw) ?? .horizontal
        switch style {
        case .horizontal: return 280
        case .grid: return 720
        }
    }
    // 设置 SwiftUI 根视图
    public func setRoot<V: View>(_ view: V) { rootView = AnyView(view) }
    public func show() {
        guard let rootView = rootView else { return }
        if window == nil {
            // 首次创建辅助窗口（utility）透明浮层，置于前台但不激活
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: targetWidth(), height: targetHeight()), styleMask: [.utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.level = .statusBar
            w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            w.isMovableByWindowBackground = false
            w.isFloatingPanel = true
            w.becomesKeyOnlyIfNeeded = true
            // HUD 材质效果与圆角
            let ev = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: targetWidth(), height: targetHeight()))
            ev.material = .popover
            ev.blendingMode = .behindWindow
            ev.state = .active
            ev.wantsLayer = true
            ev.layer?.cornerRadius = 16
            ev.layer?.masksToBounds = true
            // 使用 NSHostingView 承载 SwiftUI 内容
            let hosting = NSHostingView(rootView: rootView)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            ev.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: ev.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: ev.bottomAnchor)
            ])
            w.contentView = ev
            effectView = ev
            w.backgroundColor = .clear
            w.hasShadow = false
            w.delegate = self
            window = w
        } else {
            let width = targetWidth()
            window?.setContentSize(NSSize(width: width, height: targetHeight()))
        }
        positionCenter()
        if let w = window {
            let finalFrame = w.frame
            let scale: CGFloat = 0.96
            let initSize = NSSize(width: finalFrame.size.width * scale, height: finalFrame.size.height * scale)
            var initOrigin = finalFrame.origin
            initOrigin.x += (finalFrame.size.width - initSize.width) / 2
            initOrigin.y += (finalFrame.size.height - initSize.height) / 2
            effectView?.alphaValue = 0
            w.setFrame(NSRect(origin: initOrigin, size: initSize), display: false)
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                (w.animator()).setFrame(finalFrame, display: true)
                effectView?.animator().alphaValue = 1
            }
            if let ev = effectView { w.invalidateCursorRects(for: ev) }
            NSCursor.arrow.set()
            DispatchQueue.main.async { NSCursor.arrow.set() }
        } else {
            window?.orderFrontRegardless()
            if let w = window, let ev = effectView { w.invalidateCursorRects(for: ev) }
            NSCursor.arrow.set()
            DispatchQueue.main.async { NSCursor.arrow.set() }
        }
        inputBuffer = ""
        onQueryUpdate?("")
        // 安装失焦与外部点击自动隐藏行为
        installHidingBehavior()
        installEventTap()
        ensureEventTapActive()
        imeField?.stringValue = ""
        onShown?()
    }
    public func hide(animated: Bool = true) {
        previewService?.close()
        guard let w = window else { return }
        if !animated {
            w.orderOut(nil)
            return
        }
        let finalFrame = w.frame
        let scale: CGFloat = 0.96
        let targetSize = NSSize(width: finalFrame.size.width * scale, height: finalFrame.size.height * scale)
        var targetOrigin = finalFrame.origin
        targetOrigin.x += (finalFrame.size.width - targetSize.width) / 2
        targetOrigin.y += (finalFrame.size.height - targetSize.height) / 2
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            (w.animator()).setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            effectView?.animator().alphaValue = 0
        } completionHandler: {
            w.orderOut(nil)
        }
        inputBuffer = ""
        onQueryUpdate?("")
        uninstallEventTap()
        imeField?.stringValue = ""
        searchOverlayWindow?.orderOut(nil)
        searchOverlayWindow = nil
        onSearchOverlayVisibleChanged?(false)
    }
    public func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }
    public func updateLayoutHeight(animated: Bool = true) {
        guard let w = window else { return }
        let newH = targetHeight()
        var f = w.frame
        let delta = f.height - newH
        f.size.height = newH
        f.origin.y += delta / 2
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                (w.animator()).setFrame(f, display: true)
                effectView?.animator().setFrameSize(NSSize(width: f.size.width, height: newH))
            }
        } else {
            w.setFrame(f, display: true, animate: false)
            effectView?.setFrameSize(NSSize(width: f.size.width, height: newH))
        }
    }
    
    private func positionCenter() {
        guard let w = window else { return }
        let s = activeScreen() ?? NSScreen.main
        guard let screen = s else { return }
        let f = screen.visibleFrame
        let x = f.midX - (w.frame.width / 2)
        let y = f.midY - (w.frame.height / 2)
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activeScreen() -> NSScreen? {
        let p = NSEvent.mouseLocation
        for s in NSScreen.screens {
            if s.frame.contains(p) { return s }
        }
        return nil
    }
    private func installHidingBehavior() {
        if outsideClickMonitor == nil {
            // 全局监听鼠标点击以便面板自动隐藏
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self else { return }
                let p = NSEvent.mouseLocation
                if let w = self.window, w.isVisible, w.frame.contains(p) { return }
                if let pf = self.previewService?.windowFrame(), pf.contains(p) { return }
                if self.window?.isVisible == true { self.hide() }
            }
        }
        // 键盘事件在 CGEventTap 中处理
        // 应用失活时隐藏面板
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }
    private func installEventTap() {
        uninstallEventTap()
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let ctrl = Unmanaged<PanelWindowController>.fromOpaque(refcon).takeUnretainedValue()
            if ctrl.window?.isVisible != true { return Unmanaged.passUnretained(event) }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = ctrl.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode == 57 || keycode == 102 || keycode == 104 { return Unmanaged.passUnretained(event) }
                if keycode == 49 {
                    if ctrl.isFirstResponderTextInput() || ctrl.isAnyTextInputActive() || ctrl.isSearchActive { return Unmanaged.passUnretained(event) }
                    ctrl.onSpace?()
                    return nil
                }
                if keycode == 53 {
                    if ctrl.isSearchActive { ctrl.onHideSearchPopover?(); return nil }
                    if ctrl.previewService?.isVisible() == true { ctrl.previewService?.close(); return nil }
                    ctrl.hide();
                    return nil
                }
                let flags = event.flags
                if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) { return Unmanaged.passUnretained(event) }
                // 方向键与回车处理（面板自身拦截）
                if !ctrl.isFirstResponderTextInput() && !ctrl.isAnyTextInputActive() {
                    if keycode == 123 { ctrl.onArrowLeft?(); return nil }
                    if keycode == 124 { ctrl.onArrowRight?(); return nil }
                    if keycode == 126 { ctrl.onArrowUp?(); return nil }
                    if keycode == 125 { ctrl.onArrowDown?(); return nil }
                    if keycode == 36 || keycode == 76 { ctrl.onEnter?(); return nil }
                }
                if ctrl.isFirstResponderTextInput() { return Unmanaged.passUnretained(event) }
                if ctrl.isAnyTextInputActive() { return Unmanaged.passUnretained(event) }
                if let ne = NSEvent(cgEvent: event), let s = ne.charactersIgnoringModifiers, !s.isEmpty {
                    if ctrl.isSearchActive {
                        return Unmanaged.passUnretained(event)
                    } else {
                        ctrl.onShowSearchPopover?(nil)
                        if let copied = event.copy() {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                                copied.post(tap: .cgSessionEventTap)
                            }
                        }
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) {
            eventTap = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventRunLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            showToast(L("permission.inputMonitoring"))
        }
    }
    private func ensureEventTapActive() {
        if eventTap == nil || eventRunLoopSource == nil {
            installEventTap()
            return
        }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
    public func contentWidth() -> CGFloat {
        if let w = window { return w.frame.size.width }
        return targetWidth()
    }
    private func showSearchOverlay() {
        guard let rect = searchOverlayRect else { return }
        let size = NSSize(width: rect.size.width, height: 32)
        let w = NSPanel(contentRect: NSRect(x: rect.origin.x, y: rect.origin.y - (32 - rect.size.height)/2, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.level = .statusBar
        w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        w.backgroundColor = .clear
        w.hasShadow = false
        let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        ev.material = .hudWindow
        ev.blendingMode = .withinWindow
        ev.state = .active
        ev.wantsLayer = true
        ev.layer?.cornerRadius = 16
        ev.layer?.masksToBounds = true
        let tf = NSTextField(frame: NSRect(x: 28, y: 6, width: size.width - 40, height: 20))
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.delegate = self
        ev.addSubview(tf)
        let icon = NSImageView(frame: NSRect(x: 10, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        ev.addSubview(icon)
        w.contentView = ev
        searchOverlayField = tf
        searchOverlayWindow?.orderOut(nil)
        searchOverlayWindow = w
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.makeFirstResponder(tf)
        onSearchOverlayVisibleChanged?(true)
    }
    private func isFirstResponderTextInput() -> Bool {
        guard let w = window else { return false }
        if let r = w.firstResponder {
            if r is NSTextView || r is NSTextField { return true }
            if let clz = object_getClass(r) {
                let name = NSStringFromClass(clz)
                if name.contains("NSTextView") || name.contains("NSTextField") { return true }
            }
        }
        return false
    }
    private func isAnyTextInputActive() -> Bool {
        for w in NSApp.windows {
            if let r = w.firstResponder {
                if r is NSTextView || r is NSTextField { return true }
                let name = NSStringFromClass(type(of: r))
                if name.contains("NSTextView") || name.contains("NSTextField") { return true }
            }
        }
        return false
    }
    private func uninstallEventTap() {
        if let src = eventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            eventRunLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }
    private func prepareIMEField() {
        guard let ev = effectView else { return }
        if imeField == nil {
            let tf = NSTextField(frame: NSRect(x: 4, y: 4, width: 1, height: 22))
            tf.isBordered = false
            tf.isBezeled = false
            tf.drawsBackground = false
            tf.font = NSFont.systemFont(ofSize: 13)
            tf.delegate = self
            tf.alphaValue = 0.01
            ev.addSubview(tf)
            imeField = tf
        }
    }
    public func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == imeField {
            inputBuffer = tf.stringValue
            onQueryUpdate?(inputBuffer)
        }
    }
    private static func isIMEActive() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        if let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            let id = unsafeBitCast(idPtr, to: CFString.self) as String
            return id.contains(".inputmethod.")
        }
        return false
    }
    @objc private func appDidResignActive() { hide() }
    public func windowDidResignKey(_ notification: Notification) { hide() }
    public func showToast(_ text: String, duration: TimeInterval = 1.6) {
        toastWindow?.orderOut(nil)
        toastWindow = nil
        let size = NSSize(width: 180, height: 180)
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isOpaque = false
        w.level = .statusBar
        w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        ev.material = .popover
        ev.blendingMode = .withinWindow
        ev.state = .active
        ev.wantsLayer = true
        ev.layer?.cornerRadius = 18
        ev.layer?.masksToBounds = true
        let v = AnyView(
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let hosting = NSHostingView(rootView: v)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        ev.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: ev.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: ev.bottomAnchor)
        ])
        w.contentView = ev
        if let s = activeScreen() ?? NSScreen.main {
            let f = s.visibleFrame
            let x = f.midX - (size.width / 2)
            let y = f.midY - (size.height / 2)
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }
        toastWindow = w
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.toastWindow?.orderOut(nil)
            self.toastWindow = nil
        }
    }
    public func showPreview(_ item: ClipItem) {
        previewService?.show(item)
    }
}
