import UIKit

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {

    private let store = ClipStore()
    private var items: [Clip] = []
    private let table = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var lastChangeCount = -1
    private var timer: Timer?
    private var deleteTimer: Timer?

    // MARK: - 화면 구성

    override func viewDidLoad() {
        super.viewDidLoad()

        let height = view.heightAnchor.constraint(equalToConstant: 290)
        height.priority = .defaultHigh
        height.isActive = true

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        let bar = makeBar()
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),

            emptyLabel.centerYAnchor.constraint(equalTo: table.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func makeBar() -> UIStackView {
        let globe = key(symbol: "globe")
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let clear = key(symbol: "trash")
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let space = key(title: "간격")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        let back = key(symbol: "delete.left")
        back.addTarget(self, action: #selector(backDown), for: .touchDown)
        back.addTarget(self, action: #selector(backUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let enter = key(symbol: "return")
        enter.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        let bar = UIStackView(arrangedSubviews: [globe, clear, space, back, enter])
        bar.axis = .horizontal
        bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        for b in [globe, clear, back, enter] {
            b.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }
        return bar
    }

    private func key(symbol: String? = nil, title: String? = nil) -> UIButton {
        let b = UIButton(type: .system)
        if let symbol = symbol { b.setImage(UIImage(systemName: symbol), for: .normal) }
        if let title = title { b.setTitle(title, for: .normal) }
        b.tintColor = .label
        b.backgroundColor = .systemGray3
        b.layer.cornerRadius = 6
        return b
    }

    // MARK: - 클립보드 수집

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capture()
        reload()
        // 키보드가 떠 있는 동안 새로 복사한 것도 잡는다
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.capture()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
        backUp()
    }

    private func capture() {
        guard hasFullAccess else { return }
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard pb.hasStrings, let text = pb.string else { return }
        store.add(text)
        reload()
    }

    private func reload() {
        items = store.sorted
        table.reloadData()
        if !hasFullAccess {
            emptyLabel.text = "설정 > 일반 > 키보드 > 키보드 > 클립보드에서\n'전체 접근 허용'을 켜야 복사한 내용을 읽을 수 있습니다."
        } else {
            emptyLabel.text = "아직 기록이 없습니다.\n텍스트를 복사한 뒤 이 키보드를 열면 저장됩니다."
        }
        emptyLabel.isHidden = !items.isEmpty
    }

    // MARK: - 키 동작

    @objc private func spaceTapped() { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }

    @objc private func backDown() {
        textDocumentProxy.deleteBackward()
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.textDocumentProxy.deleteBackward()
        }
    }

    @objc private func backUp() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    @objc private func clearTapped() {
        store.clearUnpinned()   // 고정한 항목은 남긴다
        reload()
    }

    // MARK: - 목록

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        let clip = items[indexPath.row]
        cell.textLabel?.text = (clip.pinned ? "📌 " : "") + clip.text
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        textDocumentProxy.insertText(items[indexPath.row].text)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let clip = items[indexPath.row]
        let del = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, done in
            self?.store.delete(clip.id)
            self?.reload()
            done(true)
        }
        let pin = UIContextualAction(style: .normal, title: clip.pinned ? "고정 해제" : "고정") { [weak self] _, _, done in
            self?.store.togglePin(clip.id)
            self?.reload()
            done(true)
        }
        pin.backgroundColor = .systemOrange
        return UISwipeActionsConfiguration(actions: [del, pin])
    }
}
