#!/usr/bin/env python3
"""Renders the fixtures through the real web view and checks what came out.

The markdown pipeline lives in JavaScript, so a unit test in Swift cannot see
whether diagrams, maths or highlighting still work. This drives mdql-probe and
asserts on the DOM it reports.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE = ROOT / ".build/debug/mdql-probe"

EXPECTED = {
    "kitchen-sink.md": {
        "ready": "ok",
        "notice": "",
        "frontMatterRows": 4,
        "diagrams": 4,
        "diagramErrors": 0,
        "katex": 3,
        "katexDisplay": 1,
        "dollarsLeftInText": 0,
        "highlighted": 3,
        "tables": 1,
        "tableRows": 3,
        "callouts": ["note", "warning", "caution"],
        "tasks": 3,
        "checkedTasks": 1,
        "wikiLinks": 2,
        "footnotes": 2,
        "marks": 1,
        "sub": 1,
        "abbr": 1,
        "strikes": 1,
        "forbiddenNodes": 0,
        "eventHandlerAttributes": 0,
        "images": ["assets/sample.png -> 320px"],
        "missingAssets": [
            "missing image: assets/nope.png",
            "missing image: https://example.com/tracker.png",
        ],
    },
    "hostile.md": {
        "ready": "ok",
        "executedPayload": "none",
        "forbiddenNodes": 0,
        "eventHandlerAttributes": 0,
        "scriptUrls": 0,
        "checkboxes": 2,
        "details": 1,
    },
    "edge-cases.md": {
        "ready": "ok",
        "diagrams": 1,
        "diagramErrors": 0,
        "tables": 1,
        "wikiLinks": 1,
    },
}


def render(path):
    result = subprocess.run(
        [str(PROBE), str(path)], capture_output=True, text=True, timeout=120
    )
    body = result.stdout
    if "{" not in body:
        raise SystemExit(f"{path.name}: probe produced no report\n{result.stderr}")
    return json.loads(body[body.index("{") : body.rindex("}") + 1])


def main():
    if not PROBE.exists():
        raise SystemExit("build mdql-probe first: swift build")

    failures = []
    for name, expected in EXPECTED.items():
        report = render(ROOT / "fixtures" / name)
        mismatches = [
            f"{name}: {key} is {report.get(key)!r}, expected {want!r}"
            for key, want in expected.items()
            if report.get(key) != want
        ]
        print(f"{'FAIL' if mismatches else 'ok  '}  {name}")
        failures += mismatches

    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
