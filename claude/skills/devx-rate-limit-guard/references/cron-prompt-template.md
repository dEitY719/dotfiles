# Cron Prompt Template

Use this exact text for the `prompt:` argument of `CronCreate` in Step 4.
Substitute `<PWD_NOW>`, `<BRANCH>`, and `<command>` with the values
captured in Steps 1 and 3.

```
[Auto-resume by /devx:rate-limit-guard]
워크트리: <PWD_NOW>
브랜치: <BRANCH>
원본 명령: <command>

현재 워크트리·브랜치가 위와 같으면 원본 명령을 다시 실행. 명령은 멱등적으로
설계되어 이미 완료된 sub-step은 스킵됨. 다르면 사용자에게 알리고 중단.
/devx:resume-after-limit 스킬이 존재하면 우선 호출.
```

## Why self-contained

The prompt must work even before the companion `/devx:resume-after-limit`
skill is implemented. By embedding worktree/branch/command directly, the
fired prompt gives Claude enough context to resume safely on its own.

When the companion skill exists, the last line nudges Claude to delegate
to it for the standardized sanity check + announce flow.
