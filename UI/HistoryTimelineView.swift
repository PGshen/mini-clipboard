import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage
import Combine

// 历史时间轴视图：横向滚动展示剪贴条目的卡片列表
public struct HistoryTimelineView: View {
    public let items: [ClipItem]
    public let boards: [Pinboard]
    public let defaultBoardID: UUID
    public let currentBoardID: UUID?
    public let onPaste: (ClipItem, Bool) -> Void
    public let onAddToBoard: (ClipItem, UUID) -> Void
    public let onDelete: (ClipItem) -> Void
    public let selectedItemID: UUID?
    public let onSelect: (ClipItem) -> Void
    public let onRename: (ClipItem, String) -> Void
    @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
    public init(items: [ClipItem], boards: [Pinboard], defaultBoardID: UUID, currentBoardID: UUID?, onPaste: @escaping (ClipItem, Bool) -> Void, onAddToBoard: @escaping (ClipItem, UUID) -> Void, onDelete: @escaping (ClipItem) -> Void, selectedItemID: UUID?, onSelect: @escaping (ClipItem) -> Void, onRename: @escaping (ClipItem, String) -> Void) {
        self.items = items
        self.boards = boards
        self.defaultBoardID = defaultBoardID
        self.currentBoardID = currentBoardID
        self.onPaste = onPaste
        self.onAddToBoard = onAddToBoard
        self.onDelete = onDelete
        self.selectedItemID = selectedItemID
        self.onSelect = onSelect
        self.onRename = onRename
    }
    @State private var displayedCount: Int = 60
    private var displayedItems: [ClipItem] { Array(items.prefix(displayedCount)) }
    public var body: some View {
        Group {
            if layoutStyle == .horizontal {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(displayedItems) { item in
                            ItemCardView(item: item, boards: boards, defaultBoardID: defaultBoardID, currentBoardID: currentBoardID, onPaste: onPaste, onAddToBoard: onAddToBoard, onDelete: onDelete, selected: (selectedItemID == item.id), onSelect: onSelect, onRename: onRename, cardWidth: gridCardWidth)
                                .equatable()
                        }
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 1, height: 1)
                            .onAppear { if displayedCount < items.count { displayedCount = min(items.count, displayedCount + 60) } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .onChange(of: items.count) { c in displayedCount = min(c, 60) }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                        ForEach(displayedItems) { item in
                            ItemCardView(item: item, boards: boards, defaultBoardID: defaultBoardID, currentBoardID: currentBoardID, onPaste: onPaste, onAddToBoard: onAddToBoard, onDelete: onDelete, selected: (selectedItemID == item.id), onSelect: onSelect, onRename: onRename, cardWidth: gridCardWidth)
                                .equatable()
                        }
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 1)
                            .onAppear { if displayedCount < items.count { displayedCount = min(items.count, displayedCount + 60) } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .onChange(of: items.count) { c in displayedCount = min(c, 60) }
            }
        }
    }
    private func title(for item: ClipItem) -> String { item.text ?? item.contentRef?.lastPathComponent ?? "Item" }
    private var layoutStyle: HistoryLayoutStyle { HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal }
    private var gridCardWidth: CGFloat { 240 }
    private var gridColumns: [GridItem] { [GridItem(.adaptive(minimum: gridCardWidth, maximum: gridCardWidth), spacing: 12)] }
}

private struct ItemCardView: View, Equatable {
    let item: ClipItem
    let boards: [Pinboard]
    let defaultBoardID: UUID
    let currentBoardID: UUID?
    let onPaste: (ClipItem, Bool) -> Void
    let onAddToBoard: (ClipItem, UUID) -> Void
    let onDelete: (ClipItem) -> Void
    let selected: Bool
    let onSelect: (ClipItem) -> Void
    let onRename: (ClipItem, String) -> Void
    var cardWidth: CGFloat = 240
    @State private var hovering = false
    @State private var showNamePopover = false
    @State private var nameInput: String = ""
    @FocusState private var nameFocused: Bool
    @State private var hoverPaste = false
    @State private var hoverPlain = false
    @State private var hoverDelete = false
    @State private var hoverMenu = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(headerGradient)
                    HStack {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        nameInput = item.name
                        showNamePopover = true
                        DispatchQueue.main.async { nameFocused = true }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(height: 36)
                .popover(isPresented: $showNamePopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L("timeline.rename.namePlaceholder"), text: $nameInput)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .onSubmit {
                                let n = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !n.isEmpty { onRename(item, n) }
                                showNamePopover = false
                            }
                        HStack {
                            Spacer()
                            Button(L("timeline.rename.save")) {
                                let n = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !n.isEmpty { onRename(item, n) }
                                showNamePopover = false
                            }
                            Button(L("timeline.rename.cancel")) { showNamePopover = false }
                        }
                    }
                    .padding(12)
                    .frame(width: 260)
                }
                VStack(alignment: .leading, spacing: 8) {
                    contentPreview
                    Spacer()
                    HStack {
                        Text("\(characterCount) " + L("timeline.count.chars"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(relativeTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                
                if isSelected {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 14) {
                            Button { onPaste(item, false) } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)
                                    .scaleEffect(hoverPaste ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: hoverPaste)
                            }
                            .buttonStyle(.borderless)
                            .onHover { h in
                                hoverPaste = h
                                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            }
                            .help(L("timeline.help.copy"))

                            Button { onPaste(item, true) } label: {
                                Image(systemName: "textformat")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.teal)
                                    .scaleEffect(hoverPlain ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: hoverPlain)
                            }
                            .buttonStyle(.borderless)
                            .onHover { h in
                                hoverPlain = h
                                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            }
                            .help(L("timeline.help.pastePlain"))

                            Button { onDelete(item) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.red)
                                    .scaleEffect(hoverDelete ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: hoverDelete)
                            }
                            .buttonStyle(.borderless)
                            .onHover { h in
                                hoverDelete = h
                                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            }
                            .help(L("timeline.help.delete"))

                            Menu {
                                ForEach(boards.filter { $0.id != defaultBoardID }) { b in
                                    Button(action: { onAddToBoard(item, b.id) }) {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(boardColor(b))
                                                .frame(width: 8, height: 8)
                                            Text(b.name)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(.indigo)
                                    .imageScale(.medium)
                                    .scaleEffect(hoverMenu ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: hoverMenu)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .onHover { h in
                                hoverMenu = h
                                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            }
                            .help(L("timeline.help.addToBoard"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
            .frame(width: cardWidth, height: 220)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .fill(cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .overlay(alignment: .topTrailing) {
                if let img = appIcon {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .padding(6)
                }
            }
            .shadow(color: isSelected ? headerPalette.main.opacity(0.4) : AppTheme.shadowColor, radius: isSelected ? 8 : AppTheme.shadowRadius, x: 0, y: isSelected ? 0 : AppTheme.shadowY)
            // .shadow(color: shadowColor, radius: hovering ? 8 : 4, x: 0, y: hovering ? 6 : 3)
            // .scaleEffect(hovering ? 1.03 : 1.0)
            // .onHover { hovering = $0 }
            // .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hovering)
            .animation(.spring(dampingFraction: 0.85), value: isSelected)
            .highPriorityGesture(TapGesture(count: 2).onEnded { onPaste(item, false) })
            .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect(item) })
        }
    }
    private func loadPlainString(_ url: URL) -> String? {
        if let d = try? Data(contentsOf: url), let s = String(data: d, encoding: .utf8) { return s }
        return try? String(contentsOf: url)
    }
    @ViewBuilder private var contentPreview: some View {
        switch item.type {
        case .image:
            if let u = item.contentRef {
                let h = CGFloat(isSelected ? 86 : 120)
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Text(mainTitle)
                            .font(.system(size: 13))
                            .lineLimit(10)
                    @unknown default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                    }
                }
            } else {
                Text(mainTitle)
                    .font(.system(size: 13))
                    .lineLimit(10)
            }
        case .link:
            if let u = item.contentRef ?? (item.metadata["url"].flatMap { URL(string: $0) }) {
                Link(destination: u) {
                    Text(u.absoluteString)
                        .font(.system(size: 13))
                        .lineLimit(10)
                }
            } else {
                Text(mainTitle)
                    .font(.system(size: 13))
                    .lineLimit(10)
            }
        case .color:
            let h = CGFloat(isSelected ? 86 : 120)
            let hex = item.metadata["colorHex"]
            let c: Color = {
                if let s = hex, !s.isEmpty { return colorFromString(s) }
                return headerColor
            }()
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(c)
                if let s = hex, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(textColorForHex(s))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        case .text:
            let h = CGFloat(isSelected ? 86 : 120)
            let previewPlain = (item.text ?? mainTitle)
            let base: String = {
                if let t = item.text, !t.isEmpty { return t }
                if let u = item.contentRef {
                    if let a = loadAttributedString(u) { return a.string }
                    if let s = loadPlainString(u) { return s }
                }
                return previewPlain
            }()
            if let u = asURL(base) {
                Link(destination: u) {
                    Text(u.absoluteString)
                        .font(.system(size: 13))
                        .lineLimit(10)
                }
            } else {
                let truncated = truncatedPreview(base)
                Text(truncated)
                    .font(.system(size: 13))
                    .lineLimit(10)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: h, alignment: .topLeading)
            }
        case .file:
            let h = CGFloat(isSelected ? 86 : 120)
            let ext = item.contentRef?.pathExtension.uppercased() ?? ""
            let iconSize = CGFloat(isSelected ? 36 : 44)
            if let u = item.contentRef {
                let isImage: Bool = {
                    let extLower = u.pathExtension.lowercased()
                    if !extLower.isEmpty, let t = UTType(filenameExtension: extLower) { return t.conforms(to: .image) }
                    return false
                }()
                if isImage {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(maxWidth: .infinity)
                                .frame(height: h)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: h)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                                VStack(alignment: .center, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Group {
                                            if let img = fileIcon(for: u) {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                            } else {
                                                Image(systemName: "doc")
                                                    .font(.system(size: 28, weight: .semibold))
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .frame(width: iconSize, height: iconSize)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        if !ext.isEmpty {
                                            Text(ext)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    if !(item.text ?? item.contentRef?.lastPathComponent ?? "").isEmpty {
                                        Text(item.text ?? item.contentRef?.lastPathComponent ?? "")
                                            .font(.system(size: 13))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(maxWidth: .infinity)
                                .frame(height: h)
                        }
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                        VStack(alignment: .center, spacing: 4) {
                            HStack(spacing: 8) {
                                Group {
                                    if let img = fileIcon(for: u) {
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "doc")
                                            .font(.system(size: 28, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                                .frame(width: iconSize, height: iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                if !ext.isEmpty {
                                    Text(ext)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            if !(item.text ?? item.contentRef?.lastPathComponent ?? "").isEmpty {
                                Text(item.text ?? item.contentRef?.lastPathComponent ?? "")
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                    VStack(alignment: .center, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: iconSize, height: iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            if !ext.isEmpty {
                                Text(ext)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        if !(item.text ?? item.contentRef?.lastPathComponent ?? "").isEmpty {
                            Text(item.text ?? item.contentRef?.lastPathComponent ?? "")
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
    private var textLineHeight: CGFloat {
        let f = NSFont.systemFont(ofSize: 14)
        return f.ascender - f.descender + f.leading
    }
    private func truncatedPreview(_ s: String) -> String {
        let maxChars = 1200
        let normalized = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLines = lines.prefix(10)
        var joined = firstLines.joined(separator: "\n")
        if joined.count > maxChars { joined = String(joined.prefix(maxChars)) }
        return String(joined)
    }
    private func asURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let u = URL(string: t), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme) { return u }
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(t.startIndex..<t.endIndex, in: t)
            if let m = det.firstMatch(in: t, options: [], range: range) {
                if m.range.location == 0 && m.range.length >= range.length - 1 { return m.url }
            }
        }
        return nil
    }
    private var mainTitle: String { item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.text! : (item.contentRef?.lastPathComponent ?? "Item") }
    private var typeIcon: String {
        switch item.type {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }
    private var themePalette: AppTheme.Palette {
        if let bid = bundleID { return AppTheme.palette(for: bid) }
        return AppTheme.purple
    }
    private var headerPalette: AppTheme.Palette {
        if let bc = boardHeaderColor { return AppTheme.closestPalette(for: bc) }
        return themePalette
    }
    private var cardBackground: Color { AppTheme.cardBackground }
    private var borderColor: Color { isSelected ? headerPalette.main : Color.clear }
    private var borderWidth: CGFloat { isSelected ? 2 : 0 }
    private var shadowColor: Color { AppTheme.shadowColor }
    private var isSelected: Bool { selected }
    static func == (lhs: ItemCardView, rhs: ItemCardView) -> Bool {
        lhs.item == rhs.item && lhs.selected == rhs.selected && lhs.cardWidth == rhs.cardWidth
    }
    private var gradientColors: [Color] {
        // Use theme gradient colors but maybe varied slightly or just consistent
        return [AppTheme.mainPurple, AppTheme.palePinkPurple]
    }
    private static var avgColorCache: [String: NSColor] = [:]
    private var headerColor: Color {
        if let c = boardHeaderColor { return c }
        return AppTheme.mainPurple
    }
    private var headerGradient: LinearGradient {
        let p = headerPalette
        return LinearGradient(colors: [p.main, p.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var boardHeaderColor: Color? {
        guard let id = currentBoardID, id != defaultBoardID else { return nil }
        if let b = boards.first(where: { $0.id == id }) { return boardColor(b) }
        return nil
    }
    private var relativeTime: String {
        let f = RelativeDateTimeFormatter()
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
        let code = (lang == "en") ? "en" : "zh_CN"
        f.locale = Locale(identifier: code)
        f.unitsStyle = .full
        return f.localizedString(for: item.copiedAt, relativeTo: Date())
    }
    private var characterCount: Int { (item.text ?? mainTitle).count }
    private var bundleID: String? { item.metadata["bundleID"] ?? NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == item.sourceApp })?.bundleIdentifier }
    private static var iconCache: [String: NSImage] = [:]
    private static var fileIconCache: [String: NSImage] = [:]
    private var appIcon: NSImage? {
        guard let bid = bundleID else { return nil }
        if let cached = ItemCardView.iconCache[bid] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        ItemCardView.iconCache[bid] = icon
        return icon
    }
    private func fileIcon(for url: URL) -> NSImage? {
        let key = url.isFileURL ? url.path : url.absoluteString
        if let cached = ItemCardView.fileIconCache[key] { return cached }
        var icon: NSImage?
        if url.isFileURL {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        if icon == nil {
            let ext = url.pathExtension
            if !ext.isEmpty, let t = UTType(filenameExtension: ext.lowercased()) {
                icon = NSWorkspace.shared.icon(for: t)
            }
        }
        if let i = icon { ItemCardView.fileIconCache[key] = i }
        return icon
    }
    private func averageColorCached(for image: NSImage, key: String?) -> NSColor? {
        if let k = key, let cached = ItemCardView.avgColorCache[k] { return cached }
        let c = averageColor(image)
        if let k = key, let c { ItemCardView.avgColorCache[k] = c }
        return c
    }

    private func boardColor(_ b: Pinboard) -> Color {
        guard let s = b.color?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return .accentColor }
        switch s {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        default:
            let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
            if hex.count == 6, let v = Int(hex, radix: 16) {
                let r = Double((v >> 16) & 0xFF) / 255.0
                let g = Double((v >> 8) & 0xFF) / 255.0
                let b = Double(v & 0xFF) / 255.0
                return Color(red: r, green: g, blue: b)
            }
            return .accentColor
        }
    }
    private func averageColor(_ nsImage: NSImage) -> NSColor? {
        guard let tiff = nsImage.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return nil }
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height), forKey: kCIInputExtentKey)
        guard let output = filter?.value(forKey: kCIOutputImageKey) as? CIImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: nil)
        ctx.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return NSColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: CGFloat(bitmap[3]) / 255.0)
    }
    private func colorFromString(_ s: String) -> Color {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return .accentColor }
        switch v {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        default:
            let hex = v.hasPrefix("#") ? String(v.dropFirst()) : v
            if hex.count == 6, let iv = Int(hex, radix: 16) {
                let r = Double((iv >> 16) & 0xFF) / 255.0
                let g = Double((iv >> 8) & 0xFF) / 255.0
                let b = Double(iv & 0xFF) / 255.0
                return Color(red: r, green: g, blue: b)
            }
            return .accentColor
        }
    }
    private func textColorForHex(_ s: String) -> Color {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = v.hasPrefix("#") ? String(v.dropFirst()) : v
        if hex.count == 6, let iv = Int(hex, radix: 16) {
            let r = Double((iv >> 16) & 0xFF)
            let g = Double((iv >> 8) & 0xFF)
            let b = Double(iv & 0xFF)
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            return luma > 186 ? .black : .white
        }
        return .primary
    }
    private func loadAttributedString(_ url: URL) -> NSAttributedString? {
        if let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return a }
        if let d = try? Data(contentsOf: url), let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) { return a }
        if let d = try? Data(contentsOf: url), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a }
        return nil
    }
}
