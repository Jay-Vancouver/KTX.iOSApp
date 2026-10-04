# 서명·배포 — KTX Driver (iOS)

순서: **A. 무료 개인 팀으로 내 아이폰에 설치해 시험** (Apple 회사 계정이 없을 때) →
**B. 회사 계정 준비** → **C. Archive·업로드** → **D. TestFlight 시범 운영** →
**E. App Store 등록 정보·심사** → **F. Unlisted(목록 비공개) 배포**.

빌드는 Xcode 화면 없이 `xcodegen` + `xcodebuild`로 한다(설치는 `docs/SETUP.md`).
비밀 값은 저장소 밖 두 파일에 둔다(둘 다 `.gitignore`에 있음).

| 파일 | 내용 |
|---|---|
| `Secrets.xcconfig` | `KTX_ADMIN_PIN = ...` (관리자 PIN, 앱에는 SHA-256만 들어감) |
| `Signing.xcconfig` | `DEVELOPMENT_TEAM = <Team ID>` 등 서명 값 (`Config/App.xcconfig`가 읽음) |

---

## A. 무료 개인 팀으로 내 아이폰에 설치 (회사 계정 전 시험용)

무료 Apple ID로도 내 아이폰에 직접 설치해 시험할 수 있다. 제약:
- 설치한 앱은 **7일 뒤 실행이 안 된다** → 다시 설치하면 된다.
- 한 기기에 이런 앱은 최대 3개.
- **Associated Domains(Universal Links)를 쓸 수 없다** → 개인 팀용 entitlement로 빌드한다.
  SMS 로그인 링크를 눌러도 Safari에서 열린다(로그인이 앱에 남지 않음). 대신 링크 주소를 복사해
  Debug 실행 인자로 앱에 넘긴다(5번 아래 명령).
- 번들 ID `com.ktxtransport.driver`는 회사 팀이 등록하면 개인 팀이 쓸 수 없으므로 개인용 ID를 쓴다.
- 백그라운드 위치, 카메라는 개인 팀에서도 동작한다.

1. Xcode에 Apple ID 추가: Xcode → Settings → Accounts → `+` → Apple ID. (한 번만, 화면 작업 필요)
2. 개인 팀 ID 확인:
   ```sh
   security find-identity -v -p codesigning     # "Apple Development: <이름> (<10자리>)"
   ```
   팀 ID는 Xcode → Settings → Accounts → 팀 선택 시 보이는 10자리. (인증서 괄호 안 값과 다를 수 있음)
3. 저장소 루트에 `Signing.xcconfig`:
   ```
   DEVELOPMENT_TEAM = <개인 팀 ID>
   KTX_BUNDLE_ID = com.<이름>.ktxdriver
   KTX_ENTITLEMENTS = KTXDriver/KTXDriver-Personal.entitlements
   ```
4. 아이폰: USB로 Mac에 연결 → "이 컴퓨터를 신뢰" → 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켜기(재시동).
5. 빌드·설치:
   ```sh
   eval "$(/opt/homebrew/bin/brew shellenv)"
   xcodegen generate
   xcrun devicectl list devices                       # 기기 이름/ID 확인
   xcodebuild -project KTXDriver.xcodeproj -scheme KTXDriver -configuration Debug \
     -destination 'platform=iOS,name=<아이폰 이름>' -derivedDataPath build/dd \
     -allowProvisioningUpdates build
   xcrun devicectl device install app --device <기기 ID> \
     build/dd/Build/Products/Debug-iphoneos/KTXDriver.app
   ```
   SMS 로그인 링크를 앱에서 열기(개인 팀 빌드에는 Universal Links가 없으므로):
   ```sh
   xcrun devicectl device process launch --terminate-existing --device <기기 ID> com.<이름>.ktxdriver \
     -debugOpenURL 'https://www.withktx.com/driver/s/<token>'
   ```
6. 처음 실행 시 "신뢰할 수 없는 개발자" → 아이폰 설정 → 일반 → VPN 및 기기 관리 → 내 Apple ID → 신뢰.
7. Debug 빌드에서는 웹 다리 없이 추적을 켤 수 있다(로컬 수신기는 Mac과 같은 Wi-Fi에서
   `python3 tools/osmand_receiver.py --host 0.0.0.0`, 단 Debug 빌드의 http 허용은 127.0.0.1/localhost뿐이라
   실기기 시험은 실제 서버나 시험 서버로 한다):
   ```sh
   xcrun devicectl device process launch --device <기기 ID> com.<이름>.ktxdriver \
     -debugTracking start -debugPhone <10자리> -debugURL https://www.withktx.com/gps
   ```

회사 계정이 생기면 `Signing.xcconfig`에서 `KTX_BUNDLE_ID`, `KTX_ENTITLEMENTS` 줄을 지우고 팀 ID만 회사 것으로 바꾼다.

---

## B. 회사(조직) Apple Developer 계정 준비

1. **Apple Developer Program — 조직(Organization)으로 가입** (https://developer.apple.com/programs/enroll/).
   - 필요: 회사 법인명, **D-U-N-S 번호**(없으면 Apple 안내에 따라 무료 발급, 며칠 걸림), 회사 웹사이트,
     서명 권한이 있는 담당자. 연회비 99 USD(현지 통화로 청구).
   - 개인 계정으로 가입하면 App Store 판매자 이름이 개인 이름으로 나온다 → 반드시 조직으로.
2. 가입 후 **Team ID**(10자리)를 확인 → `Signing.xcconfig`의 `DEVELOPMENT_TEAM`에 넣고,
   TMS 세션에 알려 AASA 파일의 `appIDs`를 채운다(`docs/TMS_REQUEST_ios.md` 1절).
3. Xcode → Settings → Accounts에 회사 계정(또는 회사 팀에 초대된 Apple ID) 추가.
4. 자동 서명(`CODE_SIGN_STYLE = Automatic`)이므로 첫 빌드 때 `-allowProvisioningUpdates`가
   App ID(`com.ktxtransport.driver`), Associated Domains 기능, 프로비저닝 프로파일을 만든다.
   - 수동으로 할 경우 developer.apple.com → Identifiers에서 App ID 등록, Capabilities에서 **Associated Domains** 체크.
   - Background Modes(location)는 별도 등록이 필요 없다(Info.plist의 `UIBackgroundModes`).
5. (선택, 명령줄 업로드용) **App Store Connect API 키**: App Store Connect → Users and Access → Integrations →
   App Store Connect API → 키 생성(역할 App Manager). `AuthKey_<KEYID>.p8`는 저장소 밖(예: `~/.appstoreconnect/`)에 둔다.
   Key ID, Issuer ID도 저장소에 넣지 않는다.

---

## C. Archive → App Store Connect 업로드

1. 버전 올리기(`project.yml`의 `settings.base`):
   - `MARKETING_VERSION`: 사용자에게 보이는 버전(1.0.0 → 1.0.1 …)
   - `CURRENT_PROJECT_VERSION`: 업로드마다 **반드시 증가**(1, 2, 3 …). 같은 버전 안에서도 올린다.
2. `Secrets.xcconfig`(관리자 PIN)가 있는지 확인 — **없으면 Archive가 실패한다**(의도된 동작).
3. Archive:
   ```sh
   eval "$(/opt/homebrew/bin/brew shellenv)"
   xcodegen generate
   xcodebuild -project KTXDriver.xcodeproj -scheme KTXDriver -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/KTXDriver.xcarchive \
     -allowProvisioningUpdates archive
   ```
4. 업로드(App Store Connect에 앱 레코드가 먼저 있어야 한다 — E-1):
   ```sh
   xcodebuild -exportArchive -archivePath build/KTXDriver.xcarchive \
     -exportOptionsPlist tools/ExportOptions.plist -exportPath build/export \
     -allowProvisioningUpdates
   # API 키를 쓸 때는 다음 세 옵션을 덧붙인다:
   #   -authenticationKeyPath ~/.appstoreconnect/AuthKey_<KEYID>.p8
   #   -authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER_ID>
   ```
   `tools/ExportOptions.plist`는 `method = app-store-connect`, `destination = upload`.
5. 10~30분 뒤 App Store Connect → 앱 → TestFlight에 빌드가 "처리 완료"로 나온다.
   수출 규정 질문은 Info.plist의 `ITSAppUsesNonExemptEncryption = NO`(https만 사용)로 자동 처리된다.

---

## D. TestFlight 시범 운영

- **내부 테스터**: App Store Connect 사용자(회사 팀원, 최대 100명). 심사 없이 바로 설치.
- **외부 테스터**(드라이버): 최대 10,000명. 첫 빌드는 **TestFlight 베타 심사**(보통 1~2일)를 거친다.
  이메일 초대 또는 **공개 링크**. 드라이버는 App Store에서 **TestFlight** 앱을 설치한 뒤 링크를 연다.
- 빌드는 업로드 후 **90일**이 지나면 만료된다 → 시범 기간이 길면 새 빌드를 올린다.
- 베타 심사에도 데모 로그인 정보가 필요하다(E-4와 같은 내용).
- 드라이버 안내(TMS 가이드 아이폰 판): TestFlight 설치 → 링크 열기 → KTX Driver 설치 → SMS 로그인 링크 →
  "위치: 항상 허용" + "정확한 위치" → **앱 전환기에서 쓸어 올려 종료하지 말 것**.
- 시범 운영 체크리스트는 `docs/TEST.md`.

---

## E. App Store 등록 정보·심사

### E-1. 앱 레코드 (App Store Connect → 앱 → `+` 신규 앱)

| 항목 | 값 |
|---|---|
| 플랫폼 | iOS |
| 이름 | `KTX Driver` (이미 쓰이고 있으면 `KTX Driver - KTX Transport`) |
| 기본 언어 | English (Canada) 또는 English (U.S.) |
| 번들 ID | `com.ktxtransport.driver` |
| SKU | `ktx-driver-ios` |
| 사용자 액세스 | 전체 액세스 |
| 카테고리 | 비즈니스 (보조: 내비게이션 — 선택) |
| 가격 | 무료, 인앱 구매 없음 |
| 판매 국가 | 캐나다 (필요하면 미국 추가) |
| 연령 등급 | 설문에서 모두 "없음" → 4+ (업무용) |
| 개인정보처리방침 URL | `https://withktx.com/privacy` (iOS 앱 내용 보강 필요 — TMS 요청 4절) |
| 지원 URL | `https://withktx.com` |
| 저작권 | `© 2026 KTX Transport` |

### E-2. 스토어 문구

**English**

- Subtitle (30자): `Pickups, deliveries, tracking`
- Promotional text (170자): `The work app for KTX Transport drivers: scan pickups, collect delivery signatures and share your truck's location automatically while you haul.`
- Keywords (100자, 쉼표): `KTX,driver,trucking,freight,pickup,delivery,POD,signature,logbook,inspection,tracking`
- Description:
```
KTX Driver is the work app for drivers hauling freight for KTX Transport.

PICK UP
• Scan pallet tags with the phone camera, or type the order number when a load has no tag.
• Your pickups go straight to KTX dispatch — no paperwork to hand in.

DELIVERY
• Mark loads delivered and collect the receiver's name and signature on the phone.
• Proof of delivery is saved with the order right away.

AUTOMATIC LOCATION SHARING
• After pickup, the app shares your truck's location with KTX Transport so dispatch and the
  customer know where their freight is.
• It keeps working with the screen off and stops by itself after your last delivery.
• Location is used only to track the loads you are carrying.

DAILY LOG AND INSPECTION
• Fill in your driving log and pre-trip vehicle inspection, with photos of any defects.

SIMPLE SIGN-IN
• Enter your phone number and tap the link we text you. You stay signed in for months.

KTX Driver is for drivers registered with KTX Transport. A registered phone number is needed to sign in.
```

**한국어** (현지화 추가 시)

- 부제: `픽업 스캔·배송 확인·위치 공유`
- 키워드: `KTX,드라이버,트럭,화물,픽업,배송,서명,운행일지,차량점검,위치`
- 설명: Android 등록 정보(`KTX.AndroidApp/docs/store/LISTING.md` 3절)의 한국어 설명과 같다.

### E-3. 스크린샷

- 필수: App Store Connect가 요구하는 가장 큰 iPhone 크기(현재 6.9", 예: 1320×2868) 3~10장.
  작은 크기는 자동 축소된다.
- 실제 로그인된 화면이 필요하므로, 시험 드라이버로 로그인한 **시뮬레이터 iPhone 18 Pro Max**에서 찍는다:
  ```sh
  xcrun simctl io booted screenshot ~/Desktop/ktx_1.png
  ```
  추천 장면: 픽업 스캔, 배송 서명, 상태(위치 카드), 운행 일지, 첫 실행 안내(위치 항상 허용).
- 시뮬레이터에는 카메라가 없으므로 스캔 화면은 실기기에서 찍어 크기를 맞추거나 생략한다.

### E-4. 앱 심사 정보 (App Review Information)

- **로그인 정보**: SMS 링크 로그인이라 심사자가 들어갈 방법이 필요 → TMS에서 심사용 시험 드라이버
  (고정 로그인 링크 또는 비밀번호 로그인)와 픽업 가능한 시험 화물을 마련(TMS 요청 5절).
- **연락처**: 담당자 이름·전화·이메일.
- **메모(Notes)** 초안:
```
KTX Driver is an internal work app for truck drivers contracted by KTX Transport (Canada).

Sign-in: drivers sign in with a link texted to their registered phone number. For review please use:
  <demo login link or credentials from TMS>
A test pickup is assigned to this account so you can see the full flow.

Background location (UIBackgroundModes: location):
- When the driver completes a pickup in the app, the page calls the native tracker, which sends the
  truck's position to our server about once a minute, including with the screen off, so dispatch and the
  customer can follow the freight. Tracking stops automatically after the driver's last delivery of the day.
- Before any system location prompt the app shows its own disclosure explaining this collection, and the
  driver can decline. The blue location indicator is shown while tracking in the background.
- Location is used only for freight tracking; it is not shared with advertisers or used for tracking
  across apps.

Native features beyond the website: background location tracking with an offline queue, camera scanning,
Universal Links for the texted sign-in link, and a settings screen with tracking status.
```

### E-5. 앱 개인정보 보호 (App Privacy — "데이터 수집" 설문)

App Store Connect의 답과 `KTXDriver/Resources/PrivacyInfo.xcprivacy`를 맞춘다.
웹 페이지(앱 안 WebView)가 모으는 데이터도 포함한다. 모두 **추적(Tracking)에 사용 안 함**.

| 데이터 유형 | 수집 | 사용자와 연결 | 목적 |
|---|---|---|---|
| 위치 — 정확한 위치 | 예 | 예 | 앱 기능 |
| 연락처 정보 — 전화번호 | 예 | 예 | 앱 기능 (로그인·드라이버 식별) |
| 연락처 정보 — 이름 (받는 분) | 예 | 예 | 앱 기능 (배송 증빙) |
| 사용자 콘텐츠 — 사진 | 예 | 예 | 앱 기능 (점검·배송 사진) |
| 사용자 콘텐츠 — 기타(서명) | 예 | 예 | 앱 기능 |
| 진단 — 기타(배터리 잔량, 전송 오류) | 예 | 예 | 앱 기능 |

### E-6. 심사에서 자주 걸리는 항목

- **4.2 최소 기능**(웹사이트를 감싼 앱): 백그라운드 위치 전송·오프라인 큐·카메라·Universal Links 등
  네이티브 기능을 메모에 적는다(E-4).
- **2.5.4 / 5.1.1 백그라운드 위치**: 목적 문구가 구체적이어야 한다(Info.plist `NSLocation...UsageDescription`,
  한글·영문). 심사자가 실제로 위치가 쓰이는 흐름(픽업 → 전송)을 볼 수 있어야 한다 → 데모 계정·시험 화물.
- **로그인 불가**: 데모 계정이 동작하지 않으면 바로 거절된다. 제출 직전 직접 로그인해 확인.
- **개인정보처리방침**이 iOS 앱의 위치 수집(백그라운드, 자동 시작·중지)을 설명해야 한다.

---

## F. Unlisted(목록 비공개) 배포

회사 드라이버만 쓰는 앱이므로 App Store 검색·목록에는 나오지 않고 **링크로만** 설치되게 한다.

1. 앱을 일반 App Store 배포용으로 제출해 심사 통과(또는 제출과 함께 요청).
2. **Unlisted 앱 배포 요청 양식** 제출: https://developer.apple.com/contact/request/unlisted-app/
   (앱 이름, Apple ID, 사용 대상 설명: "Internal app for drivers contracted by KTX Transport; not useful to the general public").
3. 승인되면 App Store Connect의 앱 링크(`https://apps.apple.com/app/id<AppID>`)로만 설치할 수 있다.
   이 링크를 TMS 드라이버 페이지와 가이드, `/app/version.json`의 `ios.url`에 넣는다(TMS 요청 2·6절).
4. Unlisted가 거절되면 일반 공개로 두어도 된다(로그인하려면 등록된 전화번호가 필요하므로 외부인은 쓸 수 없다).

참고: Apple Business Manager의 Custom App은 "조직에 배포"하는 방식이라, 개인 휴대폰을 쓰는
계약 드라이버에게는 Unlisted가 더 맞다.

---

## 확인한 것 (2026-10-04, Xcode 27.0)

- 시뮬레이터 Debug 빌드, 기기용 Release 빌드(서명 없이 `CODE_SIGNING_ALLOWED=NO`), Archive(서명 없이) 통과.
- `Secrets.xcconfig`가 없으면 Archive가 `KTX_ADMIN_PIN not set ... refusing to archive`로 실패.
- `Signing.xcconfig`의 `KTX_ENTITLEMENTS`/`KTX_BUNDLE_ID`가 빌드 설정에 반영됨(`-showBuildSettings`).
- 실제 서명·업로드·TestFlight는 Apple 계정이 생긴 뒤 이 문서대로 진행하고 결과를 여기에 적는다.
