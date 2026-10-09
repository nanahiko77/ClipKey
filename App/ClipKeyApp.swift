import SwiftUI
import UIKit

@main
struct ClipKeyApp: App {
    var body: some Scene {
        WindowGroup { GuideView() }
    }
}

struct GuideView: View {
    @State private var test = ""

    // 앱 버전 줄
    @State private var appCaption = "확인하는 중…"
    @State private var appStrong = false
    @State private var newer = false
    @State private var checking = false

    // 맞춤법 사전 줄 (앱에 들어 있는 사전 기준. 키보드가 받은 사전은 키보드 설정에서 본다)
    @State private var dictWords = ""
    @State private var dictCaption = "키보드 설정 › 정보에서 업데이트"
    @State private var dictStrong = false
    @State private var dictChecking = false

    private static let dark = Color(red: 61 / 255, green: 61 / 255, blue: 61 / 255)

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("업데이트")) {
                    infoRow(title: "앱 버전", value: UpdateCheck.currentText,
                            caption: appCaption, strong: appStrong,
                            button: newer ? "SideStore 열기" : "업데이트 확인", filled: newer,
                            busy: checking) {
                        if newer { openSideStore() } else { checkApp() }
                    }
                    infoRow(title: "맞춤법 사전", value: dictWords,
                            caption: dictCaption, strong: dictStrong,
                            button: "업데이트 확인", filled: false, busy: dictChecking) {
                        checkDictionary()
                    }
                }
                Section(header: Text("키보드 켜기")) {
                    Text("1. 설정 › 일반 › 키보드 › 새로운 키보드 추가 › ClipKey")
                    Text("2. 추가된 '클립보드'에서 '전체 접근 허용' 켜기")
                    Text("3. 지구본 키를 길게 눌러 '클립보드' 선택")
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section(header: Text("여기서 테스트")) {
                    TextField("여기를 눌러 키보드 확인", text: $test)
                }
            }
            .navigationTitle("ClipKey")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            loadBundledWords()
            checkApp()
        }
    }

    /// 정보 줄: [제목 값 / 아래 설명] [버튼]. 버튼 폭을 같게 해서 오른쪽 끝을 맞춘다.
    private func infoRow(title: String, value: String, caption: String, strong: Bool,
                         button: String, filled: Bool, busy: Bool,
                         action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.system(size: 16))
                    Text(value).font(.system(size: 14)).foregroundColor(.secondary)
                }
                Text(caption)
                    .font(.system(size: 12, weight: strong ? .bold : .regular))
                    .foregroundColor(strong ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Text(busy ? "확인하는 중" : button)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 112, height: 34)
                    .foregroundColor(filled ? .white : .primary)
                    .background(filled ? GuideView.dark : Color(.systemGray5))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.vertical, 8)
    }

    private func checkApp() {
        guard !checking else { return }
        checking = true
        UpdateCheck.check { result in
            checking = false
            switch result {
            case .latest:
                newer = false
                appCaption = "최신 버전이에요 · 방금 확인"
                appStrong = false
            case .newer(let v):
                newer = true
                appCaption = "새 버전 \(v.text)이 있어요"
                appStrong = true
            case .failed(let why):
                newer = false
                appCaption = "확인하지 못했어요 · " + why
                appStrong = false
            }
        }
    }

    /// SideStore 를 연다. 열리지 않으면 직접 열어 달라고 안내한다.
    private func openSideStore() {
        UIApplication.shared.open(UpdateCheck.sideStoreURL) { ok in
            if !ok {
                appCaption = "SideStore를 열지 못했어요 · 직접 열어 업데이트하세요"
                appStrong = true
            }
        }
    }

    /// 앱에 들어 있는 사전
    private func bundledDictionary() -> Data? {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        let url = plugins.appendingPathComponent("ClipKeyboard.appex/ko_dict.txt")
        return try? Data(contentsOf: url)
    }

    private func loadBundledWords() {
        DispatchQueue.global(qos: .utility).async {
            let n = bundledDictionary().flatMap { String(data: $0, encoding: .utf8) }.map(UpdateCheck.wordCount) ?? 0
            let text = n > 0 ? NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) + "단어" : "없음"
            DispatchQueue.main.async { dictWords = text }
        }
    }

    /// GitHub 의 사전이 앱에 들어 있는 것과 다른지 본다. 받기는 키보드 설정에서 한다.
    private func checkDictionary() {
        guard !dictChecking else { return }
        dictChecking = true
        var request = URLRequest(url: UpdateCheck.dictionaryURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, error in
            let bundled = bundledDictionary()
            DispatchQueue.main.async {
                dictChecking = false
                guard let data = data, error == nil else {
                    dictCaption = "확인하지 못했어요 · 인터넷 연결을 확인해 주세요"
                    dictStrong = false
                    return
                }
                if data == bundled {
                    dictCaption = "앱에 들어 있는 사전이 최신이에요"
                    dictStrong = false
                } else {
                    dictCaption = "새 사전이 있어요 · 키보드 설정 › 정보에서 받으세요"
                    dictStrong = true
                }
            }
        }.resume()
    }
}
