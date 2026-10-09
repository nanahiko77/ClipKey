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
        b.setTitle(title, for: .normal)
        armTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.disarm()
        }
        return false
    }

    func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        if let b = armedButton, let t = armedTitle { b.setTitle(t, for: .normal) }
        armedButton = nil
        armedTitle = nil
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

    func buildClipboard() {
        clipItems = store.sorted
        let table = UITableView(frame: .zero, style: .plain)
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

        if clipItems.isEmpty {
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
        clipCell.configure(clip, confirming: clip.id == confirmingID, theme: theme)
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
        resetComposer()
        textDocumentProxy.insertText(clip.text)
        if freshClip?.id == clip.id { freshClip = nil }
        panel = .keys
        rebuild()
    }

    func deleteClip(_ clip: Clip) {
        store.delete(clip.id)
        if freshClip?.id == clip.id { freshClip = nil }
        reloadClips()
        showUndo(clip)
    }

    /// 지운 뒤 몇 초 동안 되돌리기를 보여 준다
    func showUndo(_ clip: Clip) {
        undoTimer?.invalidate()
        undoBar?.removeFromSuperview()
        undoClip = clip

        let bar = UIView()
        bar.backgroundColor = theme.text
        bar.layer.cornerRadius = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "1개 삭제됨"
        label.font = .systemFont(ofSize: 14)
        label.textColor = theme.bg
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let undo = UIButton(type: .system)
        undo.setTitle("되돌리기", for: .normal)
        undo.titleLabel?.font = .boldSystemFont(ofSize: 14)
        undo.setTitleColor(theme.text, for: .normal)
        undo.backgroundColor = theme.funcKey
        undo.layer.cornerRadius = 8
        undo.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        undo.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
            bar.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 42),
        ])
        undoBar = bar
        undoTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.undoBar?.removeFromSuperview()
            self?.undoClip = nil
        }
    }

    @objc func undoTapped() {
        undoTimer?.invalidate()
        if let clip = undoClip { store.restore(clip) }
        undoClip = nil
        reloadClips()
    }

    @objc func clearClipsTapped(_ sender: UIButton) {
        guard confirmed(sender, title: "삭제 확인") else { return }
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

        let close = toolButton("닫기", action: #selector(closePreview))
        let paste = toolButton("붙여넣기", active: true, action: #selector(pastePreview))
        let buttons = hstack([close, paste], spacing: 6)

        let stack = UIStackView(arrangedSubviews: [textView, buttons])
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

    @objc func pastePreview() {
        guard let clip = previewClip else { return }
        previewClip = nil
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

    /// 설정 묶음의 제목
    func settingHeader(_ title: String) -> UIView {
        let l = UILabel()
        l.text = title
        l.font = .boldSystemFont(ofSize: 16)
        l.textColor = theme.text
        l.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return l
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

        let manage = toolButton("단어 관리", action: #selector(openWords))
        manage.titleLabel?.font = .boldSystemFont(ofSize: 14)
        let clear = toolButton("모두 지우기", color: theme.danger, action: #selector(clearWordsTapped(_:)))
        clear.titleLabel?.font = .boldSystemFont(ofSize: 14)
        let wordButtons = hstack([manage, clear], spacing: 6, equal: false)

        let rows: [UIView] = [
            settingHeader("자판"),
            settingRow("한글 자판", segment(["나랏글", "두벌식"], selected: settings.hangulLayout, tag: 0)),
            settingRow("나랏글 보조키 (꾹 눌러 숫자)", toggle(settings.naraHints, tag: 10)),
            settingRow("영문 문장 첫 글자 대문자", toggle(settings.autoCap, tag: 12)),
            settingHeader("상단바"),
            settingRow("커서 좌우 화살표", toggle(settings.showArrows, tag: 14)),
            settingRow("영문 오타 자동 교정", toggle(settings.autoCorrect, tag: 13)),
            settingRow("학습한 단어", wordButtons),
            settingHeader("클립보드"),
            settingRow("기록 보관 개수", segment(["20", "50", "100"], selected: countIndex, tag: 2)),
            settingHeader("공통"),
            settingRow("화면 모드", segment(["시스템", "라이트", "다크"], selected: settings.themeMode, tag: 1)),
            settingRow("키 누를 때 진동", toggle(settings.haptic, tag: 11)),
        ]

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 묶음과 묶음 사이는 넓게 띄운다
        for i in 1..<rows.count where rows[i] is UILabel {
            stack.setCustomSpacing(18, after: rows[i - 1])
        }

        let scroll = UIScrollView()
        pinEdges(scroll, in: keyArea)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
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
        default: break
        }
    }

    @objc func openWords() {
        panel = .words
        rebuild()
    }

    @objc func clearWordsTapped(_ sender: UIButton) {
        guard confirmed(sender, title: "삭제 확인") else { return }
        words.clear()
        if panel == .words { buildBody() }
    }

    // MARK: - 학습한 단어 패널

    func buildWords() {
        wordList = words.list
        if wordList.isEmpty {
            pinEdges(emptyLabel("아직 학습한 단어가 없습니다.\n같은 단어를 두 번 이상 치면 여기에 나옵니다."),
                     in: keyArea, insets: UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24))
            return
        }

        let scroll = UIScrollView()
        pinEdges(scroll, in: keyArea)

        let full = keyArea.bounds.width > 0 ? keyArea.bounds.width : UIScreen.main.bounds.width
        let left: CGFloat = 8
        let right = full - 8

        let info = UILabel(frame: CGRect(x: left, y: 8, width: right - left, height: 16))
        info.text = "자주 친 순서입니다. × 를 누르면 그 단어만 지웁니다."
        info.font = .systemFont(ofSize: 12)
        info.textColor = theme.muted
        scroll.addSubview(info)

        var x = left
        var y: CGFloat = 32
        for (i, word) in wordList.enumerated() {
            let label = UILabel()
            label.text = word
            label.font = .systemFont(ofSize: 15)
            label.textColor = theme.text
            label.sizeToFit()
            let textWidth = min(label.bounds.width, right - left - 50)
            let chipWidth = 12 + textWidth + 6 + 28 + 4
            if x + chipWidth > right, x > left {
                x = left
                y += 42
            }
            let chip = UIView(frame: CGRect(x: x, y: y, width: chipWidth, height: 36))
            chip.backgroundColor = theme.row
            chip.layer.cornerRadius = 18
            label.frame = CGRect(x: 12, y: 0, width: textWidth, height: 36)
            chip.addSubview(label)

            let del = UIButton(type: .system)
            del.frame = CGRect(x: chipWidth - 32, y: 4, width: 28, height: 28)
            del.setImage(UIImage(systemName: "xmark",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
            del.tintColor = theme.text
            del.backgroundColor = theme.bg
            del.layer.cornerRadius = 14
            del.tag = i
            del.accessibilityLabel = "이 단어 지우기"
            del.addTarget(self, action: #selector(wordDeleteTapped(_:)), for: .touchUpInside)
            chip.addSubview(del)

            scroll.addSubview(chip)
            x += chipWidth + 6
        }
        scroll.contentSize = CGSize(width: full, height: y + 44)
    }

    @objc func wordDeleteTapped(_ sender: UIButton) {
        guard sender.tag < wordList.count else { return }
        words.remove(wordList[sender.tag])
        buildBody()
    }
}
