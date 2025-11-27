import Foundation

// 本地索引存储：维护剪贴历史、看板与关联关系，提供查询与置顶能力
public final class IndexStore: IndexStoreProtocol {
    private var items: [ClipItem] = []
    private var pinboards: [Pinboard] = []
    private var boardItems: [UUID: Set<UUID>] = [:]
    private let queue = DispatchQueue(label: "store.queue", qos: .userInitiated)
    public private(set) var defaultBoardID: UUID
    private let indexURL: URL
    private let contentDir: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let settingsStore = SettingsStore()
    private struct Snapshot: Codable {
        var items: [ClipItem]
        var pinboards: [Pinboard]
        var boardItems: [UUID: [UUID]]
    }
    public init() {
        let appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MiniClipboard")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.contentDir = appDir.appendingPathComponent("Store")
        try? FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        self.indexURL = appDir.appendingPathComponent("index.json")
        self.pinboards = []
        self.defaultBoardID = UUID()
        loadSnapshot()
        let s = settingsStore.load()
        queue.sync {
            cleanupExpiredItems(days: s.historyRetentionDays)
            cleanupExceededItems(limit: s.historyMaxItems)
        }
    }
    public func save(_ item: ClipItem) throws {
        queue.sync {
            let persisted = ensurePermanentContent(item)
            items.removeAll { isDuplicate($0, persisted) }
            if let i = items.firstIndex(where: { $0.id == persisted.id }) { items[i] = persisted } else { items.insert(persisted, at: 0) }
            persist()
            let s = settingsStore.load()
            cleanupExpiredItems(days: s.historyRetentionDays)
            cleanupExceededItems(limit: s.historyMaxItems)
        }
    }
    public func delete(_ id: UUID) throws {
        queue.sync {
            items.removeAll { $0.id == id }
            for (bid, set) in boardItems { var s = set; s.remove(id); boardItems[bid] = s }
            persist()
        }
    }
    public func item(_ id: UUID) -> ClipItem? {
        queue.sync { items.first { $0.id == id } }
    }
    public func query(_ filters: SearchFilters, query: String?, limit: Int, offset: Int) -> [ClipItem] {
        queue.sync {
            var r = items
            // 类型过滤
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            // 来源应用过滤
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if let q = query, !q.isEmpty {
                let qs = q.lowercased()
                r = r.filter { itemMatches($0, qs: qs) }
            }
            let s = offset
            let e = min(r.count, s + max(0, limit))
            if s >= e { return [] }
            return Array(r[s..<e])
        }
    }
    private func itemMatches(_ item: ClipItem, qs: String) -> Bool {
        if matches(hay: item.text?.lowercased(), needle: qs) { return true }
        if matches(hay: item.metadata["url"]?.lowercased(), needle: qs) { return true }
        if item.type == .text, let u = item.contentRef, let s = try? String(contentsOf: u) {
            if matches(hay: s.lowercased(), needle: qs) { return true }
        }
        return false
    }

    private func matches(hay: String?, needle: String) -> Bool {
        guard let h = hay, !h.isEmpty else { return false }
        if needle.count < 3 {
            let seps = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            let tokens = h.components(separatedBy: seps).filter { !$0.isEmpty }
            for t in tokens { if t == needle || t.hasPrefix(needle) { return true } }
            return false
        }
        return h.contains(needle)
    }
    public func pin(_ id: UUID, to boardID: UUID) throws {
        queue.sync {
            var set = boardItems[boardID] ?? []
            set.insert(id)
            boardItems[boardID] = set
            persist()
        }
    }
    public func unpin(_ id: UUID, from boardID: UUID) throws {
        queue.sync {
            var set = boardItems[boardID] ?? []
            set.remove(id)
            boardItems[boardID] = set
            persist()
        }
    }
    public func createPinboard(name: String, color: String?) -> UUID {
        let b = Pinboard(name: name, color: color, order: pinboards.count)
        pinboards.append(b)
        persist()
        return b.id
    }
    public func updatePinboardName(_ id: UUID, name: String) {
        guard id != defaultBoardID else { return }
        queue.sync {
            if let i = pinboards.firstIndex(where: { $0.id == id }) {
                pinboards[i].name = name
                persist()
            }
        }
    }
    public func updatePinboardColor(_ id: UUID, color: String?) {
        guard id != defaultBoardID else { return }
        queue.sync {
            if let i = pinboards.firstIndex(where: { $0.id == id }) {
                pinboards[i].color = color
                persist()
            }
        }
    }
    public func deletePinboard(_ id: UUID) throws {
        guard id != defaultBoardID else { return }
        pinboards.removeAll { $0.id == id }
        boardItems[id] = nil
        persist()
    }
    public func listPinboards() -> [Pinboard] { pinboards.sorted { $0.order < $1.order } }
    public func listItems(in boardID: UUID) -> [ClipItem] {
        if boardID == defaultBoardID { return items }
        let ids = boardItems[boardID] ?? []
        return items.filter { ids.contains($0.id) }
    }
    public func moveToFront(_ id: UUID) {
        queue.sync {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                let i = items.remove(at: idx)
                items.insert(i, at: 0)
                persist()
            }
        }
    }
    private func isDuplicate(_ a: ClipItem, _ b: ClipItem) -> Bool {
        if a.type != b.type { return false }
        switch a.type {
        case .text:
            let ta = (a.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tb = (b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !ta.isEmpty && ta == tb
        case .link:
            let ua = a.metadata["url"] ?? a.contentRef?.absoluteString ?? (a.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ub = b.metadata["url"] ?? b.contentRef?.absoluteString ?? (b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !ua.isEmpty && ua == ub
        case .file, .image:
            let pa = a.contentRef?.absoluteString ?? ""
            let pb = b.contentRef?.absoluteString ?? ""
            return !pa.isEmpty && pa == pb
        case .color:
            return false
        }
    }

    private func loadSnapshot() {
        if let d = try? Data(contentsOf: indexURL), let snap = try? decoder.decode(Snapshot.self, from: d) {
            self.items = snap.items
            self.pinboards = snap.pinboards
            var m: [UUID: Set<UUID>] = [:]
            for (k, v) in snap.boardItems { m[k] = Set(v) }
            self.boardItems = m
            if let def = pinboards.first(where: { $0.name == "剪贴板" }) {
                self.defaultBoardID = def.id
            } else {
                let def = Pinboard(name: "剪贴板", color: nil, order: 0)
                self.defaultBoardID = def.id
                pinboards.insert(def, at: 0)
                persist()
            }
        } else {
            self.items = []
            let def = Pinboard(name: "剪贴板", color: nil, order: 0)
            self.defaultBoardID = def.id
            self.pinboards = [def]
            self.boardItems = [:]
            persist()
        }
    }

    private func persist() {
        let mapped = boardItems.mapValues { Array($0) }
        let snap = Snapshot(items: items, pinboards: pinboards, boardItems: mapped)
        if let d = try? encoder.encode(snap) { try? d.write(to: indexURL) }
    }

    private func ensurePermanentContent(_ item: ClipItem) -> ClipItem {
        guard let ref = item.contentRef else { return item }
        let isTemp = ref.path.hasPrefix(FileManager.default.temporaryDirectory.path)
        if isTemp {
            var ext = ref.pathExtension
            if ext.isEmpty {
                switch item.type { case .image: ext = "png"; case .text: ext = "rtf"; default: ext = "dat" }
            }
            let dst = contentDir.appendingPathComponent(item.id.uuidString).appendingPathExtension(ext)
            if (try? FileManager.default.copyItem(at: ref, to: dst)) != nil {
                var updated = item
                updated = ClipItem(id: item.id, type: item.type, contentRef: dst, text: item.text, sourceApp: item.sourceApp, copiedAt: item.copiedAt, metadata: item.metadata, tags: item.tags, isPinned: item.isPinned, name: item.name)
                return updated
            }
        }
        return item
    }

    private func cleanupExpiredItems(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let pinned = Set(boardItems.values.flatMap { $0 })
        let beforeCount = items.count
        items.removeAll { !pinned.contains($0.id) && $0.copiedAt < cutoff }
        if items.count != beforeCount { persist() }
    }

    private func cleanupExceededItems(limit: Int) {
        let pinned = Set(boardItems.values.flatMap { $0 })
        if limit <= 0 {
            let beforeCount = items.count
            items.removeAll { !pinned.contains($0.id) }
            if items.count != beforeCount { persist() }
            return
        }
        let nonPinned = items.filter { !pinned.contains($0.id) }
        let excess = max(0, nonPinned.count - limit)
        if excess <= 0 { return }
        let sorted = nonPinned.sorted { $0.copiedAt < $1.copiedAt }
        let idsToRemove = Set(sorted.prefix(excess).map { $0.id })
        let beforeCount = items.count
        items.removeAll { idsToRemove.contains($0.id) }
        if items.count != beforeCount { persist() }
    }
}
