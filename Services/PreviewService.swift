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
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.isMovableByWindowBackground = true
            w.becomesKeyOnlyIfNeeded = true
            w.minSize = NSSize(width: 360, height: 280)
            let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            ev.material = .popover
            ev.blendingMode = .behindWindow
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
        panel?.makeFirstResponder(nil)
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
    @State private var usePrettyJSON: Bool = false
    @State private var useTimeConversion: Bool = false
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
            if item.type == .text {
                let raw = item.text ?? ""
                HStack(spacing: 8) {
                    if isJSON(raw) {
                        Button(usePrettyJSON ? L("preview.json.unformat") : L("preview.json.format")) { usePrettyJSON.toggle() }
                            .buttonStyle(.bordered)
                            .font(.system(size: 11))
                    }
                    if detectsTime(raw) {
                        Button(useTimeConversion ? L("preview.time.undo") : L("preview.time.convert")) { useTimeConversion.toggle() }
                            .buttonStyle(.bordered)
                            .font(.system(size: 11))
                    }
                }
            }
            content
        }
        .padding(14)
        .background(Color.clear)
        .id(item.id)
        .onAppear { usePrettyJSON = false; useTimeConversion = false }
        .onChange(of: item.id) { _ in usePrettyJSON = false; useTimeConversion = false }
    }
    @ViewBuilder private var content: some View {
        switch item.type {
        case .text:
            let s = computedDisplayText(item.text ?? "")
            if s.count > 50000 {
                if #available(macOS 13.0, *) {
                    TextEditor(text: .constant(s))
                        .font(isProbableCode(s) || isJSON(s) ? .system(size: 13, design: .monospaced) : .system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                } else {
                    TextEditor(text: .constant(s))
                        .font(isProbableCode(s) || isJSON(s) ? .system(size: 13, design: .monospaced) : .system(size: 13))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                }
            } else {
                if isProbableCode(s) || isJSON(s) {
                    ScrollView { Text(s).font(.system(size: 13, design: .monospaced)).textSelection(.enabled) }
                        .id(item.id)
                } else {
                    ScrollView { Text(s).font(.system(size: 13)).textSelection(.enabled) }
                        .id(item.id)
                }
            }
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

    private func isJSON(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        let data = t.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }
    private func prettyJSON(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = t.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return s }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return s }
        return String(data: out, encoding: .utf8) ?? s
    }
    private func detectsTime(_ s: String) -> Bool {
        if s.range(of: "\\b[0-9]{10}\\b", options: .regularExpression) != nil { return true }
        if s.range(of: "\\b[0-9]{13}\\b", options: .regularExpression) != nil { return true }
        if s.range(of: "\\b[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?\\b", options: .regularExpression) != nil { return true }
        return false
    }
    private func convertTimes(_ s: String) -> String {
        var r = s
        let ns = r as NSString
        let patterns = ["\\b[0-9]{13}\\b", "\\b[0-9]{10}\\b", "\\b[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?\\b"]
        for p in patterns {
            let regex = try? NSRegularExpression(pattern: p)
            let matches = regex?.matches(in: r, range: NSRange(location: 0, length: ns.length)) ?? []
            var offset = 0
            for m in matches {
                let range = NSRange(location: m.range.location + offset, length: m.range.length)
                let sub = (r as NSString).substring(with: range)
                let rep = convertOne(sub)
                r = (r as NSString).replacingCharacters(in: range, with: rep)
                offset += (rep.count - sub.count)
            }
        }
        return r
    }
    private func convertOne(_ s: String) -> String {
        if let ms = Int64(s), s.count == 13 {
            let t = Date(timeIntervalSince1970: Double(ms) / 1000.0)
            return formatDate(t)
        }
        if let sec = Int64(s), s.count == 10 {
            let t = Date(timeIntervalSince1970: Double(sec))
            return formatDate(t)
        }
        if let d = parseISODate(s) {
            let ts = Int64(d.timeIntervalSince1970)
            return String(ts)
        }
        return s
    }
    private func parseISODate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: s.replacingOccurrences(of: "T", with: " ")) { return d }
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
    private func formatDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: d)
    }
    private func isProbableCode(_ s: String) -> Bool {
        if isJSON(s) { return true }
        if s.contains("```") { return true }
        let hints = [";", "{", "}", "func ", "class ", "struct ", "import ", "const ", "let ", "var ", "def ", "#include", "<html", "</"]
        for h in hints { if s.contains(h) { return true } }
        return false
    }
    private func computedDisplayText(_ raw: String) -> String {
        var s = raw
        if usePrettyJSON && isJSON(s) { s = prettyJSON(s) }
        if useTimeConversion && detectsTime(s) { s = convertTimes(s) }
        return s
    }
}

private struct LargeTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.usesPredominantAxisScrolling = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.usesFindBar = false
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.layoutManager?.allowsNonContiguousLayout = true
        tv.string = text
        tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height))
        scroll.documentView = tv
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView {
            let w = max(1, scroll.bounds.size.width)
            tv.textContainer?.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
            tv.setFrameSize(NSSize(width: w, height: max(tv.frame.size.height, scroll.bounds.size.height)))
            if tv.string != text { tv.string = text }
        }
    }
}

private struct SyntaxTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.usesPredominantAxisScrolling = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.usesFindBar = false
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.layoutManager?.allowsNonContiguousLayout = true
        tv.string = text
        applyHighlight(to: tv)
        tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height))
        scroll.documentView = tv
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView {
            let w = max(1, scroll.bounds.size.width)
            tv.textContainer?.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
            tv.setFrameSize(NSSize(width: w, height: max(tv.frame.size.height, scroll.bounds.size.height)))
            if tv.string != text { tv.string = text }
            applyHighlight(to: tv)
        }
    }
    private func applyHighlight(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let fullRange = NSRange(location: 0, length: (storage.string as NSString).length)
        let base = [NSAttributedString.Key.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), NSAttributedString.Key.foregroundColor: NSColor.labelColor]
        storage.setAttributes(base, range: fullRange)
        if isJSON(storage.string) {
            highlightJSON(storage: storage)
        } else {
            highlightGeneric(storage: storage)
        }
    }
    private func highlightJSON(storage: NSTextStorage) {
        let s = storage.string as NSString
        let stringColor = NSColor.systemGreen
        let numberColor = NSColor.systemBlue
        let boolColor = NSColor.systemPurple
        let nullColor = NSColor.systemOrange
        let punctColor = NSColor.secondaryLabelColor
        let stringRegex = try? NSRegularExpression(pattern: "\"([^\\\"]|\\.)*\"")
        let numberRegex = try? NSRegularExpression(pattern: "(?<![A-Za-z_])-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
        let boolRegex = try? NSRegularExpression(pattern: "\\b(true|false)\\b")
        let nullRegex = try? NSRegularExpression(pattern: "\\bnull\\b")
        let punctRegex = try? NSRegularExpression(pattern: "[\\{\\}\\[\\]\\:,]")
        storage.beginEditing()
        for (regex, color) in [(stringRegex, stringColor), (numberRegex, numberColor), (boolRegex, boolColor), (nullRegex, nullColor), (punctRegex, punctColor)] {
            let matches = regex?.matches(in: storage.string, range: NSRange(location: 0, length: s.length)) ?? []
            for m in matches { storage.addAttribute(.foregroundColor, value: color, range: m.range) }
        }
        storage.endEditing()
    }
    private func highlightGeneric(storage: NSTextStorage) {
        let s = storage.string as NSString
        let stringColor = NSColor.systemGreen
        let numberColor = NSColor.systemBlue
        let commentColor = NSColor.secondaryLabelColor
        let keywordColor = NSColor.systemPurple
        let stringRegex = try? NSRegularExpression(pattern: "\"([^\\\"]|\\.)*\"|'([^\\']|\\.)*'")
        let numberRegex = try? NSRegularExpression(pattern: "(?<![A-Za-z_])-?[0-9]+(\\.[0-9]+)?")
        let lineCommentRegex = try? NSRegularExpression(pattern: "//.*|#.*")
        let blockCommentRegex = try? NSRegularExpression(pattern: "/\\*([\\s\\S]*?)\\*/", options: [.dotMatchesLineSeparators])
        let keywords = ["func","class","struct","enum","protocol","import","let","var","return","if","else","for","while","switch","case","break","continue","try","catch","throw","defer","const","async","await","def","from","as","in","not","and","or"]
        let keywordRegex = try? NSRegularExpression(pattern: "\\b(" + keywords.joined(separator: "|") + ")\\b")
        storage.beginEditing()
        for (regex, color) in [(stringRegex, stringColor), (numberRegex, numberColor), (lineCommentRegex, commentColor)] {
            let matches = regex?.matches(in: storage.string, range: NSRange(location: 0, length: s.length)) ?? []
            for m in matches { storage.addAttribute(.foregroundColor, value: color, range: m.range) }
        }
        if let regex = blockCommentRegex {
            let matches = regex.matches(in: storage.string, range: NSRange(location: 0, length: s.length))
            for m in matches { storage.addAttribute(.foregroundColor, value: commentColor, range: m.range) }
        }
        if let regex = keywordRegex {
            let matches = regex.matches(in: storage.string, range: NSRange(location: 0, length: s.length))
            for m in matches { storage.addAttribute(.foregroundColor, value: keywordColor, range: m.range) }
        }
        storage.endEditing()
    }
    private func isJSON(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        let data = t.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }
}
