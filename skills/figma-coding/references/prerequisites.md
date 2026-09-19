# Prerequisites (F0)

## When to read this

Read this at the start of every Figma-based implementation, before the first `get_figma_data` call
and before writing any estimate. In cc-task-skills terms this belongs to the design phase.

F0 answers four questions: can the tools reach the file, how many calls can you afford, is the file
built in a way that gives you spacing values, and which parts of the design are out of scope.

## Rules

1. **Configure the MCP server through a file that carries no secret.** Register
   `figma-developer-mcp` in `.mcp.json`, and pass the personal access token as an environment
   variable reference, never as a literal. Copy `<SKILL>/templates/mcp.json.example` as the starting
   point. Why: the example file can be committed, so the working file never has to be.
2. **Commit `.mcp.json.example`, ignore `.mcp.json`.** Add `.mcp.json` to `.gitignore` in the same
   change that introduces the example. Why: the working file is the one a token gets pasted into by
   mistake, and an ignored file cannot reach the remote when that happens. A session that has no
   local working file — a cloud container, or a teammate's first checkout — creates it by copying
   the example, and supplies the token through the environment.
3. **Verify the package before the first run.** `npx -y` fetches and executes without confirmation.
   The expected package is **`figma-developer-mcp`**, published from the **`glips/figma-context-mcp`**
   repository; confirm both once at the start, for example with `npm view figma-developer-mcp
   repository`. Why: a name one character away from this one costs an attacker nothing, and the
   package runs with your token in its environment.
4. **Triage a failing call with the HTTP API before changing anything.** Why: the three failures are
   indistinguishable through the MCP layer and have different fixes, so changing settings before
   triage means changing the wrong one.

   | Request | Result | Meaning |
   |---|---|---|
   | `GET /v1/me` | 401 | the token is invalid or expired |
   | `GET /v1/files/<fileKey>` | 404 | the file is not visible to this account |
   | `GET /v1/files/<fileKey>` | 403 | the token lacks the required scope |

   Read the token from the environment and ask for the status code only, so the value itself never
   reaches the command line:

   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' -H "X-Figma-Token: $FIGMA_API_KEY" \
        https://api.figma.com/v1/me
   ```

5. **Treat API calls as a budget, not a resource.** Viewer-tier accounts are limited to a handful of
   file reads per month; a paid seat raises the ceiling but not to infinity. Decide the node list
   before you start calling, and record the count as you go. Why: failed calls and retries consume
   the same allowance, so the budget runs out fastest exactly when things are going wrong.
6. **Run an Auto Layout spike on day one.** Fetch one representative section and look at whether
   frames use Auto Layout or absolute positioning. Why: if layout mode is absent, the file has no
   spacing values at all, and **every gap must be derived from the coordinate difference between
   sibling nodes**. Finding this out mid-implementation invalidates the parts already measured.
7. **Write down what you will not fetch, before fetching anything.** Typical entries: shared header
   and footer reused from an existing site, sections explicitly out of scope, and elements confirmed
   absent. Why: each entry removes API calls, and an explicit absence is a decision that can be
   reviewed, whereas silence looks like an oversight later.
8. **Pin exactly one source file and record its identity.** Record the file key, the access level
   your account holds, and the file's last-modified timestamp in the node map. When a copy and an
   original both exist, name which one wins and for which sections. Why: a duplicate's values stay
   plausible while they drift from the original, so the disagreement surfaces at review time rather
   than at read time.
9. **Treat a read-only file as read-only in every operation.** If your role on the file is viewer,
   use read calls only; do not attempt renames, comments, or exports that modify the document. Why:
   a write attempt against someone else's file is visible to them whether or not it succeeds.
10. **Keep the token minimal and temporary.** Request the narrowest scope that allows file reads and
    image exports, set an expiry, and revoke it when the work is done. Why: scope and expiry are the
    only parts of the blast radius you can decide before a leak rather than after one.
11. **If the token is ever committed, revoke first.** Revoke the token in Figma, issue a new one,
    update the environment. Only then clean the history. Why: the exposure stops at revocation;
    history rewriting is cleanup, and doing it first leaves a live credential public for longer.
12. **Define the retreat to manual mode now, not later.** Manual mode means a human supplies
    measurements and exported assets, F1 is skipped, and every value in the record carries
    `source: manual`. Why: agreed during F0, hitting a limit mid-run is a switch; agreed afterwards,
    it is a renegotiation held under time pressure, which is where guessed values come from.

## Don'ts

- **Don't let the token's value appear anywhere it is recorded**: `.mcp.json`, a task file, a commit
  message, a command line, shell history, or an agent's tool log. Reference it from the environment
  instead. Why: all of these are read, shared, or replayed later without a second look, and a tool
  log in particular is copied into conversations that outlive the token.
- **Don't start fetching before the spike in rule 6.** Why: the spike changes how every spacing
  value is obtained, and re-deriving them afterwards costs more than the spike.
- **Don't budget calls on the assumption that a failed call is free.** Why: failures and retries can
  consume the same quota, so a loop of retries can exhaust a month's allowance.
- **Don't continue after a 401/403/404 by switching to a different file "that looks the same".**
  Why: a near-identical copy with stale values is the single most expensive failure mode in this
  workflow — the numbers look plausible and disagree with the authoritative file.
- **Don't treat an absent MCP server as a blocker to be escalated.** Why: manual mode exists, is
  slower but correct, and stalling the whole task on a connectivity problem helps nobody. Escalate
  only the choice, not the work.
- **Don't record "the design says X" without naming the file the design came from.** Why: once a
  second file appears, unattributed values cannot be re-checked and must be measured again.

## Checklist

In manual mode the MCP server is never started, so items marked **(MCP only)** do not apply; leave
them unticked with "manual mode" written beside them rather than ticking them untruthfully.

- [ ] **(MCP only)** `.mcp.json` exists locally, is listed in `.gitignore`, and contains no literal
      token.
- [ ] **(MCP only)** `.mcp.json.example` is committed and references the token through an
      environment variable.
- [ ] **(MCP only)** The package name and its publishing repository were checked once against rule 3.
- [ ] The MCP tools `get_figma_data` and `download_figma_images` are both present in the session, or
      manual mode has been agreed with the user.
- [ ] **(MCP only)** A read of the pinned file succeeds; if it fails, the 401 / 404 / 403 triage has
      been run and the outcome is recorded.
- [ ] The source file's key, access level, and last-modified timestamp are written in the node map.
- [ ] **(MCP only)** The Auto Layout spike has been run on one section by fetching it, and the result
      ("Auto Layout" or "coordinate-derived spacing") is recorded.
- [ ] In manual mode, the same question was answered from the design tool's own interface for one
      section, and the answer is recorded the same way.
- [ ] The "not fetching" list exists and names each excluded area with a reason.
- [ ] **(MCP only)** The planned node list exists, with an estimated call count that fits the
      account's limit.
- [ ] **(MCP only)** The token's scope and expiry are set, and the revocation step is on the task's
      closing list.

## Exit criteria

Move on when the authoritative file is pinned and recorded, the spacing-derivation method is known
(from the spike, or from the same check made by hand), and the scope of the work — what will be
covered and what will not — is written down.

- **With the MCP server**: the tools are reachable, and the fetch plan's call count fits the budget.
  Next phase is F1.
- **In manual mode**: the supplier of the measurements and exports is agreed, and every value they
  provide will carry `source: manual`. F1 is skipped; the next phase is F2.
