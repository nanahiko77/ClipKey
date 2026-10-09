import UIKit

/// 자판이 들어가는 영역. 키 사이 틈이나 가장자리를 눌러도 가장 가까운 키가 눌리게 한다.
/// (키마다 버튼이라 틈을 누르면 아무 키도 입력되지 않아서, 빠르게 칠 때 글자가 빠졌다)
final class KeyArea: UIView {
    private var keys: [KeyButton]?
    /// 이 거리(pt) 안에 키가 있으면 그 키로 본다
    static let reach: CGFloat = 14

    /// 자판을 새로 그렸으면 부른다
    func invalidateKeys() { keys = nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if keys == nil { keys = KeyArea.collect(self) }
        // 맨 아래 줄 키 바로 위를 누르면 아래 키로 (손가락이 노린 곳보다 위에 닿는 것을 보정)
        for k in keys ?? [] where k.reachUp > 0 && !k.isHidden && k.superview != nil {
            let f = k.convert(k.bounds, to: self)
            if point.x >= f.minX, point.x <= f.maxX, point.y < f.minY, point.y >= f.minY - k.reachUp { return k }
        }
        let hit = super.hitTest(point, with: event)
        // 잘못 누르면 곤란한 키(123 등)는 가장자리를 덜 받는다: 그 자리는 옆의 글자 키로 본다
        if let k = hit as? KeyButton, k.guardInsets != .zero {
            let f = k.convert(k.bounds, to: self)
            let core = CGRect(x: f.minX + k.guardInsets.left, y: f.minY + k.guardInsets.top,
                              width: f.width - k.guardInsets.left - k.guardInsets.right,
                              height: f.height - k.guardInsets.top - k.guardInsets.bottom)
            if !core.contains(point), let other = nearestKey(to: point, excluding: k) { return other }
        }
        // 키, 버튼, 스위치, 목록 같은 것은 그대로 둔다. 빈 바탕이나 줄 사이일 때만 가까운 키를 찾는다.
        if let h = hit, !(h === self || type(of: h) == UIStackView.self) { return hit }
        guard self.point(inside: point, with: event) else { return hit }
        if keys == nil { keys = KeyArea.collect(self) }
        var best: KeyButton?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for k in keys ?? [] where !k.isHidden && k.superview != nil {
            let f = k.convert(k.bounds, to: self)
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = k
            }
        }
        if let b = best, bestDistance <= KeyArea.reach * KeyArea.reach { return b }
        return hit
    }

    /// 가장 가까운 다른 키 (reach 안에서)
    private func nearestKey(to point: CGPoint, excluding: KeyButton) -> KeyButton? {
        if keys == nil { keys = KeyArea.collect(self) }
        var best: KeyButton?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for k in keys ?? [] where k !== excluding && !k.isHidden && k.superview != nil {
            let f = k.convert(k.bounds, to: self)
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = k
            }
        }
        return bestDistance <= KeyArea.reach * KeyArea.reach ? best : nil
    }

    /// 이 위치(keyArea 좌표)의 키. inner 만큼 가장자리를 빼고 본다 (밀어서 입력할 때 옆 키 안쪽까지 들어가야 바뀌도록)
    func key(at point: CGPoint, inner: CGFloat) -> KeyButton? {
        if keys == nil { keys = KeyArea.collect(self) }
        for k in keys ?? [] where !k.isHidden && k.superview != nil {
            let f = k.convert(k.bounds, to: self)
            if f.insetBy(dx: f.width * inner, dy: f.height * inner).contains(point) { return k }
        }
        return nil
    }

    /// 지금 자판의 모든 키
    var allKeys: [KeyButton] {
        if keys == nil { keys = KeyArea.collect(self) }
        return keys ?? []
    }

    private static func collect(_ v: UIView) -> [KeyButton] {
        v.subviews.flatMap { sub -> [KeyButton] in
            if let k = sub as? KeyButton { return [k] }
            return collect(sub)
        }
    }
}

/// 자판의 키 하나. 보조 글자가 있으면 꾹 눌렀을 때 말풍선을 띄우고, 뗄 때 보조 글자를 입력한다.
final class KeyButton: UIButton {
    var id = ""
    /// 이 키의 가장자리 중 덜 받을 폭. 그 자리를 누르면 옆 키로 본다 (잘못 누르면 화면이 바뀌는 키에 쓴다).
    var guardInsets: UIEdgeInsets = .zero
    /// 키 위쪽으로 이만큼 벗어나 눌러도 이 키로 본다 (맨 아래 줄)
    var reachUp: CGFloat = 0
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

    /// 왼쪽으로 밀기 (지우기 키의 단어 단위 삭제). 0 이면 쓰지 않는다.
    /// 밀기 시작한 뒤 swipeStep 만큼 더 밀 때마다 지울 단어가 하나씩 늘고, 떼면 onSwipeCommit 이 실행된다.
    var swipeStep: CGFloat = 0
    var swipeTitle: ((Int) -> String)?
    var onSwipeChange: ((Int) -> Void)?
    var onSwipeCommit: ((Int) -> Void)?
    static let swipeStart: CGFloat = 24

    /// 길게 눌렀을 때 보조 글자 말풍선이 뜨는 시간, 전체 삭제 같은 큰 말풍선이 뜨는 시간
    var holdDelay: TimeInterval = 0.35
    var altDelay: TimeInterval = 0.6

    /// 누르고 있으면 반복 입력 (보조 글자·큰 말풍선이 없는 키에서만)
    var onRepeat: (() -> Void)?
    var repeatDelay: TimeInterval = 0.35
    var repeatInterval: TimeInterval = 0.09
    private var repeatTimer: Timer?
    private var repeated = false

    /// 밀어서 연속 입력: 손가락이 움직일 때마다 불린다. 다른 키로 넘어가 입력했으면 true.
    var slideEnabled = false
    var onSlide: ((UITouch) -> Bool)?
    private var slid = false

    /// 간격 키: 누른 채 좌우로 밀면 커서를 옮긴다. 0 이면 쓰지 않는다.
    /// 시작은 cursorStart 만큼 밀었을 때, 그 뒤로 cursorStep 만큼 움직일 때마다 한 글자.
    var cursorStep: CGFloat = 0
    static let cursorStart: CGFloat = 14
    var onCursorStart: (() -> Void)?
    var onCursorMove: ((Int) -> Void)?
    var onCursorEnd: (() -> Void)?
    /// 위아래로 밀면 줄 단위로 (위 -1, 아래 +1)
    var onCursorLine: ((Int) -> Void)?
    static let cursorLineStep: CGFloat = 26
    private var cursorX: CGFloat?
    private var cursorY: CGFloat = 0
    private var startY: CGFloat = 0

    private let hintLabel = UILabel()
    private var startX: CGFloat = 0
    private var swipeCount: Int?
    private var swipeBubble: UILabel?
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
        repeated = false
        slid = false
        onDown?()
        if altTitle != nil {
            altTimer?.invalidate()
            let a = Timer(timeInterval: altDelay, repeats: false) { [weak self] _ in self?.showAlt() }
            RunLoop.main.add(a, forMode: .common)
            altTimer = a
        }
        if onRepeat != nil, hintText == nil, altTitle == nil { startRepeat() }
        guard hintText != nil else { return }
        holdTimer?.invalidate()
        let t = Timer(timeInterval: holdDelay, repeats: false) { [weak self] _ in self?.showBubble() }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    private func startRepeat() {
        stopRepeat()
        let first = Timer(timeInterval: repeatDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.repeated = true
            self.onRepeat?()
            let again = Timer(timeInterval: self.repeatInterval, repeats: true) { [weak self] _ in self?.onRepeat?() }
            RunLoop.main.add(again, forMode: .common)
            self.repeatTimer = again
        }
        RunLoop.main.add(first, forMode: .common)
        repeatTimer = first
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    @objc private func didTouchUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        stopRepeat()
        if endCursor() {
            onUp?()
            return
        }
        // 밀어서 입력했거나 반복 입력했으면 뗄 때 한 번 더 넣지 않는다
        if slid || repeated {
            onUp?()
            return
        }
        if let n = endSwipe() {
            onUp?()
            onSwipeCommit?(n)
            return
        }
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
        stopRepeat()
        hideBubble()
        if endCursor() {
            onUp?()
            return
        }
        if slid {
            onUp?()
            return
        }
        if let n = endSwipe() {
            // 밀어서 키 밖으로 나가도 단어 삭제는 그대로 한다
            onUp?()
            onSwipeCommit?(n)
            return
        }
        let alt = endAlt()
        onUp?()
        if alt { onAlt?() }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        startX = touch.location(in: self).x
        startY = touch.location(in: self).y
        swipeCount = nil
        cursorX = nil
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.continueTracking(touch, with: event)
        if cursorStep > 0 {
            trackCursor(touch)
            return true          // 키 밖으로 나가도 계속 커서를 옮긴다
        }
        trackSwipe(touch)
        if slideEnabled, bubble == nil, altBubble == nil, let slide = onSlide, slide(touch) {
            if !slid {
                slid = true
                holdTimer?.invalidate()
                holdTimer = nil
                stopRepeat()
            }
        }
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

    private func trackCursor(_ touch: UITouch) {
        let p = touch.location(in: self)
        let x = p.x
        if cursorX == nil {
            guard abs(x - startX) > KeyButton.cursorStart || abs(p.y - startY) > KeyButton.cursorStart else { return }
            cursorX = x
            cursorY = p.y
            onCursorStart?()
            return
        }
        guard let last = cursorX else { return }
        let steps = Int((x - last) / cursorStep)
        if steps != 0 {
            cursorX = last + CGFloat(steps) * cursorStep
            onCursorMove?(steps)
        }
        let lines = Int((p.y - cursorY) / KeyButton.cursorLineStep)
        if lines != 0 {
            cursorY += CGFloat(lines) * KeyButton.cursorLineStep
            onCursorLine?(lines)
        }
    }

    /// 커서를 옮기던 중이었으면 끝내고 true
    private func endCursor() -> Bool {
        guard cursorX != nil else { return false }
        cursorX = nil
        onCursorEnd?()
        return true
    }

    private func trackSwipe(_ touch: UITouch) {
        guard swipeStep > 0, altBubble == nil else { return }
        let dx = startX - touch.location(in: self).x
        if swipeCount == nil {
            guard dx > KeyButton.swipeStart else { return }
            // 밀기 시작: 전체 삭제 말풍선은 띄우지 않는다
            altTimer?.invalidate()
            altTimer = nil
            swipeCount = -1
        }
        let n = dx > KeyButton.swipeStart ? 1 + Int((dx - KeyButton.swipeStart) / swipeStep) : 0
        guard n != swipeCount else { return }
        swipeCount = n
        showSwipeBubble(n)
        onSwipeChange?(n)
    }

    private func showSwipeBubble(_ n: Int) {
        guard let host = bubbleHost else { return }
        if swipeBubble == nil {
            let f = convert(bounds, to: host)
            let w: CGFloat = 112
            let h: CGFloat = 40
            let x = max(2, min(f.maxX - w, host.bounds.width - w - 2))
            let y = max(0, f.minY - h - 4)
            let label = UILabel(frame: CGRect(x: x, y: y, width: w, height: h))
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 15)
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true
            host.addSubview(label)
            swipeBubble = label
        }
        swipeBubble?.text = swipeTitle?(n) ?? "\(n)"
        swipeBubble?.backgroundColor = n > 0 ? altHoverBackground : altBackground
        swipeBubble?.textColor = n > 0 ? altHoverText : altText
    }

    /// 밀기 중이었으면 말풍선을 닫고 지울 단어 수를 돌려준다
    private func endSwipe() -> Int? {
        guard let n = swipeCount else { return nil }
        swipeCount = nil
        swipeBubble?.removeFromSuperview()
        swipeBubble = nil
        altTimer?.invalidate()
        altTimer = nil
        return max(n, 0)
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
    let thumb = UIImageView()
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

        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 6
        thumb.widthAnchor.constraint(equalToConstant: 37).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 37).isActive = true

        let stack = UIStackView(arrangedSubviews: [pinButton, thumb, label, deleteButton, cancelButton, confirmButton])
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

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// 사진 항목의 두 줄: 복사한 날짜와 시각, 그 아래에 크기와 용량
    static func photoText(_ clip: Clip, theme: Theme) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: dateFormatter.string(from: clip.date),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                         .foregroundColor: theme.text])
        var info = ""
        if let w = clip.width, let h = clip.height { info = "\(w) × \(h)" }
        if let b = clip.bytes {
            let mb = String(format: "%.1f MB", Double(b) / 1_048_576)
            info = info.isEmpty ? mb : info + " · " + mb
        }
        if !info.isEmpty {
            s.append(NSAttributedString(
                string: "\n" + info,
                attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: theme.muted]))
        }
        return s
    }

    func configure(_ clip: Clip, confirming: Bool, theme: Theme, thumbnail: UIImage? = nil) {
        card.backgroundColor = theme.row
        card.layer.borderWidth = confirming ? 2 : 0
        card.layer.borderColor = theme.danger.cgColor

        pinButton.isHidden = confirming
        deleteButton.isHidden = confirming
        cancelButton.isHidden = !confirming
        confirmButton.isHidden = !confirming

        thumb.isHidden = confirming || clip.image == nil
        thumb.image = thumbnail
        thumb.backgroundColor = theme.funcKey

        if confirming {
            label.attributedText = nil
            label.numberOfLines = 1
            label.text = "  고정 항목을 삭제할까요?"
            label.font = .boldSystemFont(ofSize: 15)
            label.textColor = theme.danger
        } else if clip.image != nil {
            label.numberOfLines = 2
            label.attributedText = ClipCell.photoText(clip, theme: theme)
        } else {
            label.attributedText = nil
            label.numberOfLines = 1
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
