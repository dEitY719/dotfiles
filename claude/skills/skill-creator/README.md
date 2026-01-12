# Skill Creator

**새로운 스킬 만들기** - 커스텀 스킬을 정의하고 구조화하여 Claude의 능력을 확장합니다.

---

## 🎯 이 스킬이 뭔가요?

Claude의 Claude의 새로운 기능을 만듭니다. PDF 처리, 이미지 편집, 데이터 분석 등 **특화된 도메인**에 대한 전문 지식과 워크플로우를
구성하여 스킬로 패키징합니다.

마치 전문 분야를 Claude에 가르치는 것처럼, 지식, 도구, 리소스를 체계적으로 정리합니다.

---

## 🔄 어떻게 작동하나요?

### 6단계 프로세스

````text
1. 이해 → 2. 계획 → 3. 초기화 → 4. 구현 → 5. 패키징 → 6. 반복
```text

#### 1단계: 이해 (Understanding)

**목표**: 스킬이 정확히 무엇인지 명확히 하기

질문:

- 이 스킬은 뭐 하는 건가요?

- 어떤 상황에 사용하나요?

- 구체적인 사용 예시는?

- 어떤 도구/리소스가 필요?

**결과**: 명확한 스킬 정의

#### 2단계: 계획 (Planning)

**목표**: 스킬의 내용 계획

식별:

- **Scripts**: 반복되는 코드 저장

- **References**: 참고 문서, 가이드

- **Assets**: 템플릿, 폰트, 이미지 등

**예시**:
````

pdf-editor/
├── scripts/
│ ├── merge_pdfs.py
│ └── rotate_pdf.py
├── references/
│ ├── api_guide.md
│ └── best_practices.md
└── assets/
└── templates/

````text

#### 3단계: 초기화 (Initialization)

**도구**: `init_skill.py` 스크립트

```bash
python scripts/init_skill.py pdf-editor --path ./skills
````

**결과**:

- 디렉토리 생성

- SKILL.md 템플릿

- 예시 파일 생성

#### 4단계: 구현 (Implementation)

**작업**:

1. **Scripts 작성**: 재사용 가능한 코드
2. **References 작성**: 가이드와 문서
3. **SKILL.md 작성**: 메인 스킬 가이드
4. **Assets 추가**: 필요한 리소스

**SKILL.md 구조**:

````yaml
---
name: skill-name
description: 스킬이 뭐 하는지, 언제 쓰는지
---

# 스킬 이름

## 개요
스킬에 대한 설명...

## 워크플로우
단계별 가이드...

## 참고 자료
[references/guide.md]: 심화 내용
```text

#### 5단계: 패키징 (Packaging)

**도구**: `package_skill.py` 스크립트

```bash
python scripts/package_skill.py ./skills/pdf-editor
````

**결과**: `.skill` 파일 (배포 가능)

#### 6단계: 반복 (Iteration)

**피드백 루프**:

1. 실제 사용
2. 부족한 부분 식별
3. SKILL.md/Scripts 개선
4. 재패키징

---

## 📊 Output (생산물)

### 완성된 스킬

````text
skill-name/
├── SKILL.md ✨ (메인 가이드)
│   ├── Frontmatter (name, description)
│   └── 워크플로우 및 가이드
│
├── scripts/ 📄 (재사용 가능 코드)
│   ├── tool_a.py
│   └── tool_b.js
│
├── references/ 📚 (참고 문서)
│   ├── advanced_guide.md
│   └── api_reference.md
│
└── assets/ 🎨 (리소스)
    ├── templates/
    └── icons/

↓ 패키징
skill-name.skill (배포 가능 파일)
```text

**특징**:

- 자체 완결적 (self-contained)

- 재사용 가능

- 잘 문서화됨

- 배포 가능

---

## 💡 실제 사용 예시

### 예시: 이미지 편집 스킬

#### 요청

> "이미지를 자르고, 회전하고, 필터 적용할 수 있는 스킬을 만들어줄 수 있어?"

#### 1단계: 이해

````

사용 예:

- "이 이미지 중앙 부분만 자르고 싶어"

- "사진을 45도 회전해줄래?"

- "이미지에 그레이스케일 필터 적용"

```text

#### 2단계: 계획

```

Scripts:

- crop_image.py

- rotate_image.py

- apply_filters.py

References:

- image_formats_guide.md

- filter_options.md

Assets:

- example_images/

````text

#### 3단계-5단계: 구현 및 패키징

완성된 스킬이 image-editor.skill 파일로 배포됨.

#### 6단계: 반복

사용 중에 "워터마크 추가 기능도 추가해줄 수 있어?" 하면 추가.

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **자체 완결** | 스킬 혼자 작동 가능 |
| **재사용 가능** | Scripts로 반복 작업 자동화 |
| **문서화** | SKILL.md와 references로 명확함 |
| **배포 가능** | .skill 파일로 배포 |
| **점진적 개선** | 반복적으로 개선 가능 |
| **커뮤니티 공유** | 다른 사람도 사용 가능 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"[도메인]을 위한 스킬을 만들어줄 수 있어?
[기능들]이 포함되어야 해."
````

또는

````text
"새로운 스킬을 정의하고 싶어.
[사용 사례들]을 처리할 수 있어야 해."
```text

### 예상 시간

- **이해**: 10-15분

- **계획**: 15-20분

- **구현**: 30-60분 (복잡도에 따라)

- **패키징**: 5분

---

## 🛠️ 기술 스택

**스킬 작성**:

- Markdown (SKILL.md)

- Python/JavaScript (Scripts)

- YAML (Frontmatter)

**패키징 및 관리**:

- init_skill.py (초기화)

- package_skill.py (패키징)

**배포**:

- .skill 파일 (ZIP 기반)

---

## 📚 스킬의 핵심 철학

> **"지식의 모듈화"**

- 전문성을 체계적으로 정리

- 다른 Claude 인스턴스도 사용 가능

- 프롬프트 엔지니어링 > 스킬 개발

- 400-500줄 SKILL.md가 최적

---

## ❓ FAQ

**Q: 정말 새 스킬을 만들 수 있나요?**

A: 네! 6단계 프로세스를 따르면 전문적인 스킬 완성.

**Q: 스킬에는 뭐가 들어가나요?**

A: SKILL.md (메인), Scripts, References, Assets.

**Q: 누가 사용할 수 있나요?**

A: 배포된 .skill 파일이면 누구나 로드 가능.

**Q: 얼마나 복잡할 수 있나요?**

A: 간단한 것부터 매우 복잡한 것까지, 자유도가 높음.

**Q: 기존 스킬을 개선할 수 있나요?**

A: 네! 기존 스킬을 로드 후 단계 4부터 시작.

---

## 📖 더 알고 싶으면

- **SKILL.md**: Skill Creator 전체 가이드

- **examples/**: 완성된 스킬 예시들

- **templates/**: SKILL.md 템플릿

---

**이 스킬의 목표**: Claude의 능력을 새로운 도메인으로 확장하는 전문적이고 재사용 가능한 스킬을 만드는 것입니다. 🚀✨
````
