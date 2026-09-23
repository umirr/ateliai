# AI 모드와 모델별 작성 지침

## 공통

사용자 지정 OpenAI 호환 API로 요청합니다. 일반 대화와 캐릭터 프롬프트의 기록을 분리합니다. 선택된 문서만 전송하고 참조 범위가 다른 과거 메시지는 요청에 넣지 않습니다. 캐릭터 프롬프트는 모델도 같은 이력만 사용합니다. 대표 이미지 전송은 이미지 입력을 지원하는 채팅 모델이 필요합니다.

지침 작성 기능은 0.8.3에서 제거했습니다.

## 캐릭터 프롬프트: Full 전용

선택 캐릭터와 사용자가 입력한 조건을 하나로 취급하고 명시적인 최신 지시를 우선합니다. 기본/캐릭터/제외 프롬프트를 완성본으로 제공합니다. 사용자 요청에 따라 기본 프롬프트에 1girl 같은 인원수 태그를 넣지 않습니다. 개별 캐릭터에는 공식 문법의 girl/boy/other를 사용합니다. 이는 공식 기본 프롬프트의 인원수 태그 권장과 다른 사용자 선택입니다. 제외 영역은 캐릭터의 외형·의상·소품에서 피할 요소로 구성합니다.

| 구분 | V4.5 Full | V5 Full |
|---|---|---|
| 작성 | 간결한 영어 태그와 짧은 관계 설명 | 태그와 관계·배치가 명확한 영어 문장 |
| 길이 기준 | 기본+캐릭터 합계 512 T5 토큰 고려 | 기본 프롬프트 실효 약 1,471 토큰 고려 |
| 품질 자동 추가 | 표준: location, very aesthetic, masterpiece, no text | 표준: very aesthetic, masterpiece, no text / Light: very aesthetic, amazing quality, no text |
| 전용 요소 | V5 전용 태그 배제 | 필요한 경우 complexity, depthness, 투명 배경의 alpha 사용 |
| 그림 속 문자 | 영어 중심, 최대 118자 안내 | 다국어, 최대 750자 안내 |
| 다중 캐릭터 | 요청된 경우 최대 6칸, 5×5 위치 | 요청된 경우 최대 22칸, 자유 위치 |

두 모델 모두 자연어, 중괄호·대괄호 강조 및 숫자::태그:: 가중치와 음수 가중치를 지원합니다. 품질 자동 추가가 켜져 있으면 같은 태그를 중복 작성하지 않습니다. 꺼짐은 다시 강제로 추가하지 않습니다. 토큰 수는 생성 모델에 지시하는 예산이며 앱에서 NovelAI 토크나이저로 강제 검증하지 않습니다. Curated는 옵션과 분기에서 제외했습니다.

## 공식 근거

2026-09-22 확인:

- [모델](https://docs.novelai.net/en/image/models/)
- [태그](https://docs.novelai.net/en/image/tags/)
- [품질 태그](https://docs.novelai.net/en/image/qualitytags/)
- [캐릭터 프롬프트](https://docs.novelai.net/en/image/multiplecharacters/)
- [가중치](https://docs.novelai.net/en/image/strengthening-weakening/)
- [문자 표현](https://docs.novelai.net/en/image/textrendering/)
