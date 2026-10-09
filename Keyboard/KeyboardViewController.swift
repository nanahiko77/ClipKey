import UIKit
import AudioToolbox

enum SuggestKind { case correction, original, learned, pinned, dict, next, replacement, email }

/// 앱이 알려 주는 입력 칸 종류. 칸에 맞춰 자판을 바꾼다.
enum FieldKind { case normal, number, email, url }

/// 키보드 본체: 상태, 입력 처리, 추천 단어.
/// 자판 배치는 KeyboardLayouts.swift, 패널은 KeyboardPanels.swift 에 있다.
final class KeyboardViewController: UIInputViewController {
    enum Panel { case keys, symbols, numpad, emoji, clipboard, settings, words, toolbarEdit }
    enum Lang { case hangul, english }
    enum Shift { case off, once, locked }

    static let dubeolShift: [Character: Character] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ",
    ]
    static let puncts = [".", ",", "?", "!"]

    let store = ClipStore()
    let words = WordStore()
    let nextWords = NextWordStore()
    let settings = Settings.shared
    let checker = UITextChecker()
    let stickers = StickerStore()
    /// 아이폰 설정 > 일반 > 키보드 > 텍스트 대치 (줄임말 → 바꿀 글)
    var textReplacements: [String: String] = [:]

    // 입력 칸 종류
    var fieldKind: FieldKind = .normal
    var fieldSignature = ""
    /// 줄바꿈 키 이름 (검색, 이동, 보내기 …). nil 이면 줄바꿈 모양.
    var returnTitle: String?
    var langBeforeField: Lang?

    // 추천 줄의 알림 + 되돌리기 (전체 삭제, 단어 밀어 지우기, 추천에서 빼기)
    var notice: (text: String, action: () -> Void)?
    var noticeTimer: Timer?
    // 클립보드·단어 관리 아래 알림 줄의 되돌리기
    var undoAction: (() -> Void)?
    var deletedAllText = ""

    // 간격 키로 커서 옮기는 중
    var cursorDragging = false
    weak var spaceKeyRef: KeyButton?
    lazy var selectionFeedback = UISelectionFeedbackGenerator()

    // 이모지 패널
    var emojiTab = 0                   // 0 이모지, 1 스티커
    var emojiCategory = 0              // 0 자주 쓰는
    var stickerPack = 0
    var emojiGrid: GridPanel?
    var pickerGrid: GridPanel?
    var pickerClips: [Clip] = []
    var pickerPack: UUID?
    weak var pickerAddButton: UIButton?
    weak var pickerView: UIView?
    var previewSticker: String?
    var toolbarHeight: NSLayoutConstraint?
    var viewHeight: NSLayoutConstraint?
    var isLandscape = false
    /// 추천 줄 자리에 대신 올리는 것 (단어 추가 입력 칸, 이모지 패널 탭)
    let barOverlay = UIView()
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
    /// 간격을 눌러 자동으로 고친 직후. 지우기를 한 번 누르면 원래 친 글자로 되돌린다.
    var lastCorrection: (original: String, fixed: String, separator: String)?
    /// 자동 교정 되돌리기 칩을 보여 주는 시간. 다음 단어를 치는 중에도 이 시간 동안은 보인다.
    var correctionTime = Date.distantPast
    static let correctionChipTime: TimeInterval = 6
    var correctionChipTimer: Timer?
    /// 조합 중 글자(marked text)를 마지막으로 바꾼 때. 그 직후의 커서 변화는 우리가 한 것으로 본다.
    var markEditTime = Date.distantPast
    var proxyOps: [(UITextDocumentProxy) -> Void] = []
    /// 깜빡임 시험: 앞 글자를 매번 읽지 않고 따라가는 사본. nil 이면 다음에 한 번 읽는다.
    var ctxCache: String?
    var ownEditTime = Date.distantPast
    var proxyPaused = false
    // 한글 오타 교정은 뒤에서 계산한다
    let correctorQueue = DispatchQueue(label: "clipkey.corrector", qos: .userInitiated)
    let correctorGen = Generation()
    var koCache: [String: [KoCorrector.Candidate]] = [:]
    var koPending: String?
    var koCheckerWorks: Bool?
    var iosKnownCache: [String: Bool] = [:]
    var iosGuessCache: [String: [KoCorrector.Candidate]] = [:]
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
    /// 추천 줄 (B안: 도구 줄 위에 따로 둔다). 글자 자판·숫자 화면에서만 보인다.
    let suggestBar = UIView()
    var suggestBarHeight: NSLayoutConstraint?
    static let suggestBarFull: CGFloat = 38
    /// 상단바에서 단어 추가를 열었으면 저장·취소 뒤 글자 자판으로 돌아간다
    var addReturnPanel: Panel?
    // 밀어서 연속 입력 중인 키
    weak var slideCurrent: KeyButton?
    var sliding = false
    var toolbarEditList: ToolbarEditor?
    let divider = UIView()
    let keyArea = KeyArea()
    let suggestScroll = UIScrollView()
    let suggestStack = UIStackView()
    var suggestItems: [(text: String, kind: SuggestKind)] = []
    var suggestPending = false
    var lastSuggestSignature: String?
    var toolbarTyping = false
    // 입력 중에는 숨기는 상단바 버튼 (상단바 C안)
    weak var clipToolButton: UIButton?
    weak var arrowLeftButton: UIButton?
    weak var arrowRightButton: UIButton?
    weak var hideToolButton: UIButton?
    weak var undoToolButton: UIButton?
    weak var redoToolButton: UIButton?
    /// 되돌리기 기록: 이 키보드로 바꾼 것만 단어 단위로. 커서를 옮기거나 칸이 바뀌면 비운다.
    var undoStack: [EditGroup] = []
    var redoStack: [EditGroup] = []
    var editOpen = false
    var lastEditTime = Date.distantPast
    var editRecording = true
    /// 마지막으로 그린 자판의 조건. 키보드가 다시 뜰 때 같으면 새로 그리지 않는다.
    var builtSignature = ""
    lazy var impact = UIImpactFeedbackGenerator(style: .light)

    // 설정의 사전 줄
    var dictStatus: String?
    var dictBusy = false
    weak var dictValueLabel: UILabel?
    weak var dictCaptionLabel: UILabel?
    weak var dictButton: UIButton?
    // 설정의 앱 버전 줄
    var appUpdateCaption: (text: String, strong: Bool)?
    var appUpdateBusy = false
    weak var appCaptionLabel: UILabel?
    weak var appButton: UIButton?
    var letterKeys: [KeyButton] = []
    weak var shiftKey: KeyButton?

    // 패널 상태
    var clipItems: [Clip] = []
    var confirmingID: UUID?
    weak var clipTable: UITableView?
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

        // 추천 줄(38) + 도구 줄(46) + 자판. 자판 키 높이는 아이폰 기본 키보드와 비슷하게 (아래는 아이폰의 지구본 줄이 붙는다)
        let height = view.heightAnchor.constraint(equalToConstant: 336)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        viewHeight = height
        isLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height

        toolbar.axis = .horizontal
        toolbar.spacing = 4
        toolbar.alignment = .center
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 8, right: 6)

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

        for v in [suggestBar, toolbar, divider, keyArea] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        suggestBar.clipsToBounds = true
        suggestScroll.translatesAutoresizingMaskIntoConstraints = false
        suggestBar.addSubview(suggestScroll)
        let barHeight = suggestBar.heightAnchor.constraint(equalToConstant: KeyboardViewController.suggestBarFull)
        suggestBarHeight = barHeight
        NSLayoutConstraint.activate([
            suggestBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,
            suggestScroll.leadingAnchor.constraint(equalTo: suggestBar.leadingAnchor, constant: 6),
            suggestScroll.trailingAnchor.constraint(equalTo: suggestBar.trailingAnchor, constant: -6),
            suggestScroll.bottomAnchor.constraint(equalTo: suggestBar.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: suggestBar.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarHeightConstraint(),
            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            keyArea.topAnchor.constraint(equalTo: divider.bottomAnchor),
            keyArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        barOverlay.isHidden = true
        pinEdges(barOverlay, in: suggestBar)

        KoDictionary.shared.preload()
        loadTextReplacements()
        _ = checkField()
        rebuild()
    }

    func toolbarHeightConstraint() -> NSLayoutConstraint {
        let c = toolbar.heightAnchor.constraint(equalToConstant: 46)
        toolbarHeight = c
        return c
    }

    /// 아이폰 텍스트 대치 목록을 받아 둔다 (연락처 이름처럼 그대로인 항목은 뺀다)
    func loadTextReplacements() {
        requestSupplementaryLexicon { [weak self] lexicon in
            var map: [String: String] = [:]
            for e in lexicon.entries where e.userInput != e.documentText && !e.userInput.isEmpty {
                map[e.userInput] = e.documentText
                let lower = e.userInput.lowercased()
                if map[lower] == nil { map[lower] = e.documentText }
            }
            DispatchQueue.main.async {
                self?.textReplacements = map
                self?.lastSuggestSignature = nil
            }
        }
    }

    /// 텍스트 대치에 있는 줄임말이면 바꿀 글
    func replacement(for word: String) -> String? {
        guard !adding, !word.isEmpty, fieldKind == .normal else { return nil }
        return textReplacements[word] ?? textReplacements[word.lowercased()]
    }

    // MARK: - 입력 칸 종류

    func currentFieldKind() -> FieldKind {
        switch textDocumentProxy.keyboardType ?? .default {
        case .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad: return .number
        case .emailAddress: return .email
        case .URL: return .url
        default: return .normal
        }
    }

    func currentReturnTitle() -> String? {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "이동"
        case .google, .yahoo, .search: return "검색"
        case .send: return "보내기"
        case .next: return "다음"
        case .done: return "완료"
        case .join: return "참가"
        case .route: return "경로"
        case .continue: return "계속"
        case .emergencyCall: return "긴급"
        default: return nil
        }
    }

    /// 입력 칸이 바뀌었으면 자판을 맞추고 true (다시 그려야 함)
    func checkField() -> Bool {
        let kind = currentFieldKind()
        let title = currentReturnTitle()
        let sig = "\(kind)|\(title ?? "")"
        guard sig != fieldSignature else { return false }
        let kindChanged = kind != fieldKind || fieldSignature.isEmpty
        fieldSignature = sig
        fieldKind = kind
        returnTitle = title
        guard kindChanged, !adding else { return true }
        let typingPanel = panel == .keys || panel == .symbols || panel == .numpad
        switch kind {
        case .number:
            if typingPanel { resetComposer(); panel = .numpad }
        case .email, .url:
            if typingPanel {
                resetComposer()
                if langBeforeField == nil { langBeforeField = lang }
                lang = .english
                panel = .keys
            }
        case .normal:
            if panel == .numpad { panel = .keys }
            if let l = langBeforeField {
                lang = l
                langBeforeField = nil
            }
        }
        shift = .off
        return true
    }

    /// 화면을 돌리면 높이를 바꿔 다시 그린다
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self = self else { return }
            let now = UIScreen.main.bounds.width > UIScreen.main.bounds.height
            if now != self.isLandscape {
                self.isLandscape = now
                self.rebuild()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        clearEditHistory()
        capture()
        ctxCache = nil
        // 테마나 자판이 그대로면 다시 그리지 않는다 (키보드가 더 빨리 뜬다)
        resolveTheme()
        _ = checkField()
        if layoutSignature() != builtSignature {
            rebuild()
        } else {
            lastSuggestSignature = nil
            refreshSuggestions()
        }
        if settings.haptic { impact.prepare() }
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
        cursorDragging = false
        notice = nil
        words.flush()
        nextWords.flush()
    }

    /// marked text 를 쓸 때: 우리가 바꾼 직후가 아닌데 커서가 움직였으면 사용자가 다른 곳을 누른 것이다
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if Date().timeIntervalSince(ownEditTime) > 0.3 {
            ctxCache = nil      // 사용자가 커서를 옮겼다
            clearEditHistory()  // 되돌리기 기록은 커서 자리 기준이라 더는 맞지 않는다
        }
        if marked, !composing.isEmpty, Date().timeIntervalSince(markEditTime) > 0.3 {
            // 다른 곳을 누르면 앱이 조합 중 글자를 스스로 확정한다. 문서는 건드리지 않고 조합 상태만 버린다.
            composer = HangulComposer()
            composing = ""
            snapshot = nil
            lastCorrection = nil
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if Date().timeIntervalSince(ownEditTime) > 0.3 {
            ctxCache = nil      // 앱이 글자를 바꿨다
            clearEditHistory()
        }
        let was = isDark
        resolveTheme()
        let fieldChanged = checkField()
        if was != isDark || fieldChanged {
            rebuild()
        } else {
            refreshSuggestions()
        }
    }

    // MARK: - 화면 다시 그리기

    func resolveTheme() {
        // 화면 모드만 본다. 앱이 입력 칸에 어두운 키보드를 달라고 해도(keyboardAppearance) iOS 26 기본 키보드는
        // 화면 모드를 따르므로 같게 한다 (라이트 모드인데 우리 키보드만 어둡게 나오던 것)
        let systemDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
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
        // 바탕은 투명하게: iOS 가 깐 키보드 판의 색이 그대로 보여 경계 없이 하나로 보인다
        // 단, 완전히 투명하면 iOS 가 그 자리의 터치를 키보드에 주지 않는다 (설정 여백을 밀어도 스크롤이 안 되고,
        // 키 사이 틈을 눌러도 가까운 키가 안 눌렸다). 눈에 안 보일 만큼만 색을 깔아 터치를 받는다.
        view.backgroundColor = UIColor(white: isDark ? 0 : 1, alpha: 0.015)
        divider.backgroundColor = theme.divider.withAlphaComponent(isDark ? 0.6 : 0.45)
        // 추천 줄은 글자 자판·숫자 화면·이모지에서만 (다른 패널은 그만큼 넓게 쓴다)
        // 단어 추가 중에는 같은 자리에 입력 칸을 올려서 키 높이가 바뀌지 않게 한다
        let showBar = panel == .keys || panel == .symbols || panel == .numpad || panel == .emoji
        suggestBar.isHidden = !showBar
        // 가로 화면은 세로 공간이 좁아서 전체를 낮춘다 (세로 336 → 가로 236)
        viewHeight?.constant = isLandscape ? 236 : 336
        suggestBarHeight?.constant = showBar ? (isLandscape ? 32 : KeyboardViewController.suggestBarFull) : 0
        // 추천 줄이 없는 화면(클립보드, 설정 …)은 도구 줄이 맨 위라, iOS 키보드 판의 둥근 모서리와 붙지 않게 위를 띄운다
        toolbar.layoutMargins.top = showBar ? 2 : (isLandscape ? 6 : 10)
        toolbar.layoutMargins.bottom = isLandscape ? 2 : 8
        toolbarHeight?.constant = isLandscape ? (showBar ? 40 : 44) : (showBar ? 46 : 54)
        barOverlay.subviews.forEach { $0.removeFromSuperview() }
        barOverlay.isHidden = true
        suggestScroll.isHidden = false
        if adding && (panel == .keys || panel == .symbols) {
            buildAddRow()
        } else if panel == .emoji {
            buildEmojiTabs()
        }
        buildToolbar()
        buildBody()
        lastSuggestSignature = nil
        refreshSuggestions()
        builtSignature = layoutSignature()
    }

    func layoutSignature() -> String {
        "\(isDark)|\(panel)|\(lang)|\(adding)|\(symbolPage)|\(settings.hangulLayout)|\(settings.naraHints)|\(settings.toolbarLayout.joined(separator: ","))|\(fieldSignature)|\(emojiTab)|\(emojiCategory)|\(stickerPack)|\(settings.keyFontSize)|\(isLandscape)"
    }

    /// 키를 누를 때의 진동과 소리. 둘 다 이 키보드의 설정을 따른다.
    func haptic() {
        if settings.haptic {
            impact.impactOccurred()
            impact.prepare()          // 다음 진동이 늦지 않도록 미리 준비
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
    enum BufferPurpose { case addWord, clipSearch, emojiSearch, packRename }
    var bufferPurpose: BufferPurpose = .addWord
    var searchRefreshPending = false
    /// 클립보드 검색 결과만 보여 줄 때의 검색어
    var clipFilter: String?
    /// 이름을 바꾸는 중인 스티커 팩
    var renamingPack: UUID?
    weak var packMenu: UIView?
    weak var addField: UILabel?
    var adding: Bool { addBuffer != nil }

    var docBefore: String? {
        if let b = addBuffer { return b }
        if settings.fewContextReads {
            // 처음 한 번만 읽고, 그다음부터는 우리가 넣고 지운 것으로 따라간다
            if ctxCache == nil { ctxCache = textDocumentProxy.documentContextBeforeInput ?? "" }
            return ctxCache
        }
        let ctx = textDocumentProxy.documentContextBeforeInput
        // 조합 중 글자를 앞 글자에 넣어 주지 않는 앱도 있어서, 빠져 있으면 붙여서 본다
        if marked, !composing.isEmpty, !(ctx ?? "").hasSuffix(composing) {
            return (ctx ?? "") + composing
        }
        return ctx
    }

    // MARK: 문서 바꾸기 줄 세우기 (실험: 조합 중 글자 표시)

    /// 확정 뒤 잠깐 기다리는 동안 들어온 바꾸기를 모아 두었다가 순서대로 한다
    func proxyDo(_ op: @escaping (UITextDocumentProxy) -> Void) {
        if proxyPaused || !proxyOps.isEmpty {
            proxyOps.append(op)
        } else {
            op(textDocumentProxy)
        }
    }

    func proxyMark(_ text: String) {
        markEditTime = Date()
        proxyDo { $0.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0)) }
    }

    /// 확정하고, 앱이 반영할 시간(0.03초)을 준다
    func proxyUnmark() {
        markEditTime = Date()
        proxyDo { [weak self] proxy in
            proxy.unmarkText()
            self?.pauseProxy()
        }
    }

    private func pauseProxy() {
        proxyPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self = self else { return }
            self.proxyPaused = false
            while !self.proxyOps.isEmpty, !self.proxyPaused {
                let op = self.proxyOps.removeFirst()
                op(self.textDocumentProxy)
            }
            self.markEditTime = Date()
        }
    }

    /// 조합 중 글자를 marked text 로 다룰지 (단어 추가 칸은 키보드 안의 글자라 해당 없음)
    var marked: Bool { settings.markedComposing && addBuffer == nil }

    /// 조합 중 글자를 문서에서 지운다
    func clearComposingText() {
        guard !composing.isEmpty else { return }
        if marked {
            proxyMark("")
            proxyUnmark()
        } else {
            for _ in 0..<composing.count { docDelete() }
        }
        composing = ""
    }

    func docInsert(_ s: String) {
        if addBuffer == nil { recordInsert(s) }
        if addBuffer == nil, ctxCache != nil {
            ctxCache! += s
            if ctxCache!.count > 400 { ctxCache = String(ctxCache!.suffix(300)) }
        }
        ownEditTime = Date()
        if addBuffer != nil {
            addBuffer?.append(s)
            updateAddField()
        } else {
            proxyDo { $0.insertText(s) }
        }
    }

    func docDelete() {
        if addBuffer == nil { recordDelete() }
        if addBuffer == nil, ctxCache != nil, !ctxCache!.isEmpty { ctxCache!.removeLast() }
        ownEditTime = Date()
        if let b = addBuffer {
            if !b.isEmpty { addBuffer?.removeLast() }
            updateAddField()
        } else {
            proxyDo { $0.deleteBackward() }
        }
    }

    func updateAddField() {
        addField?.text = (addBuffer ?? "") + "|"
        // 검색 중이면 결과 줄을 다시 그린다 (한 번의 키 입력에 여러 번 불려도 한 번만)
        if bufferPurpose == .clipSearch || bufferPurpose == .emojiSearch, !searchRefreshPending {
            searchRefreshPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.searchRefreshPending = false
                if self.adding { self.buildToolbar() }
            }
        }
    }

    /// 키보드 안의 입력 칸을 연다 (단어 추가, 클립보드·이모지 검색, 스티커 팩 이름)
    func openBuffer(_ purpose: BufferPurpose, text: String = "", returnTo: Panel?) {
        resetComposer()
        bufferPurpose = purpose
        addBuffer = text
        addReturnPanel = returnTo
        shift = .off
        panel = .keys
        rebuild()
    }

    @objc func startAddWord() {
        openBuffer(.addWord, returnTo: addReturnPanel)
    }

    @objc func startClipSearch() {
        clipFilter = nil
        openBuffer(.clipSearch, returnTo: .clipboard)
    }

    @objc func startEmojiSearch() {
        openBuffer(.emojiSearch, returnTo: .emoji)
    }

    /// 입력 칸에서 줄바꿈 키를 눌렀을 때
    func bufferReturn() {
        switch bufferPurpose {
        case .addWord: saveAddWord()
        case .clipSearch: showClipResults()
        case .emojiSearch: cancelAddWord()
        case .packRename: savePackName()
        }
    }

    /// 클립보드 검색: 결과만 목록으로 본다
    @objc func showClipResults() {
        resetComposer()
        let q = (addBuffer ?? "").trimmingCharacters(in: .whitespaces)
        addBuffer = nil
        clipFilter = q.isEmpty ? nil : q
        panel = .clipboard
        addReturnPanel = nil
        rebuild()
    }

    /// 검색어에 맞는 클립 (글자만, 대소문자 구분 없이)
    func clipMatches(_ q: String) -> [Clip] {
        let query = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return store.sorted.filter { $0.image == nil && $0.text.lowercased().contains(query) }
    }

    /// 상단바의 + 버튼: 치던 화면에서 바로 단어를 넣고 돌아온다
    @objc func startAddWordFromToolbar() {
        addReturnPanel = .keys
        startAddWord()
    }

    @objc func cancelAddWord() {
        resetComposer()
        addBuffer = nil
        renamingPack = nil
        panel = addReturnPanel ?? .words
        addReturnPanel = nil
        rebuild()
    }

    /// 직접 넣은 단어는 횟수와 상관없이 바로 추천에 나온다. 숫자와 하이픈도 들어간다.
    @objc func saveAddWord() {
        resetComposer()
        let text = (addBuffer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        addBuffer = nil
        if !text.isEmpty { words.addManual(text) }
        panel = addReturnPanel ?? .words
        addReturnPanel = nil
        rebuild()
    }

    // MARK: - 조합 글자와 문서 맞추기

    /// 조합기를 바꾼 뒤 호출한다. 문서의 조합 중 글자를 새 글자로 바꿔 넣는다.
    func apply(commit: String) {
        let newText = composer.text
        if marked {
            // 지웠다 다시 넣지 않고 조합 중 글자만 바꾼다 (사파리 웹 입력창의 커서 깜빡임을 막는다)
            // 실험: 확정(unmarkText) 뒤에는 앱이 반영할 시간을 잠깐 주고 다음 글자를 넣는다
            if !commit.isEmpty {
                proxyMark(commit)
                proxyUnmark()
            } else if newText.isEmpty, !composing.isEmpty {
                proxyMark("")
                proxyUnmark()
            }
            if !newText.isEmpty { proxyMark(newText) }
            composing = newText
            markEditTime = Date()
            return
        }
        for _ in 0..<composing.count { docDelete() }
        let out = commit + newText
        if !out.isEmpty { docInsert(out) }
        composing = newText
    }

    /// 조합을 끝낸다. 문서의 글자는 그대로 둔다.
    func resetComposer() {
        if marked, !composing.isEmpty {
            proxyUnmark()      // 조합 중 글자를 그대로 확정
            markEditTime = Date()
        }
        lastCorrection = nil
        composer = HangulComposer()
        composing = ""
        snapshot = nil
    }

    /// 커서를 직접 옮겼거나 다른 곳을 눌렀으면 조합을 끊는다
    func syncComposer() {
        guard !composing.isEmpty, !marked else { return }
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
        notice = nil
        let now = Date()
        let gap = now.timeIntervalSince(lastKeyTime)
        let sameKey = id == lastKeyID
        if !id.hasPrefix("v:") { snapshot = nil }
        spaceRepeat = id == "space" && sameKey && gap < 0.6

        switch id {
        case "space":
            commitWord(separator: " ")
        case "return":
            if panel == .numpad, returnTitle == nil {
                hideKeyboard()             // 숫자 칸의 "완료"
            } else {
                commitWord(separator: "\n")
            }
        case "tokeys":
            resetComposer()
            panel = .keys
            rebuild()
        case "shift":
            toggleShift(doubleTap: sameKey && gap < 0.4)
        case "punct":
            if sameKey && gap < 1.2 {
                docDelete()
                punctIndex = (punctIndex + 1) % KeyboardViewController.puncts.count
            } else {
                resetComposer()
                learn(currentWord())
                punctIndex = 0
            }
            docInsert(KeyboardViewController.puncts[punctIndex])
        case "stroke":
            composer.nara = true
            let out = composer.transformLast(HangulComposer.strokeTable)
            reclaimIfNeeded()
            apply(commit: out)
        case "double":
            composer.nara = true
            let out = composer.transformLast(HangulComposer.doubleTable)
            reclaimIfNeeded()
            apply(commit: out)
        case "v:ㅏㅓ":
            naraVowel(id, "ㅏ", "ㅓ")
        case "v:ㅗㅜ":
            naraVowel(id, "ㅗ", "ㅜ")
        case "num":
            // 자판 안의 123 / 가 / ABC 키: 숫자·기호 화면을 열고 닫는다
            numTapped()
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

    /// 단어를 배운다. 단어 추가 중이거나 이메일·주소·숫자 칸에서는 배우지 않는다.
    func learn(_ w: String) {
        guard !adding, fieldKind == .normal else { return }
        words.learn(w)
    }

    /// 조합과 상관없는 글자(숫자, 기호)를 넣는다
    func plain(_ s: String) {
        resetComposer()
        if let f = s.first, !f.isLetter, !f.isNumber {
            learn(currentWord())
        }
        docInsert(s)
    }

    /// 꾹 눌러서 나온 보조 글자
    func insertPlain(_ s: String) {
        syncComposer()
        notice = nil
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

    /// 획추가로 앞 글자 받침에 붙었으면(찬+ㅎ → 찮) 화면의 앞 글자와 조합 중 글자를 지운다.
    /// 이어서 apply 가 새로 합친 글자를 넣는다.
    func reclaimIfNeeded() {
        guard composer.reclaimed else { return }
        composer.reclaimed = false
        clearComposingText()
        docDelete()
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
            clearComposingText()
            for _ in 0..<snap.commit.count { docDelete() }
            composer = snap.composer
            let t = composer.text
            if !t.isEmpty {
                if marked {
                    proxyMark(t)
                    markEditTime = Date()
                } else {
                    docInsert(t)
                }
            }
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
            if separator == "\n" { bufferReturn() } else { docInsert(separator) }
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
        let previous = previousWord(in: String((docBefore ?? "").dropLast(word.count)))
        var final = word
        if separator == " ", let rep = replacement(for: word) {
            // 아이폰 텍스트 대치: 교정 설정과 상관없이 바꾼다. 지우기 한 번이면 되돌린다.
            replaceWord(word, with: rep)
            final = rep
            lastCorrection = (word, rep, separator)
            startCorrectionChip()
        } else if separator == " ", settings.correctMode == 2, let fix = autoCorrection(for: word, wait: true) {
            replaceWord(word, with: fix)
            final = fix
            lastCorrection = (word, fix, separator)
            startCorrectionChip()
        }
        learn(final)
        if separator == " ", fieldKind == .normal, let p = previous { nextWords.learn(previous: p, next: final) }
        docInsert(separator)
        autoCapIfNeeded()
    }

    /// 고칠 후보 (한글·영문). 앞이 가장 그럴듯한 것. 교정을 껐거나 고칠 것이 없으면 빈 배열.
    /// 학습한 단어와 직접 넣은 단어(이름, 회사명 등)는 고치지 않는다.
    func corrections(for word: String) -> [String] {
        guard settings.correctMode > 0, panel == .keys, !adding, fieldKind == .normal, word != skipCorrection else { return [] }
        // 예전에 내가 고른 단어가 있으면 그것을 맨 앞에 (같은 글자를 골랐으면 고치지 않는다)
        if let choice = settings.correctionChoices[word] {
            return choice == word ? [] : [choice]
        }
        if lang == .english { return correction(for: word).map { [$0] } ?? [] }
        // 우리 사전은 작아서 합성어(숫자키 같은)를 오타로 볼 수 있다. 아이폰 사전이 맞다고 하면 고치지 않는다.
        if iosKnowsKorean(word) { return [] }
        return koAllCandidates(word).map { $0.text }
    }

    /// 한글 오타 후보. 계산이 무거워서 키를 칠 때는 뒤에서 계산하고, 끝나면 추천 줄을 다시 그린다.
    /// 그동안에는 빈 목록을 돌려준다 (키 입력을 막지 않는다).
    /// wait: 간격을 눌러 바로 고쳐야 할 때는 기다려서 받는다.
    func koCandidates(_ word: String, wait: Bool = false) -> [KoCorrector.Candidate] {
        // 학습한 단어와 직접 넣은 단어는 고치지 않는다 (단어 저장소는 이 화면 쪽에서만 읽는다)
        if words.knows(word) || words.isManual(word) { return [] }
        let layout = settings.hangulLayout
        let key = "\(layout)|\(word)"
        if let cached = koCache[key] { return cached }
        let personal = words.personal
        if wait {
            correctorGen.bump()                    // 뒤에서 돌던 계산은 멈춘다
            let r = correctorQueue.sync { () -> [KoCorrector.Candidate] in
                let dict = KoCorrector.shared.corrections(for: word, hangulLayout: layout, protected: { _ in false }) ?? []
                return KoCorrector.merge(KoCorrector.personal(word, words: personal, hangulLayout: layout), dict)
            }
            storeKo(key, r)
            return r
        }
        guard koPending != key else { return [] }
        koPending = key
        let gen = correctorGen.bump()
        let generation = correctorGen
        // 빠르게 연타하는 중에는 건너뛰고, 손이 잠깐 멈췄을 때 계산한다
        correctorQueue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard generation.current == gen else {
                DispatchQueue.main.async { if self?.koPending == key { self?.koPending = nil } }
                return
            }
            let r = KoCorrector.shared.corrections(for: word, hangulLayout: layout, protected: { _ in false },
                                                   shouldStop: { generation.current != gen })
                .map { KoCorrector.merge(KoCorrector.personal(word, words: personal, hangulLayout: layout), $0) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.koPending == key { self.koPending = nil }
                guard let r = r else { return }
                self.storeKo(key, r)
                if self.currentWord() == word {
                    self.lastSuggestSignature = nil
                    self.refreshSuggestions()
                }
            }
        }
        return []
    }

    /// 아이폰 맞춤법 검사기가 이 한글 단어를 맞다고 보는지.
    /// 검사기가 한글을 제대로 못 보는 기기에서는 쓰지 않는다 (엉터리 말도 맞다고 하면 끈다).
    func iosKnowsKorean(_ word: String) -> Bool {
        guard let language = koLanguage, word.count >= 2 else { return false }
        if koCheckerWorks == nil {
            koCheckerWorks = iosMisspelled("뷁쉙궯", language)
        }
        guard koCheckerWorks == true else { return false }
        if let cached = iosKnownCache[word] { return cached }
        let known = !iosMisspelled(word, language)
        if iosKnownCache.count > 200 { iosKnownCache.removeAll() }
        iosKnownCache[word] = known
        return known
    }

    func iosMisspelled(_ word: String, _ language: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false,
                                             language: language).location != NSNotFound
    }

    /// 우리 사전·내 단어 후보에 아이폰 맞춤법 검사기의 고칠 말(숫자키 같은 합성어)을 더한다.
    /// 아이폰 후보도 자판에서 가까운 오타일 때만 쓴다 (엉뚱한 말로 바꾸지 않게).
    func koAllCandidates(_ word: String, wait: Bool = false) -> [KoCorrector.Candidate] {
        let base = koCandidates(word, wait: wait)
        let ios = iosGuessCandidates(word)
        return ios.isEmpty ? base : KoCorrector.merge(ios, base)
    }

    func iosGuessCandidates(_ word: String) -> [KoCorrector.Candidate] {
        guard let language = koLanguage, word.count >= 2, KoCorrector.isHangulWord(word),
              koCheckerWorks == true, !iosKnowsKorean(word) else { return [] }
        if let cached = iosGuessCache[word] { return cached }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = (checker.guesses(forWordRange: range, in: word, language: language) ?? [])
            .filter { !$0.contains(" ") }
            .prefix(5)
        // 아이폰 검사기의 첫 후보는 자주 쓰는 말일 가능성이 높다. 우리 사전은 쓰는 빈도를 거의 보지 않아서
        // 자판 거리만 가까운 드문 말(무억을 → 무역을)을 고르기 쉬워, 첫 후보는 앞에 두고 자동 교정도 허락한다.
        // (기본 키보드가 무억을·뮤억을 → 무엇을 로 고치는 것과 같게)
        let long = KoCorrector.jamo(word).count > 6
        var found: [KoCorrector.Candidate] = []
        for (i, g) in guesses.enumerated() {
            guard let c = KoCorrector.personal(word, words: [g], hangulLayout: settings.hangulLayout).first else { continue }
            if i == 0 {
                let d = c.score + 0.3
                found.append(KoCorrector.Candidate(text: c.text, score: d - 0.6, sure: d <= (long ? 1.5 : 0.5)))
            } else {
                found.append(c)
            }
        }
        found.sort { $0.score < $1.score }
        if iosGuessCache.count > 200 { iosGuessCache.removeAll() }
        iosGuessCache[word] = found
        return found
    }

    func storeKo(_ key: String, _ value: [KoCorrector.Candidate]) {
        if koCache.count > 64 { koCache.removeAll() }
        koCache[key] = value
    }

    /// 간격을 눌렀을 때 자동으로 바꿀 단어. 한글은 확실한 후보만 바꾸고, 나머지는 추천 칸에만 보여 준다.
    func autoCorrection(for word: String, wait: Bool = false) -> String? {
        guard settings.correctMode == 2, panel == .keys, !adding, fieldKind == .normal, word != skipCorrection else { return nil }
        if let choice = settings.correctionChoices[word] { return choice == word ? nil : choice }
        // 내가 쓰는 말(직접 넣은 단어, 자주 친 단어)을 치는 중이면 바꾸지 않는다 (그 단어가 최우선)
        if !words.matches(word).isEmpty { return nil }
        if lang == .english { return correction(for: word) }
        if iosKnowsKorean(word) { return nil }
        guard let best = koAllCandidates(word, wait: wait).first, best.sure else { return nil }
        return best.text
    }

    /// 자동으로 고친 것을 원래 친 글자로 되돌린다. 되돌렸으면 true.
    /// allowTail: 다음 단어를 치는 중이어도 되돌린다 (칩을 눌렀을 때). 지우기 키는 바로 뒤일 때만.
    @discardableResult
    func undoCorrection(allowTail: Bool = false) -> Bool {
        guard let c = lastCorrection else { return false }
        let tail = allowTail ? currentWord() : ""
        guard let ctx = docBefore, ctx.hasSuffix(c.fixed + c.separator + tail) else { return false }
        resetComposer()
        lastCorrection = nil
        for _ in 0..<(c.fixed.count + c.separator.count + tail.count) { docDelete() }
        docInsert(c.original + (tail.isEmpty ? "" : c.separator + tail))
        // 내가 되돌린 단어는 기억해서 다음부터 고치지 않는다
        skipCorrection = c.original
        settings.rememberChoice(typed: c.original, chosen: c.original)
        words.markChosen(c.original)
        lastKeyID = "undo"
        lastSuggestSignature = nil
        refreshSuggestions()
        return true
    }

    @objc func undoChipTapped() {
        stopDelete()
        undoCorrection(allowTail: true)
    }

    /// 자동 교정 되돌리기 칩이 아직 보일 때인지
    var correctionChipVisible: Bool {
        lastCorrection != nil && Date().timeIntervalSince(correctionTime) < KeyboardViewController.correctionChipTime
    }

    func startCorrectionChip() {
        correctionTime = Date()
        correctionChipTimer?.invalidate()
        correctionChipTimer = Timer.scheduledTimer(withTimeInterval: KeyboardViewController.correctionChipTime + 0.05,
                                                   repeats: false) { [weak self] _ in
            self?.lastSuggestSignature = nil
            self?.refreshSuggestions()
        }
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
        guard !adding, settings.autoCap, fieldKind == .normal, lang == .english, panel == .keys, shift == .off else { return }
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
        if lastCorrection != nil, currentWord().isEmpty, undoCorrection() {
            stopDelete()
            return
        }
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

    /// 누르는 순간 한 글자, 길게 누르기 시간 + 0.1초 뒤부터 반복 입력 속도로 계속 지운다
    func startDelete() {
        backspaceOnce()
        deleteTimer?.invalidate()
        let interval = settings.repeatInterval
        let first = Timer(timeInterval: settings.longPressTime + 0.1, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.backspaceOnce()
            let again = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.backspaceOnce() }
            RunLoop.main.add(again, forMode: .common)
            self.deleteTimer = again
        }
        RunLoop.main.add(first, forMode: .common)
        deleteTimer = first
    }

    /// 지우기 키를 왼쪽으로 밀었을 때: 커서 앞 단어 n개를 지운다. 띄어쓰기와 줄바꿈은 단어에 붙여 같이 지운다.
    func deleteWords(_ n: Int) {
        stopDelete()
        guard n > 0 else { return }
        resetComposer()
        let ctx = Array(docBefore ?? "")
        var i = ctx.count
        for _ in 0..<n {
            while i > 0, ctx[i - 1] == " " || ctx[i - 1] == "\n" { i -= 1 }
            let end = i
            while i > 0, ctx[i - 1].isLetter || ctx[i - 1].isNumber { i -= 1 }
            if i == end, i > 0 { i -= 1 }      // 단어가 아니면 문장부호 하나
            if i == 0 { break }
        }
        let removed = String(ctx[i...])
        for _ in 0..<(ctx.count - i) { docDelete() }
        lastKeyID = "⌫"
        if !removed.isEmpty, !adding {
            showNotice("단어 \(n)개 지웠어요") { [weak self] in
                self?.resetComposer()
                self?.docInsert(removed)
            }
        }
        refreshSuggestions()
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
        deletedAllText = ""
        moveToDocumentEnd(0) { [weak self] in self?.deleteAllPass(0) }
    }

    /// 커서를 문서 맨 끝으로 옮긴다. 앱이 커서 뒤 글자를 줄 끝까지만 알려 주는 경우가 많아서
    /// (그래서 전에는 커서가 있던 줄까지만 지워졌다) 줄 끝에 닿으면 한 칸씩 넘겨 보며 더 못 갈 때까지 반복한다.
    func moveToDocumentEnd(_ pass: Int, then done: @escaping () -> Void) {
        ctxCache = nil
        let proxy = textDocumentProxy
        guard pass < 300 else { done(); return }
        if let after = proxy.documentContextAfterInput, !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.moveToDocumentEnd(pass + 1, then: done)
            }
            return
        }
        // 뒤가 비어 보이면 한 칸 넘겨 본다. 앞 글자가 바뀌었으면 아직 뒤에 줄이 있던 것.
        let before = proxy.documentContextBeforeInput ?? ""
        proxy.adjustTextPosition(byCharacterOffset: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self = self else { return }
            let now = self.textDocumentProxy.documentContextBeforeInput ?? ""
            if now != before {
                self.moveToDocumentEnd(pass + 1, then: done)
            } else {
                done()
            }
        }
    }

    /// 키보드는 커서 앞 글자를 한 번에 일부만 볼 수 있어서, 남은 것이 없을 때까지 나눠 지운다
    func deleteAllPass(_ pass: Int, blankTries: Int = 0) {
        ctxCache = nil          // 남은 글자는 실제로 읽어서 확인한다
        // 메모 같은 앱은 문단(빈 줄) 앞에서 앞 글자를 빈 값으로 알려 준다 (그래서 한 문단씩만 지워졌다).
        // 빈 값이어도 줄바꿈 하나를 지워 보고 계속한다. hasText 도 믿을 수 없어서 보지 않는다.
        // 세 번 연달아 빈 값이면 정말 다 지운 것으로 보고, 헛지운 줄바꿈은 되돌리기 글에서 뺀다.
        if pass < 400, (docBefore ?? "").isEmpty {
            if blankTries < 3 {
                recordDeleteBlock("\n")
                editRecording = false
                docDelete()
                editRecording = true
                deletedAllText = "\n" + deletedAllText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.deleteAllPass(pass + 1, blankTries: blankTries + 1)
                }
                return
            }
            deletedAllText = String(deletedAllText.dropFirst(min(blankTries, deletedAllText.prefix { $0 == "\n" }.count)))
        }
        guard pass < 400, let before = docBefore, !before.isEmpty else {
            lastKeyID = "⌫"
            let text = deletedAllText
            deletedAllText = ""
            if !text.isEmpty {
                showNotice("\(text.count)자를 모두 지웠어요") { [weak self] in
                    self?.resetComposer()
                    self?.docInsert(text)
                }
            }
            refreshSuggestions()
            return
        }
        deletedAllText = before + deletedAllText
        recordDeleteBlock(before)
        editRecording = false
        for _ in 0..<before.count { docDelete() }
        editRecording = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.deleteAllPass(pass + 1)
        }
    }

    // MARK: - 툴바 동작

    @objc func langTapped() {
        resetComposer()
        if panel == .symbols || panel == .numpad {
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
        clipFilter = nil
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

    @objc func openEmoji() {
        resetComposer()
        panel = .emoji
        rebuild()
    }

    @objc func openSettings() {
        panel = .settings
        rebuild()
    }

    @objc func hideKeyboard() {
        resetComposer()
        dismissKeyboard()
    }

    /// 간격 키를 위로 밀면 지금 줄의 처음, 아래로 밀면 지금 줄의 끝으로 (줄바꿈 기준).
    /// 이미 줄 처음이면 윗줄 끝으로, 이미 줄 끝이면 아랫줄 처음으로 넘어간다 (계속 밀면 한 줄씩 올라가고 내려간다).
    /// 키보드는 화면의 줄 모양을 알 수 없어서, 칸 위치를 맞춰 윗줄·아랫줄로 가는 것보다 이쪽이 늘 정확하다.
    func moveCursorLines(_ lines: Int) {
        guard lines != 0 else { return }
        resetComposer()
        let proxy = textDocumentProxy
        if lines < 0 {
            let before = proxy.documentContextBeforeInput ?? ""
            let col = before.lastIndex(of: "\n").map { before.distance(from: before.index(after: $0), to: before.endIndex) } ?? before.count
            if col > 0 {
                proxy.adjustTextPosition(byCharacterOffset: -col)
            } else if !before.isEmpty {
                proxy.adjustTextPosition(byCharacterOffset: -1)      // 이미 줄 맨 앞이면 윗줄 맨 끝으로
            }
        } else {
            let after = proxy.documentContextAfterInput ?? ""
            let rest = after.firstIndex(of: "\n").map { after.distance(from: after.startIndex, to: $0) } ?? after.count
            if rest > 0 {
                proxy.adjustTextPosition(byCharacterOffset: rest)
            } else {
                // 이미 줄 맨 끝이면 아랫줄 맨 앞으로. 앱이 커서 뒤 글자를 줄 끝까지만 알려 주는 경우가 많아서
                // (아랫줄이 있어도 빈 값) 비어 있어도 한 칸 옮긴다. 문서 끝이면 그대로다.
                proxy.adjustTextPosition(byCharacterOffset: 1)
            }
        }
        ctxCache = nil
    }

    // MARK: - 되돌리기 / 다시 하기

    /// 커서 앞에서 일어난 바꾸기 한 묶음 (단어 하나 정도): removed 를 지우고 inserted 를 넣은 것과 같다
    struct EditGroup {
        var removed = ""
        var inserted = ""
    }

    func clearEditHistory() {
        guard !undoStack.isEmpty || !redoStack.isEmpty || editOpen else { return }
        undoStack.removeAll()
        redoStack.removeAll()
        editOpen = false
        updateUndoButtons()
    }

    /// 새 묶음을 열지: 간격·줄바꿈 뒤, 또는 잠깐(1.5초) 쉬었다가 치면 새 묶음
    private func currentGroupIndex() -> Int {
        let now = Date()
        if !editOpen || undoStack.isEmpty || now.timeIntervalSince(lastEditTime) > 1.5 {
            undoStack.append(EditGroup())
            if undoStack.count > 60 { undoStack.removeFirst() }
            editOpen = true
        }
        lastEditTime = now
        if !redoStack.isEmpty { redoStack.removeAll() }
        return undoStack.count - 1
    }

    func recordInsert(_ s: String) {
        guard editRecording, !s.isEmpty else { return }
        let i = currentGroupIndex()
        undoStack[i].inserted += s
        // 간격·줄바꿈을 치면 이 단어 묶음은 닫는다 (기본 키보드처럼 단어 단위로 되돌린다)
        if s.last == " " || s.last == "\n" { editOpen = false }
        updateUndoButtons()
    }

    func recordDelete() {
        guard editRecording else { return }
        let i = currentGroupIndex()
        if !undoStack[i].inserted.isEmpty {
            undoStack[i].inserted.removeLast()
        } else if let last = (textDocumentProxy.documentContextBeforeInput ?? "").last {
            undoStack[i].removed = String(last) + undoStack[i].removed
        }
        updateUndoButtons()
    }

    /// 한꺼번에 지운 글자 (전체 삭제): 글자마다 앞 글자를 읽지 않고 한 번에 적는다
    func recordDeleteBlock(_ text: String) {
        guard !text.isEmpty else { return }
        let i = currentGroupIndex()
        var t = text
        while !t.isEmpty, !undoStack[i].inserted.isEmpty {
            undoStack[i].inserted.removeLast()
            t.removeLast()
        }
        undoStack[i].removed = t + undoStack[i].removed
        updateUndoButtons()
    }

    func updateUndoButtons() {
        let canUndo = undoStack.contains { !$0.removed.isEmpty || !$0.inserted.isEmpty }
        undoToolButton?.isEnabled = canUndo
        undoToolButton?.alpha = canUndo ? 1 : 0.35
        redoToolButton?.isEnabled = !redoStack.isEmpty
        redoToolButton?.alpha = redoStack.isEmpty ? 0.35 : 1
    }

    /// 묶음을 거꾸로 적용한다: 커서 앞이 `drop` 으로 끝나야 지우고 `put` 을 넣는다
    private func applyEdit(drop: String, put: String) -> Bool {
        guard (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(drop) else { return false }
        editRecording = false
        for _ in 0..<drop.count { docDelete() }
        if !put.isEmpty { docInsert(put) }
        editRecording = true
        ctxCache = nil
        return true
    }

    @objc func editUndoTapped() {
        resetComposer()
        haptic()
        while let g = undoStack.popLast() {
            if g.removed.isEmpty && g.inserted.isEmpty { continue }
            editOpen = false
            if applyEdit(drop: g.inserted, put: g.removed) {
                redoStack.append(g)
            } else {
                clearEditHistory()       // 문서가 기록과 달라졌다
            }
            break
        }
        lastSuggestSignature = nil
        refreshSuggestions()
        updateUndoButtons()
    }

    @objc func editRedoTapped() {
        resetComposer()
        haptic()
        guard let g = redoStack.popLast() else { return }
        if applyEdit(drop: g.removed, put: g.inserted) {
            undoStack.append(g)
            editOpen = false
        } else {
            clearEditHistory()
        }
        lastSuggestSignature = nil
        refreshSuggestions()
        updateUndoButtons()
    }

    @objc func cursorLeft() {
        resetComposer()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        ctxCache = nil
    }

    @objc func cursorRight() {
        resetComposer()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        ctxCache = nil
    }

    // MARK: - 추천 단어

    /// 추천을 다시 계산하라는 요청. 한 번의 키 입력에서 여러 번 불려도 실제 계산은 한 번만 한다.
    func refreshSuggestions() {
        guard !suggestPending else { return }
        suggestPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.suggestPending = false
            self.renderSuggestions()
        }
    }

    /// 간격 하나를 건너 바로 앞 단어. 줄바꿈이나 문장부호로 끊겼으면 nil.
    func previousWord(in ctx: String) -> String? {
        guard ctx.hasSuffix(" ") else { return nil }
        var chars: [Character] = []
        for ch in ctx.dropLast().reversed() {
            if ch.isLetter { chars.append(ch) } else { break }
        }
        let w = String(chars.reversed())
        return WordStore.learnable(w) ? w : nil
    }

    func suggestionItems(for word: String) -> [(text: String, kind: SuggestKind)] {
        var items: [(text: String, kind: SuggestKind)] = []
        func add(_ t: String, _ k: SuggestKind) {
            guard items.count < 6, t != word, !items.contains(where: { $0.text == t }) else { return }
            items.append((t, k))
        }
        if fieldKind == .email { return emailItems() }
        if word.isEmpty {
            // 간격을 누른 뒤: 앞 단어 다음에 평소 이어 쓰던 단어
            if panel == .keys, let prev = previousWord(in: docBefore ?? "") {
                for w in nextWords.predictions(after: prev, limit: 3) { add(w, .next) }
            }
            // 기본 키보드처럼 추천 줄을 늘 채운다: 내가 자주 쓰는 단어 → 그래도 모자라면 기본 단어
            if panel == .keys, fieldKind == .normal, items.count < 3 {
                let hangul = lang == .hangul
                for w in words.learnedWords.prefix(30) where items.count < 3 && KoCorrector.isHangulWord(w.word) == hangul {
                    add(w.word, .next)
                }
                for w in hangul ? KeyboardViewController.starterKo : KeyboardViewController.starterEn where items.count < 3 {
                    add(w, .next)
                }
            }
            return items
        }
        // 순서: 직접 넣은 단어 → 자주 친 단어 → 맞춤법(교정, 사전) → 고정한 클립
        // 내가 쓰는 말(이름 등)은 사전 추천보다 늘 앞에 둔다. 초성 하나(ㅇ)나 첫 글자(유)만 쳐도 맞춘다.
        // 아이폰 텍스트 대치가 맨 앞 (간격을 누르면 바뀐다)
        let rep = replacement(for: word)
        if let r = rep { add(r, .replacement) }
        let matched = words.matches(word)
        for w in matched where words.isManual(w) { add(w, .learned) }
        for w in matched where !words.isManual(w) { add(w, .learned) }
        let fixes = rep == nil ? corrections(for: word) : []
        if let first = fixes.first {
            if autoCorrection(for: word) == first {
                // 간격을 누르면 바뀌는 경우에만 강조하고, 왼쪽에 "친 그대로"를 둔다
                add(first, .correction)
                add("\u{201C}\(word)\u{201D}", .original)
            } else {
                add(first, .dict)              // 확실하지 않거나 '추천만'이면 가운데에 보여 주기만 한다
            }
            for f in fixes.dropFirst() { add(f, .dict) }
        }
        // 한글은 맞춤법 사전(ko_dict.txt, 활용형 포함)에서 먼저 찾고, 모자라면 iOS 사전으로 채운다
        var dictCount = 0
        if lang == .hangul {
            let found = KoDictionary.shared.complete(word, limit: 3)
            for c in found { add(c, .dict) }
            dictCount = found.count
        }
        let language: String? = lang == .english ? "en_US" : koLanguage
        if dictCount < 3, let language = language, word.allSatisfy({ $0.isLetter }) {
            let range = NSRange(location: 0, length: (word as NSString).length)
            let found = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
            for c in found.prefix(3 - dictCount) { add(c, .dict) }
        }
        let lower = word.lowercased()
        for c in store.clips where c.pinned && c.text.count > word.count && c.text.lowercased().hasPrefix(lower) {
            add(c.text, .pinned)
        }
        return items
    }

    /// 아무것도 안 칠 때 추천 줄을 채우는 기본 단어
    static let starterKo = ["나는", "오늘", "그래서", "네", "저는"]
    static let starterEn = ["I", "The", "I'm", "Thanks"]

    static let emailDomains = ["naver.com", "gmail.com", "icloud.com", "daum.net", "hanmail.net", "kakao.com",
                               "nate.com", "outlook.com", "hotmail.com", "yahoo.com"]

    /// 이메일 칸: @ 앞을 치는 중이면 "@naver.com" 같은 주소 끝, @ 뒤를 치는 중이면 맞는 주소
    func emailItems() -> [(text: String, kind: SuggestKind)] {
        let ctx = docBefore ?? ""
        let token = String(ctx.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !token.isEmpty else { return [] }
        if let at = token.lastIndex(of: "@") {
            let part = String(token[token.index(after: at)...]).lowercased()
            return KeyboardViewController.emailDomains
                .filter { $0.hasPrefix(part) && $0 != part }
                .prefix(3).map { (text: $0, kind: SuggestKind.email) }
        }
        return ["@gmail.com", "@naver.com", "@icloud.com"].map { (text: $0, kind: SuggestKind.email) }
    }

    /// 이메일 칸에서 @ 뒤에 친 글자
    func emailDomainPart() -> String {
        let ctx = docBefore ?? ""
        let token = String(ctx.reversed().prefix { !$0.isWhitespace }.reversed())
        guard let at = token.lastIndex(of: "@") else { return "" }
        return String(token[token.index(after: at)...])
    }

    // MARK: - 추천 줄 알림 (되돌리기)

    /// 추천 줄에 "…지웠어요 [↺ 되돌리기]"를 5초 동안 보여 준다. 글자를 치면 사라진다.
    func showNotice(_ text: String, action: @escaping () -> Void) {
        notice = (text, action)
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.clearNotice()
        }
        lastSuggestSignature = nil
        refreshSuggestions()
    }

    func clearNotice() {
        noticeTimer?.invalidate()
        noticeTimer = nil
        guard notice != nil else { return }
        notice = nil
        lastSuggestSignature = nil
        refreshSuggestions()
    }

    @objc func noticeTapped() {
        let action = notice?.action
        clearNotice()
        stopDelete()
        action?()
        lastKeyID = "undo"
        refreshSuggestions()
    }

    /// 되돌리기 칩. 어디서나 같은 모양: ↺ 아이콘 + 둥근 칩. 자판 위에서는 흰 칩, 어두운 알림 줄 위에서는 진회색 칩.
    func undoChip(_ title: String, bold: Bool = true, onBar: Bool = false) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(Icon.image("undo", size: 15, line: 2.2), for: .normal)
        b.setTitle(" " + title, for: .normal)
        b.titleLabel?.font = bold ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 14)
        let fg: UIColor = onBar ? .white : theme.text
        b.tintColor = fg
        b.setTitleColor(fg, for: .normal)
        b.backgroundColor = onBar ? Theme.hex(isDark ? 0x5A5E66 : 0x4A4D54) : theme.key
        b.layer.cornerRadius = 15
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 12)
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        return b
    }

    /// 상단바 C안: 글자를 치는 중에는 한/영, 123 만 남기고 나머지 자리를 추천 단어에 준다
    /// B안부터는 치는 중에도 도구를 숨기지 않는다 (추천은 따로 한 줄을 쓴다)
    func setToolbarTyping(_ typing: Bool) {
        toolbarTyping = typing
    }

    func renderSuggestions() {
        guard !adding, panel == .keys || panel == .symbols || panel == .numpad else { return }
        if cursorDragging || notice != nil {
            renderMessageRow()
            return
        }
        let word = currentWord()
        let typing = panel == .keys && !word.isEmpty
        let items = suggestionItems(for: word)
        let clip = typing ? nil : freshClip      // 치는 중에는 복사 칩을 잠깐 숨긴다

        // 지난번과 같으면 화면을 건드리지 않는다
        let undo = correctionChipVisible ? lastCorrection?.original : nil
        var signature = "\(typing)|\(clip?.id.uuidString ?? "")|\(armedSuggestion ?? "")|\(isDark)|\(undo ?? "")"
        for item in items { signature += "|\(item.kind):\(item.text)" }
        if signature == lastSuggestSignature { return }
        lastSuggestSignature = signature

        setToolbarTyping(typing)
        suggestStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestItems = items

        if let undo = undo {
            // 방금 자동으로 고쳤으면 되돌리기 칩을 먼저 보여 준다
            let chip = undoChip(undo, bold: false)
            chip.accessibilityLabel = undo + "로 되돌리기"
            chip.addTarget(self, action: #selector(undoChipTapped), for: .touchUpInside)
            suggestStack.addArrangedSubview(chip)
            suggestStack.setCustomSpacing(6, after: chip)
        }
        if let clip = clip {
            let chip = clipChip(clip)
            suggestStack.addArrangedSubview(chip)
            suggestStack.setCustomSpacing(4, after: chip)
        }

        if typing && !items.isEmpty {
            buildSlots(items, reserved: undo == nil ? 0 : undoChipWidth(undo ?? "") + 6)
        } else if !typing, clip == nil, undo == nil, !items.isEmpty,
                  items.allSatisfy({ $0.kind == .next }) {
            // 치기 전: 기본 키보드처럼 같은 폭 세 칸 (강조 없이)
            buildSlots(items, highlight: false)
        } else {
            var previousPlain = false
            for (i, item) in items.enumerated() {
                let b = suggestionButton(item, index: i, slot: false, best: false)
                let isChip = item.kind == .learned || item.kind == .pinned
                if !isChip && previousPlain { suggestStack.addArrangedSubview(separatorLine(height: 20)) }
                suggestStack.addArrangedSubview(b)
                suggestStack.setCustomSpacing(isChip ? 4 : 0, after: b)
                previousPlain = !isChip
            }
        }
        suggestScroll.setContentOffset(.zero, animated: false)
    }

    /// 추천 줄 한가운데에 안내 한 줄: 커서 옮기는 중, 또는 "…지웠어요 [되돌리기]"
    func renderMessageRow() {
        let signature = cursorDragging ? "cursor|\(isDark)" : "notice|\(notice?.text ?? "")|\(isDark)"
        if signature == lastSuggestSignature { return }
        lastSuggestSignature = signature
        suggestStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestItems = []

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.heightAnchor.constraint(equalToConstant: 36).isActive = true
        // 너비는 화면에 붙인 뒤에 건다 (먼저 걸면 키보드가 종료된다)
        suggestStack.addArrangedSubview(holder)
        holder.widthAnchor.constraint(equalTo: suggestScroll.frameLayoutGuide.widthAnchor).isActive = true
        row.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        ])

        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = theme.muted
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if cursorDragging {
            let l = UIImageView(image: Icon.image("chevron.left", size: 16, line: 2))
            let r = UIImageView(image: Icon.image("chevron.right", size: 16, line: 2))
            l.tintColor = theme.muted
            r.tintColor = theme.muted
            label.text = "커서 이동 중 · 손을 떼면 멈춤"
            row.addArrangedSubview(l)
            row.addArrangedSubview(label)
            row.addArrangedSubview(r)
        } else if let n = notice {
            label.text = n.text
            row.addArrangedSubview(label)
            let chip = undoChip("되돌리기")
            chip.addTarget(self, action: #selector(noticeTapped), for: .touchUpInside)
            row.addArrangedSubview(chip)
        }
        suggestScroll.setContentOffset(.zero, animated: false)
    }

    func separatorLine(height: CGFloat) -> UIView {
        let line = UIView()
        line.backgroundColor = theme.divider
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: height).isActive = true
        return line
    }

    /// 고정 3칸: 가운데에 가장 잘 맞는 단어, 왼쪽에 둘째(영문 교정일 때는 친 그대로), 오른쪽에 셋째.
    /// 4번째부터는 오른쪽으로 밀어서 본다.
    func undoChipWidth(_ title: String) -> CGFloat {
        undoChip(title, bold: false).systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
    }

    func buildSlots(_ items: [(text: String, kind: SuggestKind)], reserved: CGFloat = 0, highlight: Bool = true) {
        var rest = Array(items.indices)
        var left: Int?
        if let o = items.firstIndex(where: { $0.kind == .original }) {
            left = o
            rest.removeAll { $0 == o }
        }
        // 가운데: 텍스트 대치 → 직접 넣은 단어 → 자주 친 단어 → 고친 단어 → 첫째 순서
        let replaced = rest.first { items[$0].kind == .replacement }
        let manual = rest.first { items[$0].kind == .learned && words.isManual(items[$0].text) }
        let learned = rest.first { items[$0].kind == .learned }
        let center = replaced ?? manual ?? learned ?? rest.first { items[$0].kind == .correction } ?? rest.first
        if let c = center { rest.removeAll { $0 == c } }
        if left == nil, !rest.isEmpty { left = rest.removeFirst() }
        let right = rest.isEmpty ? nil : rest.removeFirst()

        for (pos, index) in [left, center, right].enumerated() {
            let slot = UIView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.heightAnchor.constraint(equalToConstant: 36).isActive = true
            // 칸 너비는 추천 영역의 1/3. 화면에 붙인 뒤에 걸어야 한다 (먼저 걸면 키보드가 종료된다)
            suggestStack.addArrangedSubview(slot)
            slot.widthAnchor.constraint(equalTo: suggestScroll.frameLayoutGuide.widthAnchor, multiplier: 1.0 / 3.0,
                                        constant: -reserved / 3).isActive = true
            if let i = index {
                let b = suggestionButton(items[i], index: i, slot: true, best: highlight && pos == 1)
                pinEdges(b, in: slot, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3))
            }
            if pos < 2 {
                let line = separatorLine(height: 20)
                line.translatesAutoresizingMaskIntoConstraints = false
                slot.addSubview(line)
                line.trailingAnchor.constraint(equalTo: slot.trailingAnchor).isActive = true
                line.centerYAnchor.constraint(equalTo: slot.centerYAnchor).isActive = true
            }
        }
        for i in rest {
            suggestStack.addArrangedSubview(separatorLine(height: 20))
            suggestStack.addArrangedSubview(suggestionButton(items[i], index: i, slot: false, best: false))
        }
    }

    func suggestionButton(_ item: (text: String, kind: SuggestKind), index: Int, slot: Bool, best: Bool) -> UIButton {
        var title = item.text.replacingOccurrences(of: "\n", with: " ")
        if title.count > 14 { title = String(title.prefix(14)) + "…" }
        let isChip = item.kind == .learned || item.kind == .pinned
        let armed = item.kind == .learned && item.text == armedSuggestion
        let b = UIButton(type: .system)
        b.tag = index
        b.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
        if item.kind == .learned {
            b.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(suggestionLongPressed(_:))))
        }
        if slot {
            // 칸 안에서는 모두 글자로 보여 주고, 직접 넣었거나 자주 친 단어는 별, 고정 클립은 압정을 붙인다
            if isChip || armed {
                let iconName = armed ? "xmark" : (item.kind == .learned ? "star" : "pin.fill")
                b.setImage(Icon.image(iconName, size: 12, line: armed ? 2.5 : 1.75), for: .normal)
                b.setTitle(" " + title, for: .normal)
                if armed { b.semanticContentAttribute = .forceRightToLeft }
            } else {
                b.setTitle(title, for: .normal)
            }
            b.titleLabel?.font = best || armed ? .boldSystemFont(ofSize: 16) : .systemFont(ofSize: 16)
            if item.kind == .original { b.setTitleColor(theme.muted, for: .normal) }
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.75
            b.tintColor = armed ? theme.onDanger : theme.muted
            b.setTitleColor(armed ? theme.onDanger : theme.text, for: .normal)
            // 고친 단어·대치는 회색 바탕으로 강조한다: 간격을 누르면 이것으로 바뀐다
            let willApply = item.kind == .correction || item.kind == .replacement
            b.backgroundColor = armed ? theme.danger : (willApply ? theme.funcKey : .clear)
            b.layer.cornerRadius = 8
            if willApply {
                b.accessibilityLabel = item.text + ", 간격을 누르면 이것으로 바뀜"
            }
            if item.kind == .replacement {
                // 텍스트 대치는 작은 "대치" 표시를 붙인다
                let s = NSMutableAttributedString(string: title, attributes: [
                    .font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: theme.text])
                s.append(NSAttributedString(string: "  대치", attributes: [
                    .font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: theme.muted]))
                b.setAttributedTitle(s, for: .normal)
            }
            return b
        }
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
        } else {
            b.setTitle(title, for: .normal)
            let strong = item.kind == .correction
            b.titleLabel?.font = strong ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 15)
            b.setTitleColor(strong || item.kind == .next ? theme.text : theme.muted, for: .normal)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        }
        return b
    }

    /// 방금 복사한 내용 칩. undo 가 있으면 자동 교정 되돌리기 칩으로 쓴다.
    func clipChip(_ clip: Clip?, undo: String? = nil) -> UIButton {
        let b = UIButton(type: .system)
        var title = (undo ?? clip?.text ?? "").replacingOccurrences(of: "\n", with: " ")
        if title.count > 16 { title = String(title.prefix(16)) + "…" }
        b.setTitle(" " + title, for: .normal)
        b.setImage(undo != nil ? Icon.image("undo", size: 14, line: 2) : Icon.image("clipboard", size: 14, line: 2), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.tintColor = theme.text
        b.setTitleColor(theme.text, for: .normal)
        b.backgroundColor = theme.key
        b.layer.cornerRadius = 15
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        if let undo = undo {
            b.accessibilityLabel = undo + "로 되돌리기"
            b.addTarget(self, action: #selector(undoChipTapped), for: .touchUpInside)
        } else {
            b.accessibilityLabel = "방금 복사한 내용 붙여넣기"
            b.addTarget(self, action: #selector(chipTapped), for: .touchUpInside)
        }
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
            // 삭제 대기 중인 칩을 한 번 더 누르면 그 단어를 지운다 (5초 동안 되돌릴 수 있다)
            suggestArmTimer?.invalidate()
            armedSuggestion = nil
            let w = item.text
            let count = words.remove(w)
            let pairs = nextWords.remove(w)
            showNotice("‘\(w)’ 추천에서 뺐어요") { [weak self] in
                self?.words.restore(w, count: count ?? WordStore.threshold)
                self?.nextWords.restore(pairs)
            }
            return
        }
        let word = currentWord()
        // 고른 단어가 오타 교정 후보였는지 (앞글자만 친 자동 완성은 기억하지 않는다)
        let wasFix = (item.kind == .correction || item.kind == .dict) && corrections(for: word).contains(item.text)
        resetComposer()
        switch item.kind {
        case .original:
            // 고치지 않고 친 그대로 쓴다. 다음부터는 오타로 보지 않는다.
            skipCorrection = word
            words.markChosen(word)
            settings.rememberChoice(typed: word, chosen: word)
            docInsert(" ")
        case .pinned, .replacement:
            replaceWord(word, with: item.text)
        case .email:
            if item.text.hasPrefix("@") {
                docInsert(item.text)
            } else {
                for _ in 0..<emailDomainPart().count { docDelete() }
                docInsert(item.text)
            }
        default:
            replaceWord(word, with: item.text)
            // 내가 고른 단어는 바로 기억한다: 다음에 간격을 눌러도 다른 말로 고치지 않고,
            // 같은 글자를 다시 치면 이 단어를 먼저 추천한다
            skipCorrection = item.text
            if fieldKind == .normal {
                words.markChosen(item.text)
                if wasFix { settings.rememberChoice(typed: word, chosen: item.text) }
            }
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

/// 계산 차례 번호. 새 글자가 들어올 때마다 올라가고, 뒤에서 도는 계산은 번호가 바뀌면 멈춘다.
final class Generation {
    private var value = 0
    private let lock = NSLock()

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func bump() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
