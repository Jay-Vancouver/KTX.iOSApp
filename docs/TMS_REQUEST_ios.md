# TMS 작업 요청 — iOS 앱(KTX Driver) 지원

iOS 앱 저장소(KTX.iOSApp)에서 정리한, TMS 세션에서 할 일. 앱은 Android와 같은 다리
(`window.KtxAndroidApp`)를 제공하므로 **다리 호출 코드는 고치지 않는다.**

## 1. Universal Links 파일 (필수)

SMS 로그인 링크(`/driver/s/<token>`)와 `/driver/` 페이지 링크를 누르면 Safari 대신 앱이 열리게 한다.

- 경로: `/.well-known/apple-app-site-association` (확장자 없음)
- 호스트: **www.withktx.com, driver.withktx.com 둘 다**
- `Content-Type: application/json`, **리디렉션 없이 200** (driver.withktx.com → www 리디렉션에서 이 경로는 제외)
- 내용 (`<TeamID>`는 Apple 개발자 계정이 생기면 알려 줌):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TeamID>.com.ktxtransport.driver"],
        "components": [
          { "/": "/driver/*" }
        ]
      }
    ]
  }
}
```

- driver.withktx.com은 경로가 `/`부터 시작하므로 driver 호스트용 파일에는 `{ "/": "/*" }`도 넣는 것을 검토.
- 확인: `curl -i https://www.withktx.com/.well-known/apple-app-site-association` → 200, JSON.
  Apple CDN 반영 확인: `https://app-site-association.cdn-apple.com/a/v1/www.withktx.com`.
- 참고: 앱은 우리 사이트의 다운로드 파일(PDF 등)을 Safari로 넘긴다. 다운로드 주소가 `/driver/` 아래이면
  Universal Link 때문에 다시 앱으로 돌아올 수 있으므로, 그런 경로가 있으면 `"exclude": true` 항목으로 제외한다
  (실기기에서 확인 후 확정).

## 2. 앱 안 + iPhone일 때 페이지 문구

판별: User-Agent에 `KTXDriverApp/`가 있고 `iPhone`이 있으면 iOS 앱.
(예: `Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 KTXDriverApp/1.0.0`)

- APK 설치, 배터리 최적화, "출처를 알 수 없는 앱" 문구와 Traccar Client 안내를 숨긴다.
- 앱 다운로드 안내는 App Store 링크로(링크는 등록 후 알려 줌).
- `status().battery`는 iOS에서 항상 `"unrestricted"`이므로 배터리 버튼은 기존 로직대로 숨겨진다.

## 3. 드라이버 가이드 아이폰 판

App Store(또는 TestFlight) 설치 → SMS 로그인 링크 → 위치 "항상" + "정확한 위치" 허용 →
"앱 전환기에서 앱을 쓸어 올려 종료하지 말 것"(종료하면 iOS가 위치 전송을 다시 시작하지 않을 수 있음).

## 4. 개인정보처리방침

iOS 앱이 같은 위치 정보를 수집한다는 점이 포함되는지 확인(App Store 심사 시 방침 URL 필요).

## 5. App Store 심사용 데모 계정

심사자가 SMS 없이 로그인해 픽업 화면까지 볼 수 있는 시험 드라이버 계정과 심사 메모(로그인 방법, 위치 수집 시점 설명).

## 6. (선택) `/app/version.json`의 "ios" 항목

```json
{ "ios": { "version": "1.0.0", "url": "https://apps.apple.com/app/id<AppID>" } }
```
없으면 앱은 아무것도 하지 않는다.
