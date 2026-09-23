# 외부 연결 안내

## Google Drive (선택 기능)

로컬 저장을 기본으로 하고 Google Drive `appDataFolder`에 변경 이력과 이미지를 복제합니다. 일반 Drive 폴더와 별도인 앱 전용 영역입니다. 동일한 Google 계정과 같은 Google Cloud 프로젝트의 OAuth 구성을 두 기기에 사용하세요.

1. Google Cloud 프로젝트에서 Drive API를 활성화하고 OAuth 동의 화면을 구성합니다. 개인용 테스트 구성이라면 사용할 계정을 테스트 사용자로 등록합니다.
2. 데스크톱 OAuth 클라이언트를 만들고 설정에 클라이언트 ID와 시크릿을 입력합니다. Windows는 외부 브라우저 + PKCE + 로컬 루프백 콜백으로 연결합니다.
3. Android용 OAuth 클라이언트는 패키지 `studio.storyloom.storyloom`과 설치 APK의 서명 인증서 SHA-1을 등록합니다. 같은 프로젝트에서 웹 클라이언트를 만들고 그 ID를 앱의 Android 서버 클라이언트 ID에 넣습니다. 개발 APK의 서명이 바뀌면 등록도 갱신해야 합니다.
4. 각 기기의 Google 연결 버튼에서 같은 계정을 허용한 후 지금 동기화를 실행합니다.

앱 시작과 실행 중 1분 주기로 동기화합니다. 종료된 앱의 백그라운드 동기화는 지원하지 않습니다. 네트워크 오류가 나면 로컬 데이터는 유지하고 다음 주기에 재시도합니다. 앱에는 Google 프로젝트/클라이언트가 사전 구성되어 있지 않습니다.

### 동기화 범위

- 포함: 캐릭터, 폴더, 스토리, 노트, 태그, 대표 이미지 지정, 이미지 원본, 대화의 텍스트 기록, 삭제 표시.
- 제외: API 키·토큰, 기기별 설정, 별도 임시버전 파일.
- 기존 파일을 덮어쓰지 않는 고유 수정 이력으로 교환합니다. 양쪽에서 같은 문서를 수정하면 설정의 충돌 목록에서 선택합니다. 원래 이력은 남습니다.
- 파일당 64MB 제한. 원본 전체를 내려받습니다. 선택 다운로드, 이미지 전용 CDN, 장기간 이력 압축은 아직 없습니다.
- 계정 전환 시 다른 계정으로 현재 로컬 데이터가 올라갈 수 있으므로 별도 데이터 디렉터리를 사용하세요.
- Google/Notion의 실제 계정 인증 및 PC↔Android 실기기 왕복은 이 저장소의 자동 테스트로 검증하지 않습니다. 배포 전 실제 계정에서 확인해야 합니다.

## Notion

Notion에서 읽기 권한의 연결(Integration)을 만들고 가져올 페이지를 그 연결에 공유합니다. 설정의 Notion 토큰 입력 → 페이지 목록 → 가져올 페이지 선택 → 검토 → 후보의 이름/분류/포함 여부 확인 → 가져오기 순서입니다.

공유된 선택 페이지의 하위 블록을 재귀적으로 읽습니다. 제목과 내용의 키워드로 페이지 단위 분류를 제안하며, AI가 정확한 캐릭터를 확정하는 기능은 아닙니다. 한 페이지의 여러 캐릭터를 개별 항목으로 자동 분리하지는 않습니다. 최종 저장 전에 분류를 직접 검토합니다. 이미 가져온 동일 페이지는 중복 생성을 건너뜁니다. 원본 Notion 페이지는 변경하지 않습니다.

가져오기는 텍스트 중심입니다. 이미지·파일은 원본 확인 안내로 남기고, 원본의 모든 서식·데이터베이스 관계를 재현하지 않습니다. 가져온 글은 앱의 서식 편집기로 편집할 수 있습니다.

## AI

설정에서 HTTPS API 주소, 모델 이름, API 키를 입력합니다. OpenAI 호환 `/chat/completions` 인터페이스가 필요합니다. 로컬 서버에는 루프백 HTTP를 허용합니다. 선택한 참조 문서와 첨부 이미지는 사용자가 전송 버튼을 누를 때 해당 API 제공자에게 전송됩니다.

이미지 첨부는 PNG/JPEG/WEBP/GIF, 최대 4장·장당 5MB이며 지원 모델을 직접 선택해야 합니다. 이미지는 해당 요청에만 넣고 대화 이력에는 이미지 바이트를 저장하지 않습니다. 다음 질문에도 이미지가 필요하면 다시 첨부하세요.

## 공식 자료

- [Drive 앱 전용 데이터](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Google 데스크톱/모바일 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google Sign-In Android 설정](https://pub.dev/packages/google_sign_in_android)
- [Notion 연결](https://developers.notion.com/docs/create-a-notion-integration)
- [Notion 하위 블록 읽기](https://developers.notion.com/reference/get-blocks-children)
