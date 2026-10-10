import UIKit

/// 툴바와 자판 배치
extension KeyboardViewController {

    // MARK: - 툴바

    func toolButton(_ title: String? = nil, symbol: String? = nil, width: CGFloat? = nil,
                    active: Bool = false, plain: Bool = false, color: UIColor? = nil,
                    label: String? = nil, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        if let title = title {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15)
        }
        if let symbol = symbol {
            b.setImage(toolIcon(symbol), for: .normal)
        }
        let fg = color ?? (active ? theme.onAccent : theme.text)
        b.tintColor = fg
        b.setTitleColor(fg, for: .normal)
        b.backgroundColor = active ? theme.accent : (plain ? UIColor.clear : theme.funcKey)
        b.layer.cornerRadius = 8
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        if let width = width {
            b.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            // 글자 길이만큼만 차지하고, 옆의 제목 때문에 늘어나지 않게 한다
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        b.accessibilityLabel = label ?? title
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    /// 상단바와 패널에 쓰는 작은 아이콘
    func toolIcon(_ name: String) -> UIImage? {
        if name.hasPrefix("chevron") { return Icon.image(name, size: 20, line: 2) }
        if name == "keyboard.down" { return Icon.image(name, size: 20, line: 1.75) }
        return Icon.image(name, size: 18, line: 1.75)
    }

    /// 상단바 한 칸 폭: 한/영 키와 여백을 빼고 8칸이 들어가게 (작은 아이폰에서는 조금 좁게)
    func toolbarSlotWidth() -> CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let free = width - 12 - 44 - 4 * 10
        return max(30, min(40, floor(free / CGFloat(Settings.toolbarCapacity))))
    }

    /// 상단바에서 남는 폭을 채우는 빈 곳
    func toolbarSpacer() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func toolbarTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = "  " + text
        l.font = .boldSystemFont(ofSize: 16)
        l.textColor = theme.text
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    /// "한/영"에서 지금 쓰는 쪽을 굵게
    func langTitle() -> NSAttributedString {
        let on: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: theme.text]
        let off: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: theme.muted]
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "한", attributes: lang == .hangul ? on : off))
        s.append(NSAttributedString(string: "/", attributes: off))
        s.append(NSAttributedString(string: "영", attributes: lang == .english ? on : off))
        return s
    }

    func buildToolbar() {
        toolbar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        toolbar.distribution = .fill
        switch panel {
        case .keys, .symbols, .numpad:
            if adding {
                buildBufferToolbar()
                break
            }
            let langB = toolButton(width: 44, label: "한영 전환", action: #selector(langTapped))
            langB.setAttributedTitle(langTitle(), for: .normal)
            toolbar.addArrangedSubview(langB)
            // 상단바 꾸미기의 배치대로 (8칸). "gap" 자리가 늘어나는 빈 곳.
            clipToolButton = nil
            arrowLeftButton = nil
            arrowRightButton = nil
            hideToolButton = nil
            undoToolButton = nil
            redoToolButton = nil
            let w = toolbarSlotWidth()
            for item in settings.toolbarLayout {
                switch item {
                case Settings.toolbarGap:
                    let spacer = UIView()
                    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                    toolbar.addArrangedSubview(spacer)
                case "clipboard":
                    let clipB = toolButton(symbol: "clipboard", width: w, plain: true,
                                           color: theme.accent, label: "클립보드 열기", action: #selector(clipTapped))
                    toolbar.addArrangedSubview(clipB)
                    clipToolButton = clipB
                case "settings":
                    toolbar.addArrangedSubview(toolButton(symbol: "slider.horizontal.3", width: w, plain: true,
                                                          label: "설정 열기", action: #selector(openSettings)))
                case "addword":
                    toolbar.addArrangedSubview(toolButton(symbol: "plus", width: w, plain: true,
                                                          label: "단어 추가", action: #selector(startAddWordFromToolbar)))
                case "emoji":
                    toolbar.addArrangedSubview(toolButton(symbol: "smile", width: w, plain: true,
                                                          label: "이모지", action: #selector(openEmoji)))
                case "arrows":
                    let l = toolButton(symbol: "chevron.left", width: w, plain: true,
                                       label: "커서 왼쪽으로", action: #selector(cursorLeft))
                    let r = toolButton(symbol: "chevron.right", width: w, plain: true,
                                       label: "커서 오른쪽으로", action: #selector(cursorRight))
                    toolbar.addArrangedSubview(l)
                    toolbar.addArrangedSubview(r)
                    arrowLeftButton = l
                    arrowRightButton = r
                case "undo":
                    let u = toolButton(symbol: "undo", width: w, plain: true, label: "되돌리기", action: #selector(editUndoTapped))
                    let r = toolButton(symbol: "redo", width: w, plain: true, label: "다시 하기", action: #selector(editRedoTapped))
                    toolbar.addArrangedSubview(u)
                    toolbar.addArrangedSubview(r)
                    undoToolButton = u
                    redoToolButton = r
                    updateUndoButtons()
                case "hide":
                    let hideB = toolButton(symbol: "keyboard.down", width: w, plain: true,
                                           label: "키보드 닫기", action: #selector(hideKeyboard))
                    toolbar.addArrangedSubview(hideB)
                    hideToolButton = hideB
                default:
                    break
                }
            }
        case .emoji:
            buildEmojiToolbar()
        case .clipboard where clipFilter != nil:
            // 검색 결과 목록
            let back = toolButton("클립보드", symbol: "chevron.left", plain: true, label: "클립보드 전체로", action: #selector(clearClipFilter))
            back.titleLabel?.font = .systemFont(ofSize: 15)
            toolbar.addArrangedSubview(back)
            let title = toolbarTitle("‘\(clipFilter ?? "")’ \(clipMatches(clipFilter ?? "").count)개")
            title.textAlignment = .center
            title.lineBreakMode = .byTruncatingMiddle
            toolbar.addArrangedSubview(title)
            let again = toolButton("다시 검색", symbol: "search", action: #selector(startClipSearch))
            again.titleLabel?.font = .systemFont(ofSize: 13)
            again.backgroundColor = theme.key
            toolbar.addArrangedSubview(again)
        case .clipboard:
            toolbar.addArrangedSubview(toolButton("한", width: 44, label: "한글 자판으로", action: #selector(toHangul)))
            toolbar.addArrangedSubview(toolButton("ENG", width: 52, label: "영문 자판으로", action: #selector(toEnglish)))
            toolbar.addArrangedSubview(toolButton(symbol: "clipboard", width: 40, active: true,
                                                  label: "클립보드 닫기", action: #selector(backToKeys)))
            toolbar.addArrangedSubview(toolbarSpacer())   // 제목 없이 빈 곳 (다른 화면과 맞춘다)
            toolbar.addArrangedSubview(toolButton(symbol: "search", width: 40, plain: true,
                                                  label: "클립보드 검색", action: #selector(startClipSearch)))
            let clear = toolButton("전체 삭제", plain: true, color: theme.danger, action: #selector(clearClipsTapped(_:)))
            clear.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(clear)
            toolbar.addArrangedSubview(toolButton(symbol: "slider.horizontal.3", width: 40, plain: true,
                                                  label: "설정 열기", action: #selector(openSettings)))
        case .settings:
            toolbar.addArrangedSubview(toolButton("한", width: 44, label: "한글 자판으로", action: #selector(toHangul)))
            toolbar.addArrangedSubview(toolButton("ENG", width: 52, label: "영문 자판으로", action: #selector(toEnglish)))
            toolbar.addArrangedSubview(toolButton(symbol: "clipboard", width: 40, plain: true,
                                                  label: "클립보드 열기", action: #selector(clipTapped)))
            toolbar.addArrangedSubview(toolbarSpacer())
            toolbar.addArrangedSubview(toolButton(symbol: "slider.horizontal.3", width: 40, active: true,
                                                  label: "설정 닫기", action: #selector(clipTapped)))
        case .toolbarEdit:
            toolbar.addArrangedSubview(toolButton(symbol: "chevron.left", width: 44,
                                                  label: "설정으로 돌아가기", action: #selector(openSettings)))
            toolbar.addArrangedSubview(toolbarTitle("상단바 꾸미기"))
            let reset = toolButton("기본값으로", plain: true, action: #selector(resetToolbarTapped))
            reset.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(reset)
        case .words:
            toolbar.addArrangedSubview(toolButton(symbol: "chevron.left", width: 44,
                                                  label: "설정으로 돌아가기", action: #selector(openSettings)))
            toolbar.addArrangedSubview(toolbarTitle("단어 관리"))
            let clear = toolButton("모두 지우기", plain: true, color: theme.danger, action: #selector(clearWordsTapped(_:)))
            clear.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(clear)
            let add = toolButton("단어 추가", action: #selector(startAddWord))
            add.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(add)
        }
    }

    /// 입력 칸을 쓰는 동안의 도구 줄: 단어 추가·팩 이름은 [한/영][취소] 안내, 검색은 결과
    func buildBufferToolbar() {
        switch bufferPurpose {
        case .clipSearch:
            let found = clipMatches(addBuffer ?? "")
            searchResultsRow(count: found.count, empty: (addBuffer ?? "").isEmpty ? "찾을 글자를 치세요" : "맞는 항목이 없어요") { stack in
                for (i, c) in found.prefix(20).enumerated() {
                    var t = c.text.replacingOccurrences(of: "\n", with: " ")
                    if t.count > 18 { t = String(t.prefix(18)) + "…" }
                    let b = UIButton(type: .system)
                    b.setTitle(t, for: .normal)
                    b.titleLabel?.font = .systemFont(ofSize: 13)
                    b.setTitleColor(theme.text, for: .normal)
                    b.backgroundColor = theme.key
                    b.layer.cornerRadius = 15
                    b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                    b.heightAnchor.constraint(equalToConstant: 30).isActive = true
                    b.tag = i
                    b.accessibilityLabel = c.text + " 붙여넣기"
                    b.addTarget(self, action: #selector(clipSearchResultTapped(_:)), for: .touchUpInside)
                    stack.addArrangedSubview(b)
                }
            }
        case .emojiSearch:
            let found = EmojiData.search(addBuffer ?? "")
            searchResultsRow(count: found.count, empty: (addBuffer ?? "").isEmpty ? "예: 하트, 웃음, 고양이" : "맞는 이모지가 없어요") { stack in
                for e in found.prefix(40) {
                    let b = UIButton(type: .system)
                    b.setTitle(e, for: .normal)
                    b.titleLabel?.font = .systemFont(ofSize: 22)
                    b.widthAnchor.constraint(equalToConstant: 36).isActive = true
                    b.heightAnchor.constraint(equalToConstant: 34).isActive = true
                    b.addTarget(self, action: #selector(emojiSearchResultTapped(_:)), for: .touchUpInside)
                    stack.addArrangedSubview(b)
                }
            }
        case .addWord, .packRename:
            let langKey = toolButton(width: 44, label: "한영 전환", action: #selector(langTapped))
            langKey.setAttributedTitle(langTitle(), for: .normal)
            toolbar.addArrangedSubview(langKey)
            let cancel = toolButton("취소", symbol: "chevron.left", plain: true, action: #selector(cancelAddWord))
            cancel.titleLabel?.font = .systemFont(ofSize: 15)
            toolbar.addArrangedSubview(cancel)
            let note = UILabel()
            note.text = bufferPurpose == .addWord ? "추가한 단어는 추천 줄 맨 앞에" : "스티커 팩 이름"
            note.font = .systemFont(ofSize: 13)
            note.textColor = theme.muted
            note.textAlignment = .center
            note.adjustsFontSizeToFitWidth = true
            note.minimumScaleFactor = 0.8
            note.setContentHuggingPriority(.defaultLow, for: .horizontal)
            note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            toolbar.addArrangedSubview(note)
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: 44).isActive = true
            toolbar.addArrangedSubview(spacer)
        }
    }

    /// 검색 결과 한 줄: [n개] [결과…] (옆으로 밀어서 더 봄)
    func searchResultsRow(count: Int, empty: String, fill: (UIStackView) -> Void) {
        let label = UILabel()
        label.text = count > 0 ? "\(count)개" : empty
        label.font = .systemFont(ofSize: 12)
        label.textColor = theme.muted
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(label)
        guard count > 0 else {
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            toolbar.addArrangedSubview(spacer)
            return
        }
        let scroll = PanelScrollView(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        fill(stack)
        toolbar.addArrangedSubview(scroll)
    }

    @objc func clipSearchResultTapped(_ b: UIButton) {
        let found = clipMatches(addBuffer ?? "")
        guard b.tag < found.count else { return }
        let clip = found[b.tag]
        resetComposer()
        addBuffer = nil
        addReturnPanel = nil
        clipFilter = nil
        haptic()
        pasteClip(clip)            // 붙여넣고 글자 자판으로 돌아간다
    }

    @objc func emojiSearchResultTapped(_ b: UIButton) {
        guard let e = b.title(for: .normal) else { return }
        haptic()
        textDocumentProxy.insertText(e)     // 검색 칸이 아니라 입력창에 넣는다
        ctxCache = nil
        settings.useEmoji(e)
    }

    // MARK: - 본문

    func buildBody() {
        keyArea.subviews.forEach { $0.removeFromSuperview() }
        keyArea.invalidateKeys()
        letterKeys = []
        shiftKey = nil
        undoTimer?.invalidate()
        switch panel {
        case .keys:
            if lang == .english {
                buildLetters(rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
            } else if settings.hangulLayout == 0 {
                buildNara()
            } else {
                buildLetters(rows: ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"])
            }
            updateLetterTitles()
        case .symbols:
            buildSymbols()
        case .numpad:
            buildNumpad()
        case .emoji:
            buildEmojiBody()
        case .clipboard:
            buildClipboard()
        case .settings:
            buildSettings()
        case .toolbarEdit:
            buildToolbarEdit()
        case .words:
            buildWords()
        }
    }

    // MARK: - 키 만들기

    func style(_ k: KeyButton, fn: Bool) {
        k.backgroundColor = fn ? theme.fnKey : theme.letterKey
        k.setTitleColor(theme.text, for: .normal)
        k.tintColor = theme.text
        k.hintColor = theme.hint
        k.bubbleBackground = theme.key
        k.bubbleText = theme.text
        k.bubbleHost = view
    }

    /// 밀어서 연속 입력·반복 입력에서 빼는 키 (각자 다른 동작이 있거나, 실수로 눌리면 곤란한 키)
    static let noSlideKeys: Set<String> = ["space", "return", "shift", "num", "punct", "stroke", "double", "⌫", "sympage",
                                           "tokeys"]

    func wire(_ k: KeyButton) {
        k.onDown = { [weak self] in
            self?.haptic()
            self?.slideCurrent = nil
            self?.sliding = false
        }
        k.onTap = { [weak self] key in self?.handleKey(key.id) }
        k.onHint = { [weak self] s in self?.insertPlain(s) }
        k.holdDelay = settings.longPressTime
        k.altDelay = settings.altDelay
        guard !KeyboardViewController.noSlideKeys.contains(k.id) else { return }
        // 글자·숫자 키: 밀어서 연속 입력은 늘, 길게 누르면 반복은 설정에 따라 (보조 글자가 있는 키는 말풍선이 먼저)
        k.slideEnabled = true
        k.onSlide = { [weak self, weak k] touch in
            guard let self = self, let k = k else { return false }
            return self.slideTouch(touch, from: k)
        }
        if settings.repeatOnHold {
            k.repeatDelay = settings.longPressTime
            k.repeatInterval = settings.repeatInterval
            k.onRepeat = { [weak self, weak k] in
                guard let self = self, let k = k else { return }
                self.haptic()
                self.handleKey(k.id)
            }
        }
    }

    /// 밀어서 연속 입력: 옆 키의 안쪽까지 들어가면 그 키를 넣는다. 처음 넘어갈 때 시작한 키도 넣는다.
    func slideTouch(_ touch: UITouch, from origin: KeyButton) -> Bool {
        let p = touch.location(in: keyArea)
        guard let target = keyArea.key(at: p, inner: 0.22), target.slideEnabled,
              target !== (slideCurrent ?? origin) else { return sliding }
        if !sliding {
            sliding = true
            handleKey(origin.id)
        }
        slideCurrent = target
        haptic()
        handleKey(target.id)
        return true
    }

    func makeKey(_ title: String, id: String? = nil, hint: String? = nil, fn: Bool = false,
                 font: CGFloat = 20) -> KeyButton {
        let k = KeyButton()
        k.id = id ?? title
        k.setTitle(title, for: .normal)
        k.titleLabel?.font = .systemFont(ofSize: (font * settings.keyFontScale).rounded())
        style(k, fn: fn)
        k.hintText = hint
        wire(k)
        return k
    }

    func iconKey(_ symbol: String, id: String, label: String, fn: Bool = true, accent: Bool = false,
                 fallback: String = "") -> KeyButton {
        let k = KeyButton()
        k.id = id
        k.setImage(Icon.key(symbol), for: .normal)
        style(k, fn: fn)
        if accent {
            // 줄바꿈 키는 기능 키와 같은 색 (기본 키보드처럼)
            k.backgroundColor = theme.fnKey
        }
        k.accessibilityLabel = label
        wire(k)
        return k
    }

    /// 숫자·기호 화면을 열고 닫는 키 (123 / 가 / ABC)
    func numKey(_ title: String) -> KeyButton {
        let k = makeKey(title, id: "num", fn: true, font: 15)
        k.accessibilityLabel = title == "123" ? "숫자와 기호" : "글자 자판으로 돌아가기"
        return k
    }

    /// 간격 키. 누른 채 좌우로 밀면 커서를 옮긴다.
    func spaceKey() -> KeyButton {
        let k = iconKey("space", id: "space", label: "간격", fn: false, fallback: "간격")
        k.accessibilityHint = "누른 채 좌우로 밀면 커서 이동"
        k.cursorStep = 9
        k.onCursorStart = { [weak self, weak k] in
            guard let self = self else { return }
            self.resetComposer()
            self.cursorDragging = true
            self.selectionFeedback.prepare()
            // 기본 키보드처럼: 톡 하는 진동과 함께 키 글자가 사라져 빈 판(트랙패드)이 된다
            // 키 진동 설정과 상관없이: 커서 모드로 바뀌었다는 신호라서 늘 준다
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIView.animate(withDuration: 0.15) {
                for key in self.keyArea.allKeys { key.setBlank(true) }
                k?.setBlank(true)
            }
            self.refreshSuggestions()
        }
        k.onCursorMove = { [weak self] steps in
            guard let self = self, !self.adding else { return }
            self.textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
            self.ctxCache = nil
            if self.settings.haptic {
                self.selectionFeedback.selectionChanged()
                self.selectionFeedback.prepare()
            }
        }
        k.onCursorLine = { [weak self] lines in
            guard let self = self, !self.adding else { return }
            self.moveCursorLines(lines)
            if self.settings.haptic {
                self.selectionFeedback.selectionChanged()
                self.selectionFeedback.prepare()
            }
        }
        k.onCursorEnd = { [weak self] in
            guard let self = self else { return }
            self.cursorDragging = false
            UIView.animate(withDuration: 0.15) {
                for key in self.keyArea.allKeys { key.setBlank(false); key.alpha = 1 }
            }
            self.lastSuggestSignature = nil
            self.refreshSuggestions()
        }
        spaceKeyRef = k
        return k
    }

    /// 줄바꿈 키. 칸이 알려 주는 이름(검색, 이동, 보내기 …)이 있으면 글자로, 없으면 줄바꿈 모양.
    func returnKey() -> KeyButton {
        let k = iconKey("return", id: "return", label: "줄바꿈", accent: true, fallback: "↵")
        let title = returnTitle ?? (panel == .numpad ? "완료" : nil)
        if let t = title {
            k.setImage(nil, for: .normal)
            k.setTitle(t, for: .normal)
            k.titleLabel?.font = .boldSystemFont(ofSize: 16)
            k.titleLabel?.adjustsFontSizeToFitWidth = true
            k.titleLabel?.minimumScaleFactor = 0.7
            k.accessibilityLabel = t
        }
        return k
    }

    func backspaceKey() -> KeyButton {
        let k = iconKey("delete.left", id: "⌫", label: "지우기", fallback: "⌫")
        k.onTap = nil
        k.onDown = { [weak self] in
            self?.haptic()
            self?.startDelete()
        }
        k.onUp = { [weak self] in self?.stopDelete() }
        // 누르고 있으면 "전체 삭제" 말풍선이 뜨고, 그 위로 밀어서 떼면 전부 지운다
        k.altTitle = "전체 삭제"
        k.altBackground = theme.text
        k.altText = theme.bg
        // 삭제 계열은 모두 같은 빨강 + 흰 글씨 (라이트 #B3261E, 다크 #E5453B)
        k.altHoverBackground = theme.danger
        k.altHoverText = theme.onDanger
        k.onAlt = { [weak self] in self?.deleteAll() }
        k.onAltHover = {
            // 설정과 상관없이, 전체 삭제가 걸렸다는 것은 진동으로 알린다
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // 왼쪽으로 밀면 단어 단위로 지운다. 더 밀수록 지울 단어가 늘고, 되돌리면 줄어든다. 떼면 지운다.
        k.swipeStep = 28
        k.swipeTitle = { n in n > 0 ? "단어 \(n)개 지우기" : "취소" }
        k.onSwipeChange = { [weak self] n in
            self?.stopDelete()
            if n > 0 { self?.haptic() }
        }
        k.onSwipeCommit = { [weak self] n in self?.deleteWords(n) }
        return k
    }

    func letters(_ chars: String, _ hints: String) -> [KeyButton] {
        let h = Array(hints)
        var out: [KeyButton] = []
        for (i, c) in chars.enumerated() {
            let k = makeKey(String(c), hint: i < h.count ? String(h[i]) : nil)
            letterKeys.append(k)
            out.append(k)
        }
        return out
    }

    func hstack(_ views: [UIView], spacing: CGFloat = 5, equal: Bool = true, margin: CGFloat = 0) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = spacing
        s.distribution = equal ? .fillEqually : .fill
        if margin > 0 {
            s.isLayoutMarginsRelativeArrangement = true
            s.layoutMargins = UIEdgeInsets(top: 0, left: margin, bottom: 0, right: margin)
        }
        return s
    }

    func fixed(_ v: UIView, _ width: CGFloat) -> UIView {
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    func pinEdges(_ v: UIView, in parent: UIView, insets: UIEdgeInsets = .zero) {
        v.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func fillRows(_ rows: [UIView], spacing: CGFloat, insets: UIEdgeInsets) {
        let v = UIStackView(arrangedSubviews: rows)
        v.axis = .vertical
        v.spacing = spacing
        v.distribution = .fillEqually
        pinEdges(v, in: keyArea, insets: insets)
    }

    // MARK: - 자판

    /// 영문 쿼티와 한글 두벌식이 같은 배치를 쓴다
    func buildLetters(rows: [String]) {
        let on = settings.naraHints        // "보조키 표시" 설정. 모든 자판에 같이 적용된다
        let row1 = hstack(letters(rows[0], on ? "1234567890" : ""))
        let row2 = hstack(letters(rows[1], on ? "@#$%&-+()" : ""), margin: 19)

        let shiftK = iconKey("shift", id: "shift", label: lang == .english ? "대문자" : "쌍자음", fallback: "⇧")
        shiftKey = shiftK
        let mid = hstack(letters(rows[2], on ? "*\"':;!?" : ""), margin: 6)
        let row3 = hstack([fixed(shiftK, 46), mid, fixed(backspaceKey(), 46)], equal: false)

        let row4: UIStackView
        if fieldKind == .email || fieldKind == .url {
            // 이메일·주소 칸: @ 또는 / 키를 두고, 마침표를 꾹 누르면 .com
            let extra = fieldKind == .email ? "@" : "/"
            row4 = hstack([
                fixed(numKey("123"), 46),
                fixed(makeKey(extra, font: 19), 40),
                spaceKey(),
                fixed(makeKey(".", hint: ".com", font: 20), 40),
                fixed(returnKey(), 70),
            ], equal: false)
        } else {
            row4 = hstack([
                fixed(numKey("123"), 52),
                spaceKey(),
                fixed(makeKey(".", hint: ",", fn: true), 46),      // 쉼표는 마침표를 꾹 눌러서
                fixed(returnKey(), 76),
            ], equal: false)
        }

        fillRows([row1, row2, row3, row4], spacing: 8, insets: UIEdgeInsets(top: 6, left: 4, bottom: 2, right: 4))
    }

    func buildNara() {
        let hints = settings.naraHints
        func jamo(_ title: String, _ id: String, _ digit: String) -> KeyButton {
            let k = makeKey(title, id: id, hint: hints ? digit : nil, font: 24)      // 예전 22
            k.layer.cornerRadius = 8
            return k
        }
        func rounded(_ k: KeyButton) -> KeyButton {
            k.layer.cornerRadius = 8
            return k
        }
        // 오타 줄이기 B: 글자 칸과 오른쪽 기능 칸 사이를 넓히고(6→12), 줄 사이도 넓힌다(6→9)
        func row(_ letters: [UIView], _ fn: UIView) -> UIStackView {
            let r = hstack(letters + [fn], spacing: 6)
            if let last = letters.last { r.setCustomSpacing(12, after: last) }
            return r
        }
        let row1 = row([jamo("ㄱ", "ㄱ", "1"), jamo("ㄴ", "ㄴ", "2"), jamo("ㅏ ㅓ", "v:ㅏㅓ", "3")], rounded(backspaceKey()))
        let row2 = row([jamo("ㄹ", "ㄹ", "4"), jamo("ㅁ", "ㅁ", "5"), jamo("ㅗ ㅜ", "v:ㅗㅜ", "6")], rounded(spaceKey()))
        // 123 은 ㅣ 옆이라 잘못 눌리기 쉬워서 왼쪽 가장자리 9pt 는 ㅣ 로 본다
        let num = rounded(numKey("123"))
        num.guardInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 0)
        let punctAndNum = hstack([num, rounded(makeKey(settings.punctQuestionFirst ? "?!.," : ".,?!", id: "punct", fn: true, font: 15))], spacing: 5)
        let row3 = row([jamo("ㅅ", "ㅅ", "7"), jamo("ㅇ", "ㅇ", "8"), jamo("ㅣ", "ㅣ", "9")], punctAndNum)
        // 맨 아래 줄은 손가락이 위로 닿기 쉬워서, 키 위쪽 5pt 까지 이 줄의 키로 받는다
        let bottom = [rounded(makeKey("획추가", id: "stroke", font: 17)), jamo("ㅡ", "ㅡ", "0"),
                      rounded(makeKey("쌍자음", id: "double", font: 17))]
        let ret = rounded(returnKey())
        for k in bottom + [ret] { k.reachUp = 5 }
        let row4 = row(bottom, ret)
        fillRows([row1, row2, row3, row4], spacing: 9, insets: UIEdgeInsets(top: 6, left: 6, bottom: 2, right: 6))
    }

    /// 숫자·전화번호 칸: 바로 숫자판
    func buildNumpad() {
        func digit(_ d: String, _ letters: String, hint: String? = nil) -> KeyButton {
            let k = makeKey(d, hint: hint, font: 24)
            k.layer.cornerRadius = 8
            if !letters.isEmpty {
                let s = NSMutableAttributedString(string: d, attributes: [
                    .font: UIFont.systemFont(ofSize: 24), .foregroundColor: theme.text])
                s.append(NSAttributedString(string: "\n" + letters, attributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: theme.hint, .kern: 1]))
                k.setAttributedTitle(s, for: .normal)
                k.titleLabel?.numberOfLines = 2
                k.titleLabel?.textAlignment = .center
            }
            return k
        }
        func fn(_ k: KeyButton) -> KeyButton {
            k.layer.cornerRadius = 8
            return k
        }
        let back = fn(makeKey(lang == .hangul ? "가" : "ABC", id: "tokeys", fn: true, font: 16))
        back.accessibilityLabel = "글자 자판으로"
        let rows = [
            hstack([digit("1", ""), digit("2", "ABC"), digit("3", "DEF"), fn(backspaceKey())], spacing: 6),
            hstack([digit("4", "GHI"), digit("5", "JKL"), digit("6", "MNO"), fn(makeKey("-", fn: true, font: 22))], spacing: 6),
            hstack([digit("7", "PQRS"), digit("8", "TUV"), digit("9", "WXYZ"), fn(makeKey(".", fn: true, font: 22))], spacing: 6),
            hstack([back, digit("0", "", hint: "+"), fn(makeKey(",", fn: true, font: 22)), fn(returnKey())], spacing: 6),
        ]
        fillRows(rows, spacing: 6, insets: UIEdgeInsets(top: 6, left: 6, bottom: 2, right: 6))
    }

    func buildSymbols() {
        func keys(_ chars: String) -> [KeyButton] {
            chars.map { makeKey(String($0), font: 19) }
        }
        let pages: [[String]] = [
            ["1234567890", "+×÷=/_<>[]", "@#$%^&*()", "-'\":;!?,."],
            ["1234567890", "~`|\\{}€£¥₩", "°•…§¶©®™✓", "¿¡«»≠≈±←→"],
        ]
        let p = pages[symbolPage]
        let row1 = hstack(keys(p[0]))
        let row2 = hstack(keys(p[1]))
        let row3 = hstack(keys(p[2]), margin: 19)
        let pageKey = makeKey(symbolPage == 0 ? "1/2" : "2/2", id: "sympage", fn: true, font: 14)
        pageKey.accessibilityLabel = "기호 다음 쪽"
        var fourth: [UIView] = [pageKey]
        for k in keys(p[3]) { fourth.append(k) }
        let row4 = hstack(fourth)
        let back = numKey(lang == .hangul ? "가" : "ABC")
        back.accessibilityLabel = "글자 자판으로 돌아가기"
        let row5 = hstack([fixed(back, 52), spaceKey(), fixed(backspaceKey(), 59), fixed(returnKey(), 45)], equal: false)
        fillRows([row1, row2, row3, row4, row5], spacing: 6, insets: UIEdgeInsets(top: 6, left: 4, bottom: 2, right: 4))
    }
}
