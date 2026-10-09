import Foundation

/// 새 버전이 있는지 GitHub 릴리스의 SideStore 소스(source.json)를 읽어 확인한다.
/// 본체 앱과 키보드가 같이 쓴다. (키보드에서는 '전체 접근 허용'이 켜져 있어야 인터넷을 쓸 수 있다)
enum UpdateCheck {
    static let sourceURL = URL(string: "https://github.com/nanahiko77/ClipKey/releases/latest/download/source.json")!
    static let dictionaryURL = URL(string: "https://raw.githubusercontent.com/nanahiko77/ClipKey/v1.1-keyboard/Keyboard/ko_dict.txt")!
    /// SideStore 를 여는 주소
    static let sideStoreURL = URL(string: "sidestore://")!

    struct Latest {
        let version: String
        let build: Int
        var text: String { "\(version) (\(build))" }
    }

    enum Result {
        case latest
        case newer(Latest)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    static var currentText: String { "\(currentVersion) (\(currentBuild))" }

    /// 결과는 메인 스레드로 돌려준다
    static func check(completion: @escaping (Result) -> Void) {
        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, error in
            let result: Result
            if let data = data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let app = (object["apps"] as? [[String: Any]])?.first,
               let latest = (app["versions"] as? [[String: Any]])?.first,
               let version = latest["version"] as? String,
               let build = Int(latest["buildVersion"] as? String ?? "") {
                result = build > currentBuild ? .newer(Latest(version: version, build: build)) : .latest
            } else {
                result = .failed(error != nil ? "인터넷 연결을 확인해 주세요" : "버전 정보를 읽지 못했어요")
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// 사전 파일에서 단어 수를 센다 (# 줄과 자주 틀리는 말 ! 줄은 빼고)
    static func wordCount(_ text: String) -> Int {
        var n = 0
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("!") { n += 1 }
        return n
    }
}
