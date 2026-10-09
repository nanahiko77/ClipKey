import UIKit

/// 자판의 키 하나. 보조 글자가 있으면 꾹 눌렀을 때 말풍선을 띄우고, 뗄 때 보조 글자를 입력한다.
final class KeyButton: UIButton {
    var id = ""
    var hintText: String? { didSet { hintLabel.text = hintText } }
    var hintColor: UIColor = .gray { didSet { hintLabel.textColor = hintColor } }
    var bubbleBackground: UIColor = .white
    var bubbleText: UIColor = .black
    weak var bubbleHost: UIView?

    var onTap: ((KeyButton) -> Void)?
    var onHint: ((String) -> Void)?
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?

    /// 꾹 누르고 있으면 키 위에 뜨는 큰 말풍선. 손가락을 그 위로 밀어서 떼면 onAlt 가 실행된다.
    var altTitle: String?
    var onAlt: (() -> Void)?
    var onAltHover: (() -> Void)?
    var altBackground: UIColor = .black
    var altText: UIColor = .white
    var altHoverBackground: UIColor = .red
    var altHoverText: UIColor = .white

    private let hintLabel = UILabel()
    private var holdTimer: Timer?
    private var bubble: UILabel?
    private var altTimer: Timer?
    private var altBubble: UILabel?
    private var altHover = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.cornerRadius = 6
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.isUserInteractionEnabled = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        addTarget(self, action: #selector(didTouchDown), for: .touchDown)
        addTarget(self, action: #selector(didTouchUp), for: .touchUpInside)
        addTarget(self, action: #selector(didTouchCancel), for: [.touchUpOutside, .touchCancel])
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    @objc private func didTouchDown() {
        onDown?()
        if altTitle != nil {
            altTimer?.invalidate()
            let a = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in self?.showAlt() }
            RunLoop.main.add(a, forMode: .common)
            altTimer = a
        }
        guard hintText != nil else { return }
        holdTimer?.invalidate()
        let t = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in self?.showBubble() }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    @objc private func didTouchUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        let alt = endAlt()
        onUp?()
        if alt {
            onAlt?()
        } else if bubble != nil, let hint = hintText {
            hideBubble()
            onHint?(hint)
        } else {
            onTap?(self)
        }
    }

    /// 손가락을 키 밖으로 빼면 아무것도 입력하지 않는다
    @objc private func didTouchCancel() {
        holdTimer?.invalidate()
        holdTimer = nil
        hideBubble()
        let alt = endAlt()
        onUp?()
        if alt { onAlt?() }
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.continueTracking(touch, with: event)
        if let b = altBubble, let host = bubbleHost {
            let inside = b.frame.insetBy(dx: -12, dy: -12).contains(touch.location(in: host))
            if inside != altHover {
                // 말풍선 위에 올라오면 빨갛게 커지고 한 번 떨린다: 지금 떼면 실행된다는 표시
                altHover = inside
                b.backgroundColor = inside ? altHoverBackground : altBackground
                b.textColor = inside ? altHoverText : altText
                UIView.animate(withDuration: 0.12) {
                    b.transform = inside ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
                }
                if inside { onAltHover?() }
            }
        }
        return result
    }

    private func showAlt() {
        guard let host = bubbleHost, let title = altTitle, altBubble == nil else { return }
        let f = convert(bounds, to: host)
        let w: CGFloat = 92
        let h: CGFloat = 40
        let x = max(2, min(f.maxX - w, host.bounds.width - w - 2))
        let y = max(0, f.minY - h - 4)
        let label = UILabel(frame: CGRect(x: x, y: y, width: w, height: h))
        label.text = title
        label.textAlignment = .center
        label.font = .boldSystemFont(ofSize: 15)
        label.textColor = altText
        label.backgroundColor = altBackground
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        host.addSubview(label)
        altBubble = label
        altHover = false
    }

    /// 말풍선을 닫고, 손가락이 말풍선 위에 있었는지 돌려준다
    private func endAlt() -> Bool {
        altTimer?.invalidate()
        altTimer = nil
        let fire = altBubble != nil && altHover
        altBubble?.removeFromSuperview()
        altBubble = nil
        altHover = false
        return fire
    }

    private func showBubble() {
        guard let host = bubbleHost, let hint = hintText, bubble == nil else { return }
        let f = convert(bounds, to: host)
        let w: CGFloat = 44
        let h: CGFloat = 46
        var x = f.midX - w / 2
        x = max(2, min(x, host.bounds.width - w - 2))
        let y = max(0, f.minY - h + 4)
        let label = UILabel(frame: CGRect(x: x, y: y, width: w, height: h))
        label.text = hint
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 26)
        label.textColor = bubbleText
        label.backgroundColor = bubbleBackground
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.layer.borderWidth = 1
        label.layer.borderColor = hintColor.cgColor
        host.addSubview(label)
        bubble = label
    }

    private func hideBubble() {
        bubble?.removeFromSuperview()
        bubble = nil
    }
}

/// 클립보드 목록의 한 줄: 고정 버튼, 내용, 삭제 버튼. 고정 항목을 지울 때는 확인 줄로 바뀐다.
final class ClipCell: UITableViewCell {
    let card = UIView()
    let pinButton = UIButton(type: .system)
    let label = UILabel()
    let deleteButton = UIButton(type: .system)
    let cancelButton = UIButton(type: .system)
    let confirmButton = UIButton(type: .system)

    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        label.font = .systemFont(ofSize: 15)
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        cancelButton.setTitle("취소", for: .normal)
        confirmButton.setTitle("삭제", for: .normal)
        for b in [cancelButton, confirmButton] {
            b.titleLabel?.font = .systemFont(ofSize: 15)
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        for b in [pinButton, deleteButton] {
            b.widthAnchor.constraint(equalToConstant: 42).isActive = true
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            b.layer.cornerRadius = 8
        }
        deleteButton.setImage(Icon.image("trash", size: 16, line: 1.75), for: .normal)

        let stack = UIStackView(arrangedSubviews: [pinButton, label, deleteButton, cancelButton, confirmButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
        ])

        pinButton.addTarget(self, action: #selector(pinTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ clip: Clip, confirming: Bool, theme: Theme) {
        card.backgroundColor = theme.row
        card.layer.borderWidth = confirming ? 2 : 0
        card.layer.borderColor = theme.danger.cgColor

        pinButton.isHidden = confirming
        deleteButton.isHidden = confirming
        cancelButton.isHidden = !confirming
        confirmButton.isHidden = !confirming

        if confirming {
            label.text = "  고정 항목을 삭제할까요?"
            label.font = .boldSystemFont(ofSize: 15)
            label.textColor = theme.danger
        } else {
            label.text = clip.text.replacingOccurrences(of: "\n", with: " ")
            label.font = .systemFont(ofSize: 15)
            label.textColor = theme.text
        }

        // 압정 모양을 살짝 기울여서, 켜면 색을 채운다
        pinButton.setImage(Icon.image(clip.pinned ? "pin.fill" : "pin", size: 20, line: 1.75), for: .normal)
        pinButton.tintColor = clip.pinned ? theme.accent : theme.muted
        pinButton.backgroundColor = clip.pinned ? theme.pinBg : .clear
        pinButton.accessibilityLabel = clip.pinned ? "고정 해제" : "고정"
        deleteButton.tintColor = theme.muted
        deleteButton.accessibilityLabel = "삭제"

        cancelButton.backgroundColor = theme.funcKey
        cancelButton.setTitleColor(theme.text, for: .normal)
        confirmButton.backgroundColor = theme.danger
        confirmButton.setTitleColor(theme.onDanger, for: .normal)
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func deleteTapped() { onDelete?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func confirmTapped() { onConfirm?() }
}
