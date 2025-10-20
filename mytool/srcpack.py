#!/usr/bin/env python3
import argparse
import hashlib
import sys
from pathlib import Path
from datetime import datetime

DEFAULT_EXTS = [".py", ".json"]
DEFAULT_EXCLUDE_DIRS = {".git", ".hg", ".svn", ".venv", "venv",
                        "__pycache__", ".mypy_cache", ".pytest_cache", ".tox", "build", "dist"}


def _usage() -> str:
    return r"""\
주요 사용 예시

  1) 기본 사용 (현재 디렉터리 스캔)
     srcpack .
  2) 특정 확장자 추가
     srcpack . --ext .py --ext .json --ext .toml
  3) 기본 제외 디렉터리 해제
     srcpack . --no-default-excludes
  4) 특정 패턴/디렉터리 제외
     srcpack . --exclude-glob "*/migrations/*" --exclude-dir node_modules
  5) 헤더에 상대 경로 사용
     srcpack . --relative
  6) 파일별 최대 256KB만 수록 + 해시 기록
     srcpack . --max-bytes 262144 --hash sha256
  7) 대소문자 무시 정렬
     srcpack . --case-insensitive-sort
  8) 심볼릭 링크 따라가기
     srcpack . --follow-symlinks
  9) 출력 파일명 지정
     srcpack . -o my_dump.txt
 10) 디코딩 정책 지정(문자 깨짐 방지)
     srcpack . --encoding utf-8 --errors replace
"""


def human_bytes(n: int) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.0f} PB"


def iter_source_files(
    base_dir: Path,
    exts,
    include_globs,
    exclude_globs,
    exclude_dirs,
    follow_symlinks: bool,
):
    for p in base_dir.rglob("*"):
        try:
            if not follow_symlinks and p.is_symlink():
                continue
            if p.is_dir():
                if p.name in exclude_dirs:
                    continue
                else:
                    continue
            if not p.is_file():
                continue
            if exts and p.suffix.lower() not in exts:
                continue
            if include_globs and not any(p.match(g) for g in include_globs):
                continue
            if exclude_globs and any(p.match(g) for g in exclude_globs):
                continue
            if any(part in exclude_dirs for part in p.parts):
                continue
            yield p
        except Exception as e:
            print(f"[WARN] Skipped {p}: {e}", file=sys.stderr)


def sha256_head(path: Path, max_bytes: int | None) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        if max_bytes is None:
            h.update(f.read())
        else:
            remaining = max_bytes
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                h.update(chunk)
                remaining -= len(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(
        description="Recursively collect source files into one text.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=_usage(),
    )
    ap.add_argument("path", nargs="?", default=".",
                    help="Directory or single file to scan (default: .)")
    ap.add_argument(
        "-o", "--output", help="Output file name (default: [directory_name]_all_source.txt)")
    ap.add_argument("--ext", action="append",
                    help="File extension to include (e.g., --ext .py). Can be repeated.")
    ap.add_argument("--include-glob", dest="include_glob", action="append", default=[],
                    help="Glob pattern(s) to include (relative to base).")
    ap.add_argument("--exclude-glob", dest="exclude_glob", action="append", default=[],
                    help="Glob pattern(s) to exclude (relative to base).")
    ap.add_argument("--exclude-dir", dest="exclude_dir", action="append", default=[],
                    help="Directory names to exclude (exact match). Can repeat.")
    ap.add_argument("--no-default-excludes", dest="no_default_excludes", action="store_true",
                    help="Do not exclude common build/cache dirs.")
    ap.add_argument("--follow-symlinks", dest="follow_symlinks", action="store_true",
                    help="Follow symlinks.")
    ap.add_argument("--relative", dest="relative", action="store_true",
                    help="Print file paths relative to base directory.")
    ap.add_argument("--case-insensitive-sort", dest="case_insensitive_sort", action="store_true",
                    help="Case-insensitive sort of paths.")
    ap.add_argument("--max-bytes", dest="max_bytes", type=int, default=None,
                    help="Per-file maximum bytes to read; if set, truncate.")
    ap.add_argument("--hash", dest="hash", choices=["sha256"], default=None,
                    help="Include hash of file (truncated if --max-bytes is set).")
    ap.add_argument("--encoding", dest="encoding", default="utf-8",
                    help="Text decoding (default: utf-8).")
    ap.add_argument("--errors", dest="errors", default="replace",
                    help="Decode error policy (default: replace).")
    ap.add_argument("--print-usage", dest="print_usage", action="store_true",
                    help="주요 사용 예시를 출력하고 종료")

    args = ap.parse_args()

    if args.print_usage:
        print(_usage())
        return

    target = Path(args.path).resolve()
    if not target.exists():
        print(f"[ERROR] Not found: {target}", file=sys.stderr)
        sys.exit(2)

    # 확장자/제외 디렉토리 설정
    exts = [e.lower() for e in (args.ext or DEFAULT_EXTS)]
    exclude_dirs = set(args.exclude_dir)
    if not args.no_default_excludes:
        exclude_dirs |= DEFAULT_EXCLUDE_DIRS

    # 디렉터리/단일 파일 모두 지원
    if target.is_file():
        base_dir = target.parent
        files = [target]
        # 단일 파일일 때 기본 출력 파일명: <파일명>_source.txt
        output_name = args.output or f"{target.stem}_source.txt"
    elif target.is_dir():
        base_dir = target
        files = list(iter_source_files(
            base_dir=base_dir,
            exts=exts,
            include_globs=args.include_glob,
            exclude_globs=args.exclude_glob,
            exclude_dirs=exclude_dirs,
            follow_symlinks=args.follow_symlinks,
        ))
        # 디렉터리일 때 기본 출력 파일명: <디렉터리명>_all_source.txt
        dir_name = base_dir.name
        output_name = args.output or f"{dir_name}_all_source.txt"
    else:
        print(
            f"[ERROR] Not a regular file or directory: {target}", file=sys.stderr)
        sys.exit(2)

    # 출력 경로는 현재 작업 디렉터리에 생성
    output_path = Path.cwd() / Path(output_name).name

    files = list(iter_source_files(
        base_dir=base_dir,
        exts=exts,
        include_globs=args.include_glob,
        exclude_globs=args.exclude_glob,
        exclude_dirs=exclude_dirs,
        follow_symlinks=args.follow_symlinks,
    ))

    key = (lambda p: str(p).lower()) if args.case_insensitive_sort else (
        lambda p: str(p))
    files.sort(key=key)

    print(f"Scanning: {base_dir}")
    print(f"Found {len(files)} files")
    print(f"Writing to: {output_path}")

    collected = 0
    truncated = 0
    errors = 0
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    with output_path.open("w", encoding="utf-8", newline="\n") as out:
        out.write(f"##### Consolidated Source Dump\n")
        out.write(f"Base: {base_dir}\nGenerated: {now}\n")
        out.write(f"Extensions: {', '.join(exts)}\n")
        out.write(f"Exclude dirs: {', '.join(sorted(exclude_dirs))}\n")
        out.write(f"Files: {len(files)}\n")
        out.write(f"-----\n\n")

        for p in files:
            try:
                rel = p.relative_to(base_dir) if args.relative else p
                size = p.stat().st_size
                modt = datetime.fromtimestamp(
                    p.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")

                hashed = None
                if args.hash == "sha256":
                    hashed = sha256_head(p, args.max_bytes)

                out.write("##### --- FILE BREAK --- #####\n")
                out.write(f"# 경로: {rel}\n")
                out.write(f"# 크기: {size} bytes ({human_bytes(size)})\n")
                out.write(f"# 수정시각: {modt}\n")
                if args.hash:
                    out.write(f"# {args.hash}: {hashed}\n")
                out.write("# 내용 시작\n")

                if args.max_bytes is not None:
                    with p.open("rb") as f:
                        data = f.read(args.max_bytes)
                    text = data.decode(args.encoding, errors=args.errors)
                    out.write(text)
                    if size > args.max_bytes:
                        out.write("\n# [TRUNCATED]\n")
                        truncated += 1
                else:
                    with p.open("r", encoding=args.encoding, errors=args.errors) as f:
                        out.write(f.read())

                out.write("\n# 내용 끝\n\n")
                collected += 1
            except Exception as e:
                print(f"[WARN] Error processing {p}: {e}", file=sys.stderr)
                errors += 1

        out.write("##### --- SUMMARY --- #####\n")
        out.write(f"# 수록: {collected}, 잘림: {truncated}, 오류: {errors}\n")

    print(
        f"Done. Collected={collected}, Truncated={truncated}, Errors={errors}")
    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
