# Ateliai 0.8.3 verification — 2026-09-23

- Windows release / Inno installer compiled: Ateliai-Setup-0.8.3-x64.exe. Native isolated startup 1,635ms, duplicate exits 0, embedded icon extracted and visually checked. SHA256: 7D93D9474306249ABB3D80113BC1F70FF53700051A9A3CEDEDAD65284D7D044B.
- Flutter analyze: no issues.
- Flutter test --dart-define=CAPTURE=true: 53 tests passed.
- Fixed Korean sentence: 5 continuous repetitions with autosave enabled and 5 disabled (10 total), 40ms virtual interval between Hangul composition steps. Every intermediate text and completed sentence matched.
- Input occurred after a 35,919-character document. No revision was written while typing. Save occurs after the 2-second idle threshold (or explicit save when disabled), and reopened data matches.
- Drag selection from an unfocused editor activates input and replaces selected text with Korean composition.
- Ordered/bullet marker baselines and checkbox centers verified at 12/24/53.333px with 2.4 line spacing.
- Two-mode AI panel and circular AI control screenshot reviewed.
- Windows/Android icon assets derived from the supplied image. Internal storage identity preserved for existing data and secure API settings.
- Native physical Windows IME was not driven by the widget tests; intermittent real-world typing loss is not claimed conclusively fixed. External issues compared in INPUT-REVIEW-0.8.3.md.

# 0.8.2 verification — 2026-09-23

- Flutter analyze: no issues.
- Full Flutter test suite: 51 tests passed.
- Real Pretendard glyph/caret centers: 7 point sizes × 3 line spacing values, within 0.5 logical px.
- Body drag selection: down/up scrolling continues at the edge and stops on release.
- Continuous input: 240 Korean/English composition updates each in empty and 35,919-character documents, concurrent immediate saves, no parent editor replacement, focus loss, text-input reconnect or editing-state overwrite, final disk/reopen content matches.
- Separate IME-backspace interference reproduced before patch and passes after patch. This is not claimed as the cause of reported continuous typing loss.
- AI button height and send-icon contrast checked, screenshot reviewed.
- User's intermittent physical-keyboard input loss not reproduced; mitigation verified, complete resolution not claimed.
- Installed user application was already running and left untouched; native startup recheck skipped.

# 0.8.1 verification — 2026-09-22

- Flutter analyze: no issues.
- Flutter test --dart-define=CAPTURE=true: 46 tests passed.
- Screenshot review: editor toolbar, AI input inset, Full-only model selection, emoji picker.
- Tests cover cursor paint height, selection bounds, IME composition during immediate saves, clipboard/line breaks, group selection/moves, bounded chat selection scrolling, document privacy and mode reset.
- Windows release and Inno Setup compilation succeeded (0.8.1, 23,620,057 bytes). SHA256: 9B690A9909B21EFEC8A8E03B6D94E6D37A59CD23F6ABCCE8C4BFB176C7C953C8.
- Native startup/single-instance recheck skipped because an existing user Storyloom process was running; it was left untouched.
- No live external AI/NovelAI generation or exhaustive physical IME matrix was tested.

# 0.8.0 검증 — 2026-09-22

- 전체 자동 테스트 38개 통과. 마지막 글꼴 보정 후 UI 테스트 2개 재검증 통과.
- 정적 분석: 오류·경고 없음.
- 세 AI 모드의 시스템 지침·대화 기록·임시 입력·참고 자료 분리, 전송 중 전환 차단, 구역별 복사, 프롬프트 노트 저장 및 재시작 후 기록 보존 확인.
- NovelAI 완성본의 필수 구역 검사와 선택지 문법 감지. 실제 모델의 출력 품질과 NovelAI 이미지 결과는 미검증.
- Windows 릴리스 빌드, Inno Setup x64 설치 파일 생성 완료.
- 격리된 빈 데이터 경로로 네이티브 초기화 확인(이 환경에서 1,742ms). 두 번째 실행은 종료 코드 0, 첫 번째 프로세스 1개 유지. 테스트 프로세스만 종료.
- 기존 사용자 데이터 및 실제 API 키를 사용하지 않음. 외부 AI/Notion/Drive 계정 및 모든 Windows IME 조합의 실사용 검증은 미실시.
- 설치 파일 SHA256: `548B9E99AEB0F9FCF444EBD2D49543C5E3E1D8CCC5542A3950F4FD74AB2A9D5C`
- GitHub 업로드 보류.

---

# 0.7.0 검증 — 2026-09-16

- 정적 분석: 오류·경고 없음.
- 자동 테스트 24개 통과. 입력 검증 범위와 구현 변경은 [0.7 변경사항](RELEASE-0.7.md) 참고.
- 캐릭터 이동 후 폴더 수 갱신, 스토리/노트 독립 표시 및 폴더 삭제 시 별도 문서 보존 확인.
- 샘플 화면: v7-editor.png, v7-colors.png, v7-settings.png 등.
- 실제 Windows IME와 외부 프로그램 전체 조합을 검사한 것은 아닙니다. 입력 테스트는 Windows 동작을 지정한 Flutter 환경에서 수행했습니다.
- Windows x64 설치파일 빌드 성공. 별도 데이터 경로로 네이티브 실행 및 창 종료 메시지에 따른 정상 종료 확인.
- GitHub 업로드 보류.

---

# 0.6.0 검증 — 2026-09-16

- Flutter 3.47.4 / Dart 3.13.3, 정적 분석 오류·경고 없음.
- 자동 테스트 14개 통과.
- 기존 작품→폴더 마이그레이션 반복 실행, 본문 보존.
- 300개 이미지 복사·태그·재시작 후 보존, 원본 비변경.
- 변경된 텍스트만 임시버전 생성, 보관 기간 만료와 복원.
- 동시 수정 및 원격 수정 도중 로컬 편집 충돌 보존, 사용자 선택 후 충돌 해소.
- 모의 Drive 서버 왕복·중복 업로드 방지·기기 설정 제외.
- 모의 Notion 페이지/하위 블록 읽기와 분류.
- AI 이미지 형식 검사와 인라인 전송 데이터 생성, HTTPS/로컬 주소 검증.
- UI: 1440×960 좌우 중앙선, 클릭 다음 16ms 프레임 내 상세 표시, 우클릭 색상 선택, 제목 단축 입력, 1분 저장, 대표 이미지 지정, 이미지 선택 시 드롭 차단, 더블클릭 확대.
- UI: 1000×680, 390×844, 1440×960 및 11개 테마에서 Flutter 레이아웃 예외 없음.
- 샘플 데이터 스크린샷: v6-desktop / editor / colors / gallery / ai / settings / light.

실제 외부 API 호출과 계정 인증, Android 실기기 입력·동기화는 모의 테스트에 포함되지 않습니다. 파일 이력은 계속 누적되므로 수년 단위 대규모 이력의 성능까지 보증하지 않습니다. 이미지 그리드는 지연 생성하고 미리보기 디코딩 크기를 제한합니다. 배경 슬라이더는 조작 종료에만 기록하여 불필요한 저장을 줄였습니다.

---
# 개발 검증 기록

## 0.2.0 — 2026-09-16

- 정적 분석: No issues found
- 자동 테스트: 8개 통과
- 1440×960 창의 중앙선 x=720 확인, 캐릭터 카드 가로=세로 확인
- 선택 전 빈 상세 화면, 선택 시 설정 표시, 전환 시 수정 저장
- Windows 플러그인 채널의 entered/performOperation 이벤트를 이용해 파일 드롭 수신부터 복사·캐릭터 연결까지 검증
- 실제 Flutter drag 제스처로 캐릭터 간 이미지 이동 및 캐릭터의 하위 디렉터리 이동 검증
- 이전 버전 미지정 이미지의 원본/태그 보존과 마이그레이션 반복 실행 검증
- Windows Release 빌드 성공, desktop_drop_plugin.dll의 네이티브 등록 및 설치 번들 포함 확인
- 독립된 설치 ID와 테스트 데이터 폴더를 사용하는 시험 설치: 종료 코드 0
- 실제 Windows 앱에서 새 2분할 UI 표시 확인
- 탐색기 실제 마우스 드롭 종단 간 검증: 컴퓨터 사용 도구의 탐색기 접근 승인 만료로 미완료
- 테스트 화면: v2-desktop-empty.png / v2-desktop-selected.png (샘플 데이터, 앱 기본 제공 데이터 아님)

아래는 이전 버전 검증 이력입니다.

2026-09-15 / Flutter 3.47.4 / Dart 3.13.3

- Flutter analyze: 오류 없음
- 로컬 저장·재시작·삭제 이력, 손상 파일 처리, 300개 테스트 파일 복사, 경로 검증, AI 주소 검증
- 390×844 및 1440×900 화면에서 작품과 캐릭터 생성
- 두 화면의 렌더링은 preview-390.png / preview-1440.png 참고. Flutter 테스트 렌더러에서 캡처한 화면이며 실제 Android 기기 실행 화면은 아님

## 빌드 환경 진단

- Windows 개발자 모드의 심볼릭 링크 지원 필요 (pub get은 패키지 해결 후 이 조건으로 종료)
- Visual Studio C++ 빌드 환경 없음
- Android SDK 없음
- 위 항목 때문에 Windows exe / Android APK 생성 및 기기 실행은 미완료
- API 키, 클라우드 계정 미연결; 실제 AI 응답 및 동기화 검증은 미완료

위 내용은 첫 소스 작성 시점의 기록이다.

## Windows 설치 파일 검증 추가 (2026-09-15)

- Microsoft Visual Studio Build Tools 2022 17.14.40 및 C++/Windows SDK/ATL 설치 완료
- Windows 개발자 모드는 변경하지 않고 작업 폴더 안의 plugin junction으로 빌드
- Flutter Windows release 빌드 성공
- Inno Setup 7.1.0으로 한국어/영어 사용자별 설치 프로그램 생성
- Microsoft VC143 x64 런타임 DLL을 설치 번들에 포함
- 작업 폴더에 시험 설치 성공 (종료 코드 0)
- 실제 설치된 앱의 화면, 작품 생성/저장, 앱 재시작 후 작품 복원 확인
- 테스트는 기본 키 입력으로 진행; 자동화 도구의 한글 문자열 주입이 반영되지 않아 한글 IME 실사용 검증은 미완료
- AI 제공자 연결, 실제 API 키 저장, Android 빌드는 미검증
- 설치 파일은 코드 서명하지 않았음

## 0.3.0 (2026-09-16)
- Pretendard 내장, 우클릭 메뉴, 노트 분리, 이미지 폴더/선택 잠금, AI 사이드 패널 구현
- 자동 테스트 8개 통과, 정적 분석 오류 없음
- 1440×960 및 AI 패널 활성 1000×680, 모바일 390×844 레이아웃 검사
- v3-desktop-selected.png, v3-gallery.png, v3-ai-panel.png는 Flutter 테스트 렌더링
- 이 버전은 실제 API 호출 및 Windows 탐색기 마우스 드래그 미검증


## 0.4.0 (2026-09-16)
- 프레젠테이션 구조 재작성: studio_widgets.dart에 패널/도구 막대/탭/버튼/카드/메뉴 구성요소 분리
- 첫 클릭 후 16ms 테스트 프레임에서 상세 표시 확인, 350ms 더블 클릭 판별은 첫 클릭을 지연시키지 않음
- 패널 폭 드래그 조절, 우클릭 메뉴, 기존 데이터 관련 테스트 포함 8개 통과
- v4-desktop-selected.png, v4-ai-panel.png, v4-context-menu.png로 시각 확인
- Windows release 및 설치 파일 0.4.0 빌드


## 0.5.0 (2026-09-16)
- 상단 캡슐 및 210ms 선택 표시 이동, AI 인접 배치, 메뉴 묶음 중앙 정렬
- 0.4.0 대비 글자 4px 확대와 버튼 조정
- 최초/수정 일시, 5×3 파스텔 색상 선택 및 디스크 재로딩 검증
- 자동 테스트 8개 통과; 정적 분석 오류 없음
- v5-desktop-selected.png, v5-palette.png, v5-ai-panel.png는 테스트 렌더링
- AI: 선택한 저장 글만 참조; 미저장 글 및 이미지 첨부 미지원




2026-09-23 icon-only rebuild: replaced Windows app_icon.ico verbatim with the user-supplied ICO; source/resource SHA256 matched. Windows release and installer rebuilt successfully; installer checksum sidecar verified. Existing test results above are from the preceding code build.
