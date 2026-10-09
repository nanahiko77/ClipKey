import UIKit

/// 상단바 꾸미기.
/// 위: 실제 상단바 모양의 미리 보기. 꾹 눌러 끌면 순서가 바뀌고, ⊖ 를 누르거나 아래로 끌어내리면 뺀다.
/// 아래: 모든 도구를 이름과 함께. 누르면 넣고/빼고, 꾹 눌러 위로 끌어 올리면 그 자리에 넣는다.
/// 왼쪽 도구(클립보드·이모지·설정·단어 추가)는 순서를 바꿀 수 있고, 화살표와 닫기는 늘 오른쪽 끝에 붙는다.
final class ToolbarEditor: UIView {
    static let leftItems = Settings.toolbarItemsAll
    static let rightItems = ["arrows", "hide"]
    static let allItems = ["clipboard", "emoji", "settings", "addword", "arrows", "hide"]
    static let names: [String: String] = [
        "clipboard": "클립보드", "settings": "설정", "addword": "단어 추가", "emoji": "이모지",
        "arrows": "화살표", "hide": "닫기",
    ]
    static let icons: [String: String] = [
        "clipboard": "clipboard", "settings": "slider.horizontal.3", "addword": "plus", "emoji": "smile",
        "hide": "keyboard.down",
    ]

    private let settings: Settings
    private let theme: Theme
    private let scroll = PanelScrollView(frame: .zero)
    private let content = UIStackView()
    private let barCard = UIView()
    private let barStack = UIStackView()
    private let gridCard = UIView()
    private let gridStack = UIStackView()
    private let placeholder = UIView()
    private let blue = UIColor.systemBlue
    private let red = UIColor.systemRed

    /// 상단바 왼쪽에 켜 둔 도구 (순서대로)
    private var left: [String]
    private var arrowsOn: Bool
    private var hideOn: Bool
    /// 미리 보기 안의 왼쪽 도구 뷰 (끌 때 놓을 자리를 계산한다)
    private var leftViews: [(item: String, view: UIView)] = []

    private var dragItem: String?
    private var dragFromBar = false
    private var dragSource: UIView?
    private var ghost: UIView?
    private var dropIndex: Int?

    init(settings: Settings, theme: Theme) {
        self.settings = settings
        self.theme = theme
        left = settings.toolbarOrder.filter { !settings.toolbarOff.contains($0) }
        arrowsOn = settings.showArrows
        hideOn = settings.showHide
        super.init(frame: .zero)
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        barStack.spacing = 6
        barStack.translatesAutoresizingMaskIntoConstraints = false
        barCard.addSubview(barStack)
        NSLayoutConstraint.activate([
            barStack.topAnchor.constraint(equalTo: barCard.topAnchor),
            barStack.bottomAnchor.constraint(equalTo: barCard.bottomAnchor),
            barStack.leadingAnchor.constraint(equalTo: barCard.leadingAnchor, constant: 10),
            barStack.trailingAnchor.constraint(equalTo: barCard.trailingAnchor, constant: -10),
        ])

        gridCard.backgroundColor = theme.row
        gridCard.layer.cornerRadius = 12
        gridStack.axis = .horizontal
        gridStack.distribution = .fillEqually
        gridStack.alignment = .top
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        gridCard.addSubview(gridStack)
        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: gridCard.topAnchor, constant: 12),
            gridStack.bottomAnchor.constraint(equalTo: gridCard.bottomAnchor, constant: -10),
            gridStack.leadingAnchor.constraint(equalTo: gridCard.leadingAnchor, constant: 4),
            gridStack.trailingAnchor.constraint(equalTo: gridCard.trailingAnchor, constant: -4),
        ])

        placeholder.layer.cornerRadius = 8
        placeholder.layer.borderWidth = 2
        placeholder.layer.borderColor = blue.cgColor
        placeholder.backgroundColor = blue.withAlphaComponent(0.08)
        placeholder.widthAnchor.constraint(equalToConstant: 34).isActive = true
        placeholder.heightAnchor.constraint(equalToConstant: 32).isActive = true

        content.addArrangedSubview(caption("상단바 · 꾹 눌러 끌면 순서 바꾸기", size: 13, top: 10, bottom: 6))
        content.addArrangedSubview(inset(barCard))
        content.addArrangedSubview(caption("⊖ 를 누르거나 아래로 끌어내리면 뺍니다", size: 12, top: 6, bottom: 0))
        content.addArrangedSubview(caption("모든 도구 · 누르거나 위로 끌어 올리면 넣기", size: 13, top: 16, bottom: 6))
        content.addArrangedSubview(inset(gridCard))
    }

    /// 도구 아이콘. 화살표는 좌우 두 개를 붙여서.
    private func iconView(_ item: String, size: CGFloat, color: UIColor) -> UIView {
        if item == "arrows" {
            let l = UIImageView(image: Icon.image("chevron.left", size: size - 2, line: 2))
            let r = UIImageView(image: Icon.image("chevron.right", size: size - 2, line: 2))
            for v in [l, r] { v.tintColor = color; v.contentMode = .center }
            let s = UIStackView(arrangedSubviews: [l, r])
            s.spacing = 2
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

    private func barItem(_ item: String) -> UIView {
        let v = EditorItemView()
        v.backgroundColor = theme.bg
        v.layer.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: item == "arrows" ? 46 : 34).isActive = true
        v.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let icon = iconView(item, size: 18, color: theme.text)
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
        // ⊖ 자리를 누르면 빼고, 꾹 눌러 끌면 옮긴다
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
        let v = EditorItemView()
        v.item = item
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
        name.text = ToolbarEditor.names[item]
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
            box.widthAnchor.constraint(equalToConstant: 46),
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
        v.accessibilityLabel = (ToolbarEditor.names[item] ?? item) + (on ? " · 상단바에 있음" : " · 넣기")
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
        leftViews = []
        let lang = UILabel()
        lang.text = "한/영"
        lang.font = .boldSystemFont(ofSize: 12)
        lang.textAlignment = .center
        lang.textColor = theme.text
        lang.backgroundColor = theme.funcKey
        lang.layer.cornerRadius = 7
        lang.layer.masksToBounds = true
        lang.widthAnchor.constraint(equalToConstant: 40).isActive = true
        lang.heightAnchor.constraint(equalToConstant: 30).isActive = true
        barStack.addArrangedSubview(lang)
        for item in left {
            let v = barItem(item)
            leftViews.append((item, v))
            barStack.addArrangedSubview(v)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barStack.addArrangedSubview(spacer)
        if arrowsOn { barStack.addArrangedSubview(barItem("arrows")) }
        if hideOn { barStack.addArrangedSubview(barItem("hide")) }

        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in ToolbarEditor.allItems { gridStack.addArrangedSubview(tile(item)) }
    }

    // MARK: 켜고 끄기

    private func isOn(_ item: String) -> Bool {
        switch item {
        case "arrows": return arrowsOn
        case "hide": return hideOn
        default: return left.contains(item)
        }
    }

    private func set(_ item: String, on: Bool, at index: Int? = nil) {
        switch item {
        case "arrows": arrowsOn = on
        case "hide": hideOn = on
        default:
            left.removeAll { $0 == item }
            if on { left.insert(item, at: min(max(index ?? left.count, 0), left.count)) }
        }
        save()
        reload()
    }

    private func save() {
        let off = ToolbarEditor.leftItems.filter { !left.contains($0) }
        settings.toolbarOrder = left + off
        settings.toolbarOff = off
        settings.showArrows = arrowsOn
        settings.showHide = hideOn
    }

    @objc private func barItemTapped(_ g: UITapGestureRecognizer) {
        guard let v = g.view as? EditorItemView else { return }
        // ⊖ 근처(오른쪽 위 절반)를 누르면 뺀다. 가운데를 누르면 살짝 흔들어 끌 수 있다고 알려 준다.
        let p = g.location(in: v)
        if p.x > v.bounds.width * 0.45 && p.y < v.bounds.height * 0.6 {
            set(v.item, on: false)
        } else {
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, 0.08, -0.08, 0.05, 0]
            a.duration = 0.3
            v.layer.add(a, forKey: "wiggle")
        }
    }

    @objc private func tileTapped(_ g: UITapGestureRecognizer) {
        guard let v = g.view as? EditorItemView else { return }
        set(v.item, on: !isOn(v.item))
    }

    // MARK: 끌어서 옮기기

    @objc private func dragged(_ g: UILongPressGestureRecognizer) {
        guard let source = g.view as? EditorItemView else { return }
        let p = g.location(in: self)
        switch g.state {
        case .began:
            dragItem = source.item
            dragFromBar = source.isDescendant(of: barCard)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .changed:
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
        if overBar && ToolbarEditor.leftItems.contains(item) {
            let others = leftViews.filter { $0.item != item }
            var index = 0
            for o in others where o.view.convert(o.view.bounds, to: self).midX < p.x { index += 1 }
            if dropIndex != index {
                dropIndex = index
                placeholder.removeFromSuperview()
                if dragFromBar { dragSource?.isHidden = true }
                // 0번은 한/영. 숨긴 원래 자리도 칸 수에 들어 있어서 보이는 칸 기준으로 넣는다.
                let visible = barStack.arrangedSubviews.filter { !$0.isHidden }
                let anchorIndex = 1 + index
                let at = anchorIndex < visible.count ? (barStack.arrangedSubviews.firstIndex(of: visible[anchorIndex]) ?? barStack.arrangedSubviews.count) : barStack.arrangedSubviews.count
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
        let overBar = barFrame.insetBy(dx: 0, dy: -22).contains(p)
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
            set(item, on: true, at: i)                       // 순서 바꾸기 또는 그 자리에 넣기
        } else if dragFromBar && p.y > barFrame.maxY + 18 {
            set(item, on: false)                             // 아래로 끌어내려 빼기
        } else if !dragFromBar && overBar {
            set(item, on: true)                              // 화살표·닫기는 오른쪽 끝에
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
