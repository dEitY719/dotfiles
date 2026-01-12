# XLSX Skill

**Excel 생성, 수정, 분석** - 재무 모델, 데이터 분석, 보고서 스프레드시트를 완벽하게 만듭니다.

---

## 🎯 이 스킬이 뭔가요?

Excel 파일(`.xlsx`, `.csv` 등)을 생성하고, 수정하고,
분석합니다. **공식(formulas)**으로 동적인 스프레드시트를
만들고, 재무 모델부터 데이터 분석까지 모든 것을
처리합니다.

마치 재무 분석가가 모델을 구축하듯, Excel의 강력함을 모두 활용합니다.

---

## 🔄 어떻게 작동하나요?

### 3가지 주요 워크플로우

```text
1. 새 스프레드시트 생성 → 2. 스프레드시트 수정 → 3. 데이터 분석
```text

#### 1. 새 스프레드시트 생성

**도구**: openpyxl (Python)

```python
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
sheet = wb.active

# 데이터 입력
sheet['A1'] = 'Revenue'
sheet['B1'] = 1000000

# 공식 추가 (Excel이 계산)
sheet['B2'] = '=B1*0.1'  # 10% 마진

# 형식 적용
sheet['A1'].font = Font(bold=True, color='FF0000')
sheet['A1'].fill = PatternFill(start_color='FFFF00')

wb.save('model.xlsx')
```

**중요**: 계산 값이 아니라 **공식(formulas)** 입력!

#### 2. 스프레드시트 수정

```python
from openpyxl import load_workbook

wb = load_workbook('existing.xlsx')
sheet = wb.active

# 셀 수정
sheet['A5'] = 'New Value'

# 행/열 추가
sheet.insert_rows(3)
sheet.delete_cols(5)

wb.save('modified.xlsx')
```text

#### 3. 데이터 분석

**도구**: pandas (Python)

```python
import pandas as pd

# Excel 읽기
df = pd.read_excel('data.xlsx')

# 분석
print(df.describe())
print(df['Revenue'].sum())

# 새 파일로 저장
df.to_excel('analysis.xlsx', index=False)
```

---

## 📊 Output (생산물)

### 완성된 스프레드시트

```text
┌────────────────────────────────┐
│  FY2024 Financial Model        │
│                                │
│  Revenue (Blue text - input)   │

│  $ 1,000,000                   │
│                                │
│  COGS (Black text - formula)   │

│  = Revenue * 0.6               │
│  = $ 600,000                   │
│                                │
│  Gross Profit (Green - link)   │

│  = Revenue - COGS              │

│  = $ 400,000                   │
│                                │
│  [차트, 테이블, 메타데이터]    │
│  [완벽한 형식과 색상]          │
└────────────────────────────────┘
```text

**특징**:

- 공식으로 동적 계산

- 완벽한 형식 (색상, 폰트, 숫자 형식)

- 메타데이터 포함

- 재사용 가능

---

## 💡 실제 사용 예시

### 예시 1: 재무 모델

#### 요청

> "FY2024-2026의 3년 재무 모델을 만들어줄 수 있어?
> 매출, COGS, 마진, 세금까지."

#### 프로세스

1. **입력 (Blue text)**:
   - Revenue: $1M, 10% 성장

   - COGS margin: 60%

   - 세율: 25%

2. **계산 (Black text - formulas)**:

```

   COGS = Revenue * 0.6
   Gross Profit = Revenue - COGS

   Operating Expense = Revenue * 0.15
   EBITDA = Gross Profit - OpEx

   Tax = EBITDA * 0.25
   Net Income = EBITDA - Tax

```text

3. **결과**:
```

   3개 연도, 완벽한 형식

   Year 1   Year 2   Year 3
   $1.0M    $1.1M    $1.2M    (Revenue - Blue)

   $0.6M    $0.66M   $0.73M   (COGS - Black formula)

   $0.4M    $0.44M   $0.48M   (Gross Profit)
   ...모든 공식으로 계산...

```text

### 예시 2: 대시보드 스프레드시트

#### 요청

> "분기 판매 대시보드를 만들어줄 수 있어?
> 지역별 매출, 전월 대비 성장률, 차트."

#### 결과

```

Sheet 1 - Data:

Region      Q1      Q2      Q3      YTD
North       $100K   $110K   $120K   $330K  (합계 공식)
South       $80K    $85K    $90K    $255K
East        $120K   $130K   $140K   $390K
West        $90K    $95K    $100K   $285K

Total       $390K   $420K   $450K   $1.26M (합계)
Growth              7.7%    7.1%    (공식으로 계산)

Sheet 2 - Charts:

[합계 차트]
[지역별 비교 차트]
[성장률 트렌드]

```text

### 예시 3: 데이터 분석

#### 요청

> "고객 데이터 (CSV)를 분석해줄 수 있어?
> 세그먼트별 통계, 평균 주문액, 리스트 만들어줄래?"

#### 프로세스

1. CSV 로드 (pandas)
2. 세그먼트별 분석
3. 통계 계산 (합계, 평균, 중앙값)
4. 결과를 Excel로 저장

#### 결과

```

customers_analysis.xlsx

Sheet 1 - Summary:

Segment     Count   Avg Order   Total Revenue
Premium     150     $2,500      $375,000
Standard    1,200   $500        $600,000
Economy     5,000   $100        $500,000

Sheet 2 - Detail:

[모든 고객 데이터 정렬/필터링]

Sheet 3 - Charts:

[세그먼트별 매출 파이 차트]
[평균 주문액 비교]

```text

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **공식 기반** | 하드코딩이 아닌 Excel 공식 사용 |
| **다중 시트** | 한 파일에 여러 시트 |
| **형식 제어** | 색상, 폰트, 숫자 형식 |
| **조건부 형식** | 값에 따른 자동 색상 |
| **차트** | 판매 시각화 (기본 제공) |
| **테이블** | 정렬/필터링 가능한 테이블 |
| **메타데이터** | 제목, 저자, 주제 관리 |
| **대량 데이터** | pandas로 효율적 처리 |
| **공식 검증** | recalc.py로 모든 공식 검증 |
| **에러 감지** | #REF!, #DIV/0! 등 에러 식별 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"[설명]의 스프레드시트를 만들어줄 수 있어?
[요구사항들]을 포함해서."
```

예시들:

```text
"재무 모델을 만들어줄 수 있어? 3년 전망으로."

"판매 대시보드. 지역별, 월별 분석."

"고객 데이터 분석. 세그먼트별 통계."
```text

### 기대할 수 있는 것

1. **동적 계산**: 공식으로 자동 계산
2. **완벽한 형식**: 색상, 폰트, 숫자 형식
3. **검증됨**: recalc.py로 모든 공식 검증 (에러 없음)
4. **확장 가능**: 데이터 변경 시 자동 계산
5. **바로 사용**: 인쇄 가능한 수준의 품질

---

## 🛠️ 기술 스택

**스프레드시트 생성**:

- openpyxl (Python) - 공식, 형식, 스타일

**데이터 분석**:

- pandas - 데이터 조작, 통계

- numpy - 수치 계산 (선택적)

**공식 검증**:

- recalc.py - LibreOffice로 공식 계산

**변환**:

- pandas - CSV/Excel 상호 변환

---

## 📚 스킬의 핵심 철학

> **"데이터는 살아있어야 한다"**

- 고정값이 아닌 공식 사용

- 데이터 변경 시 자동 계산

- 형식은 가독성을 보장

- 색상 코딩 (파란색=입력, 검정색=공식)으로 투명성

---

## ❓ FAQ

**Q: 정말 모든 공식이 정확한가요?**

A: 네! recalc.py로 모든 공식을 LibreOffice에서 계산하여 검증합니다. #DIV/0! 같은 에러도 캡처.

**Q: 데이터가 바뀌면?**

A: 공식이 있으면 자동으로 재계산됩니다. 입력 셀만 바꾸면 끝!

**Q: 대용량 데이터도 가능한가요?**

A: 네! pandas로 10만 행 이상도 처리 가능.

**Q: 차트를 추가할 수 있나요?**

A: 기본적인 차트는 자동 생성. 복잡한 차트도 openpyxl로 가능.

**Q: 다른 시스템과 호환되나요?**

A: Excel, Google Sheets, LibreOffice 모두 호환.

---

## 📖 더 알고 싶으면

- **SKILL.md**: Excel 처리 완전 가이드

- **COLOR_STANDARDS.md**: 재무 모델 색상 기준

- **NUMBER_FORMATTING.md**: 숫자 형식 상세 가이드

- **FORMULA_EXAMPLES.md**: 일반적인 공식 패턴

---

**이 스킬의 목표**: Excel의 강력함을 완전히 활용하여 동적이고 검증된 스프레드시트를 만드는 것입니다. 📊✨
