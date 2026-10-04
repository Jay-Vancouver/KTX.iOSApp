# 개발 환경 설치 (macOS)

KTX Driver iOS 앱을 빌드하는 Mac 준비 절차. Xcode 화면 작업 없이 `xcodegen` + `xcodebuild`로 빌드한다.

## 확인한 환경 (2026-10-04)

| 항목 | 버전 |
|---|---|
| macOS | 26.6.2 (Apple Silicon, arm64) |
| Xcode | 27.0 (27A266a) |
| iOS SDK / 시뮬레이터 런타임 | iOS 27.0 |
| git | 2.54.0 (Apple Git) |
| python3 | 3.9.6 (시스템, 로컬 수신기용) |
| Homebrew | 7.0.7 |
| XcodeGen | 2.46.0 (Homebrew) |

## 1. Xcode

1. App Store에서 **Xcode** 설치(최신). 용량이 크므로 여유 공간 40GB 이상.
2. 한 번 실행해서 추가 구성요소 설치와 라이선스 동의를 마친다. 터미널로 하려면:
   ```sh
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   ```
3. 확인:
   ```sh
   xcodebuild -version
   xcodebuild -checkFirstLaunchStatus && echo OK
   ```

## 2. xcode-select (명령줄 도구가 Xcode를 가리키게)

```sh
xcode-select -p          # /Applications/Xcode.app/Contents/Developer 이어야 한다
# 다르면:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

> 주의: Homebrew 설치 과정에서 Command Line Tools가 설치되면서 xcode-select가
> `/Library/Developer/CommandLineTools`로 바뀔 수 있다. 그러면 `xcodebuild`가
> "requires Xcode" 오류를 낸다. Homebrew 설치 뒤에 위 `sudo xcode-select -s ...`를 다시 실행한다.
> (임시로는 명령 앞에 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 붙여도 된다.)

## 3. Homebrew

관리자 암호를 묻기 때문에 **터미널 앱에서 직접** 실행한다.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

설치가 끝나면 안내대로 PATH를 추가한다(Apple Silicon):

```sh
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew --version
```

## 4. XcodeGen

```sh
brew install xcodegen
xcodegen --version
```

프로젝트 생성: 저장소 루트에서 `xcodegen generate` → `KTXDriver.xcodeproj` 생성(git에 넣지 않음).
`project.yml`을 고친 뒤에는 다시 생성한다.

## 5. git

Xcode에 포함된 git을 쓴다(`git --version`). 이 저장소의 커밋 작성자는 저장소 로컬 설정:

```sh
git config user.name jay
git config user.email system@ktxtransport.com
```

## 6. 시뮬레이터 런타임

```sh
xcrun simctl list runtimes                     # iOS 런타임이 있어야 한다
xcrun simctl list devices available | grep iPhone
# 런타임이 없으면:
xcodebuild -downloadPlatform iOS
```

## 7. 빌드 확인 (2단계 이후)

```sh
xcodegen generate
xcodebuild -project KTXDriver.xcodeproj -scheme KTXDriver \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

## 8. 비밀 값 (관리자 PIN)

설정 화면에서 서버 주소를 바꿀 때 쓰는 관리자 PIN. Android 판과 같은 PIN을 쓴다.
저장소에는 넣지 않고, 빌드할 때 `tools/embed_admin_pin.sh`가 **SHA-256 해시만** 앱의 Info.plist
(`KTXAdminPinSHA256`)에 넣는다.

저장소 루트에 `Secrets.xcconfig`를 직접 만든다(`.gitignore`에 들어 있어 커밋되지 않는다):

```
KTX_ADMIN_PIN = 여기에PIN
```

또는 빌드할 때 환경변수로: `KTX_ADMIN_PIN=... xcodebuild ...`
(빌드 단계는 환경변수를 로그에 남기지 않도록 설정되어 있다.)

- PIN이 없으면 경고를 내고 `000000`을 쓴다(Android와 같음).
- **Archive(App Store/TestFlight 업로드용)는 PIN이 없으면 실패한다.**
- 확인: 빌드 후 `plutil -p <앱>.app/Info.plist | grep KTXAdminPinSHA256` 값이
  `printf '<PIN>' | shasum -a 256` 결과와 같아야 한다.
