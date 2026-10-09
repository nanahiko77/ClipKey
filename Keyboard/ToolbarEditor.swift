import UIKit

/// 상단바 꾸미기 (8칸).
/// 위: 실제 상단바 모양의 미리 보기. 꾹 눌러 끌면 자리가 바뀌고, ⊖ 를 누르거나 아래로 끌어내리면 뺀다.
///     가운데 빈 곳을 기준으로 앞은 왼쪽에, 뒤는 오른쪽 끝에 붙는다. 어떤 도구든 어디에나 놓을 수 있다.
/// 아래: 모든 도구를 이름과 함께. 누르면 넣고/빼고, 꾹 눌러 위로 끌어 올리면 그 자리에 넣는다.
/// 화살표와 되돌리기는 2칸. 칸이 모자라면 흐리게 보이고 넣을 수 없다.
final class ToolbarEditor: UIView {
    static let names: [String: String] = [
        "clipboard": "클립보드", "settings": "설정", "addword": "단어 추가", "emoji": "이모지",
        "arrows": "커서 화살표", "undo": "되돌리기", "hide": "닫기",
    ]
    static let icons: [String: String] = [
        "clipboard": "clipboard", "settings": "slider.horizontal.3", "addword": "plus", "emoji": "smile",
        "hide": "keyboard.down",
    ]
    static let singles = ["clipboard", "emoji", "settings", "addword", "hide"]
    static let doubles = ["arrows", "undo"]

    private let settings: Settings
    private let theme: Theme
    private let scroll = PanelScrollView(frame: .zero)
    private let content = UIStackView()
    private let barCard = UIView()
    private let barStack = UIStackView()
    private let gridCard = UIView()
    private let gridRows = UIStackView()
    private let placeholder = UIView()
    private var placeholderWidth: NSLayoutConstraint?
    private let meterLabel = UILabel()
    private let blue = UIColor.systemBlue
    private let red = UIColor.systemRed

    /// 상단바 배치 ("gap" 이 가운데 빈 곳)
    private var layout: [String]
    /// 미리 보기 안의 도구와 빈 곳 뷰 (끌 때 놓을 자리를 계산한다)
    private var barViews: [(item: String, view: UIView)] = []

    private var dragItem: String?
    private var dragFromBar = false
    private var dragSource: UIView?
    private var ghost: UIView?
    private var dropIndex: Int?

    init(settings: Settings, theme: Theme) {
        self.settings = settings
        self.theme = theme
        layout = settings.toolbarLayout
        super.init(frame: .zero)
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var used: Int { layout.filter { $0 != Settings.toolbarGap }.reduce(0) { $0 + Settings.toolbarSlots($1) } }
    private func fits(_ item: String) -> Bool { used + Settings.toolbarSlots(item) <= Settings.toolbarCapacity }
    private func isOn(_ item: String) -> Bool { layout.contains(item) }

    // MARK: 화면 구성

    private func caption(_ text: String, size: CGFloat, top: CGFloat, bottom: CGFloat) -> UIView {
        let l = UILabel()
        l.text = text
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: size)
        l.textColor = theme.muted
        let box = UIView()
        l.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l)
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: box.topAnchor, constant: top),
            l.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -bottom),
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 26),
            l.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -26),
        ])
        return box
    }

    /// 소제목 줄 오른쪽에 "7/8칸"
    private func meterRow() -> UIView {
        let l = UILabel()
        l.text = "상단바 · 끌어서 자리 바꾸기"
        l.font = .systemFont(ofSize: 13)
        l.textColor = theme.muted
        meterLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        meterLabel.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [l, meterLabel])
        row.axis = .horizontal
        row.spacing = 8
        let box = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 26),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -26),
        ])
        return box
    }

    private func inset(_ v: UIView) -> UIView {
        let box = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: box.topAnchor),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
        ])
        return box
    }

    private func build() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        barCard.backgroundColor = theme.row
        barCard.layer.cornerRadius = 12
        barCard.heightAnchor.constraint(equalToConstant: 52).isActive = true
        barStack.axis = .horizontal
        barStack.alignment = .center
        barStack.spacing = 4
        barStack.translatesAutoresizingMaskIntoConstraints = false
        barCard.addSubview(barStack)
        NSLayoutConstraint.activate([
            barStack.topAnchor.constraint(equalTo: barCard.topAnchor),
            barStack.bottomAnchor.constraint(equalTo: barCard.bottomAnchor),
            barStack.leadingAnchor.constraint(equalTo: barCard.leadingAnchor, constant: 8),
            barStack.trailingAnchor.constraint(equalTo: barCard.trailingAnchor, constant: -8),
        ])

        gridCard.backgroundColor = theme.row
        gridCard.layer.cornerRadius = 12
        gridRows.axis = .vertical
        gridRows.spacing = 12
        gridRows.translatesAutoresizingMaskIntoConstraints = false
        gridCard.addSubview(gridRows)
        NSLayoutConstraint.activate([
            gridRows.topAnchor.constraint(equalTo: gridCard.topAnchor, constant: 12),
            gridRows.bottomAnchor.constraint(equalTo: gridCard.bottomAnchor, constant: -10),
            gridRows.leadingAnchor.constraint(equalTo: gridCard.leadingAnchor, constant: 4),
            gridRows.trailingAnchor.constraint(equalTo: gridCard.trailingAnchor, constant: -4),
        ])

        placeholder.layer.cornerRadius = 8
        placeholder.layer.borderWidth = 2
        placeholder.layer.borderColor = blue.cgColor
        placeholder.backgroundColor = blue.withAlphaComponent(0.08)
        placeholderWidth = placeholder.widthAnchor.constraint(equalToConstant: 30)
        placeholderWidth?.isActive = true
        placeholder.heightAnchor.constraint(equalToConstant: 32).isActive = true

        content.addArrangedSubview(meterRow())
        content.addArrangedSubview(inset(barCard))
        content.addArrangedSubview(caption("⊖ 로 빼거나 아래로 끌어내리기 · 화살표와 되돌리기는 2칸", size: 12, top: 6, bottom: 0))
        content.addArrangedSubview(caption("모든 도구 · 누르거나 위로 끌어 올리면 넣기", size: 13, top: 16, bottom: 6))
        content.addArrangedSubview(inset(gridCard))
    }

    /// 도구 아이콘. 2칸 도구는 아이콘 두 개를 붙여서.
    private func iconView(_ item: String, size: CGFloat, color: UIColor) -> UIView {
        if item == "arrows" || item == "undo" {
            let names = item == "arrows" ? ("chevron.left", "chevron.right") : ("undo", "redo")
            let l = UIImageView(image: Icon.image(names.0, size: size - 1, line: item == "arrows" ? 2 : 1.75))
            let r = UIImageView(image: Icon.image(names.1, size: size - 1, line: item == "arrows" ? 2 : 1.75))
            for v in [l, r] { v.tintColor = color; v.contentMode = .center }
            let s = UIStackView(arrangedSubviews: [l, r])
            s.spacing = item == "arrows" ? 6 : 10
            s.isUserInteractionEnabled = false
            return s
        }
        let v = UIImageView(image: Icon.image(ToolbarEditor.icons[item] ?? "plus", size: size, line: 1.75))
        v.tintColor = color
        v.contentMode = .center
        v.isUserInteractionEnabled = false
        return v
    }

    private func badge(_ symbol: String, color: UIColor) -> UIView {
        let b = UIImageView(image: Icon.image(symbol, size: 11, line: 3))
        b.tintColor = .white
        b.contentMode = .center
        b.backgroundColor = color
        b.layer.cornerRadius = 9
        b.layer.borderWidth = 2
        b.layer.borderColor = theme.row.cgColor
        b.isUserInteractionEnabled = false
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        b.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    private func itemWidth(_ item: String) -> CGFloat { Settings.toolbarSlots(item) == 2 ? 64 : 30 }

    private func barItem(_ item: String) -> UIView {
        let v = EditorItemView()
        v.backgroundColor = theme.bg
        v.layer.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: itemWidth(item)).isActive = true
        v.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let icon = iconView(item, size: 17, color: theme.text)
        icon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(icon)
        let minus = badge("minus", color: red)
        v.addSubview(minus)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            minus.centerXAnchor.constraint(equalTo: v.trailingAnchor, constant: -3),
            minus.centerYAnchor.constraint(equalTo: v.topAnchor, constant: 3),
        ])
        v.item = item
        v.accessibilityLabel = (ToolbarEditor.names[item] ?? item) + " · 빼려면 오른쪽 위 빼기"
        let tap = UITapGestureRecognizer(target: self, action: #selector(barItemTapped(_:)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(dragged(_:)))
        press.minimumPressDuration = 0.25
        tap.require(toFail: press)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(press)
        return v
    }

    private func tile(_ item: String) -> UIView {
        let on = isOn(item)
        let available = on || fits(item)
        let double = Settings.toolbarSlots(item) == 2
        let v = EditorItemView()
        v.item = item
        v.alpha = available ? 1 : 0.4
        let box = UIView()
        box.layer.cornerRadius = 10
        box.backgroundColor = on ? blue.withAlphaComponent(0.13) : theme.bg
        box.translatesAutoresizingMaskIntoConstraints = false
        box.isUserInteractionEnabled = false
        let icon = iconView(item, size: 20, color: on ? blue : theme.text)
        icon.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(icon)
        let mark = badge(on ? "check" : "plus", color: on ? blue : theme.muted.withAlphaComponent(0.8))
        box.addSubview(mark)
        let name = UILabel()
        name.text = (ToolbarEditor.names[item] ?? item) + (double ? " · 2칸" : "")
        name.font = .systemFont(ofSize: 11)
        name.textColor = on ? theme.text : theme.muted
        name.textAlignment = .center
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.8
        name.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(box)
        v.addSubview(name)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: v.topAnchor),
            box.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            box.widthAnchor.constraint(equalToConstant: double ? 100 : 46),
            box.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            mark.centerXAnchor.constraint(equalTo: box.trailingAnchor, constant: -3),
            mark.centerYAnchor.constraint(equalTo: box.topAnchor, constant: 3),
            name.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 5),
            name.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 1),
            name.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -1),
            name.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        v.isAccessibilityElement = true
        v.accessibilityLabel = (ToolbarEditor.names[item] ?? item)
            + (on ? " · 상단바에 있음" : (available ? " · 넣기" : " · 칸이 모자람"))
        v.accessibilityTraits = .button
        let tap = UITapGestureRecognizer(target: self, action: #selector(tileTapped(_:)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(dragged(_:)))
        press.minimumPressDuration = 0.25
        tap.require(toFail: press)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(press)
        return v
    }

    private func reload() {
        barStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        barViews = []
        let lang = UILabel()
        lang.text = "한/영"
        lang.font = .boldSystemFont(ofSize: 12)
        lang.textAlignment = .center
        lang.textColor = theme.text
        lang.backgroundColor = theme.funcKey
        lang.layer.cornerRadius = 7
        lang.layer.masksToBounds = true
        lang.widthAnchor.constraint(equalToConstant: 38).isActive = true
        lang.heightAnchor.constraint(equalToConstant: 30).isActive = true
        barStack.addArrangedSubview(lang)
        for item in layout {
            if item == Settings.toolbarGap {
                let spacer = UIView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                barStack.addArrangedSubview(spacer)
                barViews.append((item, spacer))
            } else {
                let v = barItem(item)
                barViews.append((item, v))
                barStack.addArrangedSubview(v)
            }
        }

        let n = used
        meterLabel.text = "\(n)/\(Settings.toolbarCapacity)칸"
        meterLabel.textColor = n >= Settings.toolbarCapacity ? red : theme.muted

        gridRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let row1 = UIStackView(arrangedSubviews: ToolbarEditor.singles.map { tile($0) })
        let row2 = UIStackView(arrangedSubviews: ToolbarEditor.doubles.map { tile($0) })
        for r in [row1, row2] {
            r.axis = .horizontal
            r.distribution = .fillEqually
            r.alignment = .top
            gridRows.addArrangedSubview(r)
        }
    }

    // MARK: 넣고 빼기

    private func save() {
        settings.toolbarLayout = layout
    }

    /// 칸이 모자라서 못 넣을 때: 칸 수를 빨갛게 흔든다
    private func refuse() {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -6, 6, -4, 4, 0]
        a.duration = 0.3
        meterLabel.layer.add(a, forKey: "shake")
        meterLabel.textColor = red
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 넣기. at 은 layout 안의 자리 (없으면 가운데 빈 곳 바로 앞, 즉 왼쪽 묶음의 끝)
    private func insert(_ item: String, at index: Int? = nil) {
        let wasOn = isOn(item)
        layout.removeAll { $0 == item }
        if !wasOn && used + Settings.toolbarSlots(item) > Settings.toolbarCapacity {
            refuse()
            reload()
            return
        }
        let gapIndex = layout.firstIndex(of: Settings.toolbarGap) ?? layout.count
        let i = min(max(index ?? gapIndex, 0), layout.count)
        layout.insert(item, at: i)
        save()
        reload()
    }

    private func remove(_ item: String) {
        layout.removeAll { $0 == item }
        save()
        reload()
    }

    @objc private func barItemTapped(_ g: UITapGestureRecognizer) {
        guard let v = g.view as? EditorItemView else { return }
        // ⊖ 근처(오른쪽 위)를 누르면 뺀다. 가운데를 누르면 살짝 흔들어 끌 수 있다고 알려 준다.
        let p = g.location(in: v)
        if p.x > v.bounds.width - 22 && p.y < v.bounds.height * 0.6 {
            remove(v.item)
        } else {
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, 0.08, -0.08, 0.05, 0]
            a.duration = 0.3
            v.layer.add(a, forKey: "wiggle")
        }
    }

    @objc private func tileTapped(_ g: UITapGestureRecognizer) {
        guard let v = g.view as? EditorItemView else { return }
        if isOn(v.item) { remove(v.item) } else { insert(v.item) }
    }

    // MARK: 끌어서 옮기기

    @objc private func dragged(_ g: UILongPressGestureRecognizer) {
        guard let source = g.view as? EditorItemView else { return }
        let p = g.location(in: self)
        switch g.state {
        case .began:
            dragItem = source.item
            dragFromBar = source.isDescendant(of: barCard)
            if !dragFromBar && !isOn(source.item) && !fits(source.item) {
                dragItem = nil
                refuse()
                return
            }
            dragSource = source
            scroll.isScrollEnabled = false
            let snap = source.snapshotView(afterScreenUpdates: false) ?? UIView()
            snap.frame = source.convert(source.bounds, to: self)
            snap.layer.shadowColor = UIColor.black.cgColor
            snap.layer.shadowOpacity = 0.25
            snap.layer.shadowRadius = 9
            snap.layer.shadowOffset = CGSize(width: 0, height: 6)
            addSubview(snap)
            ghost = snap
            UIView.animate(withDuration: 0.12) {
                snap.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                snap.center = p
            }
            source.alpha = 0.3
            placeholderWidth?.constant = itemWidth(source.item)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .changed:
            guard dragItem != nil else { return }
            ghost?.center = p
            updateDrop(at: p)
        case .ended:
            finishDrag(at: p, cancelled: false)
        default:
            finishDrag(at: p, cancelled: true)
        }
    }

    private var barFrame: CGRect { barCard.convert(barCard.bounds, to: self) }

    /// 끄는 동안: 상단바 위면 놓을 자리를 벌리고, 상단바 도구를 아래로 끌어내리면 흐리게 (떼면 빠진다)
    private func updateDrop(at p: CGPoint) {
        guard let item = dragItem else { return }
        let overBar = barFrame.insetBy(dx: 0, dy: -22).contains(p)
        if overBar {
            // layout 안의 자리: 끄는 도구를 뺀 나머지(빈 곳 포함) 중 손가락보다 왼쪽에 있는 것의 수
            let others = barViews.filter { $0.item != item }
            var index = 0
            for o in others where o.view.convert(o.view.bounds, to: self).midX < p.x { index += 1 }
            if dropIndex != index {
                dropIndex = index
                placeholder.removeFromSuperview()
                if dragFromBar { dragSource?.isHidden = true }
                // 미리 보기에서 0번은 한/영. 보이는 것 기준으로 index 번째 앞에 넣는다.
                let visible = barStack.arrangedSubviews.filter { !$0.isHidden && $0 !== placeholder }
                let anchor = 1 + index
                let at = anchor < visible.count ? (barStack.arrangedSubviews.firstIndex(of: visible[anchor]) ?? barStack.arrangedSubviews.count) : barStack.arrangedSubviews.count
                barStack.insertArrangedSubview(placeholder, at: at)
                UIView.animate(withDuration: 0.15) { self.barCard.layoutIfNeeded() }
            }
            ghost?.alpha = 1
        } else {
            if dropIndex != nil {
                dropIndex = nil
                placeholder.removeFromSuperview()
                UIView.animate(withDuration: 0.15) { self.barCard.layoutIfNeeded() }
            }
            let removing = dragFromBar && p.y > barFrame.maxY + 18
            ghost?.alpha = removing ? 0.45 : 1
        }
    }

    private func finishDrag(at p: CGPoint, cancelled: Bool) {
        guard let item = dragItem else { return }
        let index = dropIndex
        placeholder.removeFromSuperview()
        ghost?.removeFromSuperview()
        ghost = nil
        dragSource?.alpha = 1
        dragSource?.isHidden = false
        dragSource = nil
        dragItem = nil
        dropIndex = nil
        scroll.isScrollEnabled = true
        guard !cancelled else { reload(); return }
        if let i = index {
            insert(item, at: i)                              // 자리 바꾸기 또는 그 자리에 넣기
        } else if dragFromBar && p.y > barFrame.maxY + 18 {
            remove(item)                                     // 아래로 끌어내려 빼기
        } else {
            reload()
        }
    }
}

/// 상단바 꾸미기의 도구 하나. 오른쪽 위로 삐져나온 ⊖·✓ 표시까지 누를 수 있게 터치 영역을 조금 넓힌다.
final class EditorItemView: UIView {
    var item = ""
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }
}
