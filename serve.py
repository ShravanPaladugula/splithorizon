#!/usr/bin/env python3
"""Thin UI bridge for SplitHorizon — shells out to Jac."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

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
            os.environ[_k.strip()] = _v.strip().strip('"').strip("'")
JAC_BIN = os.environ.get("JAC_BIN", str(Path.home() / ".local/bin/jac"))
if not Path(JAC_BIN).exists():
    JAC_BIN = "jac"
JAC_HOME = os.environ.get("JAC_HOME", "/tmp/jac_home")


def jac_env() -> dict:
    env = os.environ.copy()
    # Graph memory is per-project so walkers only see this app's OSP nodes. HOME is left
    # alone on purpose: the jac runtime (and the litellm that `jac install` syncs into it)
    # is cached under the real $HOME, and overriding it hides the LLM capability.
    run_home = ROOT / ".jac" / "run_home"
    run_home.mkdir(parents=True, exist_ok=True)
    env["JAC_HOME"] = str(run_home)
    env["PATH"] = str(Path(JAC_BIN).parent) + os.pathsep + env.get("PATH", "")
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


def run_jac_snippet(code: str, timeout: int = 90) -> str:
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


def run_intake(plan: str, answers: dict, modules: list | None = None) -> dict:
    OUT.mkdir(exist_ok=True)
    code = f"""include intake;
import json;
import os;

with entry {{
    plan = {json.dumps(plan)};
    answers = {json.dumps(answers)};
    modules = {json.dumps(modules or [])};
    result = next_intake_questions(plan, answers, modules);
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
    areas: list | None = None,
) -> dict:
    OUT.mkdir(exist_ok=True)
    company = company or {}
    areas = areas or []
    path = OUT / "last_run.json"
    if path.exists():
        path.unlink()
    # Cap depth so fork trees stay responsive.
    rounds = max(1, min(int(rounds or 3), 4))
    runner = ROOT / "run_once.jac"
    runner.write_text(
        "include agents;\ninclude fixtures;\nimport json;\nimport os;\n\n"
        "with entry {\n"
        f"    fid = {json.dumps(fixture_id)};\n"
        f"    text = {json.dumps(proposal)};\n"
        f"    company = {json.dumps(company)};\n"
        f"    areas = {json.dumps(areas)};\n"
        "    if not text {\n"
        "        fx = get_fixture(fid);\n"
        "        if fx { text = str(fx[\"proposal\"]); }\n"
        "    }\n"
        "    root spawn ProtocolWalker(\n"
        "        proposal=text,\n"
        "        fixture_id=fid,\n"
        f"        rounds={rounds},\n"
        f"        baseline={str(baseline)},\n"
        "        company_json=json.dumps(company),\n"
        "        areas_json=json.dumps(areas)\n"
        "    );\n"
        "    print(\"OK\");\n"
        "}\n"
    )
    env = jac_env()
    # Every Blue move, Red attack and the arbiter memo is a live model call, so a
    # 4-round fork is ~15 sequential round trips. Give it room.
    proc = subprocess.run(
        [JAC_BIN, "run", str(runner)],
        cwd=str(ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=420,
    )
    if path.exists():
        return json.loads(path.read_text())
    err = (proc.stderr or proc.stdout or f"jac exited {proc.returncode}").strip()
    # Collapse repeated byllm ERROR lines into one readable message.
    if "litellm" in err.lower() or "Capability 'llm'" in err:
        raise RuntimeError(
            "LLM runtime missing. Run `jac install` in the project, then retry."
        )
    if "failed after" in err and "attempts via" in err:
        # Surface the model failure verbatim — never quietly substitute canned advice.
        line = next((l for l in err.splitlines() if "attempts via" in l), err[:300])
        raise RuntimeError(f"Groq call failed, so no answer was generated: {line.strip()}")
    raise RuntimeError(err[:800] if err else f"jac exited {proc.returncode}")


EVENT_KINDS = {"seed", "blue", "red", "arbiter", "walker", "prune", "halt"}


def _write_runner(fixture_id: str, proposal: str, rounds: int, baseline: bool, company: dict, areas: list) -> Path:
    runner = ROOT / "run_once.jac"
    runner.write_text(
        "include agents;\ninclude fixtures;\nimport json;\nimport os;\n\n"
        "with entry {\n"
        f"    fid = {json.dumps(fixture_id)};\n"
        f"    text = {json.dumps(proposal)};\n"
        f"    company = {json.dumps(company)};\n"
        f"    areas = {json.dumps(areas)};\n"
        "    if not text {\n"
        "        fx = get_fixture(fid);\n"
        "        if fx { text = str(fx[\"proposal\"]); }\n"
        "    }\n"
        "    root spawn ProtocolWalker(\n"
        "        proposal=text,\n"
        "        fixture_id=fid,\n"
        f"        rounds={rounds},\n"
        f"        baseline={str(baseline)},\n"
        "        company_json=json.dumps(company),\n"
        "        areas_json=json.dumps(areas)\n"
        "    );\n"
        "    print(\"OK\");\n"
        "}\n"
    )
    return runner


def stream_engine(fixture_id, proposal, rounds=3, baseline=True, company=None, areas=None):
    """Run the protocol, yielding (event_name, payload) as the walker prints progress.

    Every Blue/Red/arbiter draft is a sequential model call, so the only honest
    progress signal is the engine's own log lines. We forward them live.
    """
    company = company or {}
    areas = areas or []
    rounds = max(1, min(int(rounds or 3), 4))
    path = OUT / "last_run.json"
    OUT.mkdir(exist_ok=True)
    if path.exists():
        path.unlink()

    runner = _write_runner(fixture_id, proposal, rounds, baseline, company, areas)
    env = jac_env()
    env["PYTHONUNBUFFERED"] = "1"

    # Round 1 forks two rival strategies, later rounds one per surviving leaf,
    # plus a Red probe each; then the baseline foil and the arbiter memo.
    expected = 4 * rounds + 2
    yield "start", {"expected_steps": expected, "rounds": rounds}

    proc = subprocess.Popen(
        [JAC_BIN, "run", str(runner)],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    done = 0
    tail: list[str] = []
    try:
        for raw in proc.stdout:
            line = raw.rstrip("\n")
            tail.append(line)
            if len(tail) > 40:
                tail.pop(0)
            if not line.startswith("["):
                continue
            kind, _, rest = line[1:].partition("] ")
            kind = kind.strip()
            msg = rest.strip()
            if kind == "step":
                yield "step", {"message": msg, "done": done, "expected": expected}
            elif kind in EVENT_KINDS:
                done += 1
                yield "event", {"kind": kind, "message": msg, "done": done, "expected": expected}
            elif kind == "SplitHorizon" and "rate-limited" in msg:
                secs = re.search(r"waiting (\d+)s", msg)
                yield "wait", {
                    "message": f"Groq rate limit — pausing {secs.group(1) if secs else 'a few'}s before retry",
                    "seconds": int(secs.group(1)) if secs else 0,
                }
    finally:
        proc.wait()

    if path.exists():
        yield "done", json.loads(path.read_text())
        return
    err = "\n".join(tail).strip()
    if "attempts:" in err:
        line = next((l for l in tail if "attempts:" in l), err[-300:])
        yield "error", {"error": f"Groq call failed, so no answer was generated: {line.strip()[:400]}"}
    else:
        yield "error", {"error": (err[-600:] or f"jac exited {proc.returncode}")}


PROFILES = ROOT / "profiles.json"


def _now_iso() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _slug(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")[:40]
    return s or "biz"


def _new_id(name: str = "") -> str:
    import uuid

    return f"{_slug(name)}-{uuid.uuid4().hex[:6]}"


def _write_profiles(profiles: list[dict]) -> None:
    PROFILES.write_text(json.dumps(profiles[:20], indent=2))


def load_profiles() -> list[dict]:
    if PROFILES.exists():
        try:
            profiles = json.loads(PROFILES.read_text())
        except json.JSONDecodeError:
            profiles = []
    else:
        profiles = []
    if not isinstance(profiles, list):
        profiles = []
    changed = False
    for p in profiles:
        if not isinstance(p, dict):
            continue
        if not p.get("id"):
            p["id"] = _new_id(str(p.get("name") or ""))
            changed = True
        if "chats" not in p or not isinstance(p.get("chats"), list):
            p["chats"] = []
            changed = True
    if changed and profiles:
        _write_profiles(profiles)
    return profiles


def find_profile(business_id: str | None = None, name: str | None = None) -> dict | None:
    profiles = load_profiles()
    if business_id:
        for p in profiles:
            if p.get("id") == business_id:
                return p
    if name:
        n = name.strip().lower()
        for p in profiles:
            if str(p.get("name") or "").lower() == n:
                return p
    return None


def save_profile(profile: dict) -> dict:
    """Upsert business profile. Preserves chats / id across form saves."""
    profiles = load_profiles()
    name = (profile.get("name") or "").strip()
    if not name:
        raise ValueError("Business name is required")
    existing = None
    pid = (profile.get("id") or "").strip()
    if pid:
        existing = next((p for p in profiles if p.get("id") == pid), None)
    if existing is None:
        existing = next((p for p in profiles if str(p.get("name") or "").lower() == name.lower()), None)

    chats = list(existing.get("chats") or []) if existing else list(profile.get("chats") or [])
    out = dict(profile)
    out["name"] = name
    out["id"] = (existing or {}).get("id") or pid or _new_id(name)
    out["chats"] = chats
    out["updated_at"] = _now_iso()
    if existing and existing.get("created_at"):
        out["created_at"] = existing["created_at"]
    else:
        out.setdefault("created_at", _now_iso())

    profiles = [p for p in profiles if p.get("id") != out["id"]]
    profiles.insert(0, out)
    _write_profiles(profiles)
    return out


def delete_profile(business_id: str = "", name: str = "") -> list[dict]:
    business_id = (business_id or "").strip()
    name = (name or "").strip().lower()
    if not business_id and not name:
        raise ValueError("Business id or name is required")
    profiles = load_profiles()
    before = len(profiles)
    kept: list[dict] = []
    for p in profiles:
        pid = str(p.get("id") or "")
        pname = str(p.get("name") or "").strip().lower()
        if business_id and pid == business_id:
            continue
        if name and pname == name:
            continue
        kept.append(p)
    if len(kept) == before:
        raise ValueError("Business not found")
    _write_profiles(kept)
    return kept


def append_chat(business_id: str = "", chat: dict | None = None, name: str = "") -> dict:
    import uuid

    profiles = load_profiles()
    target = None
    business_id = (business_id or "").strip()
    name = (name or "").strip().lower()
    if business_id:
        target = next((p for p in profiles if p.get("id") == business_id), None)
    if target is None and name:
        target = next((p for p in profiles if str(p.get("name") or "").lower() == name), None)
    if not target:
        raise ValueError("Business not found")
    entry = dict(chat or {})
    entry["id"] = entry.get("id") or f"chat_{uuid.uuid4().hex[:8]}"
    entry["created_at"] = entry.get("created_at") or _now_iso()
    outcome = entry.get("outcome") if isinstance(entry.get("outcome"), dict) else {}
    entry["outcome"] = {
        "went_through": outcome.get("went_through", None),
        "note": str(outcome.get("note") or ""),
        "decided_at": outcome.get("decided_at"),
    }
    chats = list(target.get("chats") or [])
    chats.insert(0, entry)
    target["chats"] = chats[:40]
    target["updated_at"] = _now_iso()
    _write_profiles(profiles)
    return {"profile": target, "chat": entry}


def set_chat_outcome(business_id: str = "", chat_id: str = "", went_through=None, note: str = "", name: str = "") -> dict:
    profiles = load_profiles()
    target = None
    business_id = (business_id or "").strip()
    name = (name or "").strip().lower()
    chat_id = (chat_id or "").strip()
    if business_id:
        target = next((p for p in profiles if p.get("id") == business_id), None)
    if target is None and name:
        target = next((p for p in profiles if str(p.get("name") or "").lower() == name), None)
    if not target:
        raise ValueError("Business not found")
    if not chat_id:
        raise ValueError("Chat id is required")
    chat = next((c for c in (target.get("chats") or []) if c.get("id") == chat_id), None)
    if not chat:
        raise ValueError("Chat not found")
    if went_through is not None and not isinstance(went_through, bool):
        if str(went_through).lower() in ("1", "true", "yes", "y"):
            went_through = True
        elif str(went_through).lower() in ("0", "false", "no", "n"):
            went_through = False
        else:
            went_through = None
    chat["outcome"] = {
        "went_through": went_through,
        "note": str(note or ""),
        "decided_at": _now_iso() if went_through is not None else None,
    }
    target["updated_at"] = _now_iso()
    _write_profiles(profiles)
    return {"profile": target, "chat": chat}


class _SiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.title_parts: list[str] = []
        self.in_title = False
        self.meta: dict[str, str] = {}
        self.paras: list[str] = []
        self.in_p = False
        self._pbuf: list[str] = []
        self._skip = False

    def handle_starttag(self, tag, attrs):
        attrs_d = dict(attrs)
        if tag == "title":
            self.in_title = True
        elif tag == "meta":
            key = (attrs_d.get("name") or attrs_d.get("property") or "").lower()
            content = (attrs_d.get("content") or "").strip()
            if key and content:
                self.meta[key] = content
        elif tag in ("script", "style", "noscript"):
            self._skip = True
        elif tag == "p" and len(self.paras) < 6:
            self.in_p = True
            self._pbuf = []

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        elif tag in ("script", "style", "noscript"):
            self._skip = False
        elif tag == "p" and self.in_p:
            self.in_p = False
            text = re.sub(r"\s+", " ", "".join(self._pbuf)).strip()
            if len(text) > 40:
                self.paras.append(text)

    def handle_data(self, data):
        if self._skip:
            return
        if self.in_title:
            self.title_parts.append(data)
        if self.in_p:
            self._pbuf.append(data)


def _clean_url(raw: str) -> str:
    url = (raw or "").strip()
    if not url:
        raise ValueError("Website URL is required")
    if not re.match(r"^https?://", url, re.I):
        url = "https://" + url
    parsed = urlparse(url)
    if not parsed.netloc or "." not in parsed.netloc:
        raise ValueError("That does not look like a website URL")
    return url


def scan_website(url: str) -> dict:
    """Fetch a public page and extract title / meta / blurb for the business profile."""
    import ssl

    url = _clean_url(url)
    req = Request(
        url,
        headers={
            "User-Agent": "SplitHorizonBot/1.0 (+local founder simulator)",
            "Accept": "text/html,application/xhtml+xml",
        },
        method="GET",
    )
    raw = b""
    final_url = url
    charset = "utf-8"
    last_err: Exception | None = None
    for ctx in (ssl.create_default_context(), ssl._create_unverified_context()):
        try:
            with urlopen(req, timeout=12, context=ctx) as resp:
                charset = resp.headers.get_content_charset() or "utf-8"
                raw = resp.read(450_000)
                final_url = resp.geturl()
            last_err = None
            break
        except Exception as e:  # noqa: BLE001
            last_err = e
            continue
    if last_err is not None and not raw:
        raise RuntimeError(f"Could not reach site: {last_err}") from last_err

    html = raw.decode(charset, errors="ignore")
    parser = _SiteParser()
    try:
        parser.feed(html)
    except Exception:
        pass

    title = re.sub(r"\s+", " ", "".join(parser.title_parts)).strip()
    desc = (
        parser.meta.get("description")
        or parser.meta.get("og:description")
        or parser.meta.get("twitter:description")
        or ""
    ).strip()
    site_name = (parser.meta.get("og:site_name") or "").strip()
    og_title = (parser.meta.get("og:title") or "").strip()
    if og_title and (not title or len(og_title) > len(title)):
        title = og_title

    blurb_bits = []
    if desc:
        blurb_bits.append(desc)
    for p in parser.paras[:3]:
        if p.lower() not in (desc.lower() if desc else ""):
            blurb_bits.append(p)
    summary = " ".join(blurb_bits)
    summary = re.sub(r"\s+", " ", summary).strip()
    if len(summary) > 520:
        summary = summary[:517].rstrip() + "…"
    if not summary:
        summary = title or f"Website at {urlparse(final_url).netloc}"

    # Lightweight product guess from title + summary keywords
    blob = f"{title} {summary}".lower()
    if any(k in blob for k in ("saas", "software", "platform", "api", "app")):
        product = "software / SaaS product"
    elif any(k in blob for k in ("marketplace", "ecommerce", "shop", "store")):
        product = "marketplace / commerce"
    elif any(k in blob for k in ("agency", "consult", "studio")):
        product = "services / agency"
    elif any(k in blob for k in ("ai", "ml", "model", "agent")):
        product = "AI / ML product"
    else:
        product = "startup product"

    describe = desc or summary.split(".")[0].strip()
    if describe and not describe.endswith("."):
        describe += "."
    if len(describe) > 220:
        describe = describe[:217].rstrip() + "…"

    return {
        "url": final_url,
        "title": title or site_name or urlparse(final_url).netloc,
        "site_name": site_name,
        "description": desc,
        "summary": summary,
        "describe": describe,
        "product_guess": product,
        "scanned_at": __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


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
        if parsed.path == "/api/profiles":
            return self._json(load_profiles())
        if parsed.path.startswith("/api/profiles/"):
            pid = parsed.path[len("/api/profiles/") :].strip("/")
            if pid:
                found = find_profile(business_id=pid)
                if not found:
                    return self._json({"error": "Business not found"}, 404)
                return self._json(found)
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

    def do_DELETE(self):
        parsed = urlparse(self.path)
        try:
            if parsed.path.startswith("/api/profiles/"):
                pid = parsed.path[len("/api/profiles/") :].strip("/")
                if not pid:
                    return self._json({"error": "Business id required"}, 400)
                profiles = delete_profile(business_id=pid)
                return self._json({"ok": True, "profiles": profiles})
            self.send_error(404)
        except ValueError as e:
            self._json({"error": str(e)}, 400)
        except Exception as e:  # noqa: BLE001
            self._json({"error": str(e)}, 500)

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        try:
            if parsed.path == "/api/intake":
                return self._json(
                    run_intake(
                        plan=body.get("plan") or "",
                        answers=body.get("answers") or {},
                        modules=body.get("modules") or [],
                    )
                )
            if parsed.path == "/api/profiles":
                saved = save_profile(body)
                return self._json({"ok": True, "profile": saved, "profiles": load_profiles()})
            if parsed.path == "/api/profiles/delete":
                profiles = delete_profile(
                    business_id=body.get("id") or body.get("business_id") or "",
                    name=body.get("name") or "",
                )
                return self._json({"ok": True, "profiles": profiles})
            if parsed.path == "/api/chats":
                chat = body.get("chat")
                if not isinstance(chat, dict):
                    chat = {k: v for k, v in body.items() if k not in ("business_id", "id", "name")}
                return self._json(
                    append_chat(
                        business_id=body.get("business_id") or body.get("id") or "",
                        chat=chat,
                        name=body.get("name") or "",
                    )
                )
            if parsed.path == "/api/chats/outcome":
                return self._json(
                    set_chat_outcome(
                        business_id=body.get("business_id") or "",
                        chat_id=body.get("chat_id") or "",
                        went_through=body.get("went_through"),
                        note=body.get("note") or "",
                        name=body.get("name") or "",
                    )
                )
            if parsed.path == "/api/scan-site":
                return self._json(scan_website(body.get("url") or body.get("website") or ""))
            if parsed.path == "/api/run":
                return self._json(
                    run_engine(
                        fixture_id=body.get("fixture_id") or "interlock",
                        proposal=body.get("proposal") or "",
                        rounds=int(body.get("rounds") or 3),
                        baseline=bool(body.get("baseline", True)),
                        company=body.get("company") or {},
                        areas=body.get("areas") or body.get("modules") or [],
                    )
                )
            self.send_error(404)
        except ValueError as e:
            self._json({"error": str(e)}, 400)
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
