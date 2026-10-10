import UIKit

/// 클립보드, 설정, 학습한 단어 패널
extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {

    // MARK: - 한 번 더 눌러야 실행되는 버튼 (전체 삭제 등)

    /// 처음 누르면 글자가 확인 문구로 바뀌고 false, 3초 안에 다시 누르면 true
    func confirmed(_ b: UIButton, title: String) -> Bool {
        if armedButton === b {
            disarm()
            return true
        }
        disarm()
        armedButton = b
        armedTitle = b.title(for: .normal)
        armedBackground = b.backgroundColor
        armedColor = b.titleColor(for: .normal)
        b.setTitle(title, for: .normal)
        b.backgroundColor = theme.danger
        b.setTitleColor(theme.onDanger, for: .normal)
        armTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.disarm()
        }
        return false
    }

    func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        if let b = armedButton, let t = armedTitle {
            b.setTitle(t, for: .normal)
            b.backgroundColor = armedBackground
            b.setTitleColor(armedColor, for: .normal)
        }
        armedButton = nil
        armedTitle = nil
        armedBackground = nil
        armedColor = nil
    }

    func emptyLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.numberOfLines = 0
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 14)
        l.textColor = theme.muted
        return l
    }

    // MARK: - 클립보드 패널

    @objc func clearClipFilter() {
        clipFilter = nil
        rebuild()
    }

    func buildClipboard() {
        clipItems = clipFilter.map { clipMatches($0) } ?? store.sorted
        let table = PanelTableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 50
        table.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
        table.dataSource = self
        table.delegate = self
        table.register(ClipCell.self, forCellReuseIdentifier: "clip")
        table.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(clipLongPressed(_:))))
        pinEdges(table, in: keyArea)
        clipTable = table

        if clipItems.isEmpty, clipFilter != nil {
            pinEdges(emptyLabel("맞는 항목이 없어요."), in: keyArea, insets: UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24))
        } else if clipItems.isEmpty {
            let text = hasFullAccess
                ? "아직 기록이 없습니다.\n텍스트를 복사한 뒤 이 키보드를 열면 저장됩니다."
                : "설정 > 일반 > 키보드 > 키보드 > 클립보드에서\n'전체 접근 허용'을 켜야 복사한 내용을 읽을 수 있습니다."
            pinEdges(emptyLabel(text), in: keyArea, insets: UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24))
        }
    }

    func reloadClips() {
        guard panel == .clipboard else { return }
        buildBody()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        clipItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip", for: indexPath)
        guard let clipCell = cell as? ClipCell, indexPath.row < clipItems.count else { return cell }
        let clip = clipItems[indexPath.row]
        let thumbnail = store.thumbURL(clip).flatMap { UIImage(contentsOfFile: $0.path) }
        clipCell.configure(clip, confirming: clip.id == confirmingID, theme: theme, thumbnail: thumbnail)
        clipCell.onPin = { [weak self] in
            self?.store.togglePin(clip.id)
            self?.reloadClips()
        }
        clipCell.onDelete = { [weak self] in
            guard let self = self else { return }
            if clip.pinned {
                self.confirmingID = clip.id        // 고정한 항목만 한 번 더 묻는다
                self.reloadClips()
            } else {
                self.deleteClip(clip)
            }
        }
        clipCell.onCancel = { [weak self] in
            self?.confirmingID = nil
            self?.reloadClips()
        }
        clipCell.onConfirm = { [weak self] in
            self?.confirmingID = nil
            self?.deleteClip(clip)
        }
        return clipCell
    }

    /// 항목을 누르면 붙여넣고 자판으로 돌아간다
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < clipItems.count else { return }
        let clip = clipItems[indexPath.row]
        guard clip.id != confirmingID else { return }
        pasteClip(clip)
    }

    func pasteClip(_ clip: Clip) {
        if clip.image != nil {
            copyImage(clip)
            return
        }
        resetComposer()
        docInsert(clip.text)
        clipFilter = nil
        if freshClip?.id == clip.id { freshClip = nil }
        panel = .keys
        rebuild()
    }

    /// 키보드는 입력창에 사진을 직접 넣을 수 없다. 다시 "복사된 상태"로 돌려놓고 안내한다.
    func copyImage(_ clip: Clip) {
        guard let url = store.imageURL(clip), let data = try? Data(contentsOf: url) else { return }
        let pb = UIPasteboard.general
        pb.setData(data, forPasteboardType: "public.jpeg")
        lastChangeCount = pb.changeCount       // 우리가 넣은 것을 새 복사로 다시 저장하지 않게
        showToast("사진을 복사했습니다.\n입력창을 길게 눌러 붙여넣으세요.")
    }

    /// 알림 줄 바탕: 라이트는 거의 검정, 다크는 바탕보다 밝은 회색 (글씨는 늘 흰색)
    var barColor: UIColor { Theme.hex(isDark ? 0x3A3D43 : 0x16181C) }
    /// 이모지 패널에서는 아래 [가] [간격] [지우기] 줄을 가리지 않게 그 위에 띄운다
    var barLift: CGFloat { panel == .emoji ? -48 : -6 }

    /// 목록 아래에 잠깐 뜨는 안내
    func showToast(_ text: String) {
        undoTimer?.invalidate()
        undoBar?.removeFromSuperview()
        undoAction = nil

        let bar = UIView()
        bar.backgroundColor = barColor
        bar.layer.cornerRadius = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        pinEdges(label, in: bar, insets: UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 14))
        keyArea.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -6),
            bar.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor, constant: barLift),
        ])
        undoBar = bar
        undoTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.undoBar?.removeFromSuperview()
        }
    }

    func deleteClip(_ clip: Clip) {
        store.delete(clip.id)
        if freshClip?.id == clip.id { freshClip = nil }
        reloadClips()
        showUndoBar("1개 삭제됨") { [weak self] in
            self?.store.restore(clip)
            self?.reloadClips()
        }
    }

    /// 지운 뒤 5초 동안 아래 알림 줄에 되돌리기를 보여 준다 (클립보드, 단어 관리, 스티커)
    func showUndoBar(_ text: String, action: @escaping () -> Void) {
        undoTimer?.invalidate()
        undoBar?.removeFromSuperview()
        undoAction = action

        let bar = UIView()
        bar.backgroundColor = barColor
        bar.layer.cornerRadius = 10
        bar.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let undo = undoChip("되돌리기", onBar: true)
        undo.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, undo])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        pinEdges(stack, in: bar, insets: UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 6))

        keyArea.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -6),
            bar.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor, constant: barLift),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
        undoBar = bar
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.undoBar?.removeFromSuperview()
            self?.undoAction = nil
        }
    }

    @objc func undoTapped() {
        undoTimer?.invalidate()
        undoBar?.removeFromSuperview()
        let action = undoAction
        undoAction = nil
        action?()
    }

    @objc func clearClipsTapped(_ sender: UIButton) {
        guard confirmed(sender, title: "삭제") else { return }
        store.clearUnpinned()          // 고정한 항목은 남긴다
        freshClip = nil
        reloadClips()
    }

    /// 길게 누르면 전체 내용을 보여 준다
    @objc func clipLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let table = clipTable,
              let path = table.indexPathForRow(at: g.location(in: table)),
              path.row < clipItems.count else { return }
        showPreview(clipItems[path.row])
    }

    func showPreview(_ clip: Clip) {
        previewView?.removeFromSuperview()
        previewClip = clip

        let cover = UIView()
        cover.backgroundColor = theme.bg

        let textView = UITextView()
        textView.text = clip.text
        textView.isEditable = false
        textView.isSelectable = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = theme.text
        textView.backgroundColor = theme.row
        textView.layer.cornerRadius = 8

        var content: UIView = textView
        var pasteTitle = "붙여넣기"
        if clip.image != nil, let url = store.imageURL(clip), let img = UIImage(contentsOfFile: url.path) {
            let imageView = UIImageView(image: img)
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = theme.row
            imageView.layer.cornerRadius = 8
            imageView.clipsToBounds = true
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
            content = imageView
            pasteTitle = "복사"
        }

        let close = toolButton("닫기", action: #selector(closePreview))
        let paste = toolButton(pasteTitle, active: true, action: #selector(pastePreview))
        var row: [UIView] = [close]
        if clip.image != nil {
            // 사진은 스티커 팩에 넣을 수 있다
            row.append(toolButton("스티커로", symbol: "smile", action: #selector(previewToSticker)))
        }
        row.append(paste)
        let buttons = hstack(row, spacing: 6)

        let stack = UIStackView(arrangedSubviews: [content, buttons])
        stack.axis = .vertical
        stack.spacing = 6
        pinEdges(stack, in: cover, insets: UIEdgeInsets(top: 6, left: 6, bottom: 8, right: 6))
        pinEdges(cover, in: keyArea)
        previewView = cover
    }

    @objc func closePreview() {
        previewView?.removeFromSuperview()
        previewClip = nil
    }

    @objc func previewToSticker() {
        guard let clip = previewClip else { return }
        closePreview()
        showStickerPicker(preselect: clip.id)
    }

    @objc func pastePreview() {
        guard let clip = previewClip else { return }
        closePreview()
        pasteClip(clip)
    }

    // MARK: - 설정 패널

    func settingRow(_ title: String, _ control: UIView) -> UIView {
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 15)
        l.textColor = theme.text
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.8
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [l, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    // MARK: iOS 설정 모양 묶음 (작은 회색 소제목 + 둥근 카드 + 아래 설명)

    /// 카드 안 줄 글자와 같은 들여쓰기
    static let groupIndent: CGFloat = 16

    /// 묶음 위 작은 회색 소제목
    func groupCaption(_ title: String) -> UIView {
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 13)
        l.textColor = theme.muted
        let box = UIView()
        l.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l)
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: box.topAnchor),
            l.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: KeyboardViewController.groupIndent),
            l.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -KeyboardViewController.groupIndent),
        ])
        return box
    }

    /// 묶음 아래 작은 설명
    func groupFooter(_ text: String) -> UIView {
        let l = UILabel()
        l.text = text
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 12)
        l.textColor = theme.muted
        let box = UIView()
        l.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l)
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            l.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: KeyboardViewController.groupIndent),
            l.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -KeyboardViewController.groupIndent),
        ])
        return box
    }

    /// 줄들을 둥근 카드로 묶는다. 줄 사이에는 왼쪽을 들여 쓴 구분선.
    func groupCard(_ rows: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = theme.row
        card.layer.cornerRadius = 12
        card.clipsToBounds = true
        let stack = UIStackView()
        stack.axis = .vertical
        for (i, r) in rows.enumerated() {
            let wrap = UIView()
            r.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(r)
            let tappable = r is GroupNavRow
            NSLayoutConstraint.activate([
                r.topAnchor.constraint(equalTo: wrap.topAnchor, constant: tappable ? 0 : 2),
                r.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: tappable ? 0 : -2),
                r.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: tappable ? 0 : KeyboardViewController.groupIndent),
                r.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: tappable ? 0 : -12),
                wrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])
            if i < rows.count - 1 {
                let line = UIView()
                line.backgroundColor = theme.divider.withAlphaComponent(0.7)
                line.translatesAutoresizingMaskIntoConstraints = false
                wrap.addSubview(line)
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: KeyboardViewController.groupIndent),
                    line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
                    line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                    line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                ])
            }
            stack.addArrangedSubview(wrap)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    /// 카드 안에서 위아래 여백을 더 주는 줄 (슬라이더처럼 여러 줄인 것)
    func padded(_ v: UIView, _ inset: CGFloat = 6) -> UIView {
        let box = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: box.topAnchor, constant: inset),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -inset),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }

    /// 줄 전체를 누르면 들어가는 줄: [제목 … 값 ›]
    func navRow(_ title: String, value: String?, action: Selector) -> GroupNavRow {
        let row = GroupNavRow(title: title, value: value, theme: theme)
        row.addTarget(self, action: action, for: .touchUpInside)
        return row
    }

    /// 소제목, 카드, 설명을 차례로 세로로 쌓는다. 묶음 사이는 넓게 띄운다.
    func groupedStack(_ groups: [(title: String?, rows: [UIView], footer: String?)]) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        for (i, g) in groups.enumerated() {
            if let t = g.title { stack.addArrangedSubview(groupCaption(t)) }
            let card = groupCard(g.rows)
            stack.addArrangedSubview(card)
            var last: UIView = card
            if let f = g.footer {
                last = groupFooter(f)
                stack.addArrangedSubview(last)
            }
            if i < groups.count - 1 { stack.setCustomSpacing(22, after: last) }
        }
        return stack
    }

    func segment(_ items: [String], selected: Int, tag: Int) -> UISegmentedControl {
        let s = UISegmentedControl(items: items)
        s.selectedSegmentIndex = selected
        s.tag = tag
        s.widthAnchor.constraint(equalToConstant: 200).isActive = true
        s.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        return s
    }

    func toggle(_ on: Bool, tag: Int) -> UISwitch {
        let s = UISwitch()
        s.isOn = on
        s.tag = tag
        s.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        return s
    }

    func buildSettings() {
        let counts = [20, 50, 100]
        let countIndex = counts.firstIndex(of: settings.maxClips) ?? 1

        let wordCount = words.manualWords.count + words.learnedWords.count

        let stack = groupedStack([
            ("자판", [
                settingRow("한글 자판", segment(["나랏글", "두벌식"], selected: settings.hangulLayout, tag: 0)),
                settingRow("보조키 표시 (꾹 눌러 숫자·기호)", toggle(settings.naraHints, tag: 10)),
                settingRow("키 글자 크기", segment(["작게", "보통", "크게"], selected: settings.keyFontSize, tag: 5)),
                settingRow("나랏글 문장부호 키", segment([". , ? !", "? ! . ,"], selected: settings.punctQuestionFirst ? 1 : 0, tag: 6)),
                settingRow("나랏글 줄바꿈 키 위치", segment(["맨 아래", "한 줄 위"], selected: settings.naraReturnUp ? 1 : 0, tag: 7)),
                settingRow("영문 문장 첫 글자 대문자", toggle(settings.autoCap, tag: 12)),
                settingRow("간격 두 번 누르면", segment(["끄기", "마침표 .", "쉼표 ,"], selected: settings.doubleSpace, tag: 3)),
                padded(sliderRow("키 높이", note: "100%가 지금 높이 · 낮추면 키보드가 화면을 덜 가려요",
                                 min: Float(Settings.keyHeightRange.lowerBound), max: Float(Settings.keyHeightRange.upperBound),
                                 value: Float(settings.keyHeightPercent), low: "낮게", high: "높게", tag: 3)),
                padded(sliderRow("클립보드·설정 높이", note: "이 두 화면만 키보드를 더 높여 목록을 넓게 · 0이면 같은 높이",
                                 min: Float(Settings.panelExtraRange.lowerBound), max: Float(Settings.panelExtraRange.upperBound),
                                 value: Float(settings.panelExtra), low: "같게", high: "높게", tag: 8)),
                padded(sliderRow("상단바 높이", note: "46이 지금 높이 · 도구 줄만 낮아져요",
                                 min: Float(Settings.toolbarHeightRange.lowerBound), max: Float(Settings.toolbarHeightRange.upperBound),
                                 value: Float(settings.toolbarHeightValue), low: "낮게", high: "높게", tag: 4)),
            ], nil),
            ("입력", [
                settingRow("길게 누르면 반복 입력", toggle(settings.repeatOnHold, tag: 17)),
                settingRow("입력 영역 (웹 깜빡임 줄이기)", segment(["끄기", "브라우저", "항상"], selected: settings.stagedMode, tag: 9)),
                padded(sliderRow("반복 입력 속도", note: "누르고 있을 때 반복되는 빠르기 (지우기 키도 같이)",
                                 min: 0, max: 9, value: Float(settings.repeatSpeed), low: "느리게", high: "빠르게", tag: 1)),
                padded(sliderRow("길게 누르기 시간", note: "보조 글자 말풍선과 반복 입력이 시작되는 시간 · 최소 0.3초",
                                 min: Float(Settings.longPressRange.lowerBound), max: Float(Settings.longPressRange.upperBound),
                                 value: Float(settings.longPressTime), low: "짧게", high: "길게", tag: 2)),
            ], "입력 영역: 치는 단어를 추천 줄 맨 앞 칸에 모았다가 간격·문장부호를 누르거나 잠깐 멈추면 앱에 한 번에 보내요. 사파리 웹 입력창의 커서 깜빡임이 줄어요. '브라우저'는 사파리·크롬 등에서만 자동으로 켜요."),
            ("상단바", [
                navRow("상단바 꾸미기", value: nil, action: #selector(openToolbarEdit)),
                settingRow("오타 교정 (한글·영문)", segment(["끄기", "추천만", "자동"], selected: settings.correctMode, tag: 4)),
                navRow("단어 관리", value: wordCount > 0 ? "\(formatted(wordCount))개" : nil, action: #selector(openWords)),
            ], nil),
            ("클립보드", [
                settingRow("기록 보관 개수", segment(["20", "50", "100"], selected: countIndex, tag: 2)),
                settingRow("사진도 저장 (최근 10장)", toggle(settings.savePhotos, tag: 16)),
            ], nil),
            ("공통", [
                settingRow("화면 모드", segment(["시스템", "라이트", "다크"], selected: settings.themeMode, tag: 1)),
                settingRow("키 누를 때 진동", toggle(settings.haptic, tag: 11)),
                settingRow("키 누를 때 소리", toggle(settings.keySound, tag: 15)),
            ], nil),
            ("정보", [appVersionRow(), dictionaryRow(), diagnosticsRow()], nil),
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = PanelScrollView(frame: .zero)
        pinEdges(scroll, in: keyArea)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -20),
        ])
    }

    @objc func segmentChanged(_ s: UISegmentedControl) {
        switch s.tag {
        case 0:
            settings.hangulLayout = s.selectedSegmentIndex
            resetComposer()
        case 1:
            settings.themeMode = s.selectedSegmentIndex
            rebuild()
        case 5:
            settings.keyFontSize = s.selectedSegmentIndex
        case 6:
            settings.punctQuestionFirst = s.selectedSegmentIndex == 1
        case 7:
            settings.naraReturnUp = s.selectedSegmentIndex == 1
        case 9:
            resetComposer()
            flushStaged()
            settings.stagedMode = s.selectedSegmentIndex
        case 3:
            settings.doubleSpace = s.selectedSegmentIndex
        case 4:
            settings.correctMode = min(max(s.selectedSegmentIndex, 0), 2)
        case 2:
            settings.maxClips = [20, 50, 100][min(max(s.selectedSegmentIndex, 0), 2)]
            store.trimAndSave()
        default:
            break
        }
    }

    @objc func switchChanged(_ s: UISwitch) {
        switch s.tag {
        case 10: settings.naraHints = s.isOn
        case 11: settings.haptic = s.isOn
        case 12: settings.autoCap = s.isOn
        case 13: settings.autoCorrect = s.isOn
        case 14: settings.showArrows = s.isOn
        case 15: settings.keySound = s.isOn
        case 16: settings.savePhotos = s.isOn
        case 17: settings.repeatOnHold = s.isOn

        case 19:
            settings.fewContextReads = s.isOn
            ctxCache = nil
        case 18:
            resetComposer()
            settings.markedComposing = s.isOn
        default: break
        }
    }

    // MARK: 정보

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    func valueLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14)
        l.textColor = theme.muted
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    static let numberFormat: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    func formatted(_ n: Int) -> String {
        KeyboardViewController.numberFormat.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 정보 줄: [제목 값 / 아래 설명] [버튼]. 버튼 폭을 같게 해서 오른쪽 끝을 맞춘다.
    func infoRow(_ titleText: String, action: Selector) -> (row: UIView, value: UILabel, caption: UILabel, button: UIButton) {
        let title = UILabel()
        title.text = titleText
        title.font = .systemFont(ofSize: 15)
        title.textColor = theme.text
        title.setContentHuggingPriority(.required, for: .horizontal)
        let value = valueLabel("")
        let top = UIStackView(arrangedSubviews: [title, value, UIView()])
        top.axis = .horizontal
        top.alignment = .firstBaseline
        top.spacing = 6

        let caption = UILabel()
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = theme.muted
        caption.lineBreakMode = .byTruncatingTail

        let texts = UIStackView(arrangedSubviews: [top, caption])
        texts.axis = .vertical
        texts.spacing = 3
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = UIButton(type: .system)
        button.titleLabel?.font = .boldSystemFont(ofSize: 14)
        button.layer.cornerRadius = 8
        button.backgroundColor = theme.funcKey
        button.setTitleColor(theme.text, for: .normal)
        button.widthAnchor.constraint(equalToConstant: 104).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [texts, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return (row, value, caption, button)
    }

    /// 화면 모드·높이 진단 줄: 문제가 생긴 상태에서 이 줄을 찍어 보내면 원인을 찾을 수 있다
    func diagnosticsRow() -> UIView {
        func style(_ t: UITraitCollection?) -> String {
            guard let t = t else { return "-" }
            switch t.userInterfaceStyle {
            case .dark: return "다크"
            case .light: return "라이트"
            default: return "?"
            }
        }
        let appearance: String
        switch textDocumentProxy.keyboardAppearance {
        case .dark: appearance = "다크"
        case .light: appearance = "라이트"
        default: appearance = "기본"
        }
        let win = view.window
        let top = win.map { view.convert(CGPoint.zero, to: $0).y } ?? -1
        let lines = [
            "앱 요청 \(appearance) · 창 \(style(win?.traitCollection)) · 윗뷰 \(style(view.superview?.traitCollection))",
            "컨트롤러 \(style(traitCollection)) · 화면 \(style(UIScreen.main.traitCollection)) · 적용 \(isDark ? "다크" : "라이트")",
            "앱 \(hostBundleID ?? "알 수 없음") · 입력 영역 \(stagingWanted ? "켜짐" : "꺼짐")",
            "높이 원함 \(Int(viewHeight?.constant ?? 0)) · 실제 \(Int(view.bounds.height)) · 창 안 위치 \(Int(top)) · 창 높이 \(Int(win?.bounds.height ?? 0))",
        ]
        let l = UILabel()
        l.numberOfLines = 0
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        l.textColor = theme.muted
        l.text = "진단\n" + lines.joined(separator: "\n")
        return padded(l, 8)
    }

    /// 맞춤법 사전 줄
    func dictionaryRow() -> UIView {
        let r = infoRow("맞춤법 사전", action: #selector(dictionaryButtonTapped))
        dictCaptionLabel = r.caption
        dictValueLabel = r.value
        dictButton = r.button
        updateDictionaryRow()
        if KoDictionary.shared.info == nil {
            KoDictionary.shared.preload { [weak self] in self?.updateDictionaryRow() }
        }
        return r.row
    }

    /// 앱 버전 줄. 설정을 열면 한 번 저절로 새 버전을 확인한다.
    func appVersionRow() -> UIView {
        let r = infoRow("앱 버전", action: #selector(appUpdateTapped))
        r.value.text = UpdateCheck.currentText
        appCaptionLabel = r.caption
        appButton = r.button
        updateAppVersionRow()
        if appUpdateCaption == nil { appUpdateTapped() }
        return r.row
    }

    func updateAppVersionRow() {
        guard let caption = appCaptionLabel, let button = appButton else { return }
        let c = appUpdateCaption ?? ("", false)
        caption.text = appUpdateBusy ? "확인하는 중…" : c.text
        caption.font = c.strong && !appUpdateBusy ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        caption.textColor = c.strong && !appUpdateBusy ? theme.text : theme.muted
        button.setTitle("업데이트 확인", for: .normal)
        button.isEnabled = !appUpdateBusy
        button.alpha = appUpdateBusy ? 0.5 : 1
    }

    @objc func appUpdateTapped() {
        guard !appUpdateBusy else { return }
        guard hasFullAccess else {
            appUpdateCaption = ("전체 접근 허용을 켜야 확인할 수 있어요", false)
            updateAppVersionRow()
            return
        }
        appUpdateBusy = true
        updateAppVersionRow()
        UpdateCheck.check { [weak self] result in
            guard let self = self else { return }
            self.appUpdateBusy = false
            switch result {
            case .latest: self.appUpdateCaption = ("최신 버전이에요 · 방금 확인", false)
            case .newer(let v): self.appUpdateCaption = ("새 버전 \(v.text) · SideStore에서 업데이트하세요", true)
            case .failed(let why): self.appUpdateCaption = ("확인하지 못했어요 · " + why, false)
            }
            self.updateAppVersionRow()
        }
    }

    func updateDictionaryRow() {
        guard let value = dictValueLabel, let caption = dictCaptionLabel, let button = dictButton else { return }
        let info = KoDictionary.shared.info
        let missing = info.map { $0.words == 0 } ?? false
        if let info = info, !missing {
            value.text = formatted(info.words) + "단어"
            value.font = .systemFont(ofSize: 14)
            value.textColor = theme.muted
            var where_ = "기본 사전"
            if case .downloaded(let date) = info.source {
                let f = DateFormatter()
                f.dateFormat = "MM/dd"
                where_ = "받은 사전 · " + f.string(from: date)
            }
            caption.text = "활용형 \(formatted(info.forms))개 · " + where_
        } else if missing {
            value.text = "없음"
            value.font = .boldSystemFont(ofSize: 14)
            value.textColor = theme.danger
            caption.text = "전체 접근 허용이 켜져 있어야 받을 수 있어요"
        } else {
            value.text = ""
            caption.text = "사전을 읽는 중…"
        }
        if let status = dictStatus { caption.text = status }

        value.font = missing ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 14)
        button.setTitle(dictBusy ? "받는 중" : (missing ? "사전 받기" : "업데이트"), for: .normal)
        button.isEnabled = !dictBusy && info != nil
        button.backgroundColor = missing ? theme.accent : theme.funcKey
        button.setTitleColor(missing ? theme.onAccent : theme.text, for: .normal)
        button.alpha = button.isEnabled ? 1 : 0.5
    }

    @objc func dictionaryButtonTapped() {
        guard !dictBusy else { return }
        guard hasFullAccess else {
            dictStatus = "전체 접근 허용을 켜야 받을 수 있어요"
            updateDictionaryRow()
            return
        }
        dictBusy = true
        dictStatus = "GitHub에서 받는 중…"
        updateDictionaryRow()
        KoDictionary.shared.download { [weak self] result in
            guard let self = self else { return }
            self.dictBusy = false
            switch result {
            case .updated(let n): self.dictStatus = "새 사전을 받았어요 (\(self.formatted(n))단어)"
            case .alreadyLatest: self.dictStatus = "이미 최신 사전이에요"
            case .failed(let why): self.dictStatus = "받지 못했어요: " + why
            }
            self.updateDictionaryRow()
            KoCorrector.shared.reset()
            self.koCache.removeAll()
            self.lastSuggestSignature = nil
        }
    }

    // MARK: 슬라이더

    /// [제목 값 / 설명] 아래에 [낮음 ——●—— 높음]
    func sliderRow(_ title: String, note: String, min: Float, max: Float, value: Float,
                   low: String, high: String, tag: Int) -> UIView {
        let t = UILabel()
        t.text = title
        t.font = .systemFont(ofSize: 15)
        t.textColor = theme.text
        t.setContentHuggingPriority(.required, for: .horizontal)
        let v = valueLabel(sliderText(tag, value))
        v.tag = 1000 + tag
        let top = UIStackView(arrangedSubviews: [t, v, UIView()])
        top.axis = .horizontal
        top.alignment = .firstBaseline
        top.spacing = 6
        let n = UILabel()
        n.text = note
        n.font = .systemFont(ofSize: 12)
        n.textColor = theme.muted
        n.adjustsFontSizeToFitWidth = true
        n.minimumScaleFactor = 0.8
        let lo = UILabel()
        lo.text = low
        let hi = UILabel()
        hi.text = high
        for l in [lo, hi] {
            l.font = .systemFont(ofSize: 12)
            l.textColor = theme.muted
            l.setContentHuggingPriority(.required, for: .horizontal)
        }
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.tag = tag
        slider.minimumTrackTintColor = theme.accent
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        let line = UIStackView(arrangedSubviews: [lo, slider, hi])
        line.axis = .horizontal
        line.alignment = .center
        line.spacing = 10
        let col = UIStackView(arrangedSubviews: [top, n, line])
        col.axis = .vertical
        col.spacing = 4
        return col
    }

    func sliderText(_ tag: Int, _ value: Float) -> String {
        switch tag {
        case 1: return "\(Int(value.rounded()))"
        case 3: return "\(Int(value.rounded()))%"
        case 4: return "\(Int(value.rounded()))"
        case 8: return "+\(Int(value.rounded()))"
        default: return String(format: "%.2f초", Double(value))
        }
    }

    @objc func sliderChanged(_ s: UISlider) {
        if s.tag == 1 {
            s.value = s.value.rounded()                       // 0~9 한 칸씩
            settings.repeatSpeed = Int(s.value)
        } else if s.tag == 3 {
            s.value = s.value.rounded()
            if settings.keyHeightPercent != Int(s.value) {
                settings.keyHeightPercent = Int(s.value)
                rebuildHeights()                              // 바로 높이를 바꿔 보여 준다
            }
        } else if s.tag == 8 {
            s.value = (s.value / 10).rounded() * 10           // 10 단위
            if settings.panelExtra != Int(s.value) {
                settings.panelExtra = Int(s.value)
                rebuildHeights()                              // 설정 화면도 이 높이를 쓰므로 바로 보인다
            }
        } else if s.tag == 4 {
            s.value = s.value.rounded()
            if settings.toolbarHeightValue != Int(s.value) {
                settings.toolbarHeightValue = Int(s.value)
                rebuildHeights()
            }
        } else {
            s.value = (s.value / 0.05).rounded() * 0.05       // 0.05초 단위
            settings.longPressTime = Double(s.value)
        }
        (s.superview?.superview?.viewWithTag(1000 + s.tag) as? UILabel)?.text = sliderText(s.tag, s.value)
    }

    // MARK: 상단바 꾸미기

    func openToolbarEditButton() -> UIButton {
        let b = toolButton("열기 ›", action: #selector(openToolbarEdit))
        b.titleLabel?.font = .boldSystemFont(ofSize: 14)
        return b
    }

    @objc func openToolbarEdit() {
        panel = .toolbarEdit
        rebuild()
    }

    @objc func resetToolbarTapped() {
        settings.resetToolbar()
        buildBody()
    }

    func buildToolbarEdit() {
        let editor = ToolbarEditor(settings: settings, theme: theme)
        toolbarEditList = editor
        pinEdges(editor, in: keyArea)
    }

    @objc func openWords() {
        panel = .words
        rebuild()
    }

    @objc func clearWordsTapped(_ sender: UIButton) {
        guard confirmed(sender, title: "한 번 더 누르면 모두 삭제") else { return }
        words.clear()
        nextWords.clear()
        if panel == .words { buildBody() }
    }

    // MARK: - 학습한 단어 패널

    /// 단어 관리: 위에 직접 넣은 단어(★), 아래에 자주 친 단어(횟수, ☆ 로 위로 옮기기)
    func buildWords() {
        let manual = words.manualWords
        let learned = words.learnedWords
        wordList = manual + learned.map { $0.word }
        if wordList.isEmpty {
            pinEdges(emptyLabel("아직 단어가 없습니다.\n'단어 추가'로 넣거나, 같은 단어를 다섯 번 이상 치면 여기에 나옵니다."),
                     in: keyArea, insets: UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24))
            return
        }
        let scroll = PanelScrollView(frame: .zero)
        pinEdges(scroll, in: keyArea)
        let full = keyArea.bounds.width > 0 ? keyArea.bounds.width : UIScreen.main.bounds.width
        // 설정 화면과 같은 모양: 작은 회색 소제목, 둥근 카드 안에 단어 칩, 카드 아래 설명
        let cardLeft: CGFloat = 10
        let cardRight = full - 10
        let left = cardLeft + 10
        let right = cardRight - 10
        let indent = cardLeft + KeyboardViewController.groupIndent
        var y: CGFloat = 12

        func caption(_ title: String) {
            let l = UILabel(frame: CGRect(x: indent, y: y, width: full - indent * 2, height: 16))
            l.text = title
            l.font = .systemFont(ofSize: 13)
            l.textColor = theme.muted
            scroll.addSubview(l)
            y += 22
        }

        func footer(_ text: String) {
            let l = UILabel(frame: CGRect(x: indent, y: y + 6, width: full - indent * 2, height: 15))
            l.text = text
            l.font = .systemFont(ofSize: 12)
            l.textColor = theme.muted
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.8
            scroll.addSubview(l)
            y += 21
        }

        /// 카드를 그리고 그 안에 내용을 놓는다. content 는 카드 안 y 를 받아 다 쓴 뒤의 y 를 돌려준다.
        func card(_ content: (CGFloat) -> CGFloat) {
            let top = y
            let c = UIView()
            c.backgroundColor = theme.row
            c.layer.cornerRadius = 12
            scroll.addSubview(c)
            let end = content(top + 10)
            c.frame = CGRect(x: cardLeft, y: top, width: cardRight - cardLeft, height: end - top + 10)
            scroll.sendSubviewToBack(c)
            y = end + 10
        }

        func chips(_ items: [(word: String, count: Int?)], startIndex: Int, manual: Bool, from startY: CGFloat) -> CGFloat {
            var x = left
            var cy = startY
            for (offset, item) in items.enumerated() {
                let index = startIndex + offset
                let label = UILabel()
                label.text = item.word
                label.font = .systemFont(ofSize: 15)
                label.textColor = theme.text
                label.sizeToFit()
                var extra: CGFloat = 0
                let countLabel = UILabel()
                if let c = item.count {
                    countLabel.text = "\(c)회"
                    countLabel.font = .systemFont(ofSize: 11)
                    countLabel.textColor = theme.muted
                    countLabel.sizeToFit()
                    extra += countLabel.bounds.width + 5
                }
                let starW: CGFloat = manual ? 18 : 0
                let promoteW: CGFloat = manual ? 0 : 32
                let textWidth = min(label.bounds.width, right - left - 90)
                let chipWidth = 10 + starW + textWidth + extra + 6 + promoteW + 32
                if x + chipWidth > right, x > left {
                    x = left
                    cy += 42
                }
                let chip = UIView(frame: CGRect(x: x, y: cy, width: chipWidth, height: 36))
                chip.backgroundColor = theme.bg
                chip.layer.cornerRadius = 18
                var cx: CGFloat = 10
                if manual {
                    let star = UIImageView(image: Icon.image("star", size: 13))
                    star.tintColor = theme.muted
                    star.frame = CGRect(x: cx, y: 11.5, width: 13, height: 13)
                    chip.addSubview(star)
                    cx += starW
                }
                label.frame = CGRect(x: cx, y: 0, width: textWidth, height: 36)
                chip.addSubview(label)
                cx += textWidth + 5
                if item.count != nil {
                    countLabel.frame = CGRect(x: cx, y: 0, width: countLabel.bounds.width, height: 36)
                    chip.addSubview(countLabel)
                }
                if !manual {
                    let up = UIButton(type: .system)
                    up.frame = CGRect(x: chipWidth - 64, y: 4, width: 28, height: 28)
                    up.setImage(Icon.image("star.outline", size: 14, line: 2), for: .normal)
                    up.tintColor = theme.muted
                    up.backgroundColor = theme.row
                    up.layer.cornerRadius = 14
                    up.tag = index
                    up.accessibilityLabel = "직접 넣은 단어로 옮기기"
                    up.addTarget(self, action: #selector(wordPromoteTapped(_:)), for: .touchUpInside)
                    chip.addSubview(up)
                }
                let del = UIButton(type: .system)
                del.frame = CGRect(x: chipWidth - 32, y: 4, width: 28, height: 28)
                del.setImage(Icon.image("xmark", size: 14, line: 2.5), for: .normal)
                del.tintColor = theme.text
                del.backgroundColor = theme.row
                del.layer.cornerRadius = 14
                del.tag = index
                del.accessibilityLabel = "이 단어 지우기"
                del.addTarget(self, action: #selector(wordDeleteTapped(_:)), for: .touchUpInside)
                chip.addSubview(del)
                scroll.addSubview(chip)
                x += chipWidth + 6
            }
            return cy + 36
        }

        caption("직접 넣은 단어 · \(manual.count)개")
        card { top in
            if manual.isEmpty {
                let l = UILabel(frame: CGRect(x: indent, y: top, width: full - indent * 2, height: 24))
                l.text = "상단바의 + 나 '단어 추가'로 넣을 수 있습니다."
                l.font = .systemFont(ofSize: 14)
                l.textColor = theme.muted
                scroll.addSubview(l)
                return top + 24
            }
            return chips(manual.map { ($0, nil) }, startIndex: 0, manual: true, from: top)
        }
        footer("늘 맨 먼저 추천합니다")
        y += 22
        caption("자주 친 단어 · \(learned.count)개")
        if learned.isEmpty {
            card { top in
                let l = UILabel(frame: CGRect(x: indent, y: top, width: full - indent * 2, height: 24))
                l.text = "같은 단어를 다섯 번 이상 치면 여기에 나옵니다."
                l.font = .systemFont(ofSize: 14)
                l.textColor = theme.muted
                scroll.addSubview(l)
                return top + 24
            }
        } else {
            card { top in chips(learned.map { ($0.word, Optional($0.count)) }, startIndex: manual.count, manual: false, from: top) }
            footer("☆ 를 누르면 직접 넣은 단어로 옮깁니다")
        }
        y += 22
        // 모두 지우기: 설정 첫 화면에서 빼서 여기 맨 아래로 (잘못 누르기 어렵게, 두 번 눌러야 지움)
        let clear = UIButton(type: .system)
        clear.frame = CGRect(x: cardLeft, y: y, width: cardRight - cardLeft, height: 44)
        clear.backgroundColor = theme.row
        clear.layer.cornerRadius = 12
        clear.setTitle("단어 모두 지우기", for: .normal)
        clear.setTitleColor(theme.danger, for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 15)
        clear.addTarget(self, action: #selector(clearWordsTapped(_:)), for: .touchUpInside)
        scroll.addSubview(clear)
        y += 44
        scroll.contentSize = CGSize(width: full, height: y + 14)
    }

    @objc func wordPromoteTapped(_ sender: UIButton) {
        guard sender.tag < wordList.count else { return }
        words.addManual(wordList[sender.tag])
        buildBody()
    }

    @objc func wordDeleteTapped(_ sender: UIButton) {
        guard sender.tag < wordList.count else { return }
        let w = wordList[sender.tag]
        let count = words.remove(w)
        buildBody()
        showUndoBar("‘\(w)’ 삭제됨") { [weak self] in
            self?.words.restore(w, count: count ?? WordStore.threshold)
            self?.buildBody()
        }
    }
}
