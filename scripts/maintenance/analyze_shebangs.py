#!/usr/bin/env python3
"""
Shebang Consistency Analyzer
Analyzes all .sh and .bash files for bash-specific features and shebang consistency
"""

import os
import re
from collections import defaultdict
from pathlib import Path
from typing import TypedDict


# ANSI color codes
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"


# Bash-specific feature patterns
BASH_FEATURES = {
    "[[_]]": re.compile(r"\[\[.*\]\]"),
    "BASH_SOURCE": re.compile(r"\bBASH_SOURCE\b"),
    "BASH_VERSION": re.compile(r"\bBASH_VERSION\b"),
    "arrays": re.compile(r"(\(\(|\)\)|declare\s+-[aA]|local\s+-[aA]|\[[0-9]+\]=|read\s+-r?\s+-a)"),
    "process_subst": re.compile(r"(<\(|>\()"),
    "parameter_exp": re.compile(r"\$\{[^}]*(//|:|\^|,)"),
    "shopt": re.compile(r"\bshopt\b"),
    "source": re.compile(r"\bsource\s+"),
    "readarray/mapfile": re.compile(r"\b(readarray|mapfile)\b"),
    "declare_flags": re.compile(r"\bdeclare\s+-[gnifrlux]"),
    "local_flags": re.compile(r"\blocal\s+-[gnifrlux]"),
    "export_f": re.compile(r"\bexport\s+-f\b"),
    "regex_match": re.compile(r"=~"),
    "brace_exp": re.compile(r"\{[0-9]+\.\.[0-9]+\}"),
}


class AnalysisEntry(TypedDict, total=False):
    path: str
    shebang: str
    features: list[str]
    is_exec: bool
    priority: bool
    recommended: str
    reason: str


def get_shebang(filepath: Path | str) -> str | None:
    """Extract shebang from file"""
    try:
        with open(filepath, encoding="utf-8", errors="ignore") as f:
            first_line = f.readline().strip()
            if first_line.startswith("#!"):
                return first_line
    except Exception:
        pass
    return None


def detect_bash_features(filepath: Path | str) -> list[str]:
    """Detect bash-specific features in file"""
    try:
        with open(filepath, encoding="utf-8", errors="ignore") as f:
            content = f.read()

        features = []
        for name, pattern in BASH_FEATURES.items():
            if pattern.search(content):
                features.append(name)
        return features
    except Exception:
        return []


def is_executable(filepath: Path | str) -> bool:
    """Check if file is executable"""
    return os.access(filepath, os.X_OK)


def analyze_files(root_dir: Path | str) -> tuple[dict[str, list[AnalysisEntry]], defaultdict[str, int]]:
    """Analyze all .sh and .bash files"""
    results: dict[str, list[AnalysisEntry]] = {
        "bash_required": [],
        "posix_ok": [],
        "source_only": [],
        "wrong_shebang": [],
        "missing_shebang": [],
        "correct": [],
    }

    stats: defaultdict[str, int] = defaultdict(int)

    # Find all .sh and .bash files
    for pattern in ["**/*.sh", "**/*.bash"]:
        for filepath in Path(root_dir).glob(pattern):
            if not filepath.is_file():
                continue

            stats["total"] += 1
            rel_path = filepath.relative_to(root_dir)
            shebang = get_shebang(filepath)
            features = detect_bash_features(filepath)
            is_exec = is_executable(filepath)

            entry: AnalysisEntry = {
                "path": str(rel_path),
                "shebang": shebang or "NONE",
                "features": features,
                "is_exec": is_exec,
                "priority": str(rel_path).startswith("shell-common/env/")
                or str(rel_path).startswith("shell-common/functions/"),
            }

            # Categorize
            if features:
                # Bash-required
                stats["bash_required"] += 1
                entry["recommended"] = "#!/bin/bash"
                entry["reason"] = f"Uses: {', '.join(features)}"

                if shebang and ("bash" in shebang):
                    stats["correct"] += 1
                    results["correct"].append(entry)
                elif not shebang:
                    stats["missing_shebang"] += 1
                    results["missing_shebang"].append(entry)
                else:
                    stats["wrong_shebang"] += 1
                    results["wrong_shebang"].append(entry)

                results["bash_required"].append(entry)
            else:
                # POSIX-compatible
                stats["posix_ok"] += 1
                entry["recommended"] = "#!/bin/sh"
                entry["reason"] = "POSIX-compatible, no bash features"

                if shebang and ("/sh" in shebang or shebang == "#!/bin/sh"):
                    stats["correct"] += 1
                    results["correct"].append(entry)
                elif not shebang:
                    if not is_exec:
                        stats["source_only"] += 1
                        entry["recommended"] = "optional"
                        results["source_only"].append(entry)
                    else:
                        stats["missing_shebang"] += 1
                        results["missing_shebang"].append(entry)
                elif "bash" in shebang:
                    stats["wrong_shebang"] += 1
                    results["wrong_shebang"].append(entry)
                else:
                    stats["correct"] += 1
                    results["correct"].append(entry)

                results["posix_ok"].append(entry)

    return results, stats


def print_section(title):
    """Print section header"""
    print()
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 70}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}  {title}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 70}{Colors.RESET}")
    print()


def print_entry(entry, show_features=False):
    """Print file entry"""
    print(f"  {Colors.YELLOW}File:{Colors.RESET}        {entry['path']}")
    if entry["shebang"] == "NONE":
        print(f"  {Colors.RED}Current:{Colors.RESET}     NONE")
    else:
        print(f"  {Colors.BLUE}Current:{Colors.RESET}     {entry['shebang']}")
    if "recommended" in entry:
        print(f"  {Colors.GREEN}Recommended:{Colors.RESET} {entry['recommended']}")
    if "reason" in entry:
        print(f"  {Colors.CYAN}Reason:{Colors.RESET}      {entry['reason']}")
    if show_features and entry["features"]:
        print(f"  {Colors.CYAN}Features:{Colors.RESET}    {', '.join(entry['features'])}")
    print(f"  {Colors.CYAN}Executable:{Colors.RESET}  {'yes' if entry['is_exec'] else 'no'}")
    print()


def main():
    root_dir = Path("/home/bwyoon/dotfiles")

    print_section("SHEBANG CONSISTENCY ANALYSIS")
    print(f"Analyzing all .sh and .bash files in {root_dir}...")

    results, stats = analyze_files(root_dir)

    # Print statistics
    print_section("STATISTICS")
    print(f"{Colors.BOLD}Total files analyzed:{Colors.RESET} {stats['total']}")
    print()
    print(f"{Colors.BOLD}By features:{Colors.RESET}")
    print(f"  {Colors.YELLOW}Bash-required:{Colors.RESET}    {stats['bash_required']} (need #!/bin/bash)")
    print(f"  {Colors.GREEN}POSIX-compatible:{Colors.RESET} {stats['posix_ok']} (can use #!/bin/sh)")
    print()
    print(f"{Colors.BOLD}By shebang status:{Colors.RESET}")
    print(f"  {Colors.GREEN}Correct shebang:{Colors.RESET}  {stats['correct']}")
    print(f"  {Colors.RED}Wrong shebang:{Colors.RESET}    {stats['wrong_shebang']}")
    print(f"  {Colors.YELLOW}Missing shebang:{Colors.RESET}  {stats['missing_shebang']}")
    print(f"  {Colors.BLUE}Source-only:{Colors.RESET}      {stats['source_only']} (shebang optional)")

    # Print priority files
    print_section("PRIORITY FILES (shell-common/env/ and shell-common/functions/)")

    priority_issues = [e for e in results["wrong_shebang"] + results["missing_shebang"] if e["priority"]]

    if not priority_issues:
        print(f"  {Colors.GREEN}✓ All priority files have correct shebangs!{Colors.RESET}")
    else:
        for entry in sorted(priority_issues, key=lambda x: x["path"]):
            print_entry(entry, show_features=True)

    # Print all files needing changes
    print_section("ALL FILES NEEDING SHEBANG CHANGES")

    if not results["wrong_shebang"] and not results["missing_shebang"]:
        print(f"{Colors.GREEN}✓ No files need shebang changes!{Colors.RESET}")
    else:
        if results["wrong_shebang"]:
            print(f"{Colors.BOLD}{Colors.RED}Wrong Shebang ({len(results['wrong_shebang'])} files):{Colors.RESET}")
            print()
            for entry in sorted(results["wrong_shebang"], key=lambda x: x["path"]):
                print_entry(entry, show_features=True)

        if results["missing_shebang"]:
            print(
                f"{Colors.BOLD}{Colors.YELLOW}Missing Shebang ({len(results['missing_shebang'])} files):{Colors.RESET}"
            )
            print()
            for entry in sorted(results["missing_shebang"], key=lambda x: x["path"]):
                print_entry(entry, show_features=True)

    # Print source-only files
    print_section("SOURCE-ONLY FILES (Shebang Optional)")

    if not results["source_only"]:
        print("  None")
    else:
        for entry in sorted(results["source_only"], key=lambda x: x["path"]):
            print(f"  {Colors.BLUE}{entry['path']}{Colors.RESET} - {entry['reason']}")
        print()

    # Summary
    print_section("SUMMARY AND RECOMMENDATIONS")
    print("Analysis complete. Key findings:")
    print()
    print(f"  1. {Colors.BOLD}{len(priority_issues)} priority files{Colors.RESET} need attention")
    print(f"  2. {Colors.BOLD}{stats['wrong_shebang']} files{Colors.RESET} have wrong shebang")
    print(f"  3. {Colors.BOLD}{stats['missing_shebang']} files{Colors.RESET} missing shebang")
    print()
    print(f"{Colors.BOLD}Next steps:{Colors.RESET}")
    print("  1. Review priority files (shell-common/env/ and shell-common/functions/)")
    print("  2. Fix wrong shebangs in bash-required files")
    print("  3. Add shebangs to executable files missing them")
    print("  4. Consider whether source-only files need shebangs")
    print()


if __name__ == "__main__":
    main()
