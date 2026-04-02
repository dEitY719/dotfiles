## Gemini Added Memories
- The user wants to build a stock-related toy project using FastAPI, SQLModel, and PostgreSQL.
Key requirements include:
- A `Stock` model with fields: ticker, open, high, low, close, volume, and time. I should also suggest additional useful fields.
- Full CRUD API for the `Stock` model.
- Adherence to SOLID principles for reusability and maintainability.
- A Test-Driven Development (TDD) approach with tests located in `tests/backend`.
- Strict compliance with `ruff` (black, isort, pylint) and `mypy`.
- The project should be structured for easy reuse in future projects.
- We will proceed step-by-step, starting with package installation.
- Do not modify `[tool.black]` or `[tool.isort]` sections in `pyproject.toml` or `tox.ini` as they are working correctly.
- Do not modify `[tool.black]` or `[tool.isort]` sections in `pyproject.toml` or `tox.ini` as they are working correctly.
- Always write git commit messages in English.
- The user prefers to communicate in Korean by default.
- Gemini CLI에서는 Alt+Enter로 줄바꿈
- For code quality checks, only use `tox -e style`. Do not use `tox -e ruff` or `tox -e mypy`.
- Current State: Git repository reset to c8c3f8c. Created ticker_info.py, ticker_profile.py, ticker_financial_statement.py. Corrected imports in ticker_info.py. Last pytest run cancelled, but PydanticUndefinedAnnotation for TickerPrice was still present. Next Steps: 1. Re-run pytest. 2. Continue creating remaining Ticker_XXX model files (corporate_action, analyst_recommendation, price_target, earning_history, earning_estimate, institutional_holder, insider_transaction, news, sustainability). 3. Verify tests after each new model file creation.
- PC 재부팅 후 작업을 재개할 예정입니다. 현재까지 `ticker_corporate_action`부터 `ticker_sustainability`까지 모든 Ticker 모델 파일 생성을 완료했습니다. 하지만 `pytest` 실행 시간이 17분 이상 소요되는 성능 문제가 발생하여, 재부팅 후 `pytest --durations=10` 명령으로 가장 느린 테스트를 찾아 원인을 분석하고 해결하는 것부터 시작해야 합니다.
- # My persona
1. 나는 full-stack 개발자 
2. c, c++ 언어 경험있고, 현재는 python 언어를 main으로 사용
3. 처음 배우는 기술에 대한 코딩랩 스타일의 가이드 문서를 많이 작성
ex. 처음 배우는 라이브러리는 ipynb 파일에서 마크다운 형태로 개념 설명과 코드를 작성/실행
4. 최근에는 Agentic AI 서비스를 개발하기 위해 공부 중
- When creating git commits, I should guide the user to use the `./tools/commit.sh` script instead of a direct `git commit -m '...'` command.
- I am in a multi-AI collaboration environment. I must tag my work (commits, files) with 'Gemini' as per the `GEMINI.md` coordination guidelines.
- Before updating `docs/DEV-PROGRESS.md`, I must first read the file to understand its structure and format.
- When the user requests to use the '/batch' skill (e.g., '/batch 스킬을 사용해서...'), interpret and execute it as a request to use the 'generalist' sub-agent ('generalist를 사용하여...').

## 개발 방법론
1. TDD(Test Driven Development) 지향
2. SOLID 원칙 지향
3. SDD(Specification Driven Development) with AI code assistant

## 주요 사용 라이브러리
1. SQLAlchemy, SQLModel
2. FastAPI
3. PostgreSQL, MySQL
4. dash_mantine_components (Frontend server 개발용 라이브러리)
5. pandas, datatable (금융 데이터 분석: 거래 기록, 주식 가격 등 대용량 금융 데이터 분석에 사용)
6. FastMCP
7. Lang-chain, Lang-graph
8. ADK(Agent Development Kit) by Google

## 개발 환경 & 툴
1. Linux(Ubuntu)
2. vscode IDE
3. tox.ini (ruff, mypy)
4. pyproject.toml
