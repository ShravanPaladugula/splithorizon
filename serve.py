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

# Load .env (OPENAI_API_KEY, SPLITHORIZON_LIVE, ...) so live LLM mode
# only requires dropping a key into splithorizon/.env and restarting.
_env_file = ROOT / ".env"
if _env_file.exists():
    for _line in _env_file.read_text().splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))
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
    interlock = (
        (ROOT / "fixtures" / "interlock.txt").read_text()
        if (ROOT / "fixtures" / "interlock.txt").exists()
        else "DECISION: Should we hire two engineers to hit the October launch?"
    )
    return [
        {
            "id": "interlock",
            "name": "Interlock — Hire two engineers to hit October launch?",
            "proposal": interlock,
        },
        {"id": "hire", "name": "Hiring", "proposal": "DECISION: Two engineers now, or one plus a contractor?"},
        {"id": "launch", "name": "Launch", "proposal": "DECISION: Should we ship on October 3rd?"},
        {"id": "runway", "name": "Runway", "proposal": "DECISION: How long do we have, when do we start raising?"},
    ]


def run_jac_snippet(code: str, timeout: int = 60) -> str:
    path = ROOT / "run_tmp.jac"
    path.write_text(code)
    proc = subprocess.run(
        [JAC_BIN, "run", str(path)],
        cwd=str(ROOT),
        env=jac_env(),
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or f"jac exited {proc.returncode}")
    return proc.stdout


def run_intake(plan: str, answers: dict) -> dict:
    OUT.mkdir(exist_ok=True)
    code = f"""include intake;
import json;
import os;

with entry {{
    plan = {json.dumps(plan)};
    answers = {json.dumps(answers)};
    result = next_intake_questions(plan, answers);
    os.makedirs("out", exist_ok=True);
    with open("out/last_intake.json", "w") as f {{
        json.dump(result, f, indent=2);
    }}
    print("OK");
}}
"""
    run_jac_snippet(code)
    return json.loads((OUT / "last_intake.json").read_text())


def run_engine(
    fixture_id: str,
    proposal: str,
    rounds: int = 3,
    baseline: bool = True,
    company: dict | None = None,
) -> dict:
    OUT.mkdir(exist_ok=True)
    company = company or {}
    runner = ROOT / "run_once.jac"
    runner.write_text(
        "include engine;\ninclude fixtures;\nimport json;\nimport os;\n\n"
        "with entry {\n"
        f"    fid = {json.dumps(fixture_id)};\n"
        f"    text = {json.dumps(proposal)};\n"
        f"    company = {json.dumps(company)};\n"
        "    if not text {\n"
        "        fx = get_fixture(fid);\n"
        "        if fx { text = str(fx[\"proposal\"]); }\n"
        "    }\n"
        f"    result = run_protocol(text, fid, {int(rounds)}, {str(baseline)}, company);\n"
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
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        try:
            if parsed.path == "/api/intake":
                return self._json(
                    run_intake(plan=body.get("plan") or "", answers=body.get("answers") or {})
                )
            if parsed.path == "/api/run":
                return self._json(
                    run_engine(
                        fixture_id=body.get("fixture_id") or "interlock",
                        proposal=body.get("proposal") or "",
                        rounds=int(body.get("rounds") or 3),
                        baseline=bool(body.get("baseline", True)),
                        company=body.get("company") or {},
                    )
                )
            self.send_error(404)
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
    p = fx / "interlock.txt"
    if not p.exists():
        p.write_text(
            "DECISION: Should we hire two engineers to hit the October launch?\n\n"
            "Company: Northline seed state.\n"
            "Tempted move: Hire two FTEs now so October 3 still lands.\n"
            "Counter-move: One engineer + contractor.\n"
            "Spine: cash-out date vs milestone.\n"
        )


def main():
    ensure_fixture_texts()
    port = int(os.environ.get("PORT", "8765"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"SplitHorizon UI → http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
