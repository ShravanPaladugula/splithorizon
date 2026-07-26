#!/usr/bin/env python3
"""Minimal UI server for SplitHorizon — shells out to Jac for the real engine."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
UI = ROOT / "ui"
OUT = ROOT / "out"
CACHE = ROOT / "cache"

JAC_BIN = os.environ.get("JAC_BIN", str(Path.home() / ".local/bin/jac"))
if not Path(JAC_BIN).exists():
    JAC_BIN = "jac"

# Jac standalone runtime extracts under HOME; sandbox-friendly default
JAC_HOME = os.environ.get("JAC_HOME", "/tmp/jac_home")


def jac_env() -> dict:
    env = os.environ.copy()
    env["HOME"] = JAC_HOME
    env["PATH"] = str(Path(JAC_BIN).parent) + os.pathsep + env.get("PATH", "")
    # Offline fixture cache unless explicitly live
    env.setdefault("SPLITHORIZON_LIVE", "0")
    return env


def load_fixtures() -> list[dict]:
    static = [
        {
            "id": "hire",
            "name": "Hiring — Grow the team vs stay lean",
            "proposal": (ROOT / "fixtures" / "hire.txt").read_text()
            if (ROOT / "fixtures" / "hire.txt").exists()
            else "",
        },
    ]
    return static


def run_engine(fixture_id: str, proposal: str, rounds: int = 5, baseline: bool = True) -> dict:
    OUT.mkdir(exist_ok=True)
    runner = ROOT / "run_once.jac"
    runner.write_text(
        f"""include engine;
include fixtures;
import json;
import os;

with entry {{
    fid = {json.dumps(fixture_id)};
    text = {json.dumps(proposal)};
    if not text {{
        fx = get_fixture(fid);
        if fx {{
            text = str(fx["proposal"]);
        }}
    }}
    result = run_protocol(text, fid, {int(rounds)}, {str(baseline)});
    os.makedirs("out", exist_ok=True);
    with open("out/last_run.json", "w") as f {{
        json.dump(result, f, indent=2);
    }}
    print("OK");
}}
"""
    )
    cmd = [JAC_BIN, "run", str(runner)]
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT),
        env=jac_env(),
        capture_output=True,
        text=True,
        timeout=180,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or f"jac exited {proc.returncode}")
    result_path = OUT / "last_run.json"
    if not result_path.exists():
        raise RuntimeError("Engine finished but out/last_run.json missing\n" + proc.stdout)
    return json.loads(result_path.read_text())


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in ("/", "/index.html"):
            self.path = "/ui/index.html"
            return super().do_GET()
        if parsed.path == "/api/fixtures":
            # Ensure text fixtures exist
            ensure_fixture_texts()
            data = load_fixtures()
            return self._json(data)
        if parsed.path == "/api/last":
            path = OUT / "last_run.json"
            if not path.exists():
                return self._json({"error": "no run yet"}, 404)
            return self._json(json.loads(path.read_text()))
        if parsed.path == "/api/schema":
            schema_path = ROOT / "ui" / "schema.js"
            # Prefer structured JSON extracted from the JS module constants via static file
            static_schema = ROOT / "ui" / "schema.json"
            if static_schema.exists():
                return self._json(json.loads(static_schema.read_text()))
            return self._json(
                {
                    "source": "schema.jac",
                    "note": "Interactive schema lives in /ui/schema.js",
                    "file": str(schema_path.name),
                }
            )
        return super().do_GET()

    def end_headers(self):
        # Hackathon-friendly: always fetch fresh UI assets
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
                fixture_id=body.get("fixture_id") or "hire",
                proposal=body.get("proposal") or "",
                rounds=int(body.get("rounds") or 5),
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
    """Write fixtures/*.txt so UI works even before Jac dump."""
    fx_dir = ROOT / "fixtures"
    fx_dir.mkdir(exist_ok=True)
    texts = {
        "hire": """DECISION: Hire 3 full-time people this quarter to grow faster.

Business: Bootstrapped SaaS, 4 people, ~$42k MRR, 11 months cash runway.
Tempted move: Hire 3 immediately (2 engineers + 1 AE) to hit a feature + sales push.
Monthly hire cost (fully loaded): ~$32k. Hiring budget this quarter: $96k.
HARD CONSTRAINTS: (1) Do not drop cash runway below 6 months. (2) Quarterly spend on new hires ≤ $96k. (3) Must not freeze product delivery for > 6 weeks during onboarding.
GOAL: Raise MRR ≥ 30% within 2 quarters without a bridge round.""",
    }
    for k, v in texts.items():
        p = fx_dir / f"{k}.txt"
        p.write_text(v)


def main():
    ensure_fixture_texts()
    port = int(os.environ.get("PORT", "8765"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"SplitHorizon UI → http://127.0.0.1:{port}")
    print(f"Jac binary: {JAC_BIN}  JAC_HOME={JAC_HOME}")
    server.serve_forever()


if __name__ == "__main__":
    main()
