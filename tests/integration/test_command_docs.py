"""Tests for the command reference doc generator (issue #1262).

`shell-common/tools/custom/gen_command_docs.sh` renders one markdown file per
user-facing command by executing the `_<topic>_help_rows_<section>()` row
functions with markdown-emitting ux_lib stubs.

The generated tree is what makes command behaviour greppable:
    rg "fzf 피커" docs/guide/commands/
"""

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
GENERATOR = REPO_ROOT / "shell-common" / "tools" / "custom" / "gen_command_docs.sh"
DOCS_DIR = REPO_ROOT / "docs" / "guide" / "commands"
NOTES_DIRNAME = ".notes"

# csm's help lives inside marketplace.sh, not a dedicated *_help.sh — it is the
# regression anchor for "discovery must scan every functions/*.sh file".
CSM_TOPIC = "claude_skills_marketplace"
CSM_DOC = "csm.md"


def run_generator(*args: str) -> subprocess.CompletedProcess:
    """Invoke the generator with ANSI colouring disabled."""
    return subprocess.run(
        [str(GENERATOR), *args],
        capture_output=True,
        text=True,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": str(Path.home()), "NO_COLOR": "1", "TERM": "dumb"},
    )


@pytest.fixture
def out_dir(tmp_path: Path) -> Path:
    """A scratch output dir seeded with the repo's hand-written notes."""
    target = tmp_path / "commands"
    target.mkdir()
    src_notes = DOCS_DIR / NOTES_DIRNAME
    if src_notes.is_dir():
        shutil.copytree(src_notes, target / NOTES_DIRNAME)
    return target


class TestGeneratorScript:
    """The generator itself."""

    def test_generator_is_executable(self):
        assert GENERATOR.is_file(), f"{GENERATOR} missing"
        assert GENERATOR.stat().st_mode & 0o111, f"{GENERATOR} is not executable"

    def test_help_flag_exits_clean(self):
        result = run_generator("--help")
        assert result.returncode == 0, result.stderr
        assert "gen_command_docs.sh" in result.stdout

    def test_list_discovers_topics_outside_help_files(self):
        """csm's row functions live in marketplace.sh — discovery must find them."""
        result = run_generator("--list")
        assert result.returncode == 0, result.stderr
        assert CSM_TOPIC in result.stdout
        assert "marketplace.sh" in result.stdout

    def test_legacy_help_files_warn_but_do_not_fail(self, out_dir: Path):
        """A *_help.sh without row functions is invisible to discovery — say so."""
        result = run_generator("--out-dir", str(out_dir), "--force")
        assert result.returncode == 0, result.stderr
        assert "레거시 포맷" in result.stdout, "legacy *_help.sh files should be reported"
        # the run still produces the full doc set
        assert len(list(out_dir.glob("*.md"))) > 10

    def test_unknown_topic_writes_nothing(self, out_dir: Path):
        result = run_generator("--topic", "definitely_not_a_topic", "--out-dir", str(out_dir))
        assert result.returncode == 0, result.stderr
        assert list(out_dir.glob("*.md")) == []


class TestGeneratedDoc:
    """Rendering a topic into a scratch dir."""

    def test_csm_doc_is_generated(self, out_dir: Path):
        result = run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir))
        assert result.returncode == 0, result.stderr

        doc = out_dir / CSM_DOC
        assert doc.is_file(), f"{CSM_DOC} not generated: {sorted(p.name for p in out_dir.iterdir())}"

        text = doc.read_text(encoding="utf-8")
        # (1) command list / entry point, (2) per-subcommand one-liners
        assert "claude-skills-marketplace-help" in text
        assert "info <skill-name>" in text
        assert "refresh" in text
        # source pointer back to the SSOT
        assert "shell-common/functions/marketplace.sh" in text

    def test_hand_written_edge_cases_are_spliced_in(self, out_dir: Path):
        """Source-comment-only behaviour reaches the doc via .notes/<name>.md."""
        run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir))
        text = (out_dir / CSM_DOC).read_text(encoding="utf-8")
        assert "fzf 피커" in text
        assert "Esc" in text

    def test_home_path_is_normalised(self, out_dir: Path):
        """Absolute $HOME paths would make every machine produce a different doc."""
        run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir))
        text = (out_dir / CSM_DOC).read_text(encoding="utf-8")
        assert str(Path.home()) not in text
        assert "~/.claude/plugins" in text

    def test_existing_doc_is_skipped_without_force(self, out_dir: Path):
        doc = out_dir / CSM_DOC
        doc.write_text("sentinel\n", encoding="utf-8")

        result = run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir))
        assert result.returncode == 0, result.stderr
        assert doc.read_text(encoding="utf-8") == "sentinel\n"

    def test_force_regeneration_is_idempotent(self, out_dir: Path):
        """A second --force run must not rewrite an unchanged file."""
        run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir))
        doc = out_dir / CSM_DOC
        first = doc.read_text(encoding="utf-8")
        mtime = doc.stat().st_mtime_ns

        result = run_generator("--topic", CSM_TOPIC, "--out-dir", str(out_dir), "--force")
        assert result.returncode == 0, result.stderr
        assert doc.read_text(encoding="utf-8") == first
        assert doc.stat().st_mtime_ns == mtime, "unchanged content must not be rewritten"


class TestCommittedDocs:
    """The docs checked into the repo — what `rg` actually searches."""

    def test_commands_dir_is_populated(self):
        docs = sorted(DOCS_DIR.glob("*.md"))
        assert len(docs) > 10, f"only {len(docs)} command docs found"
        assert (DOCS_DIR / "README.md").is_file()

    def test_csm_doc_is_committed_with_its_edge_cases(self):
        text = (DOCS_DIR / CSM_DOC).read_text(encoding="utf-8")
        assert "fzf 피커" in text
        assert "Esc" in text

    def test_edge_case_is_full_text_searchable(self):
        """rg-equivalent: the keyword must be findable across docs/guide/commands/."""
        hits = [p.name for p in DOCS_DIR.glob("*.md") if "fzf 피커" in p.read_text(encoding="utf-8")]
        assert CSM_DOC in hits, f"'fzf 피커' not found in command docs (hits: {hits})"

    def test_no_doc_contains_a_render_failure_marker(self):
        """A row function that dies must never reach a committed doc.

        Two docs shipped with this marker because the generator's failure
        guard tested `[ -z "$content" ]`, which could never be true — the
        document header is emitted before any row function runs.
        """
        broken = [p.name for p in DOCS_DIR.glob("*.md") if "렌더 실패" in p.read_text(encoding="utf-8")]
        assert broken == [], f"docs contain a render-failure placeholder: {broken}"

    def test_section_headings_name_tokens_the_cli_accepts(self):
        """Headings must match the dispatcher's `case` labels, not the row-function suffix.

        Row functions are `_<topic>_help_rows_release_artifacts` but the CLI
        only accepts `git-help release-artifacts`; a doc naming the underscore
        form instructs a command that errors.
        """
        offenders = []
        for doc in DOCS_DIR.glob("*.md"):
            for line in doc.read_text(encoding="utf-8").splitlines():
                if not line.startswith("### "):
                    continue
                token = line[4:].strip()
                if "_" in token:
                    offenders.append(f"{doc.name}: {token}")
        assert offenders == [], f"headings use underscore form the CLI rejects: {offenders}"

    def test_committed_docs_match_a_fresh_render(self, tmp_path: Path):
        """The drift gate.

        The generator's whole premise is that the docs cannot diverge from the
        row functions. Nothing enforced that, so a forgotten `--force` would
        leave `rg docs/guide/commands/` answering confidently wrong. This is
        the check that makes the claim real.
        """
        fresh = tmp_path / "commands"
        fresh.mkdir()
        shutil.copytree(DOCS_DIR / NOTES_DIRNAME, fresh / NOTES_DIRNAME)

        result = run_generator("--force", "--out-dir", str(fresh))
        assert result.returncode == 0, result.stderr

        committed = {p.name for p in DOCS_DIR.glob("*.md")}
        regenerated = {p.name for p in fresh.glob("*.md")}
        assert committed == regenerated, (
            f"file set drift — only committed: {sorted(committed - regenerated)}; "
            f"only regenerated: {sorted(regenerated - committed)}"
        )

        stale = [
            name
            for name in sorted(committed)
            if (DOCS_DIR / name).read_text(encoding="utf-8") != (fresh / name).read_text(encoding="utf-8")
        ]
        assert stale == [], (
            f"stale docs (row functions changed without regenerating): {stale}. "
            f"Fix: ./shell-common/tools/custom/gen_command_docs.sh --force"
        )

    @pytest.mark.parametrize("denied", ["ssl", "crt"])
    def test_host_state_topics_are_never_documented(self, denied: str):
        """`ssl`/`crt` rows print $SSL_CERT_FILE and friends.

        Generating them bakes whatever certificate paths the generating
        machine happens to have into a doc that ships to a public repo, and
        makes the output differ per machine. They are deny-listed; read them
        with `ssl-help` / `crt-help` where the values are actually yours.
        """
        assert not (DOCS_DIR / f"{denied}.md").exists(), (
            f"{denied}.md renders host environment values and must not be committed"
        )

    def test_index_links_every_doc(self):
        index = (DOCS_DIR / "README.md").read_text(encoding="utf-8")
        for doc in DOCS_DIR.glob("*.md"):
            if doc.name == "README.md":
                continue
            assert f"](./{doc.name})" in index, f"{doc.name} missing from README index"
