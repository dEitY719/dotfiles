/devx:reverse-engineering-analysis — Analyze a feature and generate a copy-pasteable AI prompt

Usage:
  /devx:reverse-engineering-analysis "<feature or file path>" [output dir]

Arguments:
  "<feature or file path>"    Feature name to search (e.g. "frontend graph 기능"),
                              or a direct file path (e.g. .github/workflows/ci.yml)
  [output dir]                Directory for analysis.md output (default: docs/)

Examples:
  /devx:reverse-engineering-analysis "frontend의 graph 기능" docs/feature/frontend-graph/
  /devx:reverse-engineering-analysis "backend의 알람메일발송 기능" docs/feature/backend-email/
  /devx:reverse-engineering-analysis .github/workflows/ci.yml docs/feature/workflows-ci/
  /devx:reverse-engineering-analysis help

Options:
  help    Show this message
