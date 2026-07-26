#!/usr/bin/env python3
"""Thin UI bridge for SplitHorizon — shells out to Jac."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
CACHE = ROOT / "cache"
JAC_BIN = os.environ.get("JAC_BIN", str(Path.home() / ".local/bin/jac"))
if not Path(JAC_BIN).exists():
    JAC_BIN = "jac"
JAC_HOME = os.environ.get("JAC_HOME", "/tmp/jac_home")


def jac_env() -> dict:
    env = os.environ.copy()
    env["HOME"] = JAC_HOME
    env["PATH"] = str(Path(JAC_BIN).parent) + os.pathsep + env.get("PATH", "")
    env.setdefault("SPLITHORIZON_LIVE", "0")
    return env


def load_fixtures() -> list[dict]:
    interlock = (ROOT / "fixtures" / "interlock.txt").read_text() if (ROOT / "fixtures" / "interlock.txt").exists() else (
        "DECISION: Should we hire two engineers to hit the October launch?"
    )
    return [
        {"id": "interlock", "name": "Interlock — Hire two engineers to hit October launch?", "proposal": interlock},
        {"id": "hire", "name": "Hiring — Two eng vs one + contractor", "proposal": "DECISION: Two engineers now, or one plus a contractor?"},
        {"id": "launch", "name": "Launch — Ship October 3?", "proposal": "DECISION: Should we ship on October 3rd?"},
        {"id": "runway", "name": "Runway — When do we start raising?", "proposal": "DECISION: How long do we have, when do we start raising?"},
    ]


def run_engine(fixture_id: str, proposal: str, rounds: int = 3, baseline: bool = True) -> dict:
    OUT.mkdir(exist_ok=True)
    runner = ROOT / "run_once.jac"
    runner.write_text(
        "include engine;\ninclude fixtures;\nimport json;\nimport os;\n\n"
        "with entry {\n"
        f"    fid = {json.dumps(fixture_id)};\n"
        f"    text = {json.dumps(proposal)};\n"
        "    if not text {\n"
        "        fx = get_fixture(fid);\n"
        "        if fx { text = str(fx[\"proposal\"]); }\n"
        "    }\n"
        f"    result = run_protocol(text, fid, {int(rounds)}, {str(baseline)});\n"
        "    os.makedirs(\"out\", exist_ok=True);\n"
        "    with open(\"out/last_run.json\", \"w\") as f {\n"
        "        json.dump(result, f, indent=2);\n"
        "    }\n"
        "    print(\"OK\");\n"
        "}\n"
    )
    proc = subprocess.run(
        [JAC_BIN, "run", str(runner)],
        cwd=str(ROOT),
        env=jac_env(),
        capture_output=True,
        text=True,
        timeout=180,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or f"jac exited {proc.returncode}")
    path = OUT / "last_run.json"
    if not path.exists():
        raise RuntimeError("out/last_run.json missing\n" + proc.stdout)
    return json.loads(path.read_text())


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in ("/", "/index.html"):
            self.path = "/ui/index.html"
            return super().do_GET()
        if parsed.path == "/api/fixtures":
            ensure_fixture_texts()
            return self._json(load_fixtures())
        if parsed.path == "/api/last":
            path = OUT / "last_run.json"
            if not path.exists():
                return self._json({"error": "no run yet"}, 404)
            return self._json(json.loads(path.read_text()))
        if parsed.path == "/api/schema":
            static = ROOT / "ui" / "schema.json"
            if static.exists():
                return self._json(json.loads(static.read_text()))
            return self._json({"source": "schema.jac"})
        return super().do_GET()

    def end_headers(self):
        if self.path.startswith("/ui/") or self.path in ("/", "/index.html", "/ui/index.html"):
            self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/run":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        try:
            result = run_engine(
                fixture_id=body.get("fixture_id") or "interlock",
                proposal=body.get("proposal") or "",
                rounds=int(body.get("rounds") or 3),
                baseline=bool(body.get("baseline", True)),
            )
            self._json(result)
        except Exception as e:  # noqa: BLE001
            self._json({"error": str(e)}, 500)

    def _json(self, obj, status: int = 200):
        raw = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, fmt, *args):
        sys.stderr.write("[ui] " + (fmt % args) + "\n")


def ensure_fixture_texts():
    fx = ROOT / "fixtures"
    fx.mkdir(exist_ok=True)
    texts = {
        "interlock": (
            "DECISION: Should we hire two engineers to hit the October launch?\n\n"
            "Company: Northline (seed CompanyState).\n"
            "Tempted move: Hire two full-time engineers now so October 3 still lands.\n"
            "Counter-move: One engineer + contractor.\n"
            "Spine: what happens to the cash-out date, and does the milestone land before it?"
        ),
        "hire": "DECISION: Two engineers now, or one plus a contractor?\n\nCompany: Northline seed state.",
        "launch": "DECISION: Should we ship on October 3rd?\n\nCompany: Northline seed state.",
        "runway": "DECISION: How long do we have, when do we start raising?\n\nCompany: Northline seed state.",
    }
    for k, v in texts.items():
        (fx / f"{k}.txt").write_text(v)


def main():
    ensure_fixture_texts()
    port = int(os.environ.get("PORT", "8765"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"SplitHorizon UI → http://127.0.0.1:{port}")
    print(f"Jac: {JAC_BIN}  JAC_HOME={JAC_HOME}  offline cache default")
    server.serve_forever()


if __name__ == "__main__":
    main()
