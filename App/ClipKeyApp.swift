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

    /// 아이폰 내장 사전이 한글 추천을 지원하는지
    private var koreanDictionary: Bool {
        UITextChecker.availableLanguages.contains { $0.hasPrefix("ko") }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("키보드 켜기")) {
                    Text("1. 설정 > 일반 > 키보드 > 키보드 > 새로운 키보드 추가 > ClipKey")
                    Text("2. 추가된 '클립보드'를 눌러 '전체 접근 허용' 켜기")
                    Text("3. 입력 중 지구본 키를 길게 눌러 '클립보드' 선택")
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section(header: Text("사용법")) {
                    Text("위쪽 줄: 한/영, 123(숫자·기호), 클립보드, 추천 단어, 커서 이동")
                    Text("글자키를 꾹 누르면 오른쪽 위의 흐린 글자가 입력됩니다")
                    Text("클립보드에서 항목을 누르면 붙여넣기, 길게 누르면 전체 보기")
                    Text("설정은 클립보드 화면 오른쪽 위에서 엽니다")
                }
                Section(header: Text("상태")) {
                    Text("한글 추천 단어 사전: " + (koreanDictionary ? "지원함" : "지원 안 함"))
                    Text("지원하지 않아도 자주 친 단어와 고정한 항목은 추천됩니다")
                }
                Section(header: Text("여기서 테스트")) {
                    TextField("여기를 눌러 키보드 확인", text: $test)
                }
            }
            .navigationTitle("ClipKey")
        }
        .navigationViewStyle(.stack)
    }
}
