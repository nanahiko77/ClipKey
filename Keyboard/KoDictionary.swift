import Foundation

/// 한국어 추천 사전 (ko_dict.txt). 학습한 단어와는 따로 둔다.
/// 한 줄이 한 단어와 그 활용형이고, 줄 순서가 자주 쓰는 순서다.
/// 키보드가 뜰 때 뒤에서 미리 읽어 둔다. 설정에서 받은 사전이 있으면 그것을 먼저 쓴다.
final class KoDictionary {
    static let shared = KoDictionary()

    enum Source: Equatable {
        case bundled
        case downloaded(Date)
    }

    struct Info {
        let words: Int
        let forms: Int
        let source: Source
    }

    /// 설정에서 받을 곳. 앞에서부터 차례로 시도한다.
    static let remoteURLs = [
        "https://raw.githubusercontent.com/nanahiko77/ClipKey/v1.1-keyboard/Keyboard/ko_dict.txt",
        "https://raw.githubusercontent.com/nanahiko77/ClipKey/main/Keyboard/ko_dict.txt",
    ]
    static let header = "# ClipKey 한국어 추천 사전"

    struct Data_ {
        var groups: [[String]] = []
        var byCho: [Int: [Int]] = [:]
        var bySyllable: [Character: [Int]] = [:]
        var forms = 0
        // 오타 교정용
        var flat: [String] = []                  // 모든 활용형, 자주 쓰는 순서
        var flatJamo: [[UInt16]] = []            // 위 활용형을 자모로 푼 것
        var byFirstJamo: [UInt16: [Int]] = [:]   // 첫 자모별 flat 번호
        var known: Set<String> = []              // 바른 말 확인용
        var typos: [(wrong: String, right: String)] = []
    }

    private enum State { case idle, loading, ready }

    private let lock = NSLock()
    private var state = State.idle
    private var data = Data_()
    private var source: Source = .bundled
    private var loaded = false        // 읽기를 끝냈고 단어가 1개 이상 있다

    private init() {}

    static var downloadedURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ko_dict.txt")
    }

    /// 뒤에서 미리 읽어 둔다. 이미 읽었거나 읽는 중이면 아무것도 하지 않는다.
    func preload(completion: (() -> Void)? = nil) {
        lock.lock()
        guard state == .idle else {
            lock.unlock()
            if let completion = completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        state = .loading
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            self.loadNow()
            if let completion = completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    private func loadNow() {
        var result: (Data_, Source)?
        let downloaded = KoDictionary.downloadedURL
        if let text = try? String(contentsOf: downloaded, encoding: .utf8), KoDictionary.isValid(text) {
            let date = (try? FileManager.default.attributesOfItem(atPath: downloaded.path)[.modificationDate] as? Date) ?? Date()
            result = (KoDictionary.parse(text), .downloaded(date))
        } else if let url = Bundle(for: KoDictionary.self).url(forResource: "ko_dict", withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8) {
            result = (KoDictionary.parse(text), .bundled)
        }
        lock.lock()
        if let (d, s) = result {
            data = d
            source = s
        }
        loaded = !data.groups.isEmpty
        state = .ready
        lock.unlock()
    }

    private static func parse(_ text: String) -> Data_ {
        var d = Data_()
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            if line.hasPrefix("!") {
                // 자주 틀리는 말: "!틀린꼴 바른꼴"
                let body = line.dropFirst()
                guard let space = body.firstIndex(of: " ") else { continue }
                let wrong = String(body[..<space])
                let right = String(body[body.index(after: space)...])
                if !wrong.isEmpty, !right.isEmpty { d.typos.append((wrong, right)) }
                continue
            }
            let forms = line.split(separator: " ").map(String.init)
            for f in forms where !d.known.contains(f) {
                d.known.insert(f)
                let jamo = KoCorrector.jamo(f)
                guard let first = jamo.first else { continue }
                d.byFirstJamo[first, default: []].append(d.flat.count)
                d.flat.append(f)
                d.flatJamo.append(jamo)
            }
            guard !forms.isEmpty else { continue }
            let index = d.groups.count
            d.groups.append(forms)
            d.forms += forms.count
            var chos = Set<Int>()
            var firsts = Set<Character>()
            for f in forms {
                guard let c = f.first else { continue }
                firsts.insert(c)
                if let p = HangulComposer.parts(c) { chos.insert(p.cho) }
            }
            for c in firsts { d.bySyllable[c, default: []].append(index) }
            for c in chos { d.byCho[c, default: []].append(index) }
        }
        return d
    }

    /// 받은 파일이 사전 형식이 맞는지: 머리줄이 있고 단어가 충분히 많아야 한다
    static func isValid(_ text: String) -> Bool {
        guard text.hasPrefix(header) else { return false }
        var lines = 0
        for _ in text.split(separator: "\n") {
            lines += 1
            if lines > 1000 { return true }
        }
        return false
    }

    /// 설정의 정보 줄에 보여 줄 내용. 아직 읽는 중이면 nil, 사전이 없으면 words 가 0.
    var info: Info? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .ready else { return nil }
        return Info(words: loaded ? data.groups.count : 0, forms: data.forms, source: source)
    }

    /// 입력 중인 글자로 시작하는 단어. 한 단어에서는 활용형을 최대 2개까지만 보여 준다.
    /// 아직 다 읽지 못했으면 기다리지 않고 빈 결과를 돌려준다.
    func complete(_ query: String, limit: Int) -> [String] {
        lock.lock()
        let ready = state == .ready
        let d = data
        lock.unlock()
        guard ready else {
            preload()
            return []
        }
        guard let first = query.first, limit > 0 else { return [] }
        let list: [Int]
        if query.count >= 2, HangulComposer.parts(first) != nil {
            list = d.bySyllable[first] ?? []
        } else if let p = HangulComposer.parts(first) {
            list = d.byCho[p.cho] ?? []
        } else if let i = HangulComposer.choList.firstIndex(of: first) {
            // 초성만 친 경우: ㅅㄱ → 생각
            list = d.byCho[i] ?? []
        } else {
            return []
        }
        let length = query.count
        var out: [String] = []
        for index in list {
            var perWord = 0
            for form in d.groups[index] where form.count >= length && form != query {
                guard HangulComposer.matches(query: query, word: form) else { continue }
                out.append(form)
                perWord += 1
                if perWord == 2 || out.count == limit { break }
            }
            if out.count >= limit { break }
        }
        return out
    }

    /// 오타 교정에 쓸 사전 데이터. 아직 다 읽지 못했으면 nil.
    func snapshot() -> Data_? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .ready, loaded else { return nil }
        return data
    }

    // MARK: - 받기

    enum DownloadResult {
        case updated(words: Int)
        case alreadyLatest
        case failed(String)
    }

    /// 사전을 받아 형식을 확인하고, 맞으면 저장한 뒤 다시 읽는다. 결과는 메인 스레드로 돌려준다.
    func download(completion: @escaping (DownloadResult) -> Void) {
        let session = URLSession(configuration: .ephemeral)
        func attempt(_ index: Int, lastError: String) {
            guard index < KoDictionary.remoteURLs.count,
                  let url = URL(string: KoDictionary.remoteURLs[index]) else {
                DispatchQueue.main.async { completion(.failed(lastError)) }
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            session.dataTask(with: request) { body, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let body = body,
                      let text = String(data: body, encoding: .utf8), KoDictionary.isValid(text) else {
                    let reason = error != nil ? "인터넷 연결을 확인해 주세요" : "받은 파일이 사전이 아닙니다"
                    attempt(index + 1, lastError: reason)
                    return
                }
                self.install(text, body: body, completion: completion)
            }.resume()
        }
        attempt(0, lastError: "받을 곳이 없습니다")
    }

    private func install(_ text: String, body: Data, completion: @escaping (DownloadResult) -> Void) {
        let target = KoDictionary.downloadedURL
        // 지금 쓰는 사전과 같으면 바꾸지 않는다
        let current: Data? = {
            if let d = try? Data(contentsOf: target) { return d }
            if let url = Bundle(for: KoDictionary.self).url(forResource: "ko_dict", withExtension: "txt") {
                return try? Data(contentsOf: url)
            }
            return nil
        }()
        lock.lock()
        let hadDictionary = loaded
        lock.unlock()
        if hadDictionary, current == body {
            DispatchQueue.main.async { completion(.alreadyLatest) }
            return
        }
        do {
            try body.write(to: target, options: .atomic)
        } catch {
            DispatchQueue.main.async { completion(.failed("저장하지 못했습니다")) }
            return
        }
        let parsed = KoDictionary.parse(text)
        lock.lock()
        data = parsed
        source = .downloaded(Date())
        loaded = !parsed.groups.isEmpty
        state = .ready
        let count = parsed.groups.count
        lock.unlock()
        DispatchQueue.main.async { completion(.updated(words: count)) }
    }
}
