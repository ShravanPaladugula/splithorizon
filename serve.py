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
    # Prefer Jac fixtures via a tiny runner; fallback to reading cache titles + embedded texts
    fixtures_path = ROOT / "fixtures.jac"
    # Static mirror for the UI (kept in sync with fixtures.jac)
    static = [
        {
            "id": "logistics",
            "name": "Defense / Logistics — Convoy Reroute",
            "proposal": (ROOT / "fixtures" / "logistics.txt").read_text()
            if (ROOT / "fixtures" / "logistics.txt").exists()
            else "",
        },
        {
            "id": "fintech",
            "name": "Fintech — Suspicious Wire Hold vs Clear",
            "proposal": (ROOT / "fixtures" / "fintech.txt").read_text()
            if (ROOT / "fixtures" / "fintech.txt").exists()
            else "",
        },
        {
            "id": "shelter",
            "name": "Social Impact — Shelter Bed Allocation",
            "proposal": (ROOT / "fixtures" / "shelter.txt").read_text()
            if (ROOT / "fixtures" / "shelter.txt").exists()
            else "",
        },
    ]
    # Fill from jac fixtures dump if texts empty — parse cache world titles only as last resort
    if not static[0]["proposal"]:
        # Read proposal strings from fixtures.jac via run
        pass
    _ = fixtures_path
    return static


def run_engine(fixture_id: str, proposal: str, rounds: int = 3, baseline: bool = True) -> dict:
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
        return super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/run":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        try:
            result = run_engine(
                fixture_id=body.get("fixture_id") or "logistics",
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
    """Write fixtures/*.txt from fixtures.jac constants via a one-liner if missing."""
    fx_dir = ROOT / "fixtures"
    fx_dir.mkdir(exist_ok=True)
    # Embedded copies so UI works even before Jac dump
    texts = {
        "logistics": """PROPOSAL: Reroute Supply Convoy Alpha through Highway 9 under fog advisory.

Context: Forward operating base needs medical and fuel resupply within 18 hours.
Current plan: Take the shortest paved route (Highway 9) through the river choke-point.
Budget: $85,000 for escort, fuel, and contingency.
Assets: 4 trucks (capacity 12 tons), 1 escort unit, limited ISR coverage in fog.
Constraints (HARD): (1) Do not exceed $85k. (2) Do not transit choke-point without overwatch if fog visibility < 200m. (3) Delivery SLA 18h.
Goal: Deliver ≥90% of medical cargo intact before SLA.""",
        "fintech": """PROPOSAL: Clear a $240,000 outbound wire flagged as medium-risk to meet client SLA.

Context: Corporate client needs same-day settlement. Fraud model score 0.62 (medium).
Ops proposes: Clear now; investigate after posting to avoid SLA breach.
Budget/risk limit: Expected fraud loss tolerance $50,000 for this corridor.
Constraints (HARD): (1) SLA clearance within 2 hours from flag. (2) Must not clear if fused fraud risk > 0.80. (3) Manual hold allowed but burns SLA.
Goal: Minimize fraud loss while keeping SLA breach rate under policy.""",
        "shelter": """PROPOSAL: Allocate all 40 remaining shelter beds to the first-arrived queue tonight.

Context: Cold weather surge. 58 people in queue. Equity policy requires proportional access for families with children and disability-priority clients.
Budget for overflow hotel vouchers: $12,000.
Constraints (HARD): (1) Physical capacity 40 beds. (2) Equity score must remain ≥ 0.70. (3) Overflow spend ≤ $12k.
Goal: Shelter the highest-need clients without collapsing equity or capacity.""",
    }
    for k, v in texts.items():
        p = fx_dir / f"{k}.txt"
        if not p.exists():
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
