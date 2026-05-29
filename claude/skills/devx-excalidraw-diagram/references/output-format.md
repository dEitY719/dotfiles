# Output Format

Artifact paths, filename convention, and structure for a diagram run.

`<slug>` = kebab-case of the topic. `<work-dir>` = the directory the user is
working in (default: current directory).

| Output    | Path                                | Notes                |
|-----------|-------------------------------------|----------------------|
| diagram   | <work-dir>/<slug>.excalidraw        | JSON, raw editable   |
| preview   | <work-dir>/<slug>.png               | 렌더 검증용          |
| iteration | <work-dir>/.iter/<slug>-<n>.png     | 2–4 회 검증 루프      |

- The `.excalidraw` JSON is the primary deliverable — editable in excalidraw.com.
- The `.png` is rendered by `render_excalidraw.py` for the render-view-fix loop
  (Step 5) and final visual verification.
- Intermediate iteration PNGs live under `.iter/` so they do not clutter the
  work directory; they may be discarded after the final render passes.
