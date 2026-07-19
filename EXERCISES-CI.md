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

---

# Act 1.5 — the engineering round

Act 1 ended on an asymmetry: the CI ran every *step* and none of the
*bookkeeping*. This act automates the bookkeeping — honestly, with each
automation named after the real-world tool category it stands in for:

| automation | file | real-world category | Act-1 human step it eats |
|---|---|---|---|
| auto-bump | `publish.yaml` (job 1) | semantic-release / release-please | "remember to bump the version" |
| repin bot | `repin.yaml` | Renovate / Dependabot | "remember to re-pin *every* consumer" (1.1 PRs 2–3) |
| drift alarm | `drift-alarm.yaml` | dependency dashboards / skew monitors | "notice the drift nobody flagged" |
| provenance manifest | `publish.yaml` (manifest step) | build provenance (SLSA-ish) | "which commit does production run?" archaeology |
| scripted hotfix | `hotfix-pinned.yaml` | release-branch / hotfix pipelines | the whole six-step per-env dance |

Starting state (the setup's own shakedown already ran the chain once —
its runs, merged bot PRs, closed drift issue, and the `release/qb-1.3.0`
branch are in the history if you want spoilers): `dev` pins `qb==1.6.1`
(both consumers) and `solver==2.0.0`; `uat` pins `qb==1.6.0`; `production`
pins `qb==1.3.1` (a hotfix line!). The registry branch holds qb 1.3.0,
1.3.1, 1.4.0, 1.5.0, 1.6.0, 1.6.1, solver 2.0.0 — and `manifest.json`.
No PRs are open; the drift issue is closed.

One repo setting worth knowing about: *Settings → Actions → General →
"Allow GitHub Actions to create and approve pull requests"* is enabled
here. Without it, `gh pr create` under any workflow token fails outright —
a different (coarser) gate than the per-event teachable you'll meet in 2.1.

---

## Exercise 2.0 — Read the machines before you feed them

**Goal:** know what's watching dev before you touch it.

**Commands:**

```sh
git switch dev && git pull
less .github/workflows/publish.yaml       # auto-bump job + manifest step
less .github/workflows/repin.yaml         # read the header block twice
less .github/workflows/drift-alarm.yaml
less .github/workflows/hotfix-pinned.yaml
git fetch origin registry
git show origin/registry:manifest.json | jq .
git log --oneline origin/registry | head
```

**What you should observe:** each workflow header names its real-world
category and the exact human failure it exists to erase. `manifest.json`
maps every wheel to a `source_commit_sha` and the run that built it —
including backfilled seed wheels (their `dev_run_url` is `"unknown"`:
provenance recorded after the fact is best-effort; provenance recorded at
publish time is exact. That difference is exercise 2.3's foundation.)

**What just happened:** nothing — that's the point. Every remaining
exercise pokes one of these five with a real change; you now know where
each reaction will come from.

---

## Exercise 2.1 — The chain, and the bot with no voice

**Goal:** ship a qb change with zero version bookkeeping, then meet the
one thing the bot can't do: trigger checks.

**Commands:**

```sh
git switch dev && git pull
# edit common/qb/src/qb/__init__.py:
#   ROUNDING -> "rounds HALF-EVEN (banker's rounding) + audit log + query cache"
# do NOT touch the version. do NOT touch any pins. that's the whole exercise.
git commit -am "qb: query cache"
git push
gh run watch                  # publish: auto-bump job mints, publish builds
git pull                      # <- a bot(bump) commit landed on dev. read it.
gh pr list                    # repin fired after publish; ONE batched PR
gh pr view --json body -q .body <N>
gh pr checks <N>              # <- zero checks. sit with that.
```

**What you should observe:** the publish run's summary shows auto-bump
minting the next patch (`bot(bump): qb 1.6.2`) and publish shipping the
wheel plus a manifest entry. Then a `bot(repin)` PR appears moving **both**
consumers in one PR — the Act-1 "forgot the worker" mistake is structurally
gone. But `gh pr checks` comes back empty: **pr-resolve-check never ran.**

**What just happened:** actions performed with the default `GITHUB_TOKEN`
do not trigger other workflows — GitHub suppresses those events to prevent
runaway loops. A PR the bot opens therefore gets no `pull_request` checks.
This is the exact reason real-world bots (Renovate, Dependabot) run under
their own identity instead of the workflow token. Now perform the
real-world fix:

1. GitHub → Settings → Developer settings → Personal access tokens →
   **Fine-grained tokens** → generate one scoped to *only this repo*, with
   repository permissions **Contents: Read and write** and **Pull requests:
   Read and write**.
2. `gh secret set LAB_BOT_PAT` (paste the token).
3. Re-arm: `gh pr close <N> --delete-branch`, then
   `gh workflow run repin.yaml && gh run watch`.
4. `gh pr checks <new-N>` — **pr-resolve-check is running.** No workflow
   file changed: every credential in `repin.yaml` already read
   `secrets.LAB_BOT_PAT || github.token`.
5. `gh pr merge <new-N> --squash --delete-branch`, then `gh run watch` —
   the dev deploy shows both consumers **deployed** at the new version.

Count your actions: one push, one secret (once, ever), one merge. Act 1's
version of this was three PRs and two separate feats of memory.

---

## Exercise 2.2 — Drift becomes a signal

**Goal:** reproduce Act 1's silent-drift state — and this time, get paged.

**Commands:**

```sh
# make fresh drift: another unbumped qb tweak
git switch dev && git pull
# edit qb's ROUNDING string again (any visible tweak)
git commit -am "qb: tune cache TTL" && git push && gh run watch
# the bot opens its repin PR. pretend the whole team is at lunch:
gh pr list
gh pr close <N> --delete-branch

gh workflow run drift-alarm.yaml && gh run watch
gh issue list                    # <- the alarm
gh issue view <issue-N>
```

**What you should observe:** the run summary is a full status table —
dev rows scream `DRIFT`, while uat/production rows behind the newest wheel
say `behind (expected promotion lag)`. The issue lists **only the dev
rows**: uat and production being behind is the promotion model working,
not a failure, and an alarm that cries about normal states trains you to
ignore it. Note the issue title is fixed — re-running the alarm *updates*
the one issue rather than opening a second.

Now clear it:

```sh
gh workflow run repin.yaml && gh run watch     # PR re-opens
gh pr merge <N> --squash --delete-branch && gh run watch
gh workflow run drift-alarm.yaml && gh run watch
gh issue list --state closed                   # auto-closed, with a comment
```

**What just happened:** Act 1's sharpest lesson was that stale pins are a
*green* state. They still are — deploy and publish are as cheerfully green
as ever. What changed is that a cron now owns the noticing (every 6 h,
plus your manual pokes), and its output is a state-managed issue: opened
when dev drifts, updated in place, closed by the machine the moment the
drift clears. One honest caveat to file away for 2.4: this alarm compares
*pins* against *published wheels*. Source that never became a wheel is
invisible to it.

---

## Exercise 2.3 — The hotfix button

**Goal:** production runs the `qb==1.3.1` hotfix line and still has the
empty-cart bug. Fix it there without shipping three versions of unrelated
dev behavior — and watch six manual steps collapse into one dispatch.

**Commands:**

```sh
# 1. what does production actually run, and where did it come from?
git fetch origin
git show origin/production:consumers/worker/pyproject.toml | grep qb==
git show origin/registry:manifest.json | jq '."qb-1.3.1-py3-none-any.whl"'
#    note: its source_commit_sha lives on release/qb-1.3.0, not on dev.

# 2. land the fix on dev first (fix-forward, then backport):
git switch dev && git pull
# edit common/qb/src/qb/__init__.py:
#   CART_NOTE -> "empty carts handled correctly"
git commit -am "fix(qb): empty-cart off-by-one"
FIX=$(git rev-parse HEAD)        # capture BEFORE the bot's bump commit lands
git push && gh run watch         # auto-bump + publish: dev line gets the fix
# merge the repin PR the bot opens (keep dev coherent):
gh pr list && gh pr merge <N> --squash --delete-branch

# 3. the button:
gh workflow run hotfix-pinned.yaml \
  -f package=qb -f fixed_version=1.3.1 -f fix_commit_sha=$FIX
gh run watch
gh pr list --base production     # "hotfix: pin qb==1.3.2 on production"
gh pr merge <N> --merge
gh run watch                     # the production deploy
```

**What you should observe:** the hotfix run's summary narrates all six
steps: manifest lookup (no `git log` spelunking), `release/qb-1.3.1`
branch cut from the manifest's commit, `cherry-pick -x` of your fix,
bump to 1.3.2, immutable publish *from that branch*, re-pin PR against
production. The production deploy then prints the tell:
`qb 1.3.2: rounds DOWN (empty carts handled correctly)` — the **old**
rounding behavior with the **new** fix. Surgical. (If you set
`LAB_BOT_PAT` in 2.1, the production PR even has checks — the upgrade
applied to every bot in this repo.)

**What just happened:** the per-env-versioning dance — archaeology,
branch cut, cherry-pick, bump, publish, re-pin — used to be the scariest
manual ritual in the pinned world, performed under incident pressure.
It's now an idempotent script with refusal guards (try dispatching it
again with the same inputs: it refuses — the branch exists and 1.3.2 is
burned). The load-bearing part is `manifest.json`: provenance written at
publish time, when it was cheap, is what made step 1 a `jq` one-liner.
Also notice what you now maintain forever: a growing family of
`release/*` branches, and a manifest whose correctness nobody checks but
everybody trusts.

---

## Exercise 2.4 — EDGE: the same number, twice

**Goal:** make two branches mint the same version and watch what an
immutable registry — and the bot — actually do. Neither does what Act 1
taught you to expect.

**Part A — the collision that refuses to happen:**

```sh
git switch dev && git pull
git switch -c solver-jitter
# edit common/solver/src/solver/__init__.py: STRATEGY -> "greedy + jitter"
# edit common/solver/pyproject.toml:          version -> "2.0.1"
git commit -am "solver 2.0.1: jitter" && git push -u origin solver-jitter
gh pr create --base dev --fill

git switch dev && git switch -c solver-tiebreak      # same parent commit!
# ADD a line to solver's __init__.py:  TIEBREAK = "lowest index wins"
# edit pyproject:                      version -> "2.0.1"   <- SAME number
git commit -am "solver 2.0.1: tiebreak" && git push -u origin solver-tiebreak
gh pr create --base dev --fill

gh pr merge solver-jitter --squash --delete-branch && gh run watch
gh pr merge solver-tiebreak --squash --delete-branch && gh run watch  # <- watch closely
```

**What you should observe (A):** the first merge publishes solver 2.0.1.
The second merge — which minted the *same* 2.0.1 on its branch — does
**not** produce the Act-1 refusal. Read its auto-bump summary: the bot
minted **2.0.2**. Why: by the time branch two landed, dev already said
2.0.1, so the squash diff contained *no version change* — to the bot this
was "source landed unbumped", and it issued a fresh number. This is
semantic-release's core trick: **version numbers assigned at land time on
the integration branch cannot collide**, because landing is serial.
Numbers chosen on feature branches (Act 1's way) collide whenever two
humans pick the same "next".

**Part B — force the refusal anyway:**

The bot trusts any push that touches the version line ("a human minted
this deliberately"). Humans mint taken numbers all the time — the classic
is a botched merge-conflict resolution that resurrects an old version:

```sh
git switch dev && git pull
# edit solver source (any small tweak) AND hand-set version DOWN to "2.0.1"
git commit -am "solver: tweak (botched conflict resolution)" && git push
gh run watch
```

**What you should observe (B):** auto-bump defers (version line touched);
publish hits the immutability gate: `REFUSED: solver 2.0.1 is already in
the registry`. Green run, no-op publish. Dev now carries source that **no
wheel contains**, under a number that is burned forever. Now dispatch
`drift-alarm.yaml`: it stays silent — it compares *pins* to *wheels*, and
the pins are fine. Two automations just watched a stale state sail past.
This is why immutable registries force fresh numbers: republishing under
a taken number would silently change what every existing pin means.

**Recovery** — let the land-time minter do its job:

```sh
git switch dev
# any solver source tweak; do NOT touch the version line
git commit -am "solver: recover the burned number" && git push && gh run watch
```

Auto-bump walks from 2.0.1 to the next **free** patch — skipping the
already-published 2.0.2 — mints 2.0.3, publishes, and the repin PR
follows (notice it's been *updating one PR in place* throughout this
exercise — that's the batching working). Merge it.

**What just happened:** every automation has edges. The minting bot's
edge is deference to humans; the alarm's edge is that it measures pins,
not source. Knowing an automation's blind spots is part of owning it —
which is the subject of the tally.

---

## Exercise 2.5 — THE TALLY

**Goal:** none. Read, and hold a question open.

One behavior change in Act 1 cost 3 PRs, ~7 runs, and three feats of
human memory. The same change now costs one push and one bot-PR merge.
Here is where each human step went — and what stayed:

| human step in Act 1 | automated by | what a human still owns |
|---|---|---|
| remember to bump the version | auto-bump (semantic-release category) | choosing MINOR/MAJOR when it matters — the bot only mints patches; reviewing `bot(bump)` commits after the fact |
| open a re-pin PR per consumer, forget none | repin bot (Renovate category) | **reviewing and merging** the bot PR; deciding when *not* to take an upgrade |
| notice drift, eventually, by accident | drift alarm (dashboard category) | answering the page; deciding that uat/prod lag stays un-alarmed (someone chose that; someone can choose wrong) |
| "which commit does production run?" archaeology | provenance manifest | manifest correctness — backfilled entries were best-effort; a wrong SHA here cuts a hotfix branch from the wrong commit, during an incident |
| the six-step hotfix ritual | hotfix-pinned | picking the fix commit; approving the production PR; the ever-growing `release/*` shelf |
| — (new work, created by this act) | — | the automations themselves: four workflows of code with known edges (2.4); `LAB_BOT_PAT` rotation when it expires; the actions-create-PRs repo setting; every summary that now goes unread because it's "handled" |

Notice the pattern in column three: nothing that remained is *labor*.
It's judgment (merge or don't), trust maintenance (the PAT, the manifest),
and edge-knowledge (2.4). The machine took the remembering and left the
owning — and added itself to the list of things owned.

Is that operational surface an acceptable price for what versioned wheels
buy — per-env pins, surgical hotfixes, immutable history? Don't answer
yet. Run Act 2 in the source world, where none of this machinery exists
because none of it is needed — and none of its powers are available.
Then compare.
