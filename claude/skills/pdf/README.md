# PDF Skill

**PDF 생성, 수정, 분석** - 여러 PDF 병합, 텍스트 추출, 새 PDF 생성을 자유자재로 합니다.

---

## 🎯 이 스킬이 뭔가요?

PDF 파일을 생성하고, 수정하고, 분석합니다. 여러 PDF를 합치거나, 페이지를 회전하거나, 텍스트를 추출하고, 새로운 PDF를 생성할 수 있습니다.

마치 PDF 전문가처럼, 메타데이터부터 폼(form) 작성까지 모든 것을 다룹니다.

---

## 🔄 어떻게 작동하나요?

### 3가지 주요 워크플로우

```text
1. PDF 생성 → 2. PDF 수정 → 3. PDF 분석
```text

#### 1. PDF 생성 (Creating PDFs)

**라이브러리**: reportlab (Python)

```python
from reportlab.pdfgen import canvas

# 새 PDF 생성
c = canvas.Canvas("output.pdf")
c.drawString(100, 750, "Hello World!")
c.save()
```

**지원**:

- 텍스트, 이미지, 테이블

- 다중 페이지

- 메타데이터 (제목, 저자 등)

- 형식 제어

#### 2. PDF 수정 (Modifying PDFs)

**라이브러리**: pypdf (Python)

```python
from pypdf import PdfReader, PdfWriter

# PDF 병합
writer = PdfWriter()
for pdf_file in ["doc1.pdf", "doc2.pdf"]:
    reader = PdfReader(pdf_file)
    for page in reader.pages:
        writer.add_page(page)

with open("merged.pdf", "wb") as output:
    writer.write(output)
```text

**지원**:

- 병합, 분할

- 페이지 회전

- 메타데이터 수정

- 암호화/해제

- 워터마크

#### 3. PDF 분석 (Analyzing PDFs)

**라이브러리**: pdfplumber (Python)

```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        tables = page.extract_tables()
```

**지원**:

- 텍스트 추출 (OCR 가능)

- 테이블 추출

- 메타데이터 읽기

- 레이아웃 보존

---

## 📊 Output (생산물)

### 완성된 PDF

```text
┌────────────────────────────────┐
│  Page 1                        │
│  [텍스트, 이미지, 테이블]      │
│                                │
│  Page 2                        │
│  [계속...]                     │
│                                │
│  [메타데이터 포함]             │
│  [암호 보호 선택적]            │
└────────────────────────────────┘
```text

**특징**:

- 완벽한 형식

- 다운로드 가능

- 인쇄 가능

- 모든 평면에서 호환

---

## 💡 실제 사용 예시

### 예시 1: 여러 PDF 병합

#### 요청

> "3개의 월간 보고서 PDF를 하나로 합쳐줄 수 있어?
> 분기 보고서 형태로."

#### 결과

```

원본:

- Jan_Report.pdf (10 페이지)

- Feb_Report.pdf (12 페이지)

- Mar_Report.pdf (8 페이지)

결과:

- Q1_Report.pdf (30 페이지)

  - 메타데이터 업데이트

  - 페이지 번호 추가

  - 목차 생성 (선택적)

```text

### 예시 2: 스캔된 문서에서 텍스트 추출

#### 요청

> "스캔된 계약서에서 텍스트를 모두 추출해줄 수 있어?
> OCR로."

#### 결과

```

원본: scanned_contract.pdf (스캔 이미지)

추출:
Contract Agreement
This agreement is entered into on [date]...
[모든 텍스트 추출됨]

저장: contract_extracted.txt

```text

### 예시 3: 새 PDF 보고서 생성

#### 요청

> "매출 분석 보고서 PDF를 만들어줄래?
> 표, 차트, 서명란 포함."

#### 결과

```

- 제목 페이지

- 실행 요약 (Executive Summary)

- 데이터 분석 표

- 차트 (이미지로)

- 권장사항

- 서명 라인

```text

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **PDF 생성** | reportlab으로 새 PDF 작성 |
| **병합/분할** | 다중 PDF 조작 |
| **페이지 회전** | 모든 방향 지원 |
| **텍스트 추출** | 일반 텍스트 및 OCR |
| **테이블 추출** | 구조화된 데이터 추출 |
| **메타데이터** | 제목, 저자, 주제 관리 |
| **암호 보호** | 문서 보안 |
| **워터마크** | 문서에 워터마크 추가 |
| **이미지 처리** | PDF에 이미지 삽입 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"이 여러 PDF를 합쳐줄 수 있어?"
```

또는

```text
"스캔된 문서에서 텍스트를 추출해줄래?"
```text

또는

```text
"분기 보고서 PDF를 만들어줄 수 있어?
[데이터]를 기반으로."
```

### 기대할 수 있는 것

1. **빠른 처리**: 대량 PDF도 빠르게 처리
2. **정확성**: 메타데이터, 형식 완벽 보존
3. **유연성**: 단순 합치기부터 복잡한 생성까지
4. **확장성**: 이미지, 테이블, 폼 모두 가능

---

## 🛠️ 기술 스택

**PDF 생성**: reportlab

- Canvas API (저수준)

- Platypus (고수준, 페이지 자동 관리)

**PDF 수정**: pypdf

- 병합, 분할, 회전

- 메타데이터 조작

**PDF 분석**: pdfplumber

- 텍스트 추출

- 테이블 감지 및 추출

- 레이아웃 분석

**OCR**: pytesseract (선택적)

- 스캔된 이미지 텍스트 인식

---

## 📚 스킬의 핵심 철학

> **"PDF는 최종 형식이다"**

- 한 번 생성하면 형식이 고정됨 (장점)

- 정확성과 일관성이 중요

- 모든 문서가 올바르게 렌더링되어야 함

- 메타데이터도 관리 대상

---

## ❓ FAQ

**Q: 스캔된 PDF에서 텍스트가 추출 안 될 때는?**

A: OCR 사용. pytesseract로 이미지 텍스트 인식 가능.

**Q: 정말 큰 PDF도 병합 가능한가요?**

A: 네, 하지만 메모리에 따라 시간이 걸릴 수 있음. 배치로 나누면 해결.

**Q: PDF에 이미지를 넣을 수 있나요?**

A: 네! JPG, PNG 모두 지원.

**Q: 암호 보호 PDF는?**

A: 암호 해제 후 처리 가능. (유저 패스워드 필요)

**Q: 메타데이터도 수정 가능한가요?**

A: 네! 제목, 저자, 주제, 키워드 모두 가능.

---

## 📖 더 알고 싶으면

- **SKILL.md**: PDF 처리 완전 가이드

- **reference.md**: 심화 기술 및 예시

- **forms.md**: PDF 폼 작성 가이드

---

**이 스킬의 목표**: PDF를 자유자재로 생성, 수정, 분석하여 문서 작업을 자동화하는 것입니다. 📄✨
