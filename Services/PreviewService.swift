import Foundation
import AppKit
import SwiftUI

public final class PreviewService: NSObject {
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var effectView: NSVisualEffectView?
    public func show(_ item: ClipItem) {
        let size = NSSize(width: 560, height: 440)
        if panel == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.titled, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.isOpaque = false
            w.level = .statusBar
            w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isFloatingPanel = true
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.becomesKeyOnlyIfNeeded = true
            w.minSize = NSSize(width: 360, height: 280)
            let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            ev.material = .popover
            ev.blendingMode = .withinWindow
            ev.state = .active
            ev.wantsLayer = true
            ev.layer?.cornerRadius = 16
            ev.layer?.masksToBounds = true
            let v = AnyView(PreviewContentView(item: item))
            let h = NSHostingView(rootView: v)
            h.translatesAutoresizingMaskIntoConstraints = false
            ev.addSubview(h)
            NSLayoutConstraint.activate([
                h.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
                h.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
                h.topAnchor.constraint(equalTo: ev.topAnchor),
                h.bottomAnchor.constraint(equalTo: ev.bottomAnchor)
            ])
            w.contentView = ev
            panel = w
            hosting = h
            effectView = ev
        } else {
            hosting?.rootView = AnyView(PreviewContentView(item: item))
        }
        guard let w = panel else { return }
        if let s = activeScreen() ?? NSScreen.main {
            let f = s.visibleFrame
            let x = f.midX - (size.width / 2)
            let y = f.midY - (size.height / 2)
            let finalFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
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
        } else {
            w.orderFrontRegardless()
        }
    }
    public func isVisible() -> Bool { panel?.isVisible == true }
    public func close() {
        guard let w = panel else { return }
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
    }
    public func windowFrame() -> NSRect? { panel?.frame }
    private func activeScreen() -> NSScreen? {
        let p = NSEvent.mouseLocation
        for s in NSScreen.screens { if s.frame.contains(p) { return s } }
        return nil
    }
}

private struct PreviewContentView: View {
    let item: ClipItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(RelativeDateTimeFormatter().localizedString(for: item.copiedAt, relativeTo: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .background(Color.clear)
    }
    @ViewBuilder private var content: some View {
        switch item.type {
        case .text:
            ScrollView { Text(item.text ?? "") .font(.system(size: 13)) .textSelection(.enabled) }
        case .link:
            let s = item.metadata["url"] ?? item.text ?? ""
            if let u = URL(string: s) { Link(destination: u) { Text(u.absoluteString).font(.system(size: 13)) } }
            else { Text(s).font(.system(size: 13)) }
        case .image:
            if let u = item.contentRef, let img = NSImage(contentsOf: u) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)); Image(systemName: "photo").font(.system(size: 36)).foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .file:
            let u = item.contentRef
            let icon: NSImage? = { if let p = u?.path { return NSWorkspace.shared.icon(forFile: p) } else { return nil } }()
            VStack(spacing: 12) {
                if let i = icon { Image(nsImage: i).resizable().aspectRatio(contentMode: .fit).frame(width: 96, height: 96) }
                Text(item.text ?? u?.lastPathComponent ?? "") .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .color:
            let hex = item.metadata["colorHex"] ?? ""
            let c = colorFromString(hex)
            RoundedRectangle(cornerRadius: 12).fill(c).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func colorFromString(_ s: String) -> Color {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return .accentColor }
        let hex = v.hasPrefix("#") ? String(v.dropFirst()) : v
        if hex.count == 6, let iv = Int(hex, radix: 16) {
            let r = Double((iv >> 16) & 0xFF) / 255.0
            let g = Double((iv >> 8) & 0xFF) / 255.0
            let b = Double(iv & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        switch v { case "red": return .red; case "orange": return .orange; case "yellow": return .yellow; case "green": return .green; case "blue": return .blue; case "indigo": return .indigo; case "purple": return .purple; case "pink": return .pink; default: return .accentColor }
    }
}
