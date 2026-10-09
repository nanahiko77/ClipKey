import Foundation

/// 한국어 추천 사전 (ko_dict.txt). 학습한 단어와는 따로 둔다.
/// 한 줄이 한 단어와 그 활용형이고, 줄 순서가 자주 쓰는 순서다.
/// 처음 한글 추천이 필요할 때 한 번 읽어 둔다.
final class KoDictionary {
    static let shared = KoDictionary()

    private var groups: [[String]] = []
    /// 첫 글자의 초성별 줄 번호 (한 글자만 쳤거나 초성으로 찾을 때)
    private var byCho: [Int: [Int]] = [:]
    /// 첫 글자별 줄 번호 (두 글자 이상 쳤을 때, 첫 글자는 이미 확정이라 이쪽이 훨씬 좁다)
    private var bySyllable: [Character: [Int]] = [:]
    private var loaded = false

    private init() {}

    private func load() {
        loaded = true
        guard let url = Bundle(for: KoDictionary.self).url(forResource: "ko_dict", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let forms = line.split(separator: " ").map(String.init)
            guard !forms.isEmpty else { continue }
            let index = groups.count
            groups.append(forms)
            var chos = Set<Int>()
            var firsts = Set<Character>()
            for f in forms {
                guard let c = f.first else { continue }
                firsts.insert(c)
                if let p = HangulComposer.parts(c) { chos.insert(p.cho) }
            }
            for c in firsts { bySyllable[c, default: []].append(index) }
            for c in chos { byCho[c, default: []].append(index) }
        }
    }

    /// 입력 중인 글자로 시작하는 단어. 한 단어에서는 활용형을 최대 2개까지만 보여 준다.
    func complete(_ query: String, limit: Int) -> [String] {
        if !loaded { load() }
        guard let first = query.first, limit > 0 else { return [] }
        let list: [Int]
        if query.count >= 2, HangulComposer.parts(first) != nil {
            list = bySyllable[first] ?? []
        } else if let p = HangulComposer.parts(first) {
            list = byCho[p.cho] ?? []
        } else if let i = HangulComposer.choList.firstIndex(of: first) {
            // 초성만 친 경우: ㅅㄱ → 생각
            list = byCho[i] ?? []
        } else {
            return []
        }
        let length = query.count
        var out: [String] = []
        for index in list {
            var perWord = 0
            for form in groups[index] where form.count >= length && form != query {
                guard HangulComposer.matches(query: query, word: form) else { continue }
                out.append(form)
                perWord += 1
                if perWord == 2 || out.count == limit { break }
            }
            if out.count >= limit { break }
        }
        return out
    }
}
