import Foundation

/// 한글 조합기. 두벌식과 나랏글이 같이 쓴다.
/// 초성 1개, 중성 낱자 1~3개, 종성 낱자 0~2개를 들고 있다가 한 글자로 합친다.
struct HangulComposer {
    static let choList: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let jungList: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let jongList: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    static let jongPairs: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]
    static let jungPairs: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    /// 나랏글에서만 쓰는 모음 결합 (ㅣ를 더해 만드는 모음)
    static let naraJungPairs: [String: Character] = [
        "ㅏㅣ": "ㅐ", "ㅓㅣ": "ㅔ", "ㅑㅣ": "ㅒ", "ㅕㅣ": "ㅖ", "ㅗㅏㅣ": "ㅙ", "ㅜㅓㅣ": "ㅞ",
    ]
    /// 나랏글 획추가
    static let strokeTable: [Character: Character] = [
        "ㄱ": "ㅋ", "ㅋ": "ㄱ", "ㄴ": "ㄷ", "ㄷ": "ㅌ", "ㅌ": "ㄴ", "ㅁ": "ㅂ", "ㅂ": "ㅍ", "ㅍ": "ㅁ",
        "ㅅ": "ㅈ", "ㅈ": "ㅊ", "ㅊ": "ㅅ", "ㅇ": "ㅎ", "ㅎ": "ㅇ",
        "ㅏ": "ㅑ", "ㅑ": "ㅏ", "ㅓ": "ㅕ", "ㅕ": "ㅓ", "ㅗ": "ㅛ", "ㅛ": "ㅗ", "ㅜ": "ㅠ", "ㅠ": "ㅜ",
    ]
    /// 나랏글 쌍자음
    static let doubleTable: [Character: Character] = [
        "ㄱ": "ㄲ", "ㄲ": "ㄱ", "ㄷ": "ㄸ", "ㄸ": "ㄷ", "ㅂ": "ㅃ", "ㅃ": "ㅂ",
        "ㅅ": "ㅆ", "ㅆ": "ㅅ", "ㅈ": "ㅉ", "ㅉ": "ㅈ",
    ]

    var nara = false
    var cho: Character?
    var jung: [Character] = []
    var jong: [Character] = []
    /// 받침이 못 돼서 방금 밀려난 앞 글자. 나랏글은 ㅎ·ㅈ·ㅌ 을 획추가로 만들기 때문에,
    /// "찬" + ㅇ(→획추가 ㅎ) 처럼 바뀐 뒤에야 겹받침(ㄶ)이 되는 경우 앞 글자로 되돌려 붙인다.
    private var prev: (cho: Character?, jung: [Character], jong: [Character])?
    /// 앞 글자로 되돌려 붙였으면 true. 화면에서 앞 글자를 지우고 다시 그려야 한다.
    var reclaimed = false

    var isEmpty: Bool { cho == nil && jung.isEmpty }

    static func jungChar(_ parts: [Character], nara: Bool) -> Character? {
        if parts.isEmpty { return nil }
        if parts.count == 1 { return parts[0] }
        let key = String(parts)
        if let v = jungPairs[key] { return v }
        return nara ? naraJungPairs[key] : nil
    }

    static func jongChar(_ parts: [Character]) -> Character? {
        if parts.count == 1 { return jongList.contains(parts[0]) ? parts[0] : nil }
        if parts.count == 2 { return jongPairs[String(parts)] }
        return nil
    }

    /// 지금 조합 중인 글자
    var text: String {
        let vowel = HangulComposer.jungChar(jung, nara: nara)
        guard let c = cho else {
            if let v = vowel { return String(v) }
            return ""
        }
        guard let v = vowel,
              let ci = HangulComposer.choList.firstIndex(of: c),
              let vi = HangulComposer.jungList.firstIndex(of: v) else { return String(c) }
        var ji = 0
        if let j = HangulComposer.jongChar(jong), let idx = HangulComposer.jongList.firstIndex(of: j) {
            ji = idx + 1
        }
        let value = UInt32(0xAC00 + (ci * 21 + vi) * 28 + ji)
        guard let scalar = UnicodeScalar(value) else { return String(c) }
        return String(Character(scalar))
    }

    /// 조합을 끝내고 그 글자를 돌려준다
    mutating func flush() -> String {
        let t = text
        cho = nil
        jung = []
        jong = []
        return t
    }

    /// 자음 입력. 확정되어 밀려난 글자를 돌려준다.
    mutating func addConsonant(_ c: Character) -> String {
        prev = nil
        if jung.isEmpty {
            let out = cho == nil ? "" : flush()
            cho = c
            return out
        }
        if cho == nil {
            let out = flush()
            cho = c
            return out
        }
        if HangulComposer.jongChar(jong + [c]) != nil {
            jong.append(c)
            return ""
        }
        let saved = (cho: cho, jung: jung, jong: jong)
        let out = flush()
        cho = c
        prev = saved
        return out
    }

    /// 모음 입력. 확정되어 밀려난 글자를 돌려준다.
    mutating func addVowel(_ v: Character) -> String {
        prev = nil
        if !jong.isEmpty {
            let moved = jong.removeLast()      // 받침이 다음 글자의 초성으로 넘어간다
            let out = flush()
            cho = moved
            jung = [v]
            return out
        }
        if jung.isEmpty {
            jung = [v]
            return ""
        }
        if HangulComposer.jungChar(jung + [v], nara: nara) != nil {
            jung.append(v)
            return ""
        }
        let out = flush()
        jung = [v]
        return out
    }

    /// 낱자 하나를 지운다. 지울 것이 없으면 false.
    mutating func backspace() -> Bool {
        prev = nil
        if !jong.isEmpty { jong.removeLast(); return true }
        if !jung.isEmpty { jung.removeLast(); return true }
        if cho != nil { cho = nil; return true }
        return false
    }

    /// 마지막 낱자를 표에 따라 바꾼다 (나랏글 획추가, 쌍자음)
    mutating func transformLast(_ table: [Character: Character]) -> String {
        if let last = jong.last {
            guard let n = table[last] else { return "" }
            var trial = jong
            trial[trial.count - 1] = n
            if HangulComposer.jongChar(trial) != nil {
                jong = trial
                return ""
            }
            jong.removeLast()                  // 받침이 될 수 없으면 다음 글자의 초성이 된다
            let out = flush()
            cho = n
            return out
        }
        if let last = jung.last {
            guard let n = table[last] else { return "" }
            var trial = jung
            trial[trial.count - 1] = n
            if HangulComposer.jungChar(trial, nara: nara) != nil { jung = trial }
            return ""
        }
        if let c = cho, let n = table[c] {
            cho = n
            // 앞 글자 받침과 겹받침이 되면 앞 글자로 붙인다 (찬+ㅎ → 찮, 안+ㅈ → 앉, 알+ㅌ → 앑)
            if jung.isEmpty, jong.isEmpty, let p = prev, p.cho != nil, !p.jung.isEmpty,
               HangulComposer.jongChar(p.jong + [n]) != nil {
                cho = p.cho
                jung = p.jung
                jong = p.jong + [n]
                prev = nil
                reclaimed = true
            }
        }
        return ""
    }

    // MARK: - 추천 단어 비교용

    static func isJamo(_ ch: Character) -> Bool {
        guard let s = ch.unicodeScalars.first else { return false }
        return s.value >= 0x3131 && s.value <= 0x3163
    }

    static func parts(_ ch: Character) -> (cho: Int, jung: Int, jong: Int)? {
        guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first,
              s.value >= 0xAC00, s.value <= 0xD7A3 else { return nil }
        let idx = Int(s.value - 0xAC00)
        return (idx / 588, (idx % 588) / 28, idx % 28)
    }

    /// 입력한 받침(typed)에서 단어 쪽 받침(kept)을 남기고 다음 글자로 넘어갈 자음. 없으면 nil.
    static func movedJong(_ typed: Int, keeping kept: Int) -> Character? {
        guard typed > 0 else { return nil }
        let t = jongList[typed - 1]
        if kept == 0 { return choList.contains(t) ? t : nil }
        let k = jongList[kept - 1]
        guard let pair = jongPairs.first(where: { $0.value == t })?.key, pair.first == k else { return nil }
        return pair.last
    }

    /// 입력 중인 글자가 단어의 앞부분과 맞는지. 초성만 쳐도 맞고, 마지막 글자는 받침이 없어도 맞는다.
    static func matches(query: String, word: String) -> Bool {
        let q = Array(query)
        let w = Array(word)
        guard !q.isEmpty, q.count <= w.count else { return false }
        for i in 0..<q.count {
            if q[i] == w[i] { continue }
            if String(q[i]).lowercased() == String(w[i]).lowercased() { continue }
            guard let d = parts(w[i]) else { return false }
            if choList.contains(q[i]) {
                if choList[d.cho] == q[i] { continue }
                return false
            }
            if i == q.count - 1, let dq = parts(q[i]), dq.cho == d.cho, dq.jung == d.jung {
                if dq.jong == 0 { continue }
                // 받침이 다음 글자 초성으로 넘어갈 자리: 갑 → 가방, 닭 → 달걀
                if i + 1 < w.count, let next = parts(w[i + 1]), let moved = movedJong(dq.jong, keeping: d.jong),
                   choList[next.cho] == moved { continue }
            }
            return false
        }
        return true
    }
}
