import Foundation

struct Clip: Codable, Equatable {
    var id: UUID
    var text: String
    var pinned: Bool
    var date: Date
}

/// 키보드 확장 자체 저장소에 JSON으로 기록을 보관한다.
/// (App Group을 쓰지 않아 무료 서명/사이드로드에서도 그대로 동작)
final class ClipStore {
    static let maxUnpinned = 50
    static let maxLength = 10_000

    private(set) var clips: [Clip] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("clips.json")
        load()
    }

    /// 고정된 항목이 위, 그 안에서는 최신순
    var sorted: [Clip] {
        clips.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    func add(_ raw: String) {
        let text = String(raw.prefix(Self.maxLength))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let i = clips.firstIndex(where: { $0.text == text }) {
            clips[i].date = Date()          // 같은 내용은 맨 위로만 올린다
        } else {
            clips.append(Clip(id: UUID(), text: text, pinned: false, date: Date()))
        }
        trim()
        save()
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].pinned.toggle()
        save()
    }

    func clearUnpinned() {
        clips.removeAll { !$0.pinned }
        save()
    }

    private func trim() {
        let unpinned = clips.filter { !$0.pinned }.sorted { $0.date > $1.date }
        guard unpinned.count > Self.maxUnpinned else { return }
        let drop = Set(unpinned.dropFirst(Self.maxUnpinned).map { $0.id })
        clips.removeAll { drop.contains($0.id) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Clip].self, from: data) else { return }
        clips = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
