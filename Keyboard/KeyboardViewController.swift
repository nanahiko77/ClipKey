import UIKit

enum SuggestKind { case correction, original, learned, pinned, dict }

/// 키보드 본체: 상태, 입력 처리, 추천 단어.
/// 자판 배치는 KeyboardLayouts.swift, 패널은 KeyboardPanels.swift 에 있다.
final class KeyboardViewController: UIInputViewController {
    enum Panel { case keys, symbols, clipboard, settings, words }
    enum Lang { case hangul, english }
    enum Shift { case off, once, locked }

    static let dubeolShift: [Character: Character] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ",
    ]
    static let puncts = [".", ",", "?", "!"]

    let store = ClipStore()
    let words = WordStore()
    let settings = Settings.shared
    let checker = UITextChecker()
    lazy var koLanguage: String? = UITextChecker.availableLanguages.first { $0.hasPrefix("ko") }

    var theme = Theme.light
    var isDark = false

    var panel: Panel = .keys
    var lang: Lang = .hangul
    var shift: Shift = .off
    var symbolPage = 0

    // 한글 조합
    var composer = HangulComposer()
    var composing = ""                 // 문서에 들어가 있는 조합 중 글자
    var snapshot: (composer: HangulComposer, commit: String, vowel: Character)?
    var lastKeyID = ""
    var lastKeyTime = Date.distantPast
    var punctIndex = 0
    var skipCorrection: String?

    // 클립보드 수집
    var freshClip: Clip?
    var lastChangeCount = -1
    var pasteTimer: Timer?
    var deleteTimer: Timer?
    var deleteTicks = 0

    // 화면
    let toolbar = UIStackView()
    let divider = UIView()
    let keyArea = UIView()
    let suggestScroll = UIScrollView()
    let suggestStack = UIStackView()
    var suggestItems: [(text: String, kind: SuggestKind)] = []
    var letterKeys: [KeyButton] = []
    weak var shiftKey: KeyButton?

    // 패널 상태
    var clipItems: [Clip] = []
    var confirmingID: UUID?
    weak var clipTable: UITableView?
    var undoClip: Clip?
    weak var undoBar: UIView?
    var undoTimer: Timer?
    var armedButton: UIButton?
    var armedTitle: String?
    var armTimer: Timer?
    var wordList: [String] = []
    var previewClip: Clip?
    weak var previewView: UIView?

    // MARK: - 생명주기

    override func viewDidLoad() {
        super.viewDidLoad()

        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = UILayoutPriority(999)
        height.isActive = true

        toolbar.axis = .horizontal
        toolbar.spacing = 4
        toolbar.alignment = .center
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

        suggestStack.axis = .horizontal
        suggestStack.alignment = .center
        suggestStack.spacing = 0
        suggestStack.translatesAutoresizingMaskIntoConstraints = false
        suggestScroll.showsHorizontalScrollIndicator = false
        suggestScroll.addSubview(suggestStack)
        suggestScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        suggestScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            suggestScroll.heightAnchor.constraint(equalToConstant: 36),
            suggestStack.topAnchor.constraint(equalTo: suggestScroll.contentLayoutGuide.topAnchor),
            suggestStack.bottomAnchor.constraint(equalTo: suggestScroll.contentLayoutGuide.bottomAnchor),
            suggestStack.leadingAnchor.constraint(equalTo: suggestScroll.contentLayoutGuide.leadingAnchor),
            suggestStack.trailingAnchor.constraint(equalTo: suggestScroll.contentLayoutGuide.trailingAnchor),
            suggestStack.heightAnchor.constraint(equalTo: suggestScroll.frameLayoutGuide.heightAnchor),
        ])

        for v in [toolbar, divider, keyArea] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 45),
            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            keyArea.topAnchor.constraint(equalTo: divider.bottomAnchor),
            keyArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capture()
        rebuild()
        autoCapIfNeeded()
        pasteTimer?.invalidate()
        pasteTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.capture()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pasteTimer?.invalidate()
        pasteTimer = nil
        stopDelete()
        resetComposer()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let was = isDark
        resolveTheme()
        if was != isDark {
            rebuild()
        } else {
            refreshSuggestions()
        }
    }

    // MARK: - 화면 다시 그리기

    func resolveTheme() {
        let systemDark = textDocumentProxy.keyboardAppearance == .dark
            || UIScreen.main.traitCollection.userInterfaceStyle == .dark
        switch settings.themeMode {
        case 1: isDark = false
        case 2: isDark = true
        default: isDark = systemDark
        }
        theme = isDark ? Theme.dark : Theme.light
        view.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    func rebuild() {
        resolveTheme()
        disarm()
        view.backgroundColor = theme.bg
        divider.backgroundColor = theme.divider
        buildToolbar()
        buildBody()
        refreshSuggestions()
    }

    func haptic() {
        guard settings.haptic else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - 클립보드 수집

    func capture() {
        guard hasFullAccess else { return }
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard pb.hasStrings, let text = pb.string else { return }
        guard let clip = store.add(text) else { return }
        freshClip = clip
        if panel == .clipboard {
            reloadClips()
        } else {
            refreshSuggestions()
        }
    }

    // MARK: - 조합 글자와 문서 맞추기

    /// 조합기를 바꾼 뒤 호출한다. 문서의 조합 중 글자를 새 글자로 바꿔 넣는다.
    func apply(commit: String) {
        let newText = composer.text
        for _ in 0..<composing.count { textDocumentProxy.deleteBackward() }
        let out = commit + newText
        if !out.isEmpty { textDocumentProxy.insertText(out) }
        composing = newText
    }

    /// 조합을 끝낸다. 문서의 글자는 그대로 둔다.
    func resetComposer() {
        composer = HangulComposer()
        composing = ""
        snapshot = nil
    }

    /// 커서를 직접 옮겼거나 다른 곳을 눌렀으면 조합을 끊는다
    func syncComposer() {
        guard !composing.isEmpty else { return }
        if let ctx = textDocumentProxy.documentContextBeforeInput, !ctx.hasSuffix(composing) {
            resetComposer()
        }
    }

    func currentWord() -> String {
        guard let ctx = textDocumentProxy.documentContextBeforeInput else { return "" }
        var chars: [Character] = []
        for ch in ctx.reversed() {
            if ch.isLetter || ch == "'" { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    func replaceWord(_ word: String, with text: String) {
        for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(text)
    }

    // MARK: - 키 입력

    func handleKey(_ id: String) {
        syncComposer()
        let now = Date()
        let gap = now.timeIntervalSince(lastKeyTime)
        let sameKey = id == lastKeyID
        if !id.hasPrefix("v:") { snapshot = nil }

        switch id {
        case "space":
            commitWord(separator: " ")
        case "return":
            commitWord(separator: "\n")
        case "shift":
            toggleShift(doubleTap: sameKey && gap < 0.4)
        case "punct":
            if sameKey && gap < 1.2 {
                textDocumentProxy.deleteBackward()
                punctIndex = (punctIndex + 1) % KeyboardViewController.puncts.count
            } else {
                resetComposer()
                words.learn(currentWord())
                punctIndex = 0
            }
            textDocumentProxy.insertText(KeyboardViewController.puncts[punctIndex])
        case "stroke":
            composer.nara = true
            let out = composer.transformLast(HangulComposer.strokeTable)
            apply(commit: out)
        case "double":
            composer.nara = true
            let out = composer.transformLast(HangulComposer.doubleTable)
            apply(commit: out)
        case "v:ㅏㅓ":
            naraVowel(id, "ㅏ", "ㅓ")
        case "v:ㅗㅜ":
            naraVowel(id, "ㅗ", "ㅜ")
        case "sympage":
            symbolPage = 1 - symbolPage
            buildBody()
        default:
            guard id.count == 1, let ch = id.first else { break }
            if panel == .symbols || !ch.isLetter {
                plain(String(ch))
            } else if lang == .english {
                inputEnglish(ch)
            } else {
                inputJamo(ch)
            }
        }

        lastKeyID = id
        lastKeyTime = now
        refreshSuggestions()
    }

    /// 조합과 상관없는 글자(숫자, 기호)를 넣는다
    func plain(_ s: String) {
        resetComposer()
        if let f = s.first, !f.isLetter, !f.isNumber {
            words.learn(currentWord())
        }
        textDocumentProxy.insertText(s)
    }

    /// 꾹 눌러서 나온 보조 글자
    func insertPlain(_ s: String) {
        syncComposer()
        plain(s)
        lastKeyID = s
        lastKeyTime = Date()
        refreshSuggestions()
    }

    func inputEnglish(_ ch: Character) {
        let s = shift == .off ? String(ch) : String(ch).uppercased()
        textDocumentProxy.insertText(s)
        if shift == .once {
            shift = .off
            updateLetterTitles()
        }
    }

    func inputJamo(_ ch: Character) {
        composer.nara = settings.hangulLayout == 0
        var c = ch
        if shift != .off, let s = KeyboardViewController.dubeolShift[c] { c = s }
        let isVowel = HangulComposer.jungList.contains(c)
        let out = isVowel ? composer.addVowel(c) : composer.addConsonant(c)
        apply(commit: out)
        if shift == .once {
            shift = .off
            updateLetterTitles()
        }
    }

    /// 나랏글 모음 키: 같은 키를 다시 누르면 앞의 입력을 되돌리고 다른 모음을 넣는다
    func naraVowel(_ id: String, _ a: Character, _ b: Character) {
        composer.nara = true
        var v = a
        if lastKeyID == id, let snap = snapshot {
            for _ in 0..<(composing.count + snap.commit.count) { textDocumentProxy.deleteBackward() }
            composer = snap.composer
            let t = composer.text
            if !t.isEmpty { textDocumentProxy.insertText(t) }
            composing = t
            v = snap.vowel == a ? b : a
        }
        let before = composer
        let out = composer.addVowel(v)
        apply(commit: out)
        snapshot = (before, out, v)
    }

    func commitWord(separator: String) {
        resetComposer()
        let word = currentWord()
        if panel == .keys, lang == .english, settings.autoCorrect, separator == " ",
           let fix = correction(for: word) {
            replaceWord(word, with: fix)
            words.learn(fix)
        } else {
            words.learn(word)
        }
        textDocumentProxy.insertText(separator)
        autoCapIfNeeded()
    }

    /// 영문 오타면 고칠 단어를 돌려준다
    func correction(for word: String) -> String? {
        guard word.count >= 2, word != skipCorrection, !words.knows(word) else { return nil }
        guard word.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
        guard miss.location != NSNotFound else { return nil }
        return checker.guesses(forWordRange: range, in: word, language: "en_US")?.first
    }

    func toggleShift(doubleTap: Bool) {
        if lang == .english, doubleTap, shift == .once {
            shift = .locked
        } else {
            shift = shift == .off ? .once : .off
        }
        updateLetterTitles()
    }

    func updateLetterTitles() {
        for k in letterKeys {
            if lang == .english {
                k.setTitle(shift == .off ? k.id : k.id.uppercased(), for: .normal)
            } else if let ch = k.id.first {
                let shifted = shift != .off ? KeyboardViewController.dubeolShift[ch] : nil
                k.setTitle(String(shifted ?? ch), for: .normal)
            }
        }
        let name = shift == .locked ? "capslock.fill" : (shift == .once ? "shift.fill" : "shift")
        shiftKey?.setImage(UIImage(systemName: name), for: .normal)
    }

    func autoCapIfNeeded() {
        guard settings.autoCap, lang == .english, panel == .keys, shift == .off else { return }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = ctx.trimmingCharacters(in: .whitespaces)
        let startOfSentence = trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("!")
            || trimmed.hasSuffix("?") || trimmed.hasSuffix("\n")
        let atBoundary = ctx.isEmpty || ctx.hasSuffix(" ") || ctx.hasSuffix("\n")
        if startOfSentence && atBoundary {
            shift = .once
            updateLetterTitles()
        }
    }

    // MARK: - 지우기 (누르고 있으면 연속)

    func backspaceOnce() {
        syncComposer()
        snapshot = nil
        if composer.backspace() {
            apply(commit: "")
        } else {
            textDocumentProxy.deleteBackward()
        }
        lastKeyID = "⌫"
        refreshSuggestions()
    }

    func startDelete() {
        backspaceOnce()
        deleteTicks = 0
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.deleteTicks += 1
            if self.deleteTicks > 4 { self.backspaceOnce() }
        }
    }

    func stopDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    // MARK: - 툴바 동작

    @objc func langTapped() {
        resetComposer()
        if panel == .symbols {
            panel = .keys
        } else {
            lang = lang == .hangul ? .english : .hangul
        }
        shift = .off
        rebuild()
        autoCapIfNeeded()
    }

    @objc func numTapped() {
        resetComposer()
        panel = panel == .symbols ? .keys : .symbols
        symbolPage = 0
        rebuild()
    }

    @objc func clipTapped() {
        resetComposer()
        confirmingID = nil
        panel = .clipboard
        rebuild()
    }

    @objc func backToKeys() {
        panel = .keys
        rebuild()
    }

    @objc func toHangul() {
        lang = .hangul
        shift = .off
        panel = .keys
        rebuild()
    }

    @objc func toEnglish() {
        lang = .english
        shift = .off
        panel = .keys
        rebuild()
        autoCapIfNeeded()
    }

    @objc func openSettings() {
        panel = .settings
        rebuild()
    }

    @objc func cursorLeft() {
        resetComposer()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
    }

    @objc func cursorRight() {
        resetComposer()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
    }

    // MARK: - 추천 단어

    func refreshSuggestions() {
        guard panel == .keys || panel == .symbols else { return }
        suggestStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestItems = []

        if let clip = freshClip {
            suggestStack.addArrangedSubview(clipChip(clip))
        }
        guard panel == .keys else { return }
        let word = currentWord()
        guard !word.isEmpty else { return }

        var items: [(text: String, kind: SuggestKind)] = []
        func add(_ t: String, _ k: SuggestKind) {
            guard items.count < 6, t != word, !items.contains(where: { $0.text == t }) else { return }
            items.append((t, k))
        }

        if lang == .english, settings.autoCorrect, let fix = correction(for: word) {
            add(fix, .correction)
            add("\u{201C}\(word)\u{201D}", .original)
        }
        for w in words.matches(word) { add(w, .learned) }
        let lower = word.lowercased()
        for c in store.clips where c.pinned && c.text.count > word.count && c.text.lowercased().hasPrefix(lower) {
            add(c.text, .pinned)
        }
        let language: String? = lang == .english ? "en_US" : koLanguage
        if let language = language {
            let range = NSRange(location: 0, length: (word as NSString).length)
            let found = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
            for c in found.prefix(4) { add(c, .dict) }
        }

        for (i, item) in items.enumerated() {
            if i > 0 || freshClip != nil {
                let line = UIView()
                line.backgroundColor = theme.divider
                line.widthAnchor.constraint(equalToConstant: 1).isActive = true
                line.heightAnchor.constraint(equalToConstant: 20).isActive = true
                suggestStack.addArrangedSubview(line)
            }
            let b = UIButton(type: .system)
            var title = item.text.replacingOccurrences(of: "\n", with: " ")
            if title.count > 14 { title = String(title.prefix(14)) + "…" }
            b.setTitle(title, for: .normal)
            let strong = item.kind == .correction
            b.titleLabel?.font = strong ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 15)
            b.setTitleColor(strong ? theme.text : theme.muted, for: .normal)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            b.tag = i
            b.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            if item.kind == .learned {
                b.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(suggestionLongPressed(_:))))
            }
            suggestStack.addArrangedSubview(b)
        }
        suggestItems = items
        suggestScroll.setContentOffset(.zero, animated: false)
    }

    func clipChip(_ clip: Clip) -> UIButton {
        let b = UIButton(type: .system)
        var title = clip.text.replacingOccurrences(of: "\n", with: " ")
        if title.count > 9 { title = String(title.prefix(9)) + "…" }
        b.setTitle(" " + title, for: .normal)
        b.setImage(UIImage(systemName: "doc.on.clipboard",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.tintColor = theme.text
        b.setTitleColor(theme.text, for: .normal)
        b.backgroundColor = theme.key
        b.layer.cornerRadius = 15
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        b.accessibilityLabel = "방금 복사한 내용 붙여넣기"
        b.addTarget(self, action: #selector(chipTapped), for: .touchUpInside)
        return b
    }

    @objc func chipTapped() {
        guard let clip = freshClip else { return }
        resetComposer()
        textDocumentProxy.insertText(clip.text)
        freshClip = nil
        refreshSuggestions()
    }

    @objc func suggestionTapped(_ sender: UIButton) {
        guard sender.tag < suggestItems.count else { return }
        let item = suggestItems[sender.tag]
        let word = currentWord()
        resetComposer()
        switch item.kind {
        case .original:
            // 고치지 않고 친 그대로 쓴다. 다음부터는 오타로 보지 않는다.
            skipCorrection = word
            words.learn(word, force: true)
            textDocumentProxy.insertText(" ")
        case .pinned:
            replaceWord(word, with: item.text)
        default:
            replaceWord(word, with: item.text)
            words.learn(item.text)
            if lang == .english { textDocumentProxy.insertText(" ") }
        }
        lastKeyID = "suggest"
        refreshSuggestions()
    }

    /// 학습한 단어를 길게 누르면 그 단어만 지운다
    @objc func suggestionLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view as? UIButton, b.tag < suggestItems.count else { return }
        words.remove(suggestItems[b.tag].text)
        refreshSuggestions()
    }
}
