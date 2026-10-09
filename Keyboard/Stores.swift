import UIKit
import ImageIO
import CryptoKit

// MARK: - 설정

/// 키보드 확장 안에 저장되는 설정
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: ["naraHints": true, "maxClips": 50, "autoCorrect": true, "showArrows": true])
    }

    /// 상단바의 커서 좌우 화살표
    var showArrows: Bool {
        get { d.bool(forKey: "showArrows") }
        set { d.set(newValue, forKey: "showArrows") }
    }

    /// 0 나랏글, 1 두벌식
    var hangulLayout: Int {
        get { d.integer(forKey: "hangulLayout") }
        set { d.set(newValue, forKey: "hangulLayout") }
    }
    var naraHints: Bool {
        get { d.bool(forKey: "naraHints") }
        set { d.set(newValue, forKey: "naraHints") }
    }
    /// 0 시스템, 1 라이트, 2 다크
    var themeMode: Int {
        get { d.integer(forKey: "themeMode") }
        set { d.set(newValue, forKey: "themeMode") }
    }
    var maxClips: Int {
        get { d.integer(forKey: "maxClips") }
        set { d.set(newValue, forKey: "maxClips") }
    }
    /// 간격을 연달아 두 번 누르면: 0 그대로, 1 마침표, 2 쉼표
    var doubleSpace: Int {
        get { d.integer(forKey: "doubleSpace") }
        set { d.set(newValue, forKey: "doubleSpace") }
    }
    /// 복사한 사진도 기록에 넣을지
    var savePhotos: Bool {
        get { d.bool(forKey: "savePhotos") }
        set { d.set(newValue, forKey: "savePhotos") }
    }
    var haptic: Bool {
        get { d.bool(forKey: "haptic") }
        set { d.set(newValue, forKey: "haptic") }
    }
    /// 키를 누를 때 나는 소리. 아이폰 설정의 키보드 피드백과는 따로 동작한다.
    var keySound: Bool {
        get { d.bool(forKey: "keySound") }
        set { d.set(newValue, forKey: "keySound") }
    }
    var autoCap: Bool {
        get { d.bool(forKey: "autoCap") }
        set { d.set(newValue, forKey: "autoCap") }
    }
    var autoCorrect: Bool {
        get { d.bool(forKey: "autoCorrect") }
        set { d.set(newValue, forKey: "autoCorrect") }
    }
}

// MARK: - 색

struct Theme {
    let bg: UIColor
    let key: UIColor
    let funcKey: UIColor
    let text: UIColor
    let muted: UIColor
    let divider: UIColor
    let accent: UIColor
    let onAccent: UIColor
    let pinBg: UIColor
    let danger: UIColor
    let onDanger: UIColor
    let row: UIColor
    let hint: UIColor

    static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1)
    }

    static let light = Theme(
        bg: hex(0xE4E6EA), key: hex(0xFFFFFF), funcKey: hex(0xC3C8D0), text: hex(0x16181C),
        muted: hex(0x4A5058), divider: hex(0xC3C8D0), accent: hex(0x3D3D3D), onAccent: hex(0xFFFFFF),
        pinBg: hex(0xDCE2F1), danger: hex(0xB3261E), onDanger: hex(0xFFFFFF), row: hex(0xFFFFFF),
        hint: hex(0x6B7280))

    static let dark = Theme(
        bg: hex(0x1B1C1F), key: hex(0x4A4D54), funcKey: hex(0x2E3035), text: hex(0xF2F3F5),
        muted: hex(0xA9AEB7), divider: hex(0x3A3D43), accent: hex(0xE4E6EA), onAccent: hex(0x16181C),
        pinBg: hex(0x3A4660), danger: hex(0xF2857D), onDanger: hex(0x16181C), row: hex(0x2E3035),
        hint: hex(0xC3C8D0))
}

// MARK: - 클립보드 기록

struct Clip: Codable, Equatable {
    var id: UUID
    var text: String
    var pinned: Bool
    var date: Date
    // 사진 항목일 때만 채워진다
    var image: String? = nil       // 줄여서 저장한 파일 이름
    var width: Int? = nil
    var height: Int? = nil
    var bytes: Int? = nil
    // 같은 사진을 다시 저장하지 않기 위한 지문: 복사된 원본과, 줄여서 저장한 파일
    var hash: String? = nil
    var hash2: String? = nil
}

/// 키보드 확장 자체 저장소에 JSON으로 기록을 보관한다.
final class ClipStore {
    static let maxLength = 10_000
    static let maxImages = 10                        // 고정하지 않은 사진은 최근 10장
    static let maxImageBytes = 20 * 1024 * 1024      // 이보다 큰 사진 데이터는 건너뛴다
    static let maxImagePixels = 1024                 // 긴 변을 이 크기로 줄여 저장

    private(set) var clips: [Clip] = []
    private let url: URL
    private let imageDir: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("clips.json")
        imageDir = dir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        load()
        removeDuplicateImages()
        purgeOrphans()
    }

    /// 고정된 항목이 위, 그 안에서는 최신순
    var sorted: [Clip] {
        clips.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    /// 새로 들어온 내용이면 그 항목을 돌려준다. 이미 가장 최근 항목이면 nil.
    @discardableResult
    func add(_ raw: String) -> Clip? {
        let text = String(raw.prefix(ClipStore.maxLength))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let newest = clips.max { $0.date < $1.date }
        if let n = newest, n.text == text { return nil }
        let result: Clip
        if let i = clips.firstIndex(where: { $0.text == text }) {
            clips[i].date = Date()
            result = clips[i]
        } else {
            result = Clip(id: UUID(), text: text, pinned: false, date: Date())
            clips.append(result)
        }
        trim()
        save()
        return result
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        save()
    }

    func restore(_ clip: Clip) {
        guard !clips.contains(where: { $0.id == clip.id }) else { return }
        clips.append(clip)
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
        purgeOrphans()
    }

    // MARK: 사진

    func imageURL(_ clip: Clip) -> URL? {
        clip.image.map { imageDir.appendingPathComponent($0) }
    }

    func thumbURL(_ clip: Clip) -> URL? {
        clip.image.map { imageDir.appendingPathComponent("t_" + $0) }
    }

    /// 복사된 사진 데이터를 줄여서 저장한다. 너무 크거나 읽을 수 없으면 nil.
    @discardableResult
    func addImage(_ data: Data) -> Clip? {
        guard data.count <= ClipStore.maxImageBytes else { return nil }
        // 이미 저장한 사진이면 새로 만들지 않는다.
        // (키보드는 열릴 때마다 클립보드를 다시 읽기 때문에, 이 확인이 없으면 같은 사진이 계속 늘어난다)
        let print = ClipStore.fingerprint(data)
        if let i = clips.firstIndex(where: { $0.image != nil && ($0.hash == print || $0.hash2 == print) }) {
            let newest = clips.max { $0.date < $1.date }
            if newest?.id == clips[i].id { return nil }
            clips[i].date = Date()
            save()
            return clips[i]
        }
        guard let full = ClipStore.downsample(data, maxPixel: ClipStore.maxImagePixels),
              let jpeg = full.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: imageDir.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        // 목록에서는 이 작은 그림만 불러온다
        if let small = ClipStore.downsample(jpeg, maxPixel: 120), let t = small.jpegData(compressionQuality: 0.7) {
            try? t.write(to: imageDir.appendingPathComponent("t_" + name), options: .atomic)
        }
        let clip = Clip(id: UUID(), text: "", pinned: false, date: Date(), image: name,
                        width: Int(full.size.width), height: Int(full.size.height), bytes: jpeg.count,
                        hash: print, hash2: ClipStore.fingerprint(jpeg))
        clips.append(clip)
        trim()
        save()
        purgeOrphans()
        return clip
    }

    /// 원본을 통째로 펼치지 않고, 처음부터 줄인 크기로만 읽는다 (메모리를 아끼기 위해)
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 예전 버전에서 같은 사진이 여러 번 저장된 것을 정리한다. 고정한 것을 먼저 남긴다.
    func removeDuplicateImages() {
        var changed = false
        for i in clips.indices where clips[i].image != nil && clips[i].hash2 == nil {
            if let url = imageURL(clips[i]), let data = try? Data(contentsOf: url) {
                clips[i].hash2 = ClipStore.fingerprint(data)
                changed = true
            }
        }
        var seen = Set<String>()
        var drop = Set<UUID>()
        let ordered = clips.filter { $0.image != nil }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
        for c in ordered {
            guard let h = c.hash2 else { continue }
            if seen.contains(h) { drop.insert(c.id) } else { seen.insert(h) }
        }
        if !drop.isEmpty {
            clips.removeAll { drop.contains($0.id) }
            changed = true
        }
        if changed { save() }
    }

    /// 어느 항목에도 속하지 않는 사진 파일을 지운다. (삭제 후 되돌리기를 위해 파일은 바로 지우지 않는다)
    func purgeOrphans() {
        var keep = Set<String>()
        for c in clips {
            if let name = c.image {
                keep.insert(name)
                keep.insert("t_" + name)
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imageDir.path)) ?? []
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(file))
        }
    }

    func trim() {
        // 사진은 글자와 따로 센다
        let images = clips.filter { !$0.pinned && $0.image != nil }.sorted { $0.date > $1.date }
        if images.count > ClipStore.maxImages {
            let drop = Set(images.dropFirst(ClipStore.maxImages).map { $0.id })
            clips.removeAll { drop.contains($0.id) }
        }
        let limit = max(Settings.shared.maxClips, 1)
        let unpinned = clips.filter { !$0.pinned && $0.image == nil }.sorted { $0.date > $1.date }
        guard unpinned.count > limit else { return }
        let drop = Set(unpinned.dropFirst(limit).map { $0.id })
        clips.removeAll { drop.contains($0.id) }
    }

    func trimAndSave() {
        trim()
        save()
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

// MARK: - 학습한 단어

/// 자주 친 단어를 횟수와 함께 기기 안에 저장한다. 두 번 이상 친 단어만 추천에 쓴다.
final class WordStore {
    private var counts: [String: Int] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("words.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            counts = saved
        }
    }

    /// 숫자가 섞인 글자, 미완성 낱자, 한 글자짜리는 배우지 않는다.
    func learn(_ raw: String, force: Bool = false) {
        let w = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard w.count >= 2, w.count <= 20 else { return }
        guard w.allSatisfy({ $0.isLetter }) else { return }
        guard !w.contains(where: { HangulComposer.isJamo($0) }) else { return }
        let next = (counts[w] ?? 0) + 1
        counts[w] = force ? max(next, 2) : next
        if counts.count > 2000 { prune() }
        save()
    }

    static let manualCount = 1_000_000

    /// 단어 관리에서 직접 넣은 단어. 숫자나 하이픈, 띄어쓰기가 있어도 되고 바로 추천에 나온다.
    func addManual(_ raw: String) {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, w.count <= 60 else { return }
        counts[w] = max(counts[w] ?? 0, WordStore.manualCount)
        save()
    }

    func knows(_ w: String) -> Bool { (counts[w] ?? 0) >= 2 }

    /// 자주 친 순서
    var list: [String] {
        counts.filter { $0.value >= 2 }
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .map { $0.key }
    }

    func matches(_ query: String) -> [String] {
        list.filter { $0 != query && HangulComposer.matches(query: query, word: $0) }
    }

    func remove(_ w: String) {
        counts[w] = nil
        save()
    }

    func clear() {
        counts = [:]
        save()
    }

    private func prune() {
        let keep = counts.sorted { $0.value > $1.value }.prefix(1500)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
