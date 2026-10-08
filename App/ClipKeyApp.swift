import SwiftUI

@main
struct ClipKeyApp: App {
    var body: some Scene {
        WindowGroup { GuideView() }
    }
}

struct GuideView: View {
    @State private var test = ""

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
                    Text("항목을 누르면 붙여넣기, 왼쪽으로 밀면 고정/삭제")
                    Text("휴지통 키는 고정하지 않은 기록을 모두 지웁니다")
                    Text("기록은 키보드가 열려 있을 때 복사한 내용만 저장됩니다")
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
