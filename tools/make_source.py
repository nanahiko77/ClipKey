#!/usr/bin/env python3
"""SideStore(AltStore 호환) 소스 파일을 만든다. GitHub Actions 가 빌드할 때마다 부른다.

사용: python3 tools/make_source.py 버전 빌드번호 날짜 ipa주소 ipa크기 아이콘주소 설명 > source.json
"""
import json
import sys

version, build, date, ipa_url, size, icon_url, notes = sys.argv[1:8]
repo_url = "https://github.com/nanahiko77/ClipKey"
source_url = repo_url + "/releases/latest/download/source.json"

app_version = {
    "version": version,
    "buildVersion": build,
    "date": date,
    "localizedDescription": notes,
    "downloadURL": ipa_url,
    "size": int(size),
    "minOSVersion": "15.0",
}
source = {
    "name": "ClipKey",
    "identifier": "com.ban.clipkey.source",
    "sourceURL": source_url,
    "website": repo_url,
    "apps": [{
        "name": "ClipKey",
        "bundleIdentifier": "com.ban.clipkey",
        "developerName": "Ban",
        "subtitle": "클립보드가 붙은 한글 키보드",
        "localizedDescription": "나랏글·두벌식·영문 쿼티 키보드에 클립보드 기록, 추천 단어, 한글 오타 교정을 붙였다.",
        "iconURL": icon_url,
        "tintColor": "3D3D3D",
        # 예전 형식을 읽는 앱을 위해 최신 버전 정보를 앱 수준에도 둔다
        "version": version,
        "versionDate": date,
        "versionDescription": notes,
        "downloadURL": ipa_url,
        "size": int(size),
        "versions": [app_version],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }],
    "news": [],
}
json.dump(source, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
