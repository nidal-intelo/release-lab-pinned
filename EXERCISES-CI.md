# Act 1 — The pinned world grows a CI

Phase 1 you did everything by hand: `./publish.sh`, `./deploy.sh`, edit pins,
try not to forget anything. Act 1 automates exactly that — no more, no less —
the way a real wheel-registry setup does:

- **`.github/workflows/publish.yaml`** — push to `dev` touching `common/**`
  builds any wheel whose version isn't in the registry yet. The registry is
  the repo's **`registry` branch** (an orphan branch full of `.whl` files —
  the hosted registry, in miniature). Immutable: *same version = no
  republish*.
- **`.github/workflows/deploy.yaml`** — push to `dev` / `uat` / `production`
  "deploys": each consumer is installed from the registry per its pins and
  run. Change detection is a floating tag `lab-<branch>-latest`; a consumer
  redeploys **only if its own `consumers/<name>/` directory changed** since
  that tag. `common/` is deliberately *not* watched. Sit with that.
- **`.github/workflows/pr-resolve-check.yaml`** — every PR gets a check:
  do all consumer pins resolve against the registry *as it exists right now*?

So the machine now runs the ritual's steps — but the machine only runs steps.
*Remembering* the steps is still yours. That's this act.

### Ground rules (changed from phase 1!)

- This repo (`pinned-world/`) now has a real remote: **release-lab-pinned** on
  GitHub. Pushing to `dev`, `uat`, `production` and opening PRs is the whole
  point here. (The other lab repos remain local-only.)
- CI's registry is the **`registry` branch**, *not* your local `../registry`
  directory (which still carries phase-1 leftovers). Inspect CI's registry:

  ```sh
  git fetch origin registry
  git ls-tree --name-only origin/registry
  ```

  To run `deploy.sh` locally the way CI sees the world:

  ```sh
  git worktree add ../registry-branch registry
  REGISTRY_DIR="$(pwd)/../registry-branch" ./deploy.sh
  ```

- Watching runs: `gh run list --limit 5`, `gh run watch`, and — do this every
  time — open the run's **summary** (`gh run view --web`, or the Actions tab).
  The summaries are written to be read; they are the deploy logs of this world.

Starting state: `dev` pins `qb==1.5.0` (both consumers), `uat` `1.4.0`,
`production` `1.3.0`; registry branch holds qb 1.3.0 / 1.4.0 / 1.5.0 and
solver 2.0.0. All three deploys have run green at least once.

---

## Exercise 1.0 — Watch the seed deploys

**Goal:** learn to read a deploy summary before you cause one.

**Commands:**

```sh
gh run list --workflow deploy.yaml --limit 6
gh run view --web <a-run-id-per-branch>   # or click through the Actions tab
```

The setup pushes already fired one deploy per branch. If you want to see one
happen live, push a whitespace commit to an env branch:

```sh
git switch uat && git commit --allow-empty -m "kick deploy" && git push
gh run watch
git switch dev
```

**What you should observe:** each summary is a table — one row per consumer,
`changed?`, and either **deployed** with the behavior string, or *skipped* with
the current pin and what it resolves to. On the very first run of a branch
everything counted as changed (no `lab-<branch>-latest` tag existed yet);
your empty kick-commit shows both consumers **skipped** — nothing under
`consumers/` changed — yet the summary still tells you `uat` runs qb 1.4.0.

**What just happened:** the deploy compared `HEAD` against the floating tag
`lab-uat-latest` per consumer directory, found nothing, deployed nothing, and
moved the tag anyway. Note the summary's footnote: `common/` changes don't
redeploy anything. Remember it; you'll trip over it in about four minutes.

---

## Exercise 1.1 — THE TWO-PR DANCE

**Goal:** ship one string change end-to-end through CI, and count what it costs.
This is phase-1 exercise 3 (the ritual) plus exercise 4 (the forgotten re-pin)
— except now every step has a green checkmark on it.

**PR 1 — the code change + bump:**

```sh
git switch dev && git pull
git switch -c qb-audit-log
# edit common/qb/src/qb/__init__.py:
#   ROUNDING = "rounds HALF-EVEN (banker's rounding) + audit log"
# edit common/qb/pyproject.toml:  version -> "1.6.0"
git commit -am "qb 1.6.0: audit log"
git push -u origin qb-audit-log
gh pr create --base dev --title "qb 1.6.0: audit log" --body "bump only; pins follow"
gh pr merge --squash --delete-branch
gh run list --limit 4        # a publish run AND a deploy run just fired
```

**What you should observe:** the *publish* summary says
`published qb-1.6.0-py3-none-any.whl` (confirm:
`git fetch origin registry && git ls-tree --name-only origin/registry`). The
*deploy* summary — read it carefully — shows **both consumers skipped**:
`skipped (no changes detected) — still pinned qb==1.5.0, currently resolves
to: qb 1.5.0: ...`. Your change is published, deployed nowhere, and CI is
entirely green about it.

**PR 2 — re-pin report (and "forget" worker, like everyone eventually does):**

```sh
git switch dev && git pull && git switch -c repin-report
# edit consumers/report/pyproject.toml:  qb==1.5.0 -> qb==1.6.0
git commit -am "pin report to qb==1.6.0"
git push -u origin repin-report
gh pr create --base dev --title "pin report to qb==1.6.0" --body ""
gh pr merge --squash --delete-branch
gh run watch
```

**What you should observe:** no publish this time (nothing under `common/`
changed). The deploy summary:

| consumer | changed? | result |
|---|---|---|
| report | yes | **deployed** → qb 1.6.0: ... + audit log ... |
| worker | no | skipped — still pinned `qb==1.5.0`, resolves to qb 1.5.0: ... |

That second row *is* the stale-wheel incident from phase-1 exercise 4 —
except now it's not you forgetting in a terminal, it's a green CI run politely
recording the drift. Nothing will ever flag it. The summary printing the stale
pin is this lab being kind; real dashboards mostly don't.

**PR 3 — the relock you almost forgot:**

```sh
git switch dev && git pull && git switch -c repin-worker
# consumers/worker/pyproject.toml:  qb==1.5.0 -> qb==1.6.0
git commit -am "pin worker to qb==1.6.0"
git push -u origin repin-worker && gh pr create --base dev --fill && gh pr merge --squash --delete-branch
gh run watch                 # worker deployed -> qb 1.6.0; dev is finally coherent
```

**What just happened:** one string change = **3 PRs**, ~7 workflow runs, and
two separate moments where a human had to *remember* that a consumer existed
and pins it. The automation executed every step flawlessly; it never once knew
whether the process was *done*. "Done" lives in your head. Compare: in
source-world this was `git commit` (phase-1 exercise 2).

---

## Exercise 1.2 — THE SERIALIZATION (why it can't be one PR)

**Goal:** try to collapse the dance into a single PR — bump *and* re-pin
together — and watch the model itself refuse.

**Commands:**

```sh
git switch dev && git pull && git switch -c qb-one-shot
# edit qb:      ROUNDING -> "rounds HALF-UP (perf rewrite)"
# edit qb:      version  -> "1.7.0"
# edit BOTH consumers:   qb==1.6.0 -> qb==1.7.0
git commit -am "qb 1.7.0: perf rewrite + re-pin consumers (one PR, what could go wrong)"
git push -u origin qb-one-shot
gh pr create --base dev --title "qb 1.7.0 + re-pin (combined)" --body "one-PR attempt"
gh pr checks --watch          # pr-resolve-check: FAIL
```

Read the failing check's summary. Reproduce it locally if you like:

```sh
git worktree add ../registry-branch registry 2>/dev/null || true
REGISTRY_DIR="$(pwd)/../registry-branch" ./deploy.sh one-shot-preview
# -> resolution error: no wheel satisfies qb==1.7.0
```

Then stand down:

```sh
gh pr close qb-one-shot --delete-branch
git switch dev
```

**What you should observe:** `pr-resolve-check` fails with *"a consumer pin
references a wheel that is not in the registry yet"*, listing a registry that
tops out at qb 1.6.0.

**What just happened:** the wheel for 1.7.0 can only come into existence when
the bump **lands on dev** (that's what triggers publish). But a pin referencing
1.7.0 must resolve against the registry *as it is*, or every deploy and every
fresh install breaks. So pins may only point at already-published wheels →
publish must fully land before any re-pin can go green → the dance is
**inherently serial, inherently ≥2 PRs**. Not a policy. A consequence of
consumers resolving artifacts instead of source. (Source-world cannot even ask
this question: there is no artifact to be missing.)

---

## Exercise 1.3 — Promotion: dev → uat

**Goal:** promote everything you shipped to the next environment, and notice
what you *don't* have to do.

**Commands:**

```sh
gh pr create --base uat --head dev --title "promote dev -> uat" \
  --body "qb 1.6.0: audit log"
gh pr checks --watch          # pr-resolve-check on the merge preview: passes
gh pr merge --merge           # merge commit, not squash: promotion keeps history
gh run watch                  # the uat deploy
```

**What you should observe:** the uat deploy shows **both** consumers changed →
**deployed** at qb 1.6.0. No publish fired (publish is dev-only). No re-pin
PRs, no dance.

**What just happened:** the pins are *files*, so they traveled inside the
merge like any other change — uat's `consumers/*/pyproject.toml` now say
`qb==1.6.0` because dev's did. The bump/publish/re-pin ritual happens **once,
at dev**; downstream environments just receive its committed results. This
matches the real-world shape: the two-PR dance is a dev-branch tax, and
promotion is a merge. (It also quietly re-confirms the phase-1 lesson: what
made uat change was the pin diff under `consumers/`, not the `common/` source
that came along in the same merge.)

---

## The tally

One behavior-string change in qb, landed on dev and promoted to uat:

| | count |
|---|---|
| PRs | 4 (bump, re-pin report, re-pin worker, promote) — 5 with the rejected one-shot |
| workflow runs | ~10 (3-4 pr-checks, 1 publish, 4 deploys) |
| steps a human had to *remember* | bump the version; re-pin **each** consumer (N=2, one forgettable at a time); promote |
| steps the machine caught you on | exactly one — the pin-without-wheel (1.2). The forgotten relock (1.1 PR2) it happily called green. |

The CI automated the *labor* of phase 1 (build, copy, install, record) and
none of the *bookkeeping* (which versions exist, who pins what, is the rollout
complete). Every summary in this act was green except the one that protected
you. Keep that asymmetry in mind for Act 2.
