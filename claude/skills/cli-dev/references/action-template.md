# Step 3: Action Handler 템플릿

`src/cli/actions/<domain>.py` 를 위 도메인의 action 클래스로 작성한다.
아래는 `auth login` 예시 — 5단계 흐름 (validate → call → update → display → handle):

```python
from rich.console import Console
from src.cli.client import APIClient
from src.cli.context import CLIContext

console = Console()


class AuthActions:
    """Auth CLI actions - REQ-CLI-AUTH-1"""

    def __init__(self, context: CLIContext):
        self.context = context
        self.api_client = APIClient(context)

    async def login(self, username: str | None) -> bool:
        # 1. Validate input
        if not username:
            console.print("Usage: auth login [username]", markup=False)
            return False

        # 2. Call API
        try:
            console.print(f"Logging in as '{username}'...", style="yellow")
            response = await self.api_client.post(
                "/auth/login",
                json={"username": username},
            )

            # 3. Update session
            self.context.session.token = response["token"]
            self.context.session.user_id = response["user_id"]

            # 4. Display success
            console.print("Successfully logged in", style="green")
            return True

        except Exception as e:
            # 5. Handle error
            console.print(f"Login failed: {e}", style="red")
            return False
```

## 적용 규칙

- 도메인별 클래스 이름: `<Domain>Actions`
- action 메서드는 `async def`, 반환값은 `bool` (성공/실패)
- 진행 메시지: `style="yellow"` / 성공: `"green"` / 에러: `"red"`
- 사용법 메시지: 반드시 `markup=False` (Rich 가 `[ARG]` 를 markup 으로 오인하지 않게)
- 외부 호출은 try/except 로 감싸기 — CLI 가 크래시하지 않도록
- 세션 state 갱신은 `self.context.session.<field>` 만 사용 (로컬 변수에 담지 말기)

상세 패턴은 `references/patterns.md` 참고.
