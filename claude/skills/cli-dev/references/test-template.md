# Step 2: pytest TDD 템플릿

새 도메인의 action 을 구현하기 전에 먼저 `tests/cli/test_<domain>_actions.py`
를 작성한다. 아래는 `auth` 도메인 예시 — happy path, missing-arg, API-error
세 가지 경우를 모두 커버.

```python
import pytest
from unittest.mock import AsyncMock, patch
from src.cli.actions.auth import AuthActions
from src.cli.context import CLIContext


class TestAuthActions:
    """Tests for REQ-CLI-AUTH-1"""

    @pytest.fixture
    def context(self):
        return CLIContext()

    @pytest.fixture
    def actions(self, context):
        return AuthActions(context)

    @pytest.mark.asyncio
    async def test_login_success(self, actions, context):
        """TC-1: Successful login stores JWT"""
        with patch.object(
            actions.api_client, "post",
            new_callable=AsyncMock,
            return_value={"token": "jwt...", "user_id": "123"},
        ):
            result = await actions.login("user")
            assert result is True
            assert context.session.token == "jwt..."

    @pytest.mark.asyncio
    async def test_login_missing_arg(self, actions):
        """TC-2: Missing username shows usage"""
        result = await actions.login(None)
        assert result is False

    @pytest.mark.asyncio
    async def test_login_api_error(self, actions):
        """TC-3: API error handled gracefully"""
        with patch.object(
            actions.api_client, "post",
            new_callable=AsyncMock,
            side_effect=Exception("Network error"),
        ):
            result = await actions.login("user")
            assert result is False
```

## 적용 규칙

- 도메인별 클래스 이름: `Test<Domain>Actions`
- 테스트 함수 이름: `test_<action>_<scenario>` (예: `test_login_success`)
- 시나리오 최소 3종: success / missing-arg or invalid-input / api-error
- `AsyncMock` 으로 `api_client.post` 등 비동기 메서드 mock
- 세션 state 검증: `context.session.<field>` 직접 단언
