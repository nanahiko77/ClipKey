import Foundation

/// 한글 오타 교정.
/// 1) 자주 틀리는 말 표 (됬→됐, 할께→할게 …)
/// 2) 글자를 자모로 풀어 사전의 바른 말과 비교한다. 자판에서 옆에 붙은 키를 잘못 누른 것은 반만 틀린 것으로 친다.
///    끝에 붙은 조사·어미(게, 데, 을, 는 …)는 떼고 앞부분만 고친 뒤 다시 붙인다. (팔뇨한게 → 필요한 + 게)
/// 사전에 있는 바른 말, 학습한 단어, 직접 넣은 단어(이름, 회사명 등)는 고치지 않는다.
final class KoCorrector {
    static let shared = KoCorrector()

    /// 떼어 볼 조사·어미. 빈 문자열은 떼지 않고 통째로 비교한다는 뜻.
    static let tails = ["", "게", "데", "걸", "거", "이", "가", "을", "를", "은", "는", "도", "에", "만", "요", "고", "지", "랑", "께"]

    struct Candidate {
        let text: String
        let score: Double
        /// 간격을 눌렀을 때 자동으로 바꿔도 될 만큼 확실한지
        let sure: Bool
    }

    static let afterNL: Set<String> = ["게", "거", "걸", "데"]

    /// 바른 말인지 볼 때 떼어 보는 조사·어미 (고칠 때보다 넓게 본다)
    static let knownTails = ["게", "데", "걸", "거", "이", "가", "을", "를", "은", "는", "도", "에", "만", "요", "고", "지", "랑",
                             "으로", "로", "에서", "에게", "한테", "와", "과", "하고", "처럼", "보다", "까지", "부터", "마다",
                             "이나", "나", "야", "아", "의", "께서", "이랑", "이에요", "예요", "이야", "입니다", "이다",
                             "에는", "에도", "에서도", "으로는", "로는", "까지는", "에서는", "이라", "라고", "이라고"]
    /// ㄴ/ㄹ 받침 뒤에 띄어 쓸 말을 붙여 쓴 경우 (할거야, 그런건데, 먹을게요)
    static let afterNLStarts: Set<Character> = ["거", "게", "걸", "건", "데", "것", "겁", "듯", "수", "줄", "때"]

    static func endsWithNL(_ w: String) -> Bool {
        guard let last = w.unicodeScalars.last, last.value >= 0xAC00, last.value <= 0xD7A3 else { return false }
        let jong = (last.value - 0xAC00) % 28
        return jong == 4 || jong == 8          // ㄴ, ㄹ
    }

    private var cacheKey = ""
    private var cacheValue: [Candidate] = []

    // MARK: 자모

    private static let cho: [UInt16] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".utf16)
    private static let jung: [String] = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ", "ㅗㅐ", "ㅗㅣ", "ㅛ", "ㅜ",
                                         "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅠ", "ㅡ", "ㅡㅣ", "ㅣ"]
    private static let jong: [String] = ["", "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ", "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ",
                                         "ㄹㅍ", "ㄹㅎ", "ㅁ", "ㅂ", "ㅂㅅ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    private static let jungUnits: [[UInt16]] = jung.map { Array($0.utf16) }
    private static let jongUnits: [[UInt16]] = jong.map { Array($0.utf16) }

    /// 글자를 자모 줄로 푼다. 겹받침과 겹모음은 나눈다. 한글이 아닌 글자는 그대로 둔다.
    static func jamo(_ word: String) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(word.count * 3)
        for scalar in word.unicodeScalars {
            let v = Int(scalar.value)
            if v >= 0xAC00 && v <= 0xD7A3 {
                let i = v - 0xAC00
                out.append(cho[i / 588])
                out.append(contentsOf: jungUnits[(i % 588) / 28])
                out.append(contentsOf: jongUnits[i % 28])
            } else if v <= 0xFFFF {
                out.append(UInt16(v))
            }
        }
        return out
    }

    static func isHangulWord(_ w: String) -> Bool {
        !w.isEmpty && w.unicodeScalars.allSatisfy { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
    }

    // MARK: 자판 위치 (옆 키를 잘못 누른 것을 가늠하는 데 쓴다)

    private static func table(_ rows: [String], offsets: [Double]) -> [UInt16: (Double, Double)] {
        var t: [UInt16: (Double, Double)] = [:]
        for (r, row) in rows.enumerated() {
            for (c, u) in row.utf16.enumerated() { t[u] = (Double(r), Double(c) + offsets[r]) }
        }
        return t
    }

    /// 두벌식: 키보드 줄마다 반 칸씩 어긋나 있다. 쌍자음과 ㅒ ㅖ 는 같은 키(Shift).
    private static let dubeol: [UInt16: (Double, Double)] = {
        var t = table(["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"], offsets: [0, 0.5, 1.5])
        for (a, b) in [("ㅃ", "ㅂ"), ("ㅉ", "ㅈ"), ("ㄸ", "ㄷ"), ("ㄲ", "ㄱ"), ("ㅆ", "ㅅ"), ("ㅒ", "ㅐ"), ("ㅖ", "ㅔ")] {
            t[a.utf16.first!] = t[b.utf16.first!]
        }
        return t
    }()

    /// 나랏글: 3×4 격자. 획추가·쌍자음으로 만드는 글자는 바탕 글자의 키에 둔다 (ㄴ ㄷ ㅌ 은 같은 키).
    private static let nara: [UInt16: (Double, Double)] = {
        let keys: [(String, Double, Double)] = [
            ("ㄱㅋㄲ", 0, 0), ("ㄴㄷㅌㄸ", 0, 1), ("ㅏㅑㅓㅕㅐㅒㅔㅖ", 0, 2),
            ("ㄹ", 1, 0), ("ㅁㅂㅍㅃ", 1, 1), ("ㅗㅛㅜㅠ", 1, 2),
            ("ㅅㅈㅊㅆㅉ", 2, 0), ("ㅇㅎ", 2, 1), ("ㅣ", 2, 2),
            ("ㅡ", 3, 1),
        ]
        var t: [UInt16: (Double, Double)] = [:]
        for (chars, r, c) in keys { for u in chars.utf16 { t[u] = (r, c) } }
        return t
    }()

    /// 두 자모를 바꿔 친 값. 같으면 0, 옆 키(또는 같은 키의 다른 글자)면 0.5, 아니면 1.
    @inline(__always)
    private static func cost(_ a: UInt16, _ b: UInt16, _ keys: [UInt16: (Double, Double)]) -> Double {
        if a == b { return 0 }
        guard let p = keys[a], let q = keys[b] else { return 1 }
        return abs(p.0 - q.0) <= 1 && abs(p.1 - q.1) <= 1.01 ? 0.5 : 1
    }

    /// 자모 줄 사이의 거리 (지우기·넣기 1, 바꾸기는 cost). cut 을 넘으면 일찍 그만두고 큰 값을 돌려준다.
    private static func distance(_ a: [UInt16], _ b: [UInt16], cut: Double,
                                 keys: [UInt16: (Double, Double)], prev: inout [Double], cur: inout [Double]) -> Double {
        let m = b.count
        if prev.count < m + 1 {
            prev = Array(repeating: 0, count: m + 1)
            cur = Array(repeating: 0, count: m + 1)
        }
        for j in 0...m { prev[j] = Double(j) }
        for i in 1...a.count {
            cur[0] = Double(i)
            var rowBest = cur[0]
            let ai = a[i - 1]
            for j in 1...m {
                let v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost(ai, b[j - 1], keys))
                cur[j] = v
                if v < rowBest { rowBest = v }
            }
            if rowBest > cut { return 99 }
            swap(&prev, &cur)
        }
        return prev[m]
    }

    // MARK: 교정

    /// 바른 말인지: 사전에 있거나, 끝의 조사·어미를 떼면 사전에 있는 말
    static func isKnown(_ w: String, _ d: KoDictionary.Data_) -> Bool {
        if d.known.contains(w) { return true }
        for t in knownTails where w.count > t.count && w.hasSuffix(t) {
            if d.known.contains(String(w.dropLast(t.count))) { return true }
        }
        let chars = Array(w)
        for i in stride(from: chars.count - 1, through: 1, by: -1) where afterNLStarts.contains(chars[i]) {
            let head = String(chars[..<i])
            if endsWithNL(head), d.known.contains(head) { return true }
        }
        return false
    }

    /// 고칠 후보. 앞이 가장 그럴듯한 것. 바른 말이거나 고칠 것이 없으면 빈 배열.
    /// - protected: 고치면 안 되는 단어인지 (학습한 단어, 직접 넣은 단어)
    func corrections(for word: String, hangulLayout: Int, limit: Int = 2,
                     protected: (String) -> Bool) -> [Candidate] {
        guard word.count >= 2, KoCorrector.isHangulWord(word), !protected(word) else { return [] }
        let key = "\(hangulLayout)|\(word)"
        if key == cacheKey { return cacheValue }
        guard let d = KoDictionary.shared.snapshot() else { return [] }
        let result = compute(word, d, keys: hangulLayout == 0 ? KoCorrector.nara : KoCorrector.dubeol, limit: limit)
        cacheKey = key
        cacheValue = result
        return result
    }

    private func compute(_ word: String, _ d: KoDictionary.Data_, keys: [UInt16: (Double, Double)], limit: Int) -> [Candidate] {
        var scores: [String: (Double, Bool)] = [:]
        func offer(_ c: String, _ score: Double, sure: Bool) {
            guard c != word else { return }
            if let old = scores[c], old.0 <= score { return }
            scores[c] = (score, sure)
        }
        func ranked() -> [Candidate] {
            scores.sorted { $0.value.0 < $1.value.0 }.prefix(limit)
                .map { Candidate(text: $0.key, score: $0.value.0, sure: $0.value.1) }
        }

        // 1) 자주 틀리는 말 표: 표에 있으면 확실한 것으로 보고 맨 앞에 둔다
        for (wrong, right) in d.typos where word.contains(wrong) {
            offer(word.replacingOccurrences(of: wrong, with: right), -1, sure: true)
        }
        // ㄹ 받침 뒤의 께/꺼 는 게/거 (할께 → 할게, 먹을꺼 → 먹을 거)
        let chars = Array(word)
        for i in 1..<chars.count where chars[i] == "께" || chars[i] == "꺼" {
            guard let p = HangulComposer.parts(chars[i - 1]), p.jong == 8 else { continue }
            var fixed = chars
            fixed[i] = chars[i] == "께" ? "게" : "거"
            offer(String(fixed), -0.5, sure: true)
        }
        if !scores.isEmpty { return ranked() }

        // 2) 바른 말이면 그대로 둔다
        if KoCorrector.isKnown(word, d) { return [] }

        // 3) 사전의 말과 자모 거리 비교
        var prev: [Double] = []
        var cur: [Double] = []
        for tail in KoCorrector.tails {
            if !tail.isEmpty && !(word.hasSuffix(tail) && word.count > tail.count) { continue }
            let head = tail.isEmpty ? word : String(word.dropLast(tail.count))
            guard head.count >= 2 || (tail.isEmpty && head.count >= 2) else { continue }
            let hj = KoCorrector.jamo(head)
            guard let first = hj.first else { continue }
            // 짧은 말일수록 엄격하게: 자모 6개 이하는 한 군데, 그보다 길면 한 군데 반까지
            let cut = hj.count <= 6 ? 1.0 : 1.5
            // 자동으로 바꾸는 것은 더 엄격하게: 사전에 없는 고유명사·신조어를 엉뚱하게 바꾸지 않도록.
            // 두 글자 이하(자모 6개 이하)는 자동으로 바꾸지 않고 추천만 한다.
            let sureCut = hj.count <= 6 ? -1.0 : 1.0
            for (firstJamo, list) in d.byFirstJamo where KoCorrector.cost(firstJamo, first, keys) <= 0.5 {
                for index in list {
                    let fj = d.flatJamo[index]
                    if abs(fj.count - hj.count) > 2 { continue }
                    let form = d.flat[index]
                    // 활용형 기본꼴(…다) 뒤에는 조사를 붙이지 않는다 (괜찮다요 같은 것 막기)
                    if !tail.isEmpty && form.hasSuffix("다") { continue }
                    // 게·거·걸·데 는 ㄴ/ㄹ 받침 뒤에만 붙는다 (필요한게, 할거, 그런데)
                    if KoCorrector.afterNL.contains(tail), !KoCorrector.endsWithNL(form) { continue }
                    let dist = KoCorrector.distance(hj, fj, cut: cut, keys: keys, prev: &prev, cur: &cur)
                    if dist <= cut {
                        offer(form + tail, dist + Double(index) / 60000, sure: dist <= sureCut)
                    }
                }
            }
        }
        return ranked()
    }

    /// 사전을 새로 받았을 때 지난 결과를 버린다
    func reset() {
        cacheKey = ""
        cacheValue = []
    }
}
