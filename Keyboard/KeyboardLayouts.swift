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
        return Icon.image(name, size: 18, line: 1.75)
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
        switch panel {
        case .keys, .symbols:
            if adding {
                // 단어 추가: 한/영과 123 은 남기고, 나머지 자리에 입력칸과 취소/저장
                let langKey = toolButton(width: 44, label: "한영 전환", action: #selector(langTapped))
                langKey.setAttributedTitle(langTitle(), for: .normal)
                toolbar.addArrangedSubview(langKey)
                toolbar.addArrangedSubview(toolButton("123", width: 44, active: panel == .symbols,
                                                      label: "숫자와 기호", action: #selector(numTapped)))
                let box = UIView()
                box.backgroundColor = theme.key
                box.layer.cornerRadius = 8
                box.heightAnchor.constraint(equalToConstant: 36).isActive = true
                box.setContentHuggingPriority(.defaultLow, for: .horizontal)
                box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                let field = UILabel()
                field.font = .systemFont(ofSize: 15)
                field.textColor = theme.text
                field.lineBreakMode = .byTruncatingHead
                field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                pinEdges(field, in: box, insets: UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10))
                addField = field
                updateAddField()
                toolbar.addArrangedSubview(box)
                toolbar.addArrangedSubview(toolButton("취소", width: 46, action: #selector(cancelAddWord)))
                toolbar.addArrangedSubview(toolButton("저장", width: 46, active: true, action: #selector(saveAddWord)))
                break
            }
            let langB = toolButton(width: 44, label: "한영 전환", action: #selector(langTapped))
            langB.setAttributedTitle(langTitle(), for: .normal)
            toolbar.addArrangedSubview(langB)
            toolbar.addArrangedSubview(toolButton("123", width: 44, active: panel == .symbols,
                                                  label: "숫자와 기호", action: #selector(numTapped)))
            toolbar.addArrangedSubview(toolButton(symbol: "clipboard", width: 40, plain: true,
                                                  color: theme.accent, label: "클립보드 열기",
                                                  action: #selector(clipTapped)))
            toolbar.addArrangedSubview(suggestScroll)
            if settings.showArrows {
                toolbar.addArrangedSubview(toolButton(symbol: "chevron.left", width: 36, plain: true,
                                                      label: "커서 왼쪽으로", action: #selector(cursorLeft)))
                toolbar.addArrangedSubview(toolButton(symbol: "chevron.right", width: 36, plain: true,
                                                      label: "커서 오른쪽으로", action: #selector(cursorRight)))
            }
        case .clipboard:
            toolbar.addArrangedSubview(toolButton("한", width: 44, label: "한글 자판으로", action: #selector(toHangul)))
            toolbar.addArrangedSubview(toolButton("ENG", width: 52, label: "영문 자판으로", action: #selector(toEnglish)))
            toolbar.addArrangedSubview(toolButton(symbol: "clipboard", width: 40, active: true,
                                                  label: "클립보드 닫기", action: #selector(backToKeys)))
            toolbar.addArrangedSubview(toolbarTitle("클립보드"))
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
            toolbar.addArrangedSubview(toolbarTitle("설정"))
            toolbar.addArrangedSubview(toolButton(symbol: "slider.horizontal.3", width: 40, active: true,
                                                  label: "설정 닫기", action: #selector(clipTapped)))
        case .words:
            toolbar.addArrangedSubview(toolButton(symbol: "chevron.left", width: 44,
                                                  label: "설정으로 돌아가기", action: #selector(openSettings)))
            toolbar.addArrangedSubview(toolbarTitle("학습한 단어"))
            let clear = toolButton("모두 지우기", plain: true, color: theme.danger, action: #selector(clearWordsTapped(_:)))
            clear.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(clear)
            let add = toolButton("단어 추가", action: #selector(startAddWord))
            add.titleLabel?.font = .boldSystemFont(ofSize: 14)
            toolbar.addArrangedSubview(add)
        }
    }

    // MARK: - 본문

    func buildBody() {
        keyArea.subviews.forEach { $0.removeFromSuperview() }
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
        case .clipboard:
            buildClipboard()
        case .settings:
            buildSettings()
        case .words:
            buildWords()
        }
    }

    // MARK: - 키 만들기

    func style(_ k: KeyButton, fn: Bool) {
        k.backgroundColor = fn ? theme.funcKey : theme.key
        k.setTitleColor(theme.text, for: .normal)
        k.tintColor = theme.text
        k.hintColor = theme.hint
        k.bubbleBackground = theme.key
        k.bubbleText = theme.text
        k.bubbleHost = view
    }

    func wire(_ k: KeyButton) {
        k.onDown = { [weak self] in self?.haptic() }
        k.onTap = { [weak self] key in self?.handleKey(key.id) }
        k.onHint = { [weak self] s in self?.insertPlain(s) }
    }

    func makeKey(_ title: String, id: String? = nil, hint: String? = nil, fn: Bool = false,
                 font: CGFloat = 20) -> KeyButton {
        let k = KeyButton()
        k.id = id ?? title
        k.setTitle(title, for: .normal)
        k.titleLabel?.font = .systemFont(ofSize: font)
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
            k.backgroundColor = theme.accent
            k.tintColor = theme.onAccent
            k.setTitleColor(theme.onAccent, for: .normal)
        }
        k.accessibilityLabel = label
        wire(k)
        return k
    }

    func spaceKey() -> KeyButton {
        iconKey("space", id: "space", label: "간격", fn: false, fallback: "간격")
    }

    func returnKey() -> KeyButton {
        iconKey("return", id: "return", label: "줄바꿈", accent: true, fallback: "↵")
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
        k.altHoverBackground = theme.danger
        k.altHoverText = theme.onDanger
        k.onAlt = { [weak self] in self?.deleteAll() }
        k.onAltHover = {
            // 설정과 상관없이, 전체 삭제가 걸렸다는 것은 진동으로 알린다
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
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
        let row1 = hstack(letters(rows[0], "1234567890"))
        let row2 = hstack(letters(rows[1], "@#$%&-+()"), margin: 19)

        let shiftK = iconKey("shift", id: "shift", label: lang == .english ? "대문자" : "쌍자음", fallback: "⇧")
        shiftKey = shiftK
        let mid = hstack(letters(rows[2], "*\"':;!?"), margin: 6)
        let row3 = hstack([fixed(shiftK, 46), mid, fixed(backspaceKey(), 46)], equal: false)

        let row4 = hstack([
            fixed(makeKey(",", fn: true), 46),
            spaceKey(),
            fixed(makeKey(".", fn: true), 46),
            fixed(returnKey(), 76),
        ], equal: false)

        fillRows([row1, row2, row3, row4], spacing: 8, insets: UIEdgeInsets(top: 6, left: 4, bottom: 8, right: 4))
    }

    func buildNara() {
        let hints = settings.naraHints
        func jamo(_ title: String, _ id: String, _ digit: String) -> KeyButton {
            let k = makeKey(title, id: id, hint: hints ? digit : nil, font: 22)
            k.layer.cornerRadius = 8
            return k
        }
        func rounded(_ k: KeyButton) -> KeyButton {
            k.layer.cornerRadius = 8
            return k
        }
        let row1 = hstack([jamo("ㄱ", "ㄱ", "1"), jamo("ㄴ", "ㄴ", "2"), jamo("ㅏ ㅓ", "v:ㅏㅓ", "3"),
                           rounded(backspaceKey())], spacing: 6)
        let row2 = hstack([jamo("ㄹ", "ㄹ", "4"), jamo("ㅁ", "ㅁ", "5"), jamo("ㅗ ㅜ", "v:ㅗㅜ", "6"),
                           rounded(spaceKey())], spacing: 6)
        let row3 = hstack([jamo("ㅅ", "ㅅ", "7"), jamo("ㅇ", "ㅇ", "8"), jamo("ㅣ", "ㅣ", "9"),
                           rounded(makeKey(". , ? !", id: "punct", fn: true, font: 18))], spacing: 6)
        let row4 = hstack([rounded(makeKey("획추가", id: "stroke", font: 16)), jamo("ㅡ", "ㅡ", "0"),
                           rounded(makeKey("쌍자음", id: "double", font: 16)), rounded(returnKey())], spacing: 6)
        fillRows([row1, row2, row3, row4], spacing: 6, insets: UIEdgeInsets(top: 6, left: 6, bottom: 8, right: 6))
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
        let row5 = hstack([spaceKey(), fixed(backspaceKey(), 60), fixed(returnKey(), 76)], equal: false)
        fillRows([row1, row2, row3, row4, row5], spacing: 6, insets: UIEdgeInsets(top: 6, left: 4, bottom: 8, right: 4))
    }
}
