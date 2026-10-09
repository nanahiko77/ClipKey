import UIKit
import ImageIO
import CryptoKit

// MARK: - 설정

/// 키보드 확장 안에 저장되는 설정
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: ["markedComposing2": false, "naraHints": true, "maxClips": 50, "autoCorrect": true, "showArrows": true,
                              "showHide": true, "repeatOnHold": true, "repeatSpeed": 5, "longPressTime": 0.35])
        // 이모지 패널이 생겼다: 예전에 "준비 중"이라 꺼져 있던 이모지를 한 번만 켠다
        if !d.bool(forKey: "emojiReady") {
            d.set(true, forKey: "emojiReady")
            if var off = d.stringArray(forKey: "toolbarOff") {
                off.removeAll { $0 == "emoji" }
                d.set(off, forKey: "toolbarOff")
            }
        }
    }

    // MARK: 한글 조합

    /// 조합 중인 글자를 "조합 중 글자"(marked text)로 넣는다.
    /// 지우고 다시 넣지 않아서 사파리 웹페이지 입력창에서 커서가 깜빡이지 않는다.
    /// 앱마다 처리가 달라 글자가 겹치거나 사라지는 경우가 있어 기본은 끈다 (실험 기능).
    /// 예전 설정 이름(markedComposing)은 기본으로 켜져 있었으므로 새 이름으로 바꿔 모두 꺼진 상태에서 시작한다.
    var markedComposing: Bool {
        get { d.bool(forKey: "markedComposing2") }
        set { d.set(newValue, forKey: "markedComposing2") }
    }

    // MARK: 내가 고른 교정

    /// 친 글자 → 내가 고른 단어. 같은 글자를 다시 치면 이 단어로 고친다. 같은 글자면 "고치지 마".
    /// 키를 칠 때마다 읽으므로 처음 한 번만 저장소에서 꺼내고 메모리에 들고 있는다
    private lazy var choicesCache: [String: String] =
        (d.dictionary(forKey: "correctionChoices") as? [String: String]) ?? [:]
    var correctionChoices: [String: String] {
        get { choicesCache }
        set {
            choicesCache = newValue
            d.set(newValue, forKey: "correctionChoices")
        }
    }

    func rememberChoice(typed: String, chosen: String) {
        guard !typed.isEmpty, !chosen.isEmpty else { return }
        var m = correctionChoices
        m[typed] = chosen
        if m.count > 800 { m = Dictionary(uniqueKeysWithValues: m.suffix(600).map { ($0.key, $0.value) }) }
        correctionChoices = m
    }

    // MARK: 이모지

    /// 최근에 쓴 이모지 (앞이 가장 최근). 자주 쓰는 칸에 그대로 보인다.
    var recentEmoji: [String] {
        get { d.stringArray(forKey: "recentEmoji") ?? [] }
        set { d.set(Array(newValue.prefix(32)), forKey: "recentEmoji") }
    }

    func useEmoji(_ e: String) {
        var r = recentEmoji
        r.removeAll { $0 == e }
        r.insert(e, at: 0)
        recentEmoji = r
    }

    // MARK: 입력

    /// 보조 글자가 없는 키를 누르고 있으면 반복 입력
    var repeatOnHold: Bool {
        get { d.bool(forKey: "repeatOnHold") }
        set { d.set(newValue, forKey: "repeatOnHold") }
    }
    /// 반복 입력 속도 0(느리게) ~ 9(빠르게). 지우기 키의 연속 삭제도 이 속도를 쓴다.
    var repeatSpeed: Int {
        get { min(max(d.integer(forKey: "repeatSpeed"), 0), 9) }
        set { d.set(min(max(newValue, 0), 9), forKey: "repeatSpeed") }
    }
    /// 반복 간격(초). 5 일 때 예전과 같은 0.09초.
    var repeatInterval: TimeInterval { 0.15 - Double(repeatSpeed) * 0.012 }
    /// 길게 누르기로 보는 시간(초). 그냥 누른 것과 헷갈리지 않도록 0.3초 아래로는 내리지 않는다.
    static let longPressRange: ClosedRange<Double> = 0.3...0.8
    var longPressTime: Double {
        get { min(max(d.double(forKey: "longPressTime"), Settings.longPressRange.lowerBound), Settings.longPressRange.upperBound) }
        set { d.set(min(max(newValue, Settings.longPressRange.lowerBound), Settings.longPressRange.upperBound), forKey: "longPressTime") }
    }
    /// 전체 삭제 같은 큰 말풍선: 반복 삭제가 먼저 시작되도록 길게 누르기 + 0.3초, 최소 0.6초
    var altDelay: Double { max(0.6, longPressTime + 0.3) }

    // MARK: 상단바 꾸미기

    /// 순서를 바꿀 수 있는 도구. 한/영은 항상 맨 앞, 화살표와 닫기는 항상 맨 뒤.
    static let toolbarItemsAll = ["clipboard", "settings", "addword", "emoji"]
    static let toolbarOffDefault: [String] = []

    var toolbarOrder: [String] {
        get {
            let saved = (d.stringArray(forKey: "toolbarOrder") ?? []).filter { Settings.toolbarItemsAll.contains($0) }
            return saved + Settings.toolbarItemsAll.filter { !saved.contains($0) }
        }
        set { d.set(newValue, forKey: "toolbarOrder") }
    }
    /// 꺼 둔 도구
    var toolbarOff: [String] {
        get { d.stringArray(forKey: "toolbarOff") ?? Settings.toolbarOffDefault }
        set { d.set(newValue, forKey: "toolbarOff") }
    }
    /// 상단바의 키보드 닫기 버튼
    var showHide: Bool {
        get { d.bool(forKey: "showHide") }
        set { d.set(newValue, forKey: "showHide") }
    }

    func resetToolbar() {
        d.removeObject(forKey: "toolbarOrder")
        d.removeObject(forKey: "toolbarOff")
        showArrows = true
        showHide = true
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
    /// 보조키 표시 (꾹 눌러 숫자·기호). 이름은 예전 그대로지만 모든 자판에 적용된다.
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
    /// 오타 교정 (한글·영문): 0 끄기, 1 추천만, 2 자동(간격을 누르면 바꿈). 예전 "영문 오타 자동 교정"을 껐으면 끄기로 시작한다.
    var correctMode: Int {
        get {
            if d.object(forKey: "correctMode") == nil { return autoCorrect ? 2 : 0 }
            return d.integer(forKey: "correctMode")
        }
        set { d.set(newValue, forKey: "correctMode") }
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
        pinBg: hex(0x3A4660), danger: hex(0xE5453B), onDanger: hex(0xFFFFFF), row: hex(0x2E3035),
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

/// 파일 저장을 바로 하지 않고 잠깐 모았다가 한 번에 한다. 키보드가 내려갈 때는 flush() 로 바로 저장한다.
final class SaveThrottle {
    private var timer: Timer?
    private let action: () -> Void

    init(_ action: @escaping () -> Void) { self.action = action }

    func schedule() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        action()
    }
}

/// 자주 친 단어를 횟수와 함께 기기 안에 저장한다.
/// 직접 넣은 단어는 바로, 자동으로 배운 단어는 threshold 번 이상 쳤을 때부터 추천에 쓴다.
final class WordStore {
    private var counts: [String: Int] = [:]
    private let url: URL
    private lazy var saver = SaveThrottle { [weak self] in self?.writeNow() }
    /// 정렬한 목록. 키를 누를 때마다 다시 정렬하지 않도록 기억해 두고, 단어가 바뀌면 지운다.
    private var cachedList: [String]?

    /// 추천에서 고르거나 교정을 되돌려서 "이건 맞는 말"이라고 알려 준 단어.
    /// 교정만 하지 않을 뿐, 추천 칩이나 단어 관리에는 나오지 않는다 (목록이 쓸데없이 길어지지 않게).
    private var chosen: Set<String> = []
    private let chosenURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("words.json")
        chosenURL = dir.appendingPathComponent("chosen.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            counts = saved
        }
        if let data = try? Data(contentsOf: chosenURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            chosen = Set(saved)
        }
    }

    /// 내가 고른 단어로 기억한다 (교정하지 않음). 친 횟수도 하나 올린다.
    func markChosen(_ raw: String) {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, w.count <= 30 else { return }
        learn(w)
        guard !chosen.contains(w) else { return }
        chosen.insert(w)
        if chosen.count > 1500 { chosen = Set(chosen.shuffled().prefix(1200)) }
        if let data = try? JSONEncoder().encode(Array(chosen)) {
            try? data.write(to: chosenURL, options: .atomic)
        }
    }

    func isChosen(_ w: String) -> Bool { chosen.contains(w) }

    /// 교정 후보로 쓸 내 단어 전부 (직접 넣은 단어, 자주 친 단어, 고른 단어)
    var personal: [String] { list + chosen.filter { (counts[$0] ?? 0) < WordStore.threshold } }

    /// 배울 만한 단어인지: 숫자가 섞인 글자, 미완성 낱자, 한 글자짜리는 배우지 않는다.
    static func learnable(_ w: String) -> Bool {
        guard w.count >= 2, w.count <= 20 else { return false }
        guard w.allSatisfy({ $0.isLetter }) else { return false }
        return !w.contains(where: { HangulComposer.isJamo($0) })
    }

    func learn(_ raw: String, force: Bool = false) {
        let w = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard WordStore.learnable(w) else { return }
        let before = counts[w] ?? 0
        let next = before + 1
        counts[w] = force ? max(next, WordStore.threshold) : next
        // 추천 목록에 들어가거나 순서가 바뀔 수 있을 때만 목록을 다시 만든다
        if counts[w]! >= WordStore.threshold { cachedList = nil }
        if counts.count > 2000 { prune() }
        save()
    }

    static let manualCount = 1_000_000
    /// 자동으로 배운 단어가 추천에 나오기 시작하는 횟수
    static let threshold = 5

    func isManual(_ w: String) -> Bool { (counts[w] ?? 0) >= WordStore.manualCount }

    /// 단어 관리에서 직접 넣은 단어. 숫자나 하이픈, 띄어쓰기가 있어도 되고 바로 추천에 나온다.
    func addManual(_ raw: String) {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, w.count <= 60 else { return }
        counts[w] = max(counts[w] ?? 0, WordStore.manualCount)
        cachedList = nil
        save()
    }

    func knows(_ w: String) -> Bool { (counts[w] ?? 0) >= WordStore.threshold || chosen.contains(w) }

    /// 자주 친 순서
    var list: [String] {
        if let l = cachedList { return l }
        let l = counts.filter { $0.value >= WordStore.threshold }
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .map { $0.key }
        cachedList = l
        return l
    }

    /// 직접 넣은 단어 (가나다순)
    var manualWords: [String] {
        counts.filter { $0.value >= WordStore.manualCount }.map { $0.key }.sorted()
    }

    /// 자주 친 단어와 친 횟수 (많이 친 순서)
    var learnedWords: [(word: String, count: Int)] {
        counts.filter { $0.value >= WordStore.threshold && $0.value < WordStore.manualCount }
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .map { ($0.key, $0.value) }
    }

    func matches(_ query: String) -> [String] {
        list.filter { $0 != query && HangulComposer.matches(query: query, word: $0) }
    }

    /// 지우고, 되돌릴 수 있도록 지우기 전 횟수를 돌려준다
    @discardableResult
    func remove(_ w: String) -> Int? {
        let old = counts[w]
        counts[w] = nil
        if chosen.remove(w) != nil, let data = try? JSONEncoder().encode(Array(chosen)) {
            try? data.write(to: chosenURL, options: .atomic)
        }
        cachedList = nil
        save()
        return old
    }

    /// 지운 단어를 되돌린다
    func restore(_ w: String, count: Int) {
        counts[w] = max(counts[w] ?? 0, count)
        cachedList = nil
        save()
    }

    func clear() {
        counts = [:]
        chosen = []
        try? FileManager.default.removeItem(at: chosenURL)
        cachedList = nil
        save()
    }

    func flush() { saver.flush() }

    private func prune() {
        let keep = counts.sorted { $0.value > $1.value }.prefix(1500)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        cachedList = nil
    }

    private func save() { saver.schedule() }

    private func writeNow() {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 다음 단어

/// 앞 단어 다음에 이어 친 단어를 센다. 간격을 누른 뒤 평소 이어 쓰던 단어를 추천한다. 기기 안에만 저장한다.
final class NextWordStore {
    private var pairs: [String: [String: Int]] = [:]
    private var total = 0
    private let url: URL
    private lazy var saver = SaveThrottle { [weak self] in self?.writeNow() }
    static let threshold = 2
    static let maxPairs = 3000

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("nextwords.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            pairs = saved
            total = saved.values.reduce(0) { $0 + $1.count }
        }
    }

    func learn(previous: String, next: String) {
        guard WordStore.learnable(previous), WordStore.learnable(next) else { return }
        if pairs[previous]?[next] == nil { total += 1 }
        pairs[previous, default: [:]][next, default: 0] += 1
        if total > NextWordStore.maxPairs { prune() }
        saver.schedule()
    }

    /// 앞 단어 다음에 threshold 번 이상 쳤던 단어, 많이 친 순서
    func predictions(after previous: String, limit: Int) -> [String] {
        guard let next = pairs[previous] else { return [] }
        return next.filter { $0.value >= NextWordStore.threshold }
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .prefix(limit).map { $0.key }
    }

    /// 지우고, 되돌릴 수 있도록 지운 짝을 돌려준다
    @discardableResult
    func remove(_ word: String) -> [String: [String: Int]] {
        var removed: [String: [String: Int]] = [:]
        for key in Array(pairs.keys) {
            if let c = pairs[key]?[word] { removed[key, default: [:]][word] = c }
            pairs[key]?[word] = nil
            if pairs[key]?.isEmpty == true { pairs[key] = nil }
        }
        if let own = pairs[word] {
            for (k, v) in own { removed[word, default: [:]][k] = v }
        }
        pairs[word] = nil
        total = pairs.values.reduce(0) { $0 + $1.count }
        saver.schedule()
        return removed
    }

    func restore(_ removed: [String: [String: Int]]) {
        for (prev, nexts) in removed {
            for (next, c) in nexts { pairs[prev, default: [:]][next] = c }
        }
        total = pairs.values.reduce(0) { $0 + $1.count }
        saver.schedule()
    }

    func clear() {
        pairs = [:]
        total = 0
        saver.schedule()
    }

    func flush() { saver.flush() }

    /// 한 번만 친 짝부터 지운다
    private func prune() {
        for key in Array(pairs.keys) {
            pairs[key] = pairs[key]?.filter { $0.value > 1 }
            if pairs[key]?.isEmpty == true { pairs[key] = nil }
        }
        total = pairs.values.reduce(0) { $0 + $1.count }
    }

    private func writeNow() {
        guard let data = try? JSONEncoder().encode(pairs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 스티커

/// 내가 만든 스티커 팩. 클립보드에 저장된 사진을 골라 팩에 넣는다. 키보드 안에만 저장한다.
struct StickerPack: Codable, Equatable {
    var id: UUID
    var name: String
    var items: [String]          // 파일 이름 (stickers 폴더)
}

final class StickerStore {
    private(set) var packs: [StickerPack] = []
    private let url: URL
    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("stickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = base.appendingPathComponent("stickers.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([StickerPack].self, from: data) {
            packs = saved
        }
        cleanUp()            // 지난번에 지운 팩·스티커 파일 정리
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[i].name = String(name.prefix(20))
        save()
    }

    func moveToFront(_ id: UUID) {
        guard let i = packs.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let p = packs.remove(at: i)
        packs.insert(p, at: 0)
        save()
    }

    /// 팩을 목록에서 뺀다. 되돌릴 수 있도록 파일은 다음에 키보드를 열 때 정리한다.
    func deletePack(_ id: UUID) -> Int? {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return nil }
        packs.remove(at: i)
        save()
        return i
    }

    func restorePack(_ pack: StickerPack, at index: Int) {
        guard !packs.contains(where: { $0.id == pack.id }) else { return }
        packs.insert(pack, at: min(index, packs.count))
        save()
    }

    func fileURL(_ name: String) -> URL { dir.appendingPathComponent(name) }
    func thumbURL(_ name: String) -> URL { dir.appendingPathComponent("t_" + name) }

    /// 새 팩. 이름은 "팩 1", "팩 2" 처럼 붙인다.
    @discardableResult
    func newPack() -> StickerPack {
        var n = packs.count + 1
        while packs.contains(where: { $0.name == "팩 \(n)" }) { n += 1 }
        let p = StickerPack(id: UUID(), name: "팩 \(n)", items: [])
        packs.append(p)
        save()
        return p
    }

    /// 사진 파일을 복사해 팩에 넣는다. 넣은 개수를 돌려준다.
    @discardableResult
    func add(images: [URL], to packID: UUID) -> Int {
        guard let i = packs.firstIndex(where: { $0.id == packID }) else { return 0 }
        var added = 0
        for src in images {
            guard let data = try? Data(contentsOf: src) else { continue }
            let name = UUID().uuidString + ".jpg"
            do { try data.write(to: fileURL(name), options: .atomic) } catch { continue }
            if let small = ClipStore.downsample(data, maxPixel: 200), let t = small.jpegData(compressionQuality: 0.75) {
                try? t.write(to: thumbURL(name), options: .atomic)
            }
            packs[i].items.append(name)
            added += 1
        }
        save()
        return added
    }

    /// 스티커 하나를 뺀다. 되돌리기를 위해 파일은 남겨 두고, 다음에 정리한다.
    func remove(_ name: String) -> (pack: UUID, index: Int)? {
        for i in packs.indices {
            if let j = packs[i].items.firstIndex(of: name) {
                packs[i].items.remove(at: j)
                save()
                return (packs[i].id, j)
            }
        }
        return nil
    }

    func restore(_ name: String, pack: UUID, index: Int) {
        guard let i = packs.firstIndex(where: { $0.id == pack }) else { return }
        packs[i].items.insert(name, at: min(index, packs[i].items.count))
        save()
    }

    /// 빈 팩과 어디에도 속하지 않는 파일을 정리한다
    func cleanUp() {
        packs.removeAll { $0.items.isEmpty }
        save()
        var keep = Set<String>()
        for p in packs { for n in p.items { keep.insert(n); keep.insert("t_" + n) } }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(packs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
