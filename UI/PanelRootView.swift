import SwiftUI
import AppKit

struct PanelRootView: View {
    @ObservedObject var controller: AppController
    @State private var showSearchPopover: Bool = false
    @FocusState private var searchPopoverFocused: Bool
    @State private var tab: Int = 0
    @State private var sidebarWidth: CGFloat = 180
    @State private var dragStartWidth: CGFloat = 180
    @State private var isDragging: Bool = false
    @State private var showNewBoardPopover: Bool = false
    @State private var newBoardName: String = ""
    @State private var editingBoard: Pinboard?
    @State private var showRenamePopover: Bool = false
    @State private var showColorPopover: Bool = false
    @State private var renameInput: String = ""
    @State private var colorInput: String = ""
    @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    if !controller.query.isEmpty {
                        Button(action: { controller.query = ""; controller.refresh() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    Button(action: { showNewBoardPopover = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showNewBoardPopover) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("panel.newBoard.title")).font(.system(size: 13, weight: .medium))
                            TextField(L("panel.name.placeholder"), text: $newBoardName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let presetColors = ["red","orange","yellow","green","blue","indigo","purple","pink"]
                                    let randomColor = presetColors.randomElement()
                                    _ = controller.store.createPinboard(name: name.isEmpty ? L("panel.newBoard.title") : name, color: randomColor)
                                    controller.refresh()
                                    showNewBoardPopover = false
                                    newBoardName = ""
                                }
                            HStack {
                                Spacer()
                                Button(L("panel.cancel")) { showNewBoardPopover = false; newBoardName = "" }
                                Button(L("panel.add")) {
                                    let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let presetColors = ["red","orange","yellow","green","blue","indigo","purple","pink"]
                                    let randomColor = presetColors.randomElement()
                                    _ = controller.store.createPinboard(name: name.isEmpty ? L("panel.newBoard.title") : name, color: randomColor)
                                    controller.refresh()
                                    showNewBoardPopover = false
                                    newBoardName = ""
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding(12)
                        .frame(width: 220)
                    }
                    Button(action: {
                        layoutStyleRaw = ((HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal) == .horizontal ? HistoryLayoutStyle.grid.rawValue : HistoryLayoutStyle.horizontal.rawValue)
                    }) {
                        Image(systemName: ((HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal) == .horizontal) ? "square.grid.2x2" : "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    Spacer(minLength: 6)
                    Button(action: { controller.searchPopoverVisible = true }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $controller.searchPopoverVisible, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                        HStack(spacing: 8) {
                            // Image(systemName: "magnifyingglass")
                            TextField(L("panel.search.placeholder"), text: $controller.query)
                                .textFieldStyle(.plain)
                                .focused($searchPopoverFocused)
                                .onSubmit { }
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .frame(width: 115)
                        .background(Color.clear)
                        .onAppear { searchPopoverFocused = true }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                controller.searchBarWidth = geo.size.width
                                reportSearchFrame(geo)
                            }
                            .onChange(of: geo.size.width) { w in
                                controller.searchBarWidth = w
                                reportSearchFrame(geo)
                            }
                    }
                )
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.boards) { b in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(boardColor(b))
                                    .frame(width: 10, height: 10)
                                Text(boardDisplayName(b))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle((controller.selectedBoardID == b.id) ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Group {
                                    if controller.selectedBoardID == b.id {
                                        AppTheme.highlightGradient
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .contextMenu {
                                if b.id == controller.store.defaultBoardID {
                                    Text(L("panel.defaultBoard.uneditable"))
                                } else {
                                    Button(L("panel.editName")) {
                                        editingBoard = b
                                        renameInput = b.name
                                        showRenamePopover = true
                                    }
                                    Button(L("panel.changeColor")) {
                                        editingBoard = b
                                        colorInput = b.color ?? ""
                                        showColorPopover = true
                                    }
                                    Divider()
                                    Button(L("panel.deleteBoard")) {
                                        try? controller.store.deletePinboard(b.id)
                                        controller.refresh()
                                    }
                                }
                            }
                            .onTapGesture { controller.selectBoard(b.id) }
                            .popover(isPresented: Binding(get: { showRenamePopover && editingBoard?.id == b.id }, set: { v in showRenamePopover = v })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("panel.rename.title")).font(.system(size: 13, weight: .medium))
                                    TextField(L("panel.name.placeholder"), text: $renameInput)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit {
                                            let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let id = editingBoard?.id { controller.store.updatePinboardName(id, name: name.isEmpty ? L("panel.rename.untitled") : name) }
                                            controller.refresh()
                                            showRenamePopover = false
                                        }
                                    HStack {
                                        Spacer()
                                        Button(L("panel.cancel")) { showRenamePopover = false }
                                        Button(L("timeline.rename.save")) {
                                            let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let id = editingBoard?.id { controller.store.updatePinboardName(id, name: name.isEmpty ? L("panel.rename.untitled") : name) }
                                            controller.refresh()
                                            showRenamePopover = false
                                        }.keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding(12)
                                .frame(width: 220)
                            }
                            .popover(isPresented: Binding(get: { showColorPopover && editingBoard?.id == b.id }, set: { v in showColorPopover = v })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("panel.boardColor.title")).font(.system(size: 13, weight: .medium))
                                    HStack(spacing: 8) {
                                        ForEach(["red","orange","yellow","green","blue","indigo","purple","pink"], id: \.self) { c in
                                            Circle()
                                                .fill(boardColor(Pinboard(name: "", color: c)))
                                                .frame(width: 16, height: 16)
                                                .onTapGesture {
                                                    if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: c) }
                                                    controller.refresh()
                                                    showColorPopover = false
                                                }
                                        }
                                        Button(L("panel.clear")) {
                                            if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: nil) }
                                            controller.refresh()
                                            showColorPopover = false
                                        }
                                    }
                                    TextField(L("panel.color.hexPlaceholder"), text: $colorInput)
                                        .textFieldStyle(.roundedBorder)
                                    HStack {
                                        Spacer()
                                        Button(L("panel.cancel")) { showColorPopover = false }
                                        Button(L("timeline.rename.save")) {
                                            var s = colorInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if s.isEmpty { s = "" }
                                            if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: s.isEmpty ? nil : s) }
                                            controller.refresh()
                                            showColorPopover = false
                                        }.keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding(12)
                                .frame(width: 260)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .frame(width: sidebarWidth)
            .background(AppTheme.sidebarBackground)
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
                .frame(width: 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if !isDragging {
                        if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging { isDragging = true; dragStartWidth = sidebarWidth }
                            let minW: CGFloat = 180
                            let maxW: CGFloat = 480
                            let newW = dragStartWidth + value.translation.width
                            sidebarWidth = max(minW, min(maxW, newW))
                        }
                        .onEnded { _ in
                            isDragging = false
                            NSCursor.arrow.set()
                        }
                )
                VStack(spacing: 0) {
                    HistoryTimelineView(items: controller.items, boards: controller.boards, defaultBoardID: controller.store.defaultBoardID, currentBoardID: controller.selectedBoardID, onPaste: { item, plain in controller.pasteItem(item, plain: plain) }, onAddToBoard: { item, bid in controller.addToBoard(item, bid) }, onDelete: { item in controller.deleteItem(item) }, selectedItemID: controller.selectedItemID, onSelect: { item in controller.selectItem(item) }, onRename: { item, name in controller.renameItem(item, name: name) }, scrollOnSelection: controller.selectionByKeyboard)
                        .animation(.easeInOut(duration: 0.35), value: controller.items)
                        .animation(.easeInOut(duration: 0.35), value: layoutStyleRaw)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.panelBackground)
            }
        }
        .background(AppTheme.panelBackground)
        .onAppear { controller.sidebarWidth = sidebarWidth }
        .onChange(of: sidebarWidth) { w in controller.sidebarWidth = w }
        .onChange(of: layoutStyleRaw) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .frame(minWidth: 880, minHeight: 290)
    }
    private func boardDisplayName(_ b: Pinboard) -> String {
        if b.id == controller.store.defaultBoardID && b.name == "剪贴板" { return L("boards.default.displayName") }
        return b.name
    }
    private func reportSearchFrame(_ geo: GeometryProxy) {
        if let win = NSApp.keyWindow ?? NSApp.windows.first {
            let local = geo.frame(in: .global)
            let nsRect = NSRect(x: local.origin.x, y: local.origin.y, width: local.size.width, height: local.size.height)
            let screenRect = win.convertToScreen(nsRect)
            controller.panel.updateSearchOverlayRect(screenRect)
        }
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
}
// 搜索弹窗视图已移除，统一由顶部按钮弹出

