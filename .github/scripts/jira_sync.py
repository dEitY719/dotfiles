#!/usr/bin/env python3
"""
GitHub → JIRA one-way mirror sync.

Supports three actions:
  create-issue  GitHub Issue opened  → create JIRA ticket
  close-issue   GitHub Issue closed  → transition JIRA ticket to Done
  pr-merged     GitHub PR merged     → transition linked JIRA tickets to Done

Required env vars:
  JIRA_BASE_URL       https://<org>.atlassian.net
  JIRA_PROJECT_KEY    e.g. PROJ
  JIRA_USER_EMAIL     e.g. user@org.com
  JIRA_API_TOKEN      Atlassian API token
  GITHUB_TOKEN        GitHub token (Actions GITHUB_TOKEN works)

Optional env vars:
  JIRA_ISSUE_TYPE         Task (default)
  JIRA_FIELD_TOKENS       customfield_10100 (default) — AI tokens used
  JIRA_FIELD_HUMAN_H      customfield_10101 (default) — estimated human hours
  JIRA_FIELD_AI_MIN       customfield_10102 (default) — AI time in minutes
  JIRA_FIELD_GITHUB_LINK  customfield_10103 (default) — GitHub issue URL

Usage:
  jira_sync.py create-issue --repo OWNER/REPO --issue N
  jira_sync.py close-issue  --repo OWNER/REPO --issue N
  jira_sync.py pr-merged    --repo OWNER/REPO --pr N
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any

# ── Constants ──────────────────────────────────────────────────────────────────

JIRA_TICKET_TAG_RE = re.compile(r"<!--\s*jira-ticket:\s*([A-Z]+-\d+)\s*-->")
AI_METRICS_TAG_RE = re.compile(
    r"<!--\s*ai-metrics:[^\s>]*\s+tokens=(\d+)\s+human_h=([\d.]+)\s+ai_min=(\d+)\s*-->"
)
AI_METRICS_EMOJI_RE = re.compile(
    r"📊\s*~?([\d,]+)\s*tokens?.*?👤\s*~?([\d.]+)\s*(h|d).*?🤖\s*~?([\d.]+)\s*min",
    re.DOTALL,
)
PR_CLOSES_RE = re.compile(
    r"(?:closes|fixes|resolves)\s+#(\d+)",
    re.IGNORECASE,
)

GITHUB_API = "https://api.github.com"
JIRA_DONE_NAMES = {"done", "closed", "complete", "완료", "종료"}

# ── Helpers: HTTP ──────────────────────────────────────────────────────────────


def _gh_headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
    }


def _jira_headers(email: str, token: str) -> dict[str, str]:
    credentials = base64.b64encode(f"{email}:{token}".encode()).decode()
    return {
        "Authorization": f"Basic {credentials}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def _request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return exc.code, payload


# ── Helpers: GitHub API ────────────────────────────────────────────────────────


def gh_get_issue(repo: str, issue_number: int, token: str) -> dict[str, Any]:
    url = f"{GITHUB_API}/repos/{repo}/issues/{issue_number}"
    status, data = _request(url, headers=_gh_headers(token))
    if status != 200:
        raise RuntimeError(f"GitHub: failed to fetch issue #{issue_number}: HTTP {status}")
    return data


def gh_get_issue_comments(repo: str, issue_number: int, token: str) -> list[dict[str, Any]]:
    comments: list[dict[str, Any]] = []
    page = 1
    while True:
        url = (
            f"{GITHUB_API}/repos/{repo}/issues/{issue_number}/comments"
            f"?per_page=100&page={page}"
        )
        status, data = _request(url, headers=_gh_headers(token))
        if status != 200:
            raise RuntimeError(f"GitHub: failed to fetch comments: HTTP {status}")
        if not data:
            break
        comments.extend(data)
        if len(data) < 100:
            break
        page += 1
    return comments


def gh_post_comment(repo: str, issue_number: int, body: str, token: str) -> None:
    url = f"{GITHUB_API}/repos/{repo}/issues/{issue_number}/comments"
    status, data = _request(
        url, method="POST", headers=_gh_headers(token), body={"body": body}
    )
    if status not in (200, 201):
        raise RuntimeError(f"GitHub: failed to post comment: HTTP {status}")


def gh_get_pr(repo: str, pr_number: int, token: str) -> dict[str, Any]:
    url = f"{GITHUB_API}/repos/{repo}/pulls/{pr_number}"
    status, data = _request(url, headers=_gh_headers(token))
    if status != 200:
        raise RuntimeError(f"GitHub: failed to fetch PR #{pr_number}: HTTP {status}")
    return data


# ── Helpers: JIRA API ──────────────────────────────────────────────────────────


def jira_create_issue(
    base_url: str,
    email: str,
    token: str,
    project_key: str,
    summary: str,
    description_text: str,
    issue_type: str,
    extra_fields: dict[str, Any],
) -> str:
    url = f"{base_url}/rest/api/3/issue"
    body: dict[str, Any] = {
        "fields": {
            "project": {"key": project_key},
            "summary": summary,
            "description": {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": description_text}],
                    }
                ],
            },
            "issuetype": {"name": issue_type},
            **extra_fields,
        }
    }
    status, data = _request(
        url, method="POST", headers=_jira_headers(email, token), body=body
    )
    if status not in (200, 201):
        raise RuntimeError(f"JIRA: create issue failed: HTTP {status} — {data}")
    return data["key"]


def jira_get_transitions(
    base_url: str, email: str, token: str, issue_key: str
) -> list[dict[str, Any]]:
    url = f"{base_url}/rest/api/3/issue/{issue_key}/transitions"
    status, data = _request(url, headers=_jira_headers(email, token))
    if status != 200:
        raise RuntimeError(f"JIRA: get transitions failed: HTTP {status}")
    return data.get("transitions", [])


def jira_transition(
    base_url: str, email: str, token: str, issue_key: str, transition_id: str
) -> None:
    url = f"{base_url}/rest/api/3/issue/{issue_key}/transitions"
    body = {"transition": {"id": transition_id}}
    status, data = _request(
        url, method="POST", headers=_jira_headers(email, token), body=body
    )
    if status not in (200, 204):
        raise RuntimeError(f"JIRA: transition failed: HTTP {status} — {data}")


def jira_find_done_transition(transitions: list[dict[str, Any]]) -> str | None:
    for t in transitions:
        if t.get("name", "").lower() in JIRA_DONE_NAMES:
            return t["id"]
    return None


# ── Parsing ────────────────────────────────────────────────────────────────────


def parse_jira_ticket_tag(text: str) -> str | None:
    m = JIRA_TICKET_TAG_RE.search(text)
    return m.group(1) if m else None


def parse_ai_metrics(text: str) -> tuple[int | None, float | None, int | None]:
    """Return (tokens, human_h, ai_min) from ai-metrics HTML comment or emoji line."""
    m = AI_METRICS_TAG_RE.search(text)
    if m:
        return int(m.group(1)), float(m.group(2)), int(m.group(3))
    m = AI_METRICS_EMOJI_RE.search(text)
    if m:
        tokens = int(m.group(1).replace(",", ""))
        raw_h = float(m.group(2))
        human_h = raw_h * 8 if m.group(3) == "d" else raw_h
        ai_min = int(float(m.group(4)))
        return tokens, human_h, ai_min
    return None, None, None


def find_jira_ticket_for_issue(
    repo: str, issue_number: int, token: str
) -> str | None:
    issue = gh_get_issue(repo, issue_number, token)
    key = parse_jira_ticket_tag(issue.get("body") or "")
    if key:
        return key
    for comment in gh_get_issue_comments(repo, issue_number, token):
        key = parse_jira_ticket_tag(comment.get("body") or "")
        if key:
            return key
    return None


def find_closing_issue_numbers(pr_body: str) -> list[int]:
    return [int(n) for n in PR_CLOSES_RE.findall(pr_body or "")]


# ── Error notification helper ──────────────────────────────────────────────────


def _try_post_error_comment(
    repo: str, issue_number: int, exc: Exception, token: str
) -> None:
    try:
        body = (
            "⚠️ **JIRA 미러링 실패**\n\n"
            "JIRA API 호출에 실패했습니다. 수동으로 JIRA 티켓을 확인하거나 관리자에게 문의하세요.\n\n"
            f"**오류:**\n```\n{exc}\n```"
        )
        gh_post_comment(repo, issue_number, body, token)
    except Exception as comment_exc:
        print(
            f"[warn] Also failed to post error comment: {comment_exc}",
            file=sys.stderr,
        )


# ── Actions ────────────────────────────────────────────────────────────────────


def action_create_issue(
    repo: str,
    issue_number: int,
    *,
    jira_base: str,
    jira_project: str,
    jira_email: str,
    jira_token: str,
    jira_issue_type: str,
    gh_token: str,
    field_tokens: str,
    field_human_h: str,
    field_ai_min: str,
    field_github_link: str,
) -> None:
    issue = gh_get_issue(repo, issue_number, gh_token)
    title = issue["title"]
    body = issue.get("body") or ""
    html_url = issue["html_url"]

    existing = find_jira_ticket_for_issue(repo, issue_number, gh_token)
    if existing:
        print(
            f"[idempotency] JIRA ticket {existing} already linked to #{issue_number} — skipping"
        )
        return

    tokens, human_h, ai_min = parse_ai_metrics(body)

    description_text = f"GitHub Issue: {html_url}\n\n{body}"

    extra_fields: dict[str, Any] = {field_github_link: html_url}
    if tokens is not None:
        extra_fields[field_tokens] = tokens
    if human_h is not None:
        extra_fields[field_human_h] = human_h
    if ai_min is not None:
        extra_fields[field_ai_min] = ai_min

    try:
        jira_key = jira_create_issue(
            jira_base,
            jira_email,
            jira_token,
            jira_project,
            title,
            description_text,
            jira_issue_type,
            extra_fields,
        )
    except RuntimeError as exc:
        _try_post_error_comment(repo, issue_number, exc, gh_token)
        raise

    print(f"[create] JIRA {jira_key} created for GitHub Issue #{issue_number}")

    back_comment = (
        f"JIRA 티켓이 자동으로 생성되었습니다.\n\n"
        f"**JIRA 티켓:** [{jira_key}]({jira_base}/browse/{jira_key})\n\n"
        f"<!-- jira-ticket: {jira_key} -->"
    )
    gh_post_comment(repo, issue_number, back_comment, gh_token)
    print(f"[create] Back-posted {jira_key} link to GitHub Issue #{issue_number}")


def action_close_issue(
    repo: str,
    issue_number: int,
    *,
    jira_base: str,
    jira_email: str,
    jira_token: str,
    gh_token: str,
) -> None:
    jira_key = find_jira_ticket_for_issue(repo, issue_number, gh_token)
    if not jira_key:
        print(f"[close] No JIRA ticket linked to #{issue_number} — skipping")
        return

    try:
        transitions = jira_get_transitions(jira_base, jira_email, jira_token, jira_key)
        done_id = jira_find_done_transition(transitions)
        if not done_id:
            available = ", ".join(f"{t['name']}({t['id']})" for t in transitions)
            raise RuntimeError(
                f"JIRA: no 'Done' transition for {jira_key}. Available: {available}"
            )
        jira_transition(jira_base, jira_email, jira_token, jira_key, done_id)
    except RuntimeError as exc:
        _try_post_error_comment(repo, issue_number, exc, gh_token)
        raise

    print(f"[close] JIRA {jira_key} transitioned to Done (Issue #{issue_number} closed)")


def action_pr_merged(
    repo: str,
    pr_number: int,
    *,
    jira_base: str,
    jira_email: str,
    jira_token: str,
    gh_token: str,
) -> None:
    pr = gh_get_pr(repo, pr_number, gh_token)
    closing_issues = find_closing_issue_numbers(pr.get("body") or "")

    if not closing_issues:
        print(f"[pr-merged] No closing issues found in PR #{pr_number}")
        return

    for issue_num in closing_issues:
        try:
            jira_key = find_jira_ticket_for_issue(repo, issue_num, gh_token)
            if not jira_key:
                print(f"[pr-merged] No JIRA ticket linked to #{issue_num} — skipping")
                continue

            transitions = jira_get_transitions(jira_base, jira_email, jira_token, jira_key)
            done_id = jira_find_done_transition(transitions)
            if not done_id:
                print(f"[pr-merged] No 'Done' transition for {jira_key} — skipping")
                continue

            jira_transition(jira_base, jira_email, jira_token, jira_key, done_id)
            print(f"[pr-merged] JIRA {jira_key} (Issue #{issue_num}) transitioned to Done")
        except Exception as exc:
            print(f"[pr-merged] Warning: Issue #{issue_num}: {exc}", file=sys.stderr)
            try:
                _try_post_error_comment(repo, issue_num, exc, gh_token)
            except Exception:
                pass


# ── Main ───────────────────────────────────────────────────────────────────────


def _env(name: str, default: str | None = None) -> str:
    val = os.environ.get(name, default)
    if val is None:
        raise SystemExit(f"Error: required env var {name!r} is not set")
    return val


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="action", required=True)

    p_create = sub.add_parser("create-issue")
    p_create.add_argument("--repo", required=True)
    p_create.add_argument("--issue", type=int, required=True)

    p_close = sub.add_parser("close-issue")
    p_close.add_argument("--repo", required=True)
    p_close.add_argument("--issue", type=int, required=True)

    p_pr = sub.add_parser("pr-merged")
    p_pr.add_argument("--repo", required=True)
    p_pr.add_argument("--pr", type=int, required=True)

    args = parser.parse_args(argv)

    jira_base = _env("JIRA_BASE_URL").rstrip("/")
    jira_project = _env("JIRA_PROJECT_KEY")
    jira_email = _env("JIRA_USER_EMAIL")
    jira_token = _env("JIRA_API_TOKEN")
    gh_token = _env("GITHUB_TOKEN")

    try:
        if args.action == "create-issue":
            action_create_issue(
                args.repo,
                args.issue,
                jira_base=jira_base,
                jira_project=jira_project,
                jira_email=jira_email,
                jira_token=jira_token,
                jira_issue_type=os.environ.get("JIRA_ISSUE_TYPE", "Task"),
                gh_token=gh_token,
                field_tokens=os.environ.get("JIRA_FIELD_TOKENS", "customfield_10100"),
                field_human_h=os.environ.get("JIRA_FIELD_HUMAN_H", "customfield_10101"),
                field_ai_min=os.environ.get("JIRA_FIELD_AI_MIN", "customfield_10102"),
                field_github_link=os.environ.get("JIRA_FIELD_GITHUB_LINK", "customfield_10103"),
            )
        elif args.action == "close-issue":
            action_close_issue(
                args.repo,
                args.issue,
                jira_base=jira_base,
                jira_email=jira_email,
                jira_token=jira_token,
                gh_token=gh_token,
            )
        elif args.action == "pr-merged":
            action_pr_merged(
                args.repo,
                args.pr,
                jira_base=jira_base,
                jira_email=jira_email,
                jira_token=jira_token,
                gh_token=gh_token,
            )
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
