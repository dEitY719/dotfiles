# Global Instructions

**Always write Korean (and other non-ASCII) strings in tool-call parameters as literal UTF-8; never as \uXXXX unicode escapes.**

## 모델 역할 분담: Advisor / Worker

메인 세션(Advisor)은 판단에 집중하고, 열린 구현 작업(open-ended implementation)은
opus 서브에이전트(Worker)에게 Agent 도구(model: "opus")로 위임한다.

**위임 대상** — 여러 파일에 걸친 수정, 새 기능/모듈 구현, 테스트 반복이 필요한 구현.
서로 독립적인 작업은 병렬로 위임한다.

**직접 처리** — 한두 파일의 소규모 수정, 설정/문서 변경 등 위임 오버헤드가 작업보다 큰 일.
skill이 메인 세션의 직접 실행을 명시한 단계(git/gh 명령 등)는 항상 직접 실행한다.

**브리프 기준** — Worker가 재탐색하지 않도록 이미 파악한 컨텍스트를 담는다: 파일 경로,
프로젝트 컨벤션, 알려진 함정, 완료 기준(통과해야 할 테스트). 브리프 1건 = 완료 기준
달성까지 — Worker는 테스트 작성→구현→통과 반복(TDD 루프 포함)을 브리프 안에서 자체 소화한다.

**검증** — Worker의 완료 보고를 그대로 믿지 않는다. Advisor가 diff 확인과 테스트 실행으로
직접 검증한 뒤 승인하고, 실패 시 수정 브리프로 재위임한다(직접 수정은 사소한 마무리만).

계획 문서 기반 다중 작업 실행 시에는 superpowers:subagent-driven-development가 이 원칙의
구체 절차다.

## 슬래시 명령 안내 규칙

사용자에게 `/명령`을 안내할 때는 SKILL.md description·README·스킬 출력에 적힌 이름
(`/gh-flow:issue` 같은 plugin 네임스페이스형)을 그대로 옮기지 않는다. 그 이름은 plugin 으로
설치됐을 때만 유효하다. 반드시 **현재 세션의 available skills 목록에 실제로 등록된 이름**을
쓴다 — 목록에 `gh-flow:issue` 가 있으면 `/gh-flow:issue`, `issue` 만 있으면 `/issue`
(`~/.claude*/skills/` 의 평면 심볼릭 링크는 네임스페이스가 붙지 않는다). 둘 다 없으면 없다고
말한다. 목록 이름과 문서 이름이 다르면 그 불일치(plugin 미설치 drift)도 함께 알린다.

## 무인 세션 rm 규칙

yolo 무인 세션에서 `rm` 이 `sh -c`/`xargs ... sh -c`/`eval`/`$(...)` 안에 들어 있으면 하네스가
`could not be checked` 프롬프트를 띄우고, 응답이 없으면 자동 거부돼 작업이 끊긴다.

- `rm`/`rmdir` 은 복합 쉘 안에 넣지 말고 **독립된 단순 명령 한 줄**로 분리한다 (`rm -rf "$C"`).
- 임시 파일·디렉토리는 scratchpad(`/tmp/claude-<uid>/...`) 안에서만 만들고 지운다. 대상은 리터럴
  경로이거나 같은 명령에서 `mktemp -d /tmp/claude-<uid>/...` 로 대입한 변수여야 한다.
- `$sh -c "..."`·`env -i ... zsh -c "..."` 처럼 스크립트가 불투명한 `-c` 도 같은 프롬프트를 띄운다 — 임시 스크립트 파일로 쓰고 `bash file.sh` 로 실행한다.
- 대상이 불확실하면(`$HOME`, `~`, `..`, 미할당 변수) 지우지 말고 사용자 결정 사항으로 남긴다.

<!-- BEGIN AWS Agent Toolkit rules -->
# AWS Guidance for the new AWS experience

This user has signed up for the new AWS experience. This experience lets you sign into AWS using a social provider and requires the following additional context.

Where this guidance conflicts with the project's own instructions, the project's instructions take precedence.

## Context

### Terminology:

- Say "project" instead of "account" — a project contains an AWS account and settings for sharing with other collaborators
- Say "team member" instead of "IAM user" — users are invited by email, not created or federated in IAM
- Say "AWS Settings" when referring to management tasks at [settings.aws.com](https://settings.aws.com/) (project management, billing, team members, spend limits). Users view their actual AWS resources in the AWS Management Console.
- Say "selected Region" when referring to the user's Region — not "home Region"
- The user has a managed IAM experience. This includes a managed service control policies (SCP) and resource control policies (RCP) that govern the use of AWS. They will still need to use IAM to create policies to let services work with each other. If there are questions about the SCPs or RCPs, go to the documentation at https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html

### Constraints:

- All projects share a single AWS Region determined by the user's contact address. Resources cannot be created in other Regions
- When developing:
  - MUST create all Regional resources in the project's assigned Region
  - You CAN create AWS WAF and Cloudwatch Logs resources in us-east-1 when there are global resources (like a global WAF instance) that require a connection to dependencies in us-east-1. You should not use these for any other reason, because resources in the selected Region will provide lower cost (due to no cross-Region traffic), increased availability (due to no cross-Region traffic), and easier manageability (due to not needing to look in another Region). When you need to do an inventory of resources, you need to look in both the selected Region and us-east-1 for Cloudwatch Logs or WAF resources.
  - MUST NOT attempt to create Lambda, API Gateway, or other Regional resources in any other Region
  - MUST direct users to confirm their Region in AWS Settings > View all projects > Overview > Additional Info > Region. If the user cannot confirm their Region, check in ~/.aws/config
  - MUST NOT use Lambda@Edge — excluded from both Lambda and CloudFront
  - MUST NOT use CloudFormation StackSets — no multi-account or multi-Region deployments
  - MUST NOT attempt cross-Region actions — no cross-Region replication for DynamoDB/S3/RDS, no multi-Region KMS keys
  - MUST NOT use Route 53 cross-Region routing — geolocation, latency-based, and failover routing policies are not available
  - CloudFront is a global service and its actions ARE allowed in `us-east-1`. A user can create a CloudFront distribution pointing to their project-region Lambda function URL or API Gateway. However, Lambda and API Gateway themselves MUST NOT be created in `us-east-1` — they must be in the project Region.
  - Reduced availability in `eu-north-1` specifically: Amazon Rekognition, Amazon Textract, Amazon Personalize, AWS App Runner are not available in that Region.
- IAM permissions for human access are managed by AWS. Don't assign roles to team members unless absolutely necessary
- The user may have a spend limit if they are on the paid plan. The limit that pauses their project if it's exceeded. If resources suddenly become inaccessible, ask if they have a spend limit configured. Only project owners can modify a spend limit.
- When developing:
  - MUST ask about spend limit status if the user reports sudden "Access Denied" errors on operations that previously worked
  - MUST direct users to check spend status in AWS Settings > Billing
  - MUST check if a user has upgraded their account to the paid plan
  - MUST ask the user if they want to clean up the successfully created resources or keep them to reduce cost
- The user sets up billing, creates spend limits, and retrieves and pays invoices in AWS Settings. The user creates budgets and optimizes their costs in the AWS Billing and Cost Management console
- Not all AWS services are available. If a service isn't working, do the following:
  1. Run the command `aws freetier get-account-plan-state`
  2. If accountPlanType": "FREE", check the [Free Tier supported services list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html#supported-services-free-tier) next,
  3. If accountPlanType": "PAID", check the [Paid Tier supported services list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html#supported-services-paid-plan).
  4. If neither list shows the service, check the [Not supported for this experience list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html#unsupported-services). The user will need to activate advanced features to access this service.
- Users can activate advanced AWS services and capabilities for their account.
- Before starting a task, check whether a relevant AWS skill is available. Load the skill with retrieve_skill and prefer its guidance over general knowledge.

### Help level

- help_level (required): LOW, MEDIUM, or HIGH. While a user is building, you MUST ask the user: "How much guidance would you like from me? Low (I only flag security risks), medium (I ask a couple of clarifying questions if something seems off), or high (I explain what I'm doing, suggest alternatives, and flag best practices)."

You CAN update this rule file to save a user's help_level.

**Saved help_level: HIGH** (2026-10-23) — user is new to AWS and asked Claude to do all the work, flagging only steps that need them.

Constraints for each level:

**LOW:**

- MUST follow all constraints in this context file
- MUST execute the user’s request without modification
- MUST NOT ask clarifying questions unless the action would create a security vulnerability
- MUST NOT suggest alternatives or improvements

**MEDIUM:**

- MUST execute the user's request
- MAY ask up to two clarifying questions per task if the request has an ambiguity or a potential issue
- MUST NOT repeat a question or suggestion the user has already dismissed
- MUST NOT explain trade-offs or alternatives unless the user asks

**HIGH:**

- MUST explain what each step does and why before executing it
- MUST suggest alternatives when a better approach exists
- MUST flag best practices and explain trade-offs
- MUST still execute the user's choice if they disagree with a suggestion
<!-- END AWS Agent Toolkit rules -->
