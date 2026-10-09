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
            settingHeader("입력"),
            settingRow("길게 누르면 반복 입력", toggle(settings.repeatOnHold, tag: 17)),
            sliderRow("반복 입력 속도", note: "누르고 있을 때 반복되는 빠르기 (지우기 키도 같이)",
                      min: 0, max: 9, value: Float(settings.repeatSpeed), low: "느리게", high: "빠르게", tag: 1),
            sliderRow("길게 누르기 시간", note: "보조 글자 말풍선과 반복 입력이 시작되는 시간 · 최소 0.3초",
                      min: Float(Settings.longPressRange.lowerBound), max: Float(Settings.longPressRange.upperBound),
                      value: Float(settings.longPressTime), low: "짧게", high: "길게", tag: 2),
            settingHeader("상단바"),
            settingRow("상단바 꾸미기", openToolbarEditButton()),
            settingRow("오타 교정 (한글·영문)", segment(["끄기", "추천만", "자동"], selected: settings.correctMode, tag: 4)),
            settingRow("단어 관리", wordButtons),
            settingHeader("클립보드"),
            settingRow("기록 보관 개수", segment(["20", "50", "100"], selected: countIndex, tag: 2)),
            settingRow("사진도 저장 (최근 10장)", toggle(settings.savePhotos, tag: 16)),
            settingHeader("공통"),
            settingRow("화면 모드", segment(["시스템", "라이트", "다크"], selected: settings.themeMode, tag: 1)),
            settingRow("키 누를 때 진동", toggle(settings.haptic, tag: 11)),
            settingRow("키 누를 때 소리", toggle(settings.keySound, tag: 15)),
            settingHeader("정보"),
            appVersionRow(),
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
        case 17: settings.repeatOnHold = s.isOn
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
        tag == 1 ? "\(Int(value.rounded()))" : String(format: "%.2f초", Double(value))
    }

    @objc func sliderChanged(_ s: UISlider) {
        if s.tag == 1 {
            s.value = s.value.rounded()                       // 0~9 한 칸씩
            settings.repeatSpeed = Int(s.value)
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
        let list = ToolbarEditList(settings: settings, theme: theme)
        toolbarEditList = list
        pinEdges(list.table, in: keyArea)
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
        let scroll = UIScrollView()
        pinEdges(scroll, in: keyArea)
        let full = keyArea.bounds.width > 0 ? keyArea.bounds.width : UIScreen.main.bounds.width
        let left: CGFloat = 8
        let right = full - 8
        var y: CGFloat = 6

        func header(_ title: String, _ note: String) {
            let l = UILabel(frame: CGRect(x: left + 2, y: y, width: right - left, height: 20))
            let s = NSMutableAttributedString(string: title, attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: theme.text])
            s.append(NSAttributedString(string: "  " + note, attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: theme.muted]))
            l.attributedText = s
            scroll.addSubview(l)
            y += 26
        }

        func chips(_ items: [(word: String, count: Int?)], startIndex: Int, manual: Bool) {
            var x = left
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
                    y += 42
                }
                let chip = UIView(frame: CGRect(x: x, y: y, width: chipWidth, height: 36))
                chip.backgroundColor = theme.row
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
                    up.backgroundColor = theme.bg
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
                del.backgroundColor = theme.bg
                del.layer.cornerRadius = 14
                del.tag = index
                del.accessibilityLabel = "이 단어 지우기"
                del.addTarget(self, action: #selector(wordDeleteTapped(_:)), for: .touchUpInside)
                chip.addSubview(del)
                scroll.addSubview(chip)
                x += chipWidth + 6
            }
            y += 48
        }

        header("직접 넣은 단어", "\(manual.count)개 · 늘 맨 먼저 추천")
        if manual.isEmpty {
            let l = UILabel(frame: CGRect(x: left + 2, y: y, width: right - left, height: 20))
            l.text = "상단바의 + 나 '단어 추가'로 넣을 수 있습니다."
            l.font = .systemFont(ofSize: 13)
            l.textColor = theme.muted
            scroll.addSubview(l)
            y += 30
        } else {
            chips(manual.map { ($0, nil) }, startIndex: 0, manual: true)
        }
        header("자주 친 단어", "\(learned.count)개 · ☆ 를 누르면 위로 옮김")
        chips(learned.map { ($0.word, Optional($0.count)) }, startIndex: manual.count, manual: false)
        scroll.contentSize = CGSize(width: full, height: y + 8)
    }

    @objc func wordPromoteTapped(_ sender: UIButton) {
        guard sender.tag < wordList.count else { return }
        words.addManual(wordList[sender.tag])
        buildBody()
    }

    @objc func wordDeleteTapped(_ sender: UIButton) {
        guard sender.tag < wordList.count else { return }
        words.remove(wordList[sender.tag])
        buildBody()
    }
}


// MARK: - 상단바 꾸미기 목록

/// 상단바 도구를 켜고 끄고, ≡ 를 끌어서 순서를 바꾼다.
/// 위 묶음: 순서를 바꿀 수 있는 도구. 아래 묶음: 오른쪽 끝에 붙는 화살표와 닫기.
final class ToolbarEditList: NSObject, UITableViewDataSource, UITableViewDelegate {
    let table = UITableView(frame: .zero, style: .plain)
    private let settings: Settings
    private let theme: Theme
    private var order: [String]
    private let preview = UIStackView()

    static let names: [String: String] = [
        "clipboard": "클립보드", "settings": "설정", "addword": "단어 추가", "emoji": "이모지",
        "arrows": "커서 좌우 화살표", "hide": "키보드 닫기",
    ]
    static let notes: [String: String] = ["addword": "치던 말을 바로 등록", "emoji": "준비 중 · 다음 단계에서 만듦"]
    static let icons: [String: String] = [
        "clipboard": "clipboard", "settings": "slider.horizontal.3", "addword": "plus", "emoji": "smile",
        "arrows": "chevron.right", "hide": "keyboard.down",
    ]
    static let fixed = ["arrows", "hide"]

    init(settings: Settings, theme: Theme) {
        self.settings = settings
        self.theme = theme
        self.order = settings.toolbarOrder
        super.init()
        table.dataSource = self
        table.delegate = self
        table.isEditing = true
        table.allowsSelectionDuringEditing = false
        table.backgroundColor = .clear
        table.separatorColor = theme.divider
        table.rowHeight = 48
        table.tableHeaderView = makeHeader()
    }

    // 미리 보기와 안내 문구
    private func makeHeader() -> UIView {
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 104))
        let top = UILabel()
        top.text = "미리 보기 · 켠 것만 이 순서대로 보입니다"
        top.font = .systemFont(ofSize: 12)
        top.textColor = theme.muted
        let bottom = UILabel()
        bottom.text = "≡ 를 끌어서 순서를 바꿉니다. 화살표와 닫기는 오른쪽 끝에 붙습니다."
        bottom.font = .systemFont(ofSize: 12)
        bottom.textColor = theme.muted
        bottom.adjustsFontSizeToFitWidth = true
        bottom.minimumScaleFactor = 0.8
        let card = UIView()
        card.backgroundColor = theme.row
        card.layer.cornerRadius = 10
        preview.axis = .horizontal
        preview.alignment = .center
        preview.spacing = 2
        preview.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(preview)
        for v in [top, card, bottom] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            card.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            card.heightAnchor.constraint(equalToConstant: 42),
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            preview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            preview.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            bottom.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
        ])
        updatePreview()
        return box
    }

    private func previewIcon(_ name: String) -> UIView {
        let v = UIImageView(image: Icon.image(name, size: 18, line: 1.75))
        v.tintColor = theme.text
        v.contentMode = .center
        v.widthAnchor.constraint(equalToConstant: 32).isActive = true
        v.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return v
    }

    private func updatePreview() {
        preview.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let lang = UILabel()
        lang.text = "한/영"
        lang.font = .boldSystemFont(ofSize: 13)
        lang.textAlignment = .center
        lang.textColor = theme.text
        lang.backgroundColor = theme.funcKey
        lang.layer.cornerRadius = 7
        lang.layer.masksToBounds = true
        lang.widthAnchor.constraint(equalToConstant: 42).isActive = true
        lang.heightAnchor.constraint(equalToConstant: 30).isActive = true
        preview.addArrangedSubview(lang)
        let off = settings.toolbarOff
        for item in order where !off.contains(item) && item != "emoji" {
            preview.addArrangedSubview(previewIcon(ToolbarEditList.icons[item] ?? "plus"))
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        preview.addArrangedSubview(spacer)
        if settings.showArrows {
            preview.addArrangedSubview(previewIcon("chevron.left"))
            preview.addArrangedSubview(previewIcon("chevron.right"))
        }
        if settings.showHide { preview.addArrangedSubview(previewIcon("keyboard.down")) }
    }

    private func key(_ indexPath: IndexPath) -> String {
        indexPath.section == 0 ? order[indexPath.row] : ToolbarEditList.fixed[indexPath.row]
    }

    private func isOn(_ item: String) -> Bool {
        switch item {
        case "arrows": return settings.showArrows
        case "hide": return settings.showHide
        default: return !settings.toolbarOff.contains(item)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? order.count : ToolbarEditList.fixed.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = key(indexPath)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.text = ToolbarEditList.names[item]
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.textColor = theme.text
        cell.detailTextLabel?.text = ToolbarEditList.notes[item]
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = theme.muted
        cell.imageView?.image = Icon.image(ToolbarEditList.icons[item] ?? "plus", size: 18, line: 1.75)
        cell.imageView?.tintColor = theme.text
        let sw = UISwitch()
        sw.isOn = item == "emoji" ? false : isOn(item)
        sw.isEnabled = item != "emoji"
        sw.accessibilityLabel = ToolbarEditList.names[item]
        sw.tag = indexPath.section * 100 + indexPath.row
        sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        cell.accessoryView = sw
        cell.editingAccessoryView = sw
        cell.showsReorderControl = indexPath.section == 0
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "왼쪽 (한/영 다음)" : "오른쪽 끝"
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.section == 0 }

    /// 위 묶음 안에서만 옮길 수 있다
    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath,
                   toProposedIndexPath proposed: IndexPath) -> IndexPath {
        proposed.section == 0 ? proposed : IndexPath(row: order.count - 1, section: 0)
    }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let item = order.remove(at: source.row)
        order.insert(item, at: destination.row)
        settings.toolbarOrder = order
        updatePreview()
        // 스위치의 tag 가 줄 번호라서 다시 그린다
        DispatchQueue.main.async { tableView.reloadData() }
    }

    @objc private func switchChanged(_ sw: UISwitch) {
        let item = key(IndexPath(row: sw.tag % 100, section: sw.tag / 100))
        switch item {
        case "arrows": settings.showArrows = sw.isOn
        case "hide": settings.showHide = sw.isOn
        default:
            var off = settings.toolbarOff.filter { $0 != item }
            if !sw.isOn { off.append(item) }
            settings.toolbarOff = off
        }
        updatePreview()
    }
}
