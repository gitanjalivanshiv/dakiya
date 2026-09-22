#!/usr/bin/env python3
"""
Drive the Dakiya agent through scripted conversations and check what it says.

Uses `sf agent preview start|send|end --json`, which unlike the interactive
preview TUI needs no terminal, so the agent's behaviour can be regression-tested
rather than spot-checked by hand.

Each scenario runs in a FRESH session, so one test cannot contaminate the next.
Multi-turn scenarios (for example: ask in English, then switch to Hinglish) send
their turns in order within one session, because that is the whole point.

Usage:
    python3 scripts/agent_preview_test.py scenarios.json --org trial3 [--live]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field

CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def sf(args: list[str]) -> dict:
    """Run an sf command and parse its JSON, stripping the control characters
    the CLI mixes into --json output."""
    proc = subprocess.run(args, capture_output=True, text=True)
    raw = CONTROL_CHARS.sub("", proc.stdout)
    start = raw.find("{")
    if start < 0:
        raise RuntimeError(f"no JSON in output: {proc.stdout[:300]} {proc.stderr[:300]}")
    return json.loads(raw[start:])


@dataclass
class Turn:
    say: str
    expect: list[str] = field(default_factory=list)      # all must appear (case-insensitive)
    forbid: list[str] = field(default_factory=list)      # none may appear
    expect_any: list[str] = field(default_factory=list)  # at least one must appear
    note: str = ""


@dataclass
class Result:
    scenario: str
    turn_index: int
    said: str
    reply: str
    failures: list[str]


def check(turn: Turn, reply: str) -> list[str]:
    low = reply.lower()
    problems: list[str] = []
    for needle in turn.expect:
        if needle.lower() not in low:
            problems.append(f"missing {needle!r}")
    for needle in turn.forbid:
        if needle.lower() in low:
            problems.append(f"must NOT contain {needle!r}")
    if turn.expect_any and not any(n.lower() in low for n in turn.expect_any):
        problems.append(f"none of {turn.expect_any} present")
    return problems


def run_scenario(name: str, turns: list[Turn], org: str, bundle: str, live: bool) -> list[Result]:
    mode = "--use-live-actions" if live else "--simulate-actions"
    started = sf([
        "sf", "agent", "preview", "start", "--json",
        "--authoring-bundle", bundle, mode, "-o", org,
    ])
    session_id = started.get("result", {}).get("sessionId")
    if not session_id:
        raise RuntimeError(f"no sessionId: {json.dumps(started)[:400]}")

    results: list[Result] = []
    try:
        for i, turn in enumerate(turns):
            sent = sf([
                "sf", "agent", "preview", "send", "--json",
                "--session-id", session_id,
                "--authoring-bundle", bundle,
                "--utterance", turn.say,
                "-o", org,
            ])
            messages = sent.get("result", {}).get("messages", []) or []
            reply = messages[-1].get("message", "") if messages else ""
            results.append(Result(name, i, turn.say, reply, check(turn, reply)))
    finally:
        subprocess.run(
            ["sf", "agent", "preview", "end", "--json",
             "--session-id", session_id, "--authoring-bundle", bundle, "-o", org],
            capture_output=True, text=True,
        )
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios")
    ap.add_argument("--org", default="trial3")
    ap.add_argument("--bundle", default="Dakiya")
    ap.add_argument("--live", action="store_true", help="run real actions instead of simulated ones")
    ap.add_argument("--only", default=None, help="run one scenario by name substring")
    ap.add_argument("--reset", default=None,
                    help="anonymous Apex file to run before EACH scenario. Write actions mutate "
                         "shared org data, so without this a suite only passes on its first run.")
    args = ap.parse_args()

    spec = json.load(open(args.scenarios))
    scenarios = [s for s in spec["scenarios"]
                 if not args.only or args.only.lower() in s["name"].lower()]

    print(f"\nagent={args.bundle} org={args.org} actions={'LIVE' if args.live else 'simulated'}")
    print(f"scenarios={len(scenarios)}\n")

    all_results: list[Result] = []
    for s in scenarios:
        if args.reset:
            rc = subprocess.run(
                ["sf", "apex", "run", "-o", args.org, "-f", args.reset],
                capture_output=True, text=True,
            )
            if rc.returncode != 0:
                print(f"  ERROR  reset failed before {s['name']}: {rc.stderr[:200]}")
                continue
        turns = [Turn(**t) for t in s["turns"]]
        try:
            rs = run_scenario(s["name"], turns, args.org, args.bundle, args.live)
        except Exception as e:  # a broken session must not hide the other scenarios
            print(f"  ERROR  {s['name']}: {e}")
            all_results.append(Result(s["name"], 0, "", "", [f"harness error: {e}"]))
            continue
        all_results.extend(rs)

        ok = all(not r.failures for r in rs)
        print(f"  {'PASS ' if ok else 'FAIL '} {s['name']}")
        for r in rs:
            flag = "   " if not r.failures else "  !"
            print(f"{flag}   > {r.said}")
            print(f"{flag}   < {r.reply[:300]}{'...' if len(r.reply) > 300 else ''}")
            for f in r.failures:
                print(f"       ^ {f}")
        print()

    failed = [r for r in all_results if r.failures]
    total = len({(r.scenario) for r in all_results})
    bad = len({r.scenario for r in failed})
    print(f"{'-' * 60}\nscenarios: {total}   failing: {bad}\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
