#!/usr/bin/env python3
"""Moneypenny eval (2026-10-03): asks each question in Evals/moneypenny-eval.json through the
app's sandbox-only test link, then grades her answer by code:

  path            "instant" = answered by code (no AI call), "ai" = went through the model
  card            the pop-up card's title
  action_contains text that must appear in what she did on screen
  say_contains    text that must all appear in what she said
  say_any         at least one of these must appear
  figures_verified every dollar figure she says must appear in September's verified facts
                  (Regression/<realm>-2026-09.json) - catches invented numbers

Prints a score, writes Evals/results/<timestamp>.json, and appends a line to Evals/history.tsv so
each run shows up or down against the last. Usage: Scripts/eval-moneypenny.py [--fast] [--only id,id]
(--fast skips AI cases, ~30s each). The app must be running on the sandbox company.
"""
import json, os, re, sqlite3, subprocess, sys, time, urllib.parse
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DESKTOP = os.path.dirname(HERE)
REALM = "9341456442848752"
DB = os.path.expanduser(f"~/Library/Application Support/VoiceLedger/{REALM}/store.sqlite")
EVAL = os.path.join(DESKTOP, "Evals", "moneypenny-eval.json")
FACTS = os.path.join(DESKTOP, "Regression", f"{REALM}-2026-09.json")
MONEY = re.compile(r"\(?\$[\d,]+\.\d{2}\)?")


def entries():
    con = sqlite3.connect(DB)
    row = con.execute("select value from kv where key='voice-transcript'").fetchone()
    con.close()
    return json.loads(row[0]) if row else []


def ask(question, timeout):
    """Send one question; return its COMMAND RESULT fields and seconds taken, or None on timeout."""
    before = max([e.get("timestamp", 0) for e in entries()] or [0])
    subprocess.run(["open", "voiceledger-dev://ask?silent=1&q=" + urllib.parse.quote(question)], check=True)
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(0.7)
        new = [e for e in entries() if e.get("timestamp", 0) > before and e.get("speaker") == "assistant"
               and e.get("text", "").startswith("COMMAND RESULT")]
        if new:
            fields, key = {}, None
            for line in new[-1]["text"].split("\n")[1:]:
                m = re.match(r"^(HEARD|SOURCE|PATH|ACTION|RESPONSE): ?(.*)$", line)
                if m:
                    key = m.group(1); fields[key] = m.group(2)
                elif key == "RESPONSE":
                    fields[key] += "\n" + line
            return fields, time.time() - start
    return None, timeout


def verified_figures():
    """Every dollar amount September's verified facts contain (facts, findings, diagnosis)."""
    text = open(FACTS).read()
    return {m.strip("()") for m in MONEY.findall(text)}


def grade(case, fields, allowed):
    problems = []
    if fields is None:
        return ["no answer (timed out)"]
    say, action = fields.get("RESPONSE", ""), fields.get("ACTION", "")
    if case.get("path") and fields.get("PATH") != case["path"]:
        problems.append(f"path {fields.get('PATH')!r}, expected {case['path']!r}")
    if case.get("card") and f"card: {case['card']}" not in action:
        problems.append(f"card {case['card']!r} not shown ({action})")
    for t in case.get("action_contains", []):
        if t not in action:
            problems.append(f"action lacks {t!r}")
    for t in case.get("say_contains", []):
        if t not in say:
            problems.append(f"answer lacks {t!r}")
    if case.get("say_any") and not any(t.lower() in say.lower() for t in case["say_any"]):
        problems.append(f"answer has none of {case['say_any']}")
    if case.get("figures_verified"):
        unverified = sorted({m.strip("()") for m in MONEY.findall(say)} - allowed)
        if unverified:
            problems.append(f"unverified figures {unverified}")
    return problems


def main():
    fast = "--fast" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    spec = json.load(open(EVAL))
    cases = [c for c in spec["cases"] if (not fast or c.get("path") != "ai") and (only is None or c["id"] in only)]
    allowed = verified_figures()

    print(f"Moneypenny eval: {len(cases)} cases" + (" (fast: AI cases skipped)" if fast else ""))
    ask(spec["period"], 30)          # make sure the app reviews September
    time.sleep(40)                   # the month switch re-syncs

    results = []
    for case in cases:
        fields, secs = ask(case["ask"], 120 if case.get("path") == "ai" else 45)
        problems = grade(case, fields, allowed)
        results.append({"id": case["id"], "ask": case["ask"], "pass": not problems, "problems": problems,
                        "seconds": round(secs, 1), "answer": (fields or {}).get("RESPONSE", ""), "action": (fields or {}).get("ACTION", "")})
        print(f"  {'PASS' if not problems else 'FAIL'}  {case['id']:<32} {secs:5.1f}s" + ("" if not problems else "  " + "; ".join(problems)))

    passed = sum(r["pass"] for r in results)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=DESKTOP, capture_output=True, text=True).stdout.strip()
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    hist = os.path.join(DESKTOP, "Evals", "history.tsv")
    previous = None
    if os.path.exists(hist):
        rows = [l.split("\t") for l in open(hist).read().splitlines()[1:] if l.strip()]
        same = [r for r in rows if r[3] == ("fast" if fast else "full")]
        if same: previous = same[-1][2]
    else:
        open(hist, "w").write("when\tcommit\tscore\tmode\n")
    open(hist, "a").write(f"{stamp}\t{commit}\t{passed}/{len(results)}\t{'fast' if fast else 'full'}\n")
    os.makedirs(os.path.join(DESKTOP, "Evals", "results"), exist_ok=True)
    json.dump({"when": stamp, "commit": commit, "score": f"{passed}/{len(results)}", "results": results},
              open(os.path.join(DESKTOP, "Evals", "results", datetime.now().strftime("%Y%m%d-%H%M%S") + ".json"), "w"), indent=2)
    print(f"\nScore: {passed}/{len(results)}" + (f" (last {'fast' if fast else 'full'} run: {previous})" if previous else ""))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
