# ClipKey

아이폰용 키보드. 한글(나랏글/두벌식), 영문 쿼티, 숫자·기호 자판에 클립보드 기록과 추천 단어를 붙였다.

## 구조
- `App/` 안내 화면만 있는 본체 앱 (SwiftUI)
- `Keyboard/` 키보드 확장
  - `KeyboardViewController.swift` 상태, 입력 처리, 추천 단어
  - `KeyboardLayouts.swift` 상단바와 자판 배치
  - `KeyboardPanels.swift` 클립보드, 설정, 학습한 단어 패널
  - `Hangul.swift` 한글 조합
  - `KeyViews.swift` 키 버튼(꾹 눌러 보조 글자), 클립보드 목록 줄
  - `Stores.swift` 설정, 색, 클립보드 기록, 학습한 단어 저장
  - `KoDictionary.swift` 한국어 추천 사전 읽기와 검색
  - `KoCorrector.swift` 한글 오타 교정 (자모 거리 + 자판 이웃 키 + 조사 떼기, 자주 틀리는 말 표)
  - `ko_dict.txt` 한국어 추천 사전 (만든 파일, 직접 고치지 않는다)
- `tools/` 사전 만들기
  - `ko_vocab.tsv` 국립국어원 한국어 학습용 어휘 목록 (UTF-8로 바꾼 것)
  - `ko_typos.tsv` 자주 틀리는 말 (틀린꼴 → 바른꼴). 언제나 틀린 꼴만 넣는다
  - `make_ko_dict.py` 어휘 목록에서 `ko_dict.txt`를 만든다. 동사·형용사는 활용형(갔어, 추워요, 들은 …)까지 넣는다
- `project.yml` XcodeGen 설정. Xcode 프로젝트 파일은 빌드할 때 생성
- `.github/workflows/build.yml` 서명 없는 ipa를 만드는 GitHub Actions

## 한국어 사전 받기
키보드 설정 > 정보 > 맞춤법 사전의 [업데이트]를 누르면 GitHub의 `Keyboard/ko_dict.txt`를 받아 바로 쓴다
(전체 접근 허용 필요). 사전만 고쳤을 때는 ipa를 다시 설치하지 않아도 된다.

## 한국어 사전 다시 만들기
`tools/ko_vocab.tsv`나 `make_ko_dict.py`를 고친 뒤 `python3 tools/make_ko_dict.py`를 돌리고 `Keyboard/ko_dict.txt`를 같이 올린다.

## 빌드
Actions의 "Build IPA"를 직접 실행한다 (Run workflow). 끝나면 GitHub 릴리스에 `ClipKey.ipa`와
SideStore 소스(`source.json`)가 올라간다. 빌드 번호는 Actions 실행 번호를 쓴다.

## 설치와 업데이트
SideStore > Sources > `+` 에 아래 주소를 한 번 등록하면, 새 빌드가 SideStore의 업데이트로 뜬다.

    https://github.com/nanahiko77/ClipKey/releases/latest/download/source.json

처음 설치할 때 확장을 묻는 창이 뜨면 Keep App Extensions를 고른다.

## 키보드 켜기
설정 > 일반 > 키보드 > 키보드 > 새로운 키보드 추가 > ClipKey,
그다음 '클립보드'를 눌러 '전체 접근 허용'을 켠다.
