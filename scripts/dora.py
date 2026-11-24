#!/usr/bin/env python3
"""DORA metrics and pipeline KPIs of MicroCRM, computed from the GitHub Actions history (read-only).

Usage:  scripts/dora.py [--repo M0l42/P7-FSJA]
Needs:  the GitHub CLI (gh), logged in. Only reads public data (workflow runs, jobs, pull requests).

Definitions (documented in docs/documentation-technique.md, section 6):
  Deployment            = a successful run of the CD job on main: images published to GHCR, ready to pull.
  Deployment frequency  = deployments per day over the observed period.
  Lead time for changes = for each merged pull request: its first commit -> first deployment that contains it.
  Scope                 = from the first CD run on main (before it, nothing could be deployed).
  Change failure rate   = pipeline runs on main (push) that failed after a merge / all such runs.
  Time to restore       = for each failed run on main: its end -> end of the next successful run on main.
  K1 CI duration        = duration of the CI run of each pull request (with back, front and sonar job durations).
  K2 Quality gate       = share of pull request runs whose SonarQube job (quality gate) passed.
"""
import argparse
import json
import re
import statistics
import subprocess
from datetime import datetime

CD_JOB = "CD / Build, test, scan and publish images"


def gh(path):
    out = subprocess.run(["gh", "api", "--paginate", path], check=True, capture_output=True, text=True).stdout
    # --paginate concatenates JSON documents: decode them one after the other
    dec, i, docs = json.JSONDecoder(), 0, []
    while i < len(out):
        while i < len(out) and out[i].isspace():
            i += 1
        if i >= len(out):
            break
        obj, i = dec.raw_decode(out, i)
        docs.append(obj)
    return docs


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def hours(delta):
    return delta.total_seconds() / 3600


def fmt_h(h):
    return f"{h * 60:.0f} min" if h < 1 else f"{h:.1f} h"


def summary(values):
    if not values:
        return "n/a"
    return f"median {fmt_h(statistics.median(values))}, min {fmt_h(min(values))}, max {fmt_h(max(values))} (n={len(values)})"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default="M0l42/P7-FSJA")
    args = ap.parse_args()
    # The repository becomes part of the gh command: accept only the "owner/name" form (no option injection)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        ap.error("--repo must be of the form owner/name")
    repo = args.repo

    runs = [r for page in gh(f"repos/{repo}/actions/workflows/ci.yml/runs?per_page=100") for r in page["workflow_runs"]]
    runs = [r for r in runs if r["status"] == "completed" and r["conclusion"] != "cancelled"]

    def jobs(run):
        return [j for page in gh(f"repos/{repo}/actions/runs/{run['id']}/jobs?per_page=100") for j in page["jobs"]]

    # ---- deployments and main pipeline health (push on main)
    main_runs = sorted([r for r in runs if r["head_branch"] == "main" and r["event"] == "push"], key=lambda r: r["created_at"])
    deployments, cd_attempts, first_cd = [], 0, None
    for r in main_runs:
        cd = next((j for j in jobs(r) if j["name"] == CD_JOB), None)
        if cd and cd["conclusion"] in ("success", "failure"):
            cd_attempts += 1
            first_cd = first_cd or ts(r["created_at"])
            if cd["conclusion"] == "success":
                deployments.append({"sha": r["head_sha"], "at": ts(cd["completed_at"])})
        r["_end"] = ts(r["updated_at"])
    # DORA measures a delivery pipeline: only the period since the CD workflow exists is considered
    main_runs = [r for r in main_runs if first_cd and ts(r["created_at"]) >= first_cd]

    failed = [r for r in main_runs if r["conclusion"] == "failure"]
    restore = []
    for f in failed:
        nxt = next((r for r in main_runs if r["created_at"] > f["created_at"] and r["conclusion"] == "success"), None)
        if nxt:
            restore.append(hours(nxt["_end"] - f["_end"]))

    # ---- lead time: merged pull requests -> first deployment after the merge
    prs = [p for page in gh(f"repos/{repo}/pulls?state=closed&per_page=100") for p in page
           if p.get("merged_at") and first_cd and ts(p["merged_at"]) >= first_cd]
    lead, merge_to_deploy = [], []
    for p in prs:
        merged = ts(p["merged_at"])
        dep = next((d for d in sorted(deployments, key=lambda d: d["at"]) if d["at"] >= merged), None)
        if not dep:
            continue
        commits = [c for page in gh(f"repos/{repo}/pulls/{p['number']}/commits?per_page=100") for c in page]
        first = min(ts(c["commit"]["author"]["date"]) for c in commits) if commits else merged
        lead.append(hours(dep["at"] - first))
        merge_to_deploy.append(hours(dep["at"] - merged))

    # ---- K1 CI duration and K2 quality gate, on pull request runs
    pr_runs = [r for r in runs if r["event"] == "pull_request"]
    ci_minutes, job_minutes, gate = [], {"back": [], "front": [], "sonar": []}, {"success": 0, "failure": 0}
    for r in pr_runs:
        js = jobs(r)
        start, end = ts(r["run_started_at"]), ts(r["updated_at"])
        if r["conclusion"] == "success":
            ci_minutes.append((end - start).total_seconds() / 60)
        for j in js:
            if not (j["started_at"] and j["completed_at"]) or j["conclusion"] == "skipped":
                continue
            d = (ts(j["completed_at"]) - ts(j["started_at"])).total_seconds() / 60
            key = "back" if j["name"].startswith("Back") else "front" if j["name"].startswith("Front") else "sonar" if j["name"].startswith("SonarQube") else None
            if key:
                job_minutes[key].append(d)
            if key == "sonar" and j["conclusion"] in gate:
                gate[j["conclusion"]] += 1

    days = max(hours(main_runs[-1]["_end"] - ts(main_runs[0]["created_at"])) / 24, 1 / 24) if main_runs else 1
    releases = [r["tag_name"] for page in gh(f"repos/{repo}/releases?per_page=100") for r in page]
    cfr = len(failed) / len(main_runs) * 100 if main_runs else 0
    gate_total = gate["success"] + gate["failure"]

    m = lambda xs: f"median {statistics.median(xs):.1f} min, max {max(xs):.1f} min (n={len(xs)})" if xs else "n/a"
    print(f"# DORA metrics and pipeline KPIs: {repo}")
    print(f"Observed period (since the first CD run): {ts(main_runs[0]['created_at']):%Y-%m-%d %H:%M} to {main_runs[-1]['_end']:%Y-%m-%d %H:%M} UTC ({days:.1f} days); "
          f"{len(main_runs)} pipeline runs on main, {len(prs)} merged pull requests, {len(pr_runs)} pull request runs.\n")
    print("| Metric | Value | Method |")
    print("|---|---|---|")
    print(f"| Deployment frequency | {len(deployments)} deployments in {days:.1f} days = {len(deployments) / days:.1f} per day "
          f"(CD attempts: {cd_attempts}; releases: {', '.join(sorted(releases)) or 'none'}) | successful CD job runs on main |")
    print(f"| Lead time for changes | {summary(lead)} | first commit of the PR -> first deployment after its merge |")
    print(f"| (of which merge -> deployment) | {summary(merge_to_deploy)} | merge -> first deployment |")
    print(f"| Change failure rate | {len(failed)}/{len(main_runs)} = {cfr:.0f} % | failed pipeline runs on main / all runs on main |")
    print(f"| Time to restore | {summary(restore)} | failed run on main -> next successful run on main |")
    print(f"| K1 CI duration per PR | {m(ci_minutes)} | successful pull request runs |")
    print(f"| K1 job durations | back {m(job_minutes['back'])}; front {m(job_minutes['front'])}; sonar {m(job_minutes['sonar'])} | jobs of pull request runs |")
    print(f"| K2 quality gate pass rate | {gate['success']}/{gate_total} = {gate['success'] / gate_total * 100 if gate_total else 0:.0f} % | SonarQube job of pull request runs |")


if __name__ == "__main__":
    main()
