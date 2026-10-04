# TMS 작업 요청 — iOS 앱(KTX Driver) 지원

## 진행 상황 (2026-10-04, TMS 회신 `docs/APP_REVIEW_NOTES.md` 기준 — 그 파일은 데모 로그인 때문에 git 제외)

| # | 항목 | 상태 |
|---|---|---|
| 1 | AASA 파일 | TMS는 "제공 중(200, JSON)"이라고 회신했지만, **2026-10-04 11:3x 확인 시 www.withktx.com은 302 → `/vendor/login`, driver.withktx.com은 301 → `/driver/`** (배포 전이거나 nginx가 가로챔). 배포 확인 필요. `TMS_IOS_TEAM_ID`는 Team ID가 생기면 설정. 아래 1-1 추가 요청 |
| 2 | 앱 안 + iPhone 문구 | `TMS_IOS_APP_URL` 설정 시 Safari에 App Store 안내. 앱 안 문구 숨김은 실기기에서 확인 |
| 3 | 드라이버 가이드 아이폰 판 | 미확인 |
| 4 | 개인정보처리방침 | **완료** — https://withktx.com/privacy 2절에 Android·iPhone 앱, 90일 보관 |
| 5 | 심사용 데모 계정 | **완료** — SMS 없이 로그인되는 시험 번호(운영 서버 설정, 심사 기간 동안 유지) |
| 6 | version.json "ios" | 서버는 파일을 그대로 제공. 앱 등록 후 링크 넣기 |

### 1-1. AASA 추가 요청 (iOS 세션 의견)

- 회신에 따르면 AASA가 `/driver/*`와 **`/*`** 둘 다를 앱에 연결한다. `/*`이면 앱이 설치된 아이폰에서
  www.withktx.com의 **모든** 링크(고객용 화물 조회 페이지, 다운로드 파일 등)가 앱으로 열린다.
  앱은 우리 사이트의 다운로드를 Safari로 넘기는데, 그 주소가 다시 앱으로 돌아오는 문제도 생길 수 있다.
  → **`/driver/*`만 남기고 `/*`는 빼는 것**을 요청한다(다운로드 경로가 `/driver/` 아래라면 `"exclude": true`로 제외).
- 앱 entitlement에 `applinks:driver.withktx.com`도 있으므로, driver.withktx.com의
  `/.well-known/apple-app-site-association`도 리디렉션 없이 200이어야 한다(nginx 예외). 안 되면 그 도메인의
  Universal Link만 동작하지 않는다(www는 영향 없음). 어려우면 앱에서 이 도메인을 빼도 된다 — 알려 주면 앱을 고친다.

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
