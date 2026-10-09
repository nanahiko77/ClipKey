import UIKit
import AudioToolbox

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
    var spaceRepeat = false            // 간격을 방금 연달아 눌렀는지
    var armedSuggestion: String?       // 길게 눌러 삭제 대기 중인 추천 단어
    var suggestArmTimer: Timer?

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
    var armedBackground: UIColor?
    var armedColor: UIColor?
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
        // 위쪽 여백은 줄이고, 자판과의 사이를 넓힌다
        toolbar.layoutMargins = UIEdgeInsets(top: 1, left: 6, bottom: 14, right: 6)

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
            toolbar.heightAnchor.constraint(equalToConstant: 51),
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
        addBuffer = nil
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

    /// 키를 누를 때의 진동과 소리. 둘 다 이 키보드의 설정을 따른다.
    func haptic() {
        if settings.haptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if settings.keySound {
            AudioServicesPlaySystemSound(1104)     // 시스템 키보드 누름 소리
        }
    }

    // MARK: - 클립보드 수집

    func capture() {
        guard hasFullAccess else { return }
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if pb.hasStrings, let text = pb.string {
            guard let clip = store.add(text) else { return }
            freshClip = clip
        } else if settings.savePhotos, pb.hasImages, let data = pastedImageData(pb) {
            guard store.addImage(data) != nil else { return }
        } else {
            return
        }
        if panel == .clipboard {
            reloadClips()
        } else {
            refreshSuggestions()
        }
    }

    /// 복사된 사진의 원본 데이터. 사진을 펼치지 않고 데이터만 가져온다.
    func pastedImageData(_ pb: UIPasteboard) -> Data? {
        for type in ["public.jpeg", "public.heic", "public.png", "public.tiff"] {
            if let d = pb.data(forPasteboardType: type) { return d }
        }
        return nil
    }

    // MARK: - 글자가 들어가는 곳

    /// 단어 추가 화면에서는 글자를 앱 입력창이 아니라 이 칸에 넣는다. nil 이면 평소 입력.
    var addBuffer: String?
    weak var addField: UILabel?
    var adding: Bool { addBuffer != nil }

    var docBefore: String? {
        if let b = addBuffer { return b }
        return textDocumentProxy.documentContextBeforeInput
    }

    func docInsert(_ s: String) {
        if addBuffer != nil {
            addBuffer?.append(s)
            updateAddField()
        } else {
            textDocumentProxy.insertText(s)
        }
    }

    func docDelete() {
        if let b = addBuffer {
            if !b.isEmpty { addBuffer?.removeLast() }
            updateAddField()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    func updateAddField() {
        addField?.text = (addBuffer ?? "") + "|"
    }

    @objc func startAddWord() {
        resetComposer()
        addBuffer = ""
        shift = .off
        panel = .keys
        rebuild()
    }

    @objc func cancelAddWord() {
        resetComposer()
        addBuffer = nil
        panel = .words
        rebuild()
    }

    /// 직접 넣은 단어는 횟수와 상관없이 바로 추천에 나온다. 숫자와 하이픈도 들어간다.
    @objc func saveAddWord() {
        resetComposer()
        let text = (addBuffer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        addBuffer = nil
        if !text.isEmpty { words.addManual(text) }
        panel = .words
        rebuild()
    }

    // MARK: - 조합 글자와 문서 맞추기

    /// 조합기를 바꾼 뒤 호출한다. 문서의 조합 중 글자를 새 글자로 바꿔 넣는다.
    func apply(commit: String) {
        let newText = composer.text
        for _ in 0..<composing.count { docDelete() }
        let out = commit + newText
        if !out.isEmpty { docInsert(out) }
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
        if let ctx = docBefore, !ctx.hasSuffix(composing) {
            resetComposer()
        }
    }

    func currentWord() -> String {
        guard let ctx = docBefore else { return "" }
        var chars: [Character] = []
        for ch in ctx.reversed() {
            if ch.isLetter || ch.isNumber || ch == "'" {
                chars.append(ch)
            } else if ch == "-", let last = chars.last, last.isNumber {
                chars.append(ch)        // 전화번호처럼 숫자 사이의 하이픈
            } else {
                break
            }
        }
        return String(chars.reversed())
    }

    func replaceWord(_ word: String, with text: String) {
        for _ in 0..<word.count { docDelete() }
        docInsert(text)
    }

    // MARK: - 키 입력

    func handleKey(_ id: String) {
        syncComposer()
        armedSuggestion = nil
        let now = Date()
        let gap = now.timeIntervalSince(lastKeyTime)
        let sameKey = id == lastKeyID
        if !id.hasPrefix("v:") { snapshot = nil }
        spaceRepeat = id == "space" && sameKey && gap < 0.6

        switch id {
        case "space":
            commitWord(separator: " ")
        case "return":
            commitWord(separator: "\n")
        case "shift":
            toggleShift(doubleTap: sameKey && gap < 0.4)
        case "punct":
            if sameKey && gap < 1.2 {
                docDelete()
                punctIndex = (punctIndex + 1) % KeyboardViewController.puncts.count
            } else {
                resetComposer()
                if !adding { words.learn(currentWord()) }
                punctIndex = 0
            }
            docInsert(KeyboardViewController.puncts[punctIndex])
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
            if !adding { words.learn(currentWord()) }
        }
        docInsert(s)
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
        docInsert(s)
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
        // 글자가 완성되는 쪽을 먼저 넣는다. 예: "주" 뒤에서 ㅏㅓ 키를 누르면 "주ㅏ"가 아니라 "줘".
        if composer.jong.isEmpty, !composer.jung.isEmpty,
           HangulComposer.jungChar(composer.jung + [a], nara: true) == nil,
           HangulComposer.jungChar(composer.jung + [b], nara: true) != nil {
            v = b
        }
        if lastKeyID == id, let snap = snapshot {
            for _ in 0..<(composing.count + snap.commit.count) { docDelete() }
            composer = snap.composer
            let t = composer.text
            if !t.isEmpty { docInsert(t) }
            composing = t
            v = snap.vowel == a ? b : a
        }
        let before = composer
        let out = composer.addVowel(v)
        apply(commit: out)
        snapshot = (before, out, v)
    }

    func commitWord(separator: String) {
        if adding {
            // 단어 추가 화면: 줄바꿈은 저장, 간격은 그대로 넣는다
            resetComposer()
            if separator == "\n" { saveAddWord() } else { docInsert(separator) }
            return
        }
        resetComposer()
        // 간격 두 번: 방금 넣은 간격을 "마침표+간격" 또는 "쉼표+간격"으로 바꾼다
        if separator == " ", spaceRepeat, settings.doubleSpace != 0,
           let ctx = docBefore, ctx.hasSuffix(" "), let prev = ctx.dropLast().last,
           prev.isLetter || prev.isNumber {
            docDelete()
            docInsert(settings.doubleSpace == 1 ? ". " : ", ")
            autoCapIfNeeded()
            return
        }
        let word = currentWord()
        if panel == .keys, lang == .english, settings.autoCorrect, separator == " ",
           let fix = correction(for: word) {
            replaceWord(word, with: fix)
            words.learn(fix)
        } else {
            words.learn(word)
        }
        docInsert(separator)
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
        shiftKey?.setImage(Icon.key(name), for: .normal)
    }

    func autoCapIfNeeded() {
        guard !adding, settings.autoCap, lang == .english, panel == .keys, shift == .off else { return }
        let ctx = docBefore ?? ""
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
            docDelete()
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

    /// 입력창의 글자를 전부 지운다. 커서 뒤쪽 글자도 지우려고 먼저 커서를 끝으로 옮긴다.
    func deleteAll() {
        stopDelete()
        resetComposer()
        if adding {
            addBuffer = ""
            updateAddField()
            return
        }
        if let after = textDocumentProxy.documentContextAfterInput, !after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.deleteAllPass(0)
        }
    }

    /// 키보드는 커서 앞 글자를 한 번에 일부만 볼 수 있어서, 남은 것이 없을 때까지 나눠 지운다
    func deleteAllPass(_ pass: Int) {
        guard pass < 40, let before = docBefore, !before.isEmpty else {
            lastKeyID = "⌫"
            refreshSuggestions()
            return
        }
        for _ in 0..<before.count { docDelete() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.deleteAllPass(pass + 1)
        }
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

    @objc func hideKeyboard() {
        resetComposer()
        dismissKeyboard()
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
        guard !adding, panel == .keys || panel == .symbols else { return }
        suggestStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestItems = []

        if let clip = freshClip {
            let chip = clipChip(clip)
            suggestStack.addArrangedSubview(chip)
            suggestStack.setCustomSpacing(4, after: chip)
        }
        // 숫자·기호 화면에서도 추천한다 (등록해 둔 전화번호 등)
        let word = currentWord()
        guard !word.isEmpty else { return }

        var items: [(text: String, kind: SuggestKind)] = []
        func add(_ t: String, _ k: SuggestKind) {
            guard items.count < 6, t != word, !items.contains(where: { $0.text == t }) else { return }
            items.append((t, k))
        }

        // 순서: 직접 넣은 단어 → 맞춤법(교정, 사전) → 자주 친 단어 → 고정한 클립
        let matched = words.matches(word)
        for w in matched where words.isManual(w) { add(w, .learned) }
        if lang == .english, settings.autoCorrect, let fix = correction(for: word) {
            add(fix, .correction)
            add("\u{201C}\(word)\u{201D}", .original)
        }
        let language: String? = lang == .english ? "en_US" : koLanguage
        if let language = language, word.allSatisfy({ $0.isLetter }) {
            let range = NSRange(location: 0, length: (word as NSString).length)
            let found = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
            for c in found.prefix(3) { add(c, .dict) }
        }
        for w in matched where !words.isManual(w) { add(w, .learned) }
        let lower = word.lowercased()
        for c in store.clips where c.pinned && c.text.count > word.count && c.text.lowercased().hasPrefix(lower) {
            add(c.text, .pinned)
        }

        var previousPlain = false
        for (i, item) in items.enumerated() {
            var title = item.text.replacingOccurrences(of: "\n", with: " ")
            if title.count > 14 { title = String(title.prefix(14)) + "…" }
            let isChip = item.kind == .learned || item.kind == .pinned
            let armed = item.kind == .learned && item.text == armedSuggestion
            let b = UIButton(type: .system)
            b.tag = i
            b.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            if isChip {
                // 내가 등록했거나 자주 친 단어는 별표, 고정한 클립은 압정이 붙은 반투명 칩.
                // 길게 눌러 삭제 대기가 되면 빨간 "단어 ×" 칩으로 바뀐다.
                let iconName = armed ? "xmark" : (item.kind == .learned ? "star" : "pin.fill")
                b.setImage(Icon.image(iconName, size: 13, line: armed ? 2.5 : 1.75), for: .normal)
                b.setTitle(armed ? title + " " : " " + title, for: .normal)
                if armed { b.semanticContentAttribute = .forceRightToLeft }
                b.titleLabel?.font = armed ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 14)
                b.tintColor = armed ? theme.onDanger : theme.muted
                b.setTitleColor(armed ? theme.onDanger : theme.text, for: .normal)
                b.backgroundColor = armed ? theme.danger : theme.key.withAlphaComponent(isDark ? 0.35 : 0.6)
                b.layer.cornerRadius = 15
                b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 10)
                b.heightAnchor.constraint(equalToConstant: 30).isActive = true
                if item.kind == .learned {
                    b.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(suggestionLongPressed(_:))))
                }
                previousPlain = false
            } else {
                if previousPlain {
                    let line = UIView()
                    line.backgroundColor = theme.divider
                    line.widthAnchor.constraint(equalToConstant: 1).isActive = true
                    line.heightAnchor.constraint(equalToConstant: 20).isActive = true
                    suggestStack.addArrangedSubview(line)
                }
                b.setTitle(title, for: .normal)
                let strong = item.kind == .correction
                b.titleLabel?.font = strong ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 15)
                b.setTitleColor(strong ? theme.text : theme.muted, for: .normal)
                b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                previousPlain = true
            }
            suggestStack.addArrangedSubview(b)
            suggestStack.setCustomSpacing(isChip ? 4 : 0, after: b)
        }
        suggestItems = items
        suggestScroll.setContentOffset(.zero, animated: false)
    }

    func clipChip(_ clip: Clip) -> UIButton {
        let b = UIButton(type: .system)
        var title = clip.text.replacingOccurrences(of: "\n", with: " ")
        if title.count > 9 { title = String(title.prefix(9)) + "…" }
        b.setTitle(" " + title, for: .normal)
        b.setImage(Icon.image("clipboard", size: 14, line: 2), for: .normal)
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
        docInsert(clip.text)
        freshClip = nil
        refreshSuggestions()
    }

    @objc func suggestionTapped(_ sender: UIButton) {
        guard sender.tag < suggestItems.count else { return }
        let item = suggestItems[sender.tag]
        if item.kind == .learned, item.text == armedSuggestion {
            // 삭제 대기 중인 칩을 한 번 더 누르면 그 단어를 지운다
            suggestArmTimer?.invalidate()
            armedSuggestion = nil
            words.remove(item.text)
            refreshSuggestions()
            return
        }
        let word = currentWord()
        resetComposer()
        switch item.kind {
        case .original:
            // 고치지 않고 친 그대로 쓴다. 다음부터는 오타로 보지 않는다.
            skipCorrection = word
            words.learn(word, force: true)
            docInsert(" ")
        case .pinned:
            replaceWord(word, with: item.text)
        default:
            replaceWord(word, with: item.text)
            words.learn(item.text)
            if lang == .english { docInsert(" ") }
        }
        lastKeyID = "suggest"
        refreshSuggestions()
    }

    /// 별표 칩을 길게 누르면 삭제 대기 상태가 된다. 3초 안에 다시 누르면 지워진다.
    @objc func suggestionLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view as? UIButton, b.tag < suggestItems.count else { return }
        armedSuggestion = suggestItems[b.tag].text
        refreshSuggestions()
        suggestArmTimer?.invalidate()
        suggestArmTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.armedSuggestion = nil
            self?.refreshSuggestions()
        }
    }
}
