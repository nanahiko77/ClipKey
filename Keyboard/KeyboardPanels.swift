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

    /// 목록 아래에 잠깐 뜨는 안내
    func showToast(_ text: String) {
        undoTimer?.invalidate()
        undoBar?.removeFromSuperview()
        undoClip = nil

        let bar = UIView()
        bar.backgroundColor = theme.text
        bar.layer.cornerRadius = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        label.textColor = theme.bg
        pinEdges(label, in: bar, insets: UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 14))
        keyArea.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -6),
            bar.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor, constant: -6),
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
        let buttons = hstack([close, paste], spacing: 6)

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
            settingRow("보조키 표시 (꾹 눌러 숫자·기호)", toggle(settings.naraHints, tag: 10)),
            settingRow("영문 문장 첫 글자 대문자", toggle(settings.autoCap, tag: 12)),
            settingRow("간격 두 번 누르면", segment(["끄기", "마침표 .", "쉼표 ,"], selected: settings.doubleSpace, tag: 3)),
            settingHeader("상단바"),
            settingRow("커서 좌우 화살표", toggle(settings.showArrows, tag: 14)),
            settingRow("오타 교정 (한글·영문)", segment(["끄기", "추천만", "자동"], selected: settings.correctMode, tag: 4)),
            settingRow("학습한 단어", wordButtons),
            settingHeader("클립보드"),
            settingRow("기록 보관 개수", segment(["20", "50", "100"], selected: countIndex, tag: 2)),
            settingRow("사진도 저장 (최근 10장)", toggle(settings.savePhotos, tag: 16)),
            settingHeader("공통"),
            settingRow("화면 모드", segment(["시스템", "라이트", "다크"], selected: settings.themeMode, tag: 1)),
            settingRow("키 누를 때 진동", toggle(settings.haptic, tag: 11)),
            settingRow("키 누를 때 소리", toggle(settings.keySound, tag: 15)),
            settingHeader("정보"),
            settingRow("버전", valueLabel(appVersion)),
            dictionaryRow(),
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

    /// 맞춤법 사전 줄: 제목과 작은 설명, 단어 수, 받기/업데이트 버튼
    func dictionaryRow() -> UIView {
        let title = UILabel()
        title.text = "맞춤법 사전"
        title.font = .systemFont(ofSize: 15)
        title.textColor = theme.text
        let caption = UILabel()
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = theme.muted
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.8
        let texts = UIStackView(arrangedSubviews: [title, caption])
        texts.axis = .vertical
        texts.spacing = 2
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let value = valueLabel("")
        let button = toolButton("업데이트", action: #selector(dictionaryButtonTapped))
        button.titleLabel?.font = .boldSystemFont(ofSize: 14)

        let row = UIStackView(arrangedSubviews: [texts, value, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 48).isActive = true

        dictCaptionLabel = caption
        dictValueLabel = value
        dictButton = button
        updateDictionaryRow()
        if KoDictionary.shared.info == nil {
            KoDictionary.shared.preload { [weak self] in self?.updateDictionaryRow() }
        }
        return row
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
            self.lastSuggestSignature = nil
        }
    }

    @objc func openWords() {
        panel = .words
        rebuild()
    }

    @objc func clearWordsTapped(_ sender: UIButton) {
        guard confirmed(sender, title: "삭제") else { return }
        words.clear()
        nextWords.clear()
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
            del.setImage(Icon.image("xmark", size: 14, line: 2.5), for: .normal)
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
