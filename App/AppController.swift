import SwiftUI
import Combine

final class AppController: ObservableObject {
    let store: IndexStore
    let monitor: ClipboardMonitor
    let paste: PasteService
    let preview: PreviewService
    let hotkeys: HotkeyService
    let panel: PanelWindowController
    @Published var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var filters: SearchFilters = SearchFilters()
    @Published var boards: [Pinboard] = []
    @Published var selectedBoardID: UUID?
    @Published var selectedItemID: UUID?
    @Published var searchPopoverVisible: Bool = false
    @Published var searchBarWidth: CGFloat = 0
    @Published var sidebarWidth: CGFloat = 180
    private let search: SearchService
    private var cancellables: Set<AnyCancellable> = []
    init() {
        store = IndexStore()
        monitor = ClipboardMonitor()
        paste = PasteService()
        hotkeys = HotkeyService()
        preview = PreviewService()
        panel = PanelWindowController()
        search = SearchService(store: store)
        if let bid = Bundle.main.bundleIdentifier { monitor.setIgnoredApps([bid]) }
        monitor.onItemCaptured = { [weak self] item in
            try? self?.store.save(item)
            self?.paste.pushToStack(item)
            self?.refresh()
        }
        hotkeys.onShowPanel = { [weak self] in self?.panel.toggle() }
        hotkeys.onQuickPaste = { [weak self] idx, plain in
            guard let self = self else { return }
            let list = self.search.search(self.query, filters: self.filters, limit: 100)
            if idx-1 < list.count {
                self.monitor.suppressCaptures(for: 1.0)
                self.paste.paste(list[idx-1], plainText: plain)
                self.store.moveToFront(list[idx-1].id)
                self.refresh()
            }
        }
        hotkeys.onStackToggle = { [weak self] in
            guard let self = self else { return }
            self.paste.activateStack(directionAsc: true)
        }
        panel.setRoot(PanelRootView(controller: self))
        panel.onQueryUpdate = { [weak self] q in self?.query = q }
        panel.onSearchOverlayVisibleChanged = { [weak self] in self?.searchPopoverVisible = $0 }
        panel.onShowSearchPopover = { [weak self] _ in
            self?.searchPopoverVisible = true
        }
        panel.onHideSearchPopover = { [weak self] in self?.searchPopoverVisible = false }
        panel.onShown = { [weak self] in self?.selectFirstItemIfNeeded() }
        panel.onArrowLeft = { [weak self] in self?.moveSelectionLeft() }
        panel.onArrowRight = { [weak self] in self?.moveSelectionRight() }
        panel.onArrowUp = { [weak self] in self?.moveSelectionUp() }
        panel.onArrowDown = { [weak self] in self?.moveSelectionDown() }
        panel.onEnter = { [weak self] in self?.confirmSelectionAndPaste() }
        panel.previewService = preview
        panel.onSpace = { [weak self] in
            guard let self = self else { return }
            if let id = self.selectedItemID, let item = self.items.first(where: { $0.id == id }) {
                self.panel.showPreview(item)
            }
        }
        $searchPopoverVisible
            .sink { [weak self] v in self?.panel.setSearchActive(v) }
            .store(in: &cancellables)
        selectedBoardID = store.defaultBoardID

        $query
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }
    
    func start() {
        monitor.start()
        hotkeys.registerShowPanel()
        hotkeys.registerQuickPasteSlots()
        hotkeys.registerStackToggle()
        refresh()
    }
    func refresh() {
        if let bid = selectedBoardID, bid != store.defaultBoardID {
            var r = store.listItems(in: bid)
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if !query.isEmpty {
                let qs = query.lowercased()
                r = r.filter { ($0.text?.lowercased().contains(qs) ?? false) || ($0.metadata["url"]?.lowercased().contains(qs) ?? false) }
            }
            items = Array(r.prefix(200))
        } else {
            items = search.search(query, filters: filters, limit: 200)
        }
        boards = store.listPinboards()
    }
    func pasteItem(_ item: ClipItem, plain: Bool) {
        monitor.suppressCaptures(for: 1.0)
        paste.paste(item, plainText: plain)
        store.moveToFront(item.id)
        refresh()
        panel.hide()
        let msg = plain ? "已复制为纯文本" : "已复制到剪贴板"
        panel.showToast(msg)
    }
    func addToBoard(_ item: ClipItem, _ boardID: UUID) {
        try? store.pin(item.id, to: boardID)
        refresh()
        panel.showToast("已添加到分组")
    }
    func deleteItem(_ item: ClipItem) {
        try? store.delete(item.id)
        if selectedItemID == item.id { selectedItemID = nil }
        refresh()
        panel.showToast("已删除")
    }
    func renameItem(_ item: ClipItem, name: String) {
        var updated = item
        updated.name = name
        try? store.save(updated)
        refresh()
    }
    func selectBoard(_ id: UUID) {
        selectedBoardID = id
        refresh()
    }
    func selectItem(_ item: ClipItem) {
        selectedItemID = item.id
    }
    private func selectFirstItemIfNeeded() {
        if selectedItemID == nil { selectedItemID = items.first?.id }
    }
    private func currentIndex() -> Int? {
        guard let id = selectedItemID, let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return idx
    }
    private func setIndex(_ idx: Int) {
        guard !items.isEmpty else { return }
        let clamped = max(0, min(items.count - 1, idx))
        selectedItemID = items[clamped].id
    }
    private func layoutStyle() -> HistoryLayoutStyle {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        return HistoryLayoutStyle(rawValue: raw) ?? .horizontal
    }
    private func estimatedGridColumns() -> Int {
        let width = panel.contentWidth()
        let divider: CGFloat = 8
        let horizontalPadding: CGFloat = 24
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let contentArea = max(0, width - sidebarWidth - divider)
        let available = max(0, contentArea - horizontalPadding)
        let cols = Int(floor((available + spacing) / (cardWidth + spacing)))
        return max(1, cols)
    }
    private func moveSelectionLeft() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let idx = currentIndex() ?? 0
            setIndex(idx - 1)
        } else {
            let idx = currentIndex() ?? 0
            setIndex(idx - 1)
        }
    }
    private func moveSelectionRight() {
        guard !items.isEmpty else { return }
        let idx = currentIndex() ?? 0
        setIndex(idx + 1)
    }
    private func moveSelectionUp() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            setIndex(idx - cols)
        }
    }
    private func moveSelectionDown() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            setIndex(idx + cols)
        }
    }
    private func confirmSelectionAndPaste() {
        if let id = selectedItemID, let item = items.first(where: { $0.id == id }) {
            pasteItem(item, plain: false)
        } else if let first = items.first {
            pasteItem(first, plain: false)
        }
    }
}
