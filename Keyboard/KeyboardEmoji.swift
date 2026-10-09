import UIKit

// MARK: - 격자 (이모지, 스티커, 스티커로 넣을 사진 고르기)

final class GridCell: UICollectionViewCell {
    let label = UILabel()
    let imageView = UIImageView()
    let check = UIImageView()
    let ring = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 28)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        ring.layer.cornerRadius = 11
        ring.layer.borderWidth = 2.5
        ring.isHidden = true
        check.contentMode = .center
        check.layer.cornerRadius = 10
        check.clipsToBounds = true
        for v in [label, imageView, ring, check] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            ring.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -1),
            ring.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 1),
            ring.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -1),
            ring.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 1),
            check.widthAnchor.constraint(equalToConstant: 20),
            check.heightAnchor.constraint(equalToConstant: 20),
            check.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 4),
            check.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 이모지·스티커를 칸에 나눠 보여 준다. 사진 고르기에서는 여러 개를 선택할 수 있다.
final class GridPanel: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Item {
        case emoji(String)
        case image(URL)
    }

    let view: UICollectionView
    var items: [Item]
    let columns: Int
    let rowHeight: CGFloat
    let theme: Theme
    var selectable = false
    var selected: [Int] = []
    var onPick: ((Int) -> Void)?
    var onLongPress: ((Int) -> Void)?
    var onSelectionChange: (() -> Void)?

    init(items: [Item], columns: Int, rowHeight: CGFloat, theme: Theme) {
        self.items = items
        self.columns = columns
        self.rowHeight = rowHeight
        self.theme = theme
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init()
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.register(GridCell.self, forCellWithReuseIdentifier: "cell")
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        guard let c = cell as? GridCell, indexPath.item < items.count else { return cell }
        switch items[indexPath.item] {
        case .emoji(let e):
            c.label.text = e
            c.label.isHidden = false
            c.imageView.isHidden = true
            c.imageView.image = nil
        case .image(let url):
            c.label.isHidden = true
            c.imageView.isHidden = false
            c.imageView.image = UIImage(contentsOfFile: url.path)
            c.imageView.backgroundColor = theme.row
        }
        let on = selected.contains(indexPath.item)
        c.ring.isHidden = !(selectable && on)
        c.ring.layer.borderColor = theme.accent.cgColor
        c.check.isHidden = !selectable
        c.check.backgroundColor = on ? theme.accent : UIColor.white.withAlphaComponent(0.8)
        c.check.tintColor = theme.onAccent
        c.check.image = on ? Icon.image("check", size: 13, line: 3) : nil
        c.check.layer.borderWidth = on ? 0 : 2
        c.check.layer.borderColor = theme.funcKey.cgColor
        return c
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = floor(collectionView.bounds.width / CGFloat(columns))
        return CGSize(width: max(w, 1), height: rowHeight)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if selectable {
            if let i = selected.firstIndex(of: indexPath.item) {
                selected.remove(at: i)
            } else {
                selected.append(indexPath.item)
            }
            collectionView.reloadItems(at: [indexPath])
            onSelectionChange?()
        } else {
            onPick?(indexPath.item)
        }
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let path = view.indexPathForItem(at: g.location(in: view)) else { return }
        onLongPress?(path.item)
    }
}

// MARK: - 이모지 패널

extension KeyboardViewController {

    /// 추천 줄 자리: [이모지 | 스티커 | 기호]
    func buildEmojiTabs() {
        barOverlay.isHidden = false
        suggestScroll.isHidden = true
        let seg = UISegmentedControl(items: ["이모지", "스티커", "기호"])
        seg.selectedSegmentIndex = emojiTab
        seg.addTarget(self, action: #selector(emojiTabChanged(_:)), for: .valueChanged)
        seg.translatesAutoresizingMaskIntoConstraints = false
        barOverlay.addSubview(seg)
        NSLayoutConstraint.activate([
            seg.centerXAnchor.constraint(equalTo: barOverlay.centerXAnchor),
            seg.centerYAnchor.constraint(equalTo: barOverlay.centerYAnchor, constant: 2),
            seg.widthAnchor.constraint(equalToConstant: 252),
            seg.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc func emojiTabChanged(_ s: UISegmentedControl) {
        if s.selectedSegmentIndex == 2 {
            panel = .symbols
            symbolPage = 0
        } else {
            emojiTab = s.selectedSegmentIndex
        }
        rebuild()
    }

    /// 도구 줄 자리: 이모지 분류, 또는 스티커 팩
    func buildEmojiToolbar() {
        func pill(_ b: UIButton, on: Bool, width: CGFloat = 36) -> UIButton {
            b.backgroundColor = on ? theme.funcKey : .clear
            b.alpha = on ? 1 : 0.55
            b.layer.cornerRadius = 8
            b.widthAnchor.constraint(equalToConstant: width).isActive = true
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            return b
        }
        if emojiTab == 0 {
            let icons = ["🕘"] + EmojiData.categories.map { $0.icon }
            let names = ["자주 쓰는 이모지"] + EmojiData.categories.map { $0.name }
            toolbar.distribution = .equalSpacing
            // 맨 앞: 이모지 검색
            let search = toolButton(symbol: "search", width: 33, label: "이모지 검색", action: #selector(startEmojiSearch))
            search.backgroundColor = theme.key
            search.heightAnchor.constraint(equalToConstant: 34).isActive = true
            toolbar.addArrangedSubview(search)
            for (i, icon) in icons.enumerated() {
                let b = UIButton(type: .system)
                b.setTitle(icon, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 19)
                b.tag = i
                b.accessibilityLabel = names[i]
                b.addTarget(self, action: #selector(emojiCategoryTapped(_:)), for: .touchUpInside)
                toolbar.addArrangedSubview(pill(b, on: i == emojiCategory, width: 31))
            }
            return
        }
        let packs = stickers.packs
        if stickerPack >= packs.count { stickerPack = 0 }
        for (i, p) in packs.enumerated() {
            let b = UIButton(type: .custom)
            if let first = p.items.first, let img = UIImage(contentsOfFile: stickers.thumbURL(first).path) {
                b.setImage(img, for: .normal)
                b.imageView?.contentMode = .scaleAspectFill
                b.imageView?.layer.cornerRadius = 6
                b.imageEdgeInsets = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
            } else {
                b.setTitle("\(i + 1)", for: .normal)
                b.setTitleColor(theme.text, for: .normal)
            }
            b.clipsToBounds = true
            b.tag = i
            b.accessibilityLabel = p.name
            b.addTarget(self, action: #selector(stickerPackTapped(_:)), for: .touchUpInside)
            b.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(stickerPackLongPressed(_:))))
            toolbar.addArrangedSubview(pill(b, on: i == stickerPack))
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)
        let add = toolButton("추가", symbol: "plus", action: #selector(openStickerPicker))
        add.titleLabel?.font = .boldSystemFont(ofSize: 14)
        add.backgroundColor = theme.key
        add.layer.cornerRadius = 15
        add.heightAnchor.constraint(equalToConstant: 30).isActive = true
        add.accessibilityLabel = "클립보드 사진으로 스티커 추가"
        toolbar.addArrangedSubview(add)
    }

    @objc func emojiCategoryTapped(_ b: UIButton) {
        emojiCategory = b.tag
        rebuild()
    }

    @objc func stickerPackTapped(_ b: UIButton) {
        stickerPack = b.tag
        rebuild()
    }

    /// 본문: 위에 작은 제목, 가운데 격자, 아래 [가] [간격] [지우기]
    func buildEmojiBody() {
        let title = UILabel()
        title.font = .systemFont(ofSize: 11)
        title.textColor = theme.muted

        var gridView: UIView
        if emojiTab == 0 {
            let list: [String]
            if emojiCategory == 0 {
                let recent = settings.recentEmoji
                list = recent.isEmpty ? EmojiData.starter : recent
                title.text = "자주 쓰는 이모지"
            } else {
                let c = EmojiData.categories[min(emojiCategory - 1, EmojiData.categories.count - 1)]
                list = c.items
                title.text = c.name
            }
            let grid = GridPanel(items: list.map { GridPanel.Item.emoji($0) }, columns: 8, rowHeight: 40, theme: theme)
            grid.onPick = { [weak self] i in
                guard let self = self, i < list.count else { return }
                self.haptic()
                self.resetComposer()
                self.docInsert(list[i])
                self.settings.useEmoji(list[i])
            }
            emojiGrid = grid
            gridView = grid.view
        } else {
            let packs = stickers.packs
            if packs.isEmpty {
                title.text = "내 스티커"
                gridView = emptyLabel("클립보드에 저장된 사진으로 스티커 팩을 만들 수 있어요.\n위의 [+ 추가]를 누르세요. 누르면 복사되고, 입력 칸에 붙여넣어 보냅니다.")
            } else {
                let pack = packs[min(stickerPack, packs.count - 1)]
                title.text = "\(pack.name) · \(pack.items.count)개 · 누르면 복사, 길게 누르면 빼기"
                let names = pack.items
                let grid = GridPanel(items: names.map { GridPanel.Item.image(self.stickers.thumbURL($0)) }, columns: 5, rowHeight: 70, theme: theme)
                grid.onPick = { [weak self] i in
                    guard let self = self, i < names.count else { return }
                    self.copySticker(names[i])
                }
                grid.onLongPress = { [weak self] i in
                    guard let self = self, i < names.count else { return }
                    self.removeSticker(names[i])
                }
                emojiGrid = grid
                gridView = grid.view
            }
        }

        let back = makeKey(lang == .hangul ? "가" : "ABC", id: "tokeys", fn: true, font: 16)
        back.accessibilityLabel = "글자 자판으로"
        let bottom = hstack([fixed(back, 52), spaceKey(), fixed(backspaceKey(), 52)], spacing: 6, equal: false)
        for v in [title, gridView, bottom] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            keyArea.addSubview(v)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: keyArea.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -10),
            title.heightAnchor.constraint(equalToConstant: 16),
            gridView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            gridView.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 4),
            gridView.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -4),
            gridView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -6),
            bottom.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: 6),
            bottom.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -6),
            bottom.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor, constant: -2),
            bottom.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: 스티커

    /// 스티커를 누르면 그림을 복사한다. 키보드는 그림을 바로 넣을 수 없어서 붙여넣기로 보낸다.
    func copySticker(_ name: String) {
        guard hasFullAccess else {
            showToast("스티커를 복사하려면 '전체 접근 허용'을 켜야 합니다.")
            return
        }
        guard let data = try? Data(contentsOf: stickers.fileURL(name)) else { return }
        haptic()
        let pb = UIPasteboard.general
        pb.setData(data, forPasteboardType: "public.jpeg")
        lastChangeCount = pb.changeCount       // 우리가 넣은 것을 새 복사로 다시 저장하지 않게
        showToast("복사했어요 · 입력 칸을 꾹 눌러 붙여넣으세요")
    }

    func removeSticker(_ name: String) {
        guard let place = stickers.remove(name) else { return }
        rebuild()
        showUndoBar("스티커 1개 뺐어요") { [weak self] in
            self?.stickers.restore(name, pack: place.pack, index: place.index)
            self?.rebuild()
        }
    }

    /// 클립보드에 저장된 사진을 골라 스티커 팩에 넣는 화면
    @objc func openStickerPicker() {
        showStickerPicker(preselect: nil)
    }

    func showStickerPicker(preselect: UUID?) {
        pickerView?.removeFromSuperview()
        pickerClips = store.sorted.filter { $0.image != nil }
        pickerPack = stickers.packs.indices.contains(stickerPack) ? stickers.packs[stickerPack].id : stickers.packs.first?.id

        let cover = UIView()
        cover.backgroundColor = theme.bg
        pinEdges(cover, in: keyArea)
        pickerView = cover

        let title = UILabel()
        title.font = .boldSystemFont(ofSize: 14)
        title.textColor = theme.text
        title.text = "클립보드 사진에서 고르기"

        let body: UIView
        if pickerClips.isEmpty {
            body = emptyLabel("클립보드에 저장된 사진이 없어요.\n설정 › '사진도 저장'을 켜고 사진을 복사한 뒤 다시 열어 주세요.")
        } else {
            let grid = GridPanel(items: pickerClips.compactMap { self.store.thumbURL($0) }.map { GridPanel.Item.image($0) },
                                 columns: 5, rowHeight: 66, theme: theme)
            grid.selectable = true
            if let id = preselect, let i = pickerClips.firstIndex(where: { $0.id == id }) { grid.selected = [i] }
            grid.onSelectionChange = { [weak self] in self?.updatePickerButton() }
            pickerGrid = grid
            body = grid.view
        }

        // 넣을 팩: 지금 팩들 + 새 팩
        let packRow = UIStackView()
        packRow.axis = .horizontal
        packRow.spacing = 6
        packRow.distribution = .fillEqually
        for (i, p) in stickers.packs.prefix(3).enumerated() {
            let b = toolButton(p.name, action: #selector(pickerPackTapped(_:)))
            b.tag = i
            b.titleLabel?.font = .systemFont(ofSize: 13)
            styleChoice(b, on: p.id == pickerPack)
            packRow.addArrangedSubview(b)
        }
        let newB = toolButton("새 팩", symbol: "plus", action: #selector(pickerPackTapped(_:)))
        newB.tag = -1
        newB.titleLabel?.font = .systemFont(ofSize: 13)
        styleChoice(newB, on: pickerPack == nil)
        packRow.addArrangedSubview(newB)

        let close = toolButton("닫기", action: #selector(closeStickerPicker))
        let add = toolButton("스티커로 추가", active: true, action: #selector(confirmStickerPicker))
        add.titleLabel?.font = .boldSystemFont(ofSize: 15)
        pickerAddButton = add
        let buttons = hstack([fixed(close, 70), add], spacing: 6, equal: false)

        let stack = UIStackView(arrangedSubviews: [title, body, packRow, buttons])
        stack.axis = .vertical
        stack.spacing = 6
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        pinEdges(stack, in: cover, insets: UIEdgeInsets(top: 6, left: 8, bottom: 8, right: 8))
        updatePickerButton()
    }

    func styleChoice(_ b: UIButton, on: Bool) {
        b.backgroundColor = theme.key
        b.layer.borderWidth = on ? 2 : 0
        b.layer.borderColor = theme.accent.cgColor
        b.setTitleColor(theme.text, for: .normal)
        b.tintColor = theme.text
    }

    func updatePickerButton() {
        let n = pickerGrid?.selected.count ?? 0
        pickerAddButton?.setTitle(n > 0 ? "스티커로 추가 (\(n))" : "사진을 골라 주세요", for: .normal)
        pickerAddButton?.isEnabled = n > 0
        pickerAddButton?.alpha = n > 0 ? 1 : 0.5
    }

    @objc func pickerPackTapped(_ b: UIButton) {
        pickerPack = b.tag >= 0 && b.tag < stickers.packs.count ? stickers.packs[b.tag].id : nil
        // 고른 사진은 그대로 두고 팩 버튼 표시만 바꾼다
        if let row = b.superview as? UIStackView {
            for case let other as UIButton in row.arrangedSubviews { styleChoice(other, on: other === b) }
        }
    }

    @objc func closeStickerPicker() {
        pickerView?.removeFromSuperview()
        pickerGrid = nil
    }

    @objc func confirmStickerPicker() {
        guard let grid = pickerGrid, !grid.selected.isEmpty else { return }
        let urls = grid.selected.compactMap { i in i < pickerClips.count ? store.imageURL(pickerClips[i]) : nil }
        let packID = pickerPack ?? stickers.newPack().id
        let n = stickers.add(images: urls, to: packID)
        closeStickerPicker()
        panel = .emoji
        emojiTab = 1
        stickerPack = stickers.packs.firstIndex { $0.id == packID } ?? 0
        rebuild()
        showToast("스티커 \(n)개를 넣었어요")
    }

    // MARK: 단어 추가 줄

    /// 단어 추가: 추천 줄 자리에 입력 칸과 저장. 전체 높이와 키 크기는 평소와 같다.
    func buildAddRow() {
        barOverlay.isHidden = false
        suggestScroll.isHidden = true
        let box = UIView()
        box.backgroundColor = theme.key
        box.layer.cornerRadius = 8
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let field = UILabel()
        field.font = .systemFont(ofSize: 16)
        field.textColor = theme.text
        field.lineBreakMode = .byTruncatingHead
        pinEdges(field, in: box, insets: UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10))
        addField = field
        updateAddField()
        func rowButton(_ title: String, primary: Bool, action: Selector) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .boldSystemFont(ofSize: 15)
            b.backgroundColor = primary ? theme.accent : theme.funcKey
            b.setTitleColor(primary ? theme.onAccent : theme.text, for: .normal)
            b.layer.cornerRadius = 8
            b.widthAnchor.constraint(equalToConstant: 58).isActive = true
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }
        var views: [UIView] = [box]
        switch bufferPurpose {
        case .addWord:
            views.append(rowButton("저장", primary: true, action: #selector(saveAddWord)))
        case .packRename:
            views.append(rowButton("저장", primary: true, action: #selector(savePackName)))
        case .clipSearch:
            views.append(rowButton("목록", primary: false, action: #selector(showClipResults)))
            views.append(rowButton("닫기", primary: false, action: #selector(cancelAddWord)))
        case .emojiSearch:
            views.append(rowButton("닫기", primary: false, action: #selector(cancelAddWord)))
        }
        if bufferPurpose == .clipSearch || bufferPurpose == .emojiSearch {
            // 검색 칸 앞에 돋보기
            let glass = UIImageView(image: Icon.image("search", size: 16, line: 2))
            glass.tintColor = theme.muted
            glass.contentMode = .center
            glass.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
                glass.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])
            for c in box.constraints where c.firstItem === field && c.firstAttribute == .leading { c.constant = 30 }
        }
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 6
        pinEdges(row, in: barOverlay, insets: UIEdgeInsets(top: 4, left: 8, bottom: 2, right: 8))
    }
}

// MARK: - 스티커 팩 관리

extension KeyboardViewController {

    @objc func stickerPackLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view, b.tag < stickers.packs.count else { return }
        haptic()
        stickerPack = b.tag
        rebuild()
        showPackMenu(stickers.packs[b.tag])
    }

    /// 아래에서 올라오는 팩 메뉴: 이름 바꾸기, 맨 앞으로, 삭제
    func showPackMenu(_ pack: StickerPack) {
        packMenu?.removeFromSuperview()
        let cover = UIView()
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        pinEdges(cover, in: keyArea)
        cover.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closePackMenu)))
        packMenu = cover

        let sheet = UIView()
        sheet.backgroundColor = theme.bg
        sheet.layer.cornerRadius = 14
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(sheet)
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
        ])

        let thumb = UIImageView()
        thumb.backgroundColor = theme.row
        thumb.layer.cornerRadius = 8
        thumb.clipsToBounds = true
        thumb.contentMode = .scaleAspectFill
        if let first = pack.items.first { thumb.image = UIImage(contentsOfFile: stickers.thumbURL(first).path) }
        thumb.widthAnchor.constraint(equalToConstant: 40).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let name = UILabel()
        name.numberOfLines = 2
        let t = NSMutableAttributedString(string: pack.name, attributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: theme.text])
        t.append(NSAttributedString(string: "\n스티커 \(pack.items.count)개", attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: theme.muted]))
        name.attributedText = t
        let close = toolButton(symbol: "xmark", width: 32, label: "닫기", action: #selector(closePackMenu))
        close.layer.cornerRadius = 16
        close.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let head = UIStackView(arrangedSubviews: [thumb, name, close])
        head.axis = .horizontal
        head.alignment = .center
        head.spacing = 10

        func item(_ title: String, danger: Bool = false, action: Selector) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.contentHorizontalAlignment = .left
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            b.titleLabel?.font = danger ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 15)
            b.setTitleColor(danger ? theme.danger : theme.text, for: .normal)
            b.backgroundColor = theme.row
            b.layer.cornerRadius = 10
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }
        let stack = UIStackView(arrangedSubviews: [
            head,
            item("이름 바꾸기", action: #selector(renamePackTapped)),
            item("맨 앞으로 옮기기", action: #selector(movePackToFrontTapped)),
            item("팩 삭제", danger: true, action: #selector(deletePackTapped)),
        ])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(10, after: head)
        pinEdges(stack, in: sheet, insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
    }

    @objc func closePackMenu() {
        packMenu?.removeFromSuperview()
    }

    var currentPack: StickerPack? {
        stickers.packs.indices.contains(stickerPack) ? stickers.packs[stickerPack] : nil
    }

    @objc func renamePackTapped() {
        guard let p = currentPack else { return }
        closePackMenu()
        renamingPack = p.id
        openBuffer(.packRename, text: p.name, returnTo: .emoji)
    }

    @objc func savePackName() {
        resetComposer()
        let name = (addBuffer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = renamingPack, !name.isEmpty { stickers.rename(id, to: name) }
        addBuffer = nil
        renamingPack = nil
        addReturnPanel = nil
        panel = .emoji
        emojiTab = 1
        rebuild()
    }

    @objc func movePackToFrontTapped() {
        guard let p = currentPack else { return }
        closePackMenu()
        stickers.moveToFront(p.id)
        stickerPack = 0
        rebuild()
    }

    @objc func deletePackTapped() {
        guard let p = currentPack, let index = stickers.deletePack(p.id) else { return }
        closePackMenu()
        stickerPack = 0
        rebuild()
        showUndoBar("‘\(p.name)’ 팩을 지웠어요") { [weak self] in
            self?.stickers.restorePack(p, at: index)
            self?.stickerPack = index
            self?.rebuild()
        }
    }
}
