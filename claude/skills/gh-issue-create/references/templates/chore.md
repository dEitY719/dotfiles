# chore — 본문 템플릿

빌드·CI·도구·deps·스타일 변경 이슈에 사용한다. conventional commit
의 `build`, `ci`, `style`, `revert` 도 본 템플릿으로 흡수한다 (사용
빈도가 높아지면 별도 분리).

## 타이틀

```
chore[(<scope>)]: <한 줄 요약>
```

예) `chore(tox): mdlint envlist 비활성화`

## 본문 골격

```markdown
## TL;DR
<1~3줄 — 어떤 인프라/도구 변경인가>

## 변경 내용
<설정·스크립트·deps·workflow 변경>

## 동기
<왜 지금 — 외부 도구 업데이트, CI 안정성, 보안 패치 등>

## 영향 범위
<로컬 워크플로·CI·팀원에게 가시적인 변화. 마이그레이션 단계 필요
시 명시>

## References
- 관련 파일·도구 docs·이슈/PR
```

## 작성 노트

- 제품 동작 변경이 섞이면 feat / fix / refactor 다. 본 템플릿은
  레포 운영 인프라에만 사용.
- deps 업데이트는 changelog 링크와 breaking change 여부를
  References 에 첨부.
