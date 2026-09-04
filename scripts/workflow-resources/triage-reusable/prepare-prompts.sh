#!/usr/bin/env bash
set -e

RUNNER_TEMP="${RUNNER_TEMP:-}"
RECOVERY_MODE_INPUT="${RECOVERY_MODE:-false}"
COMMENT_BODY="${COMMENT_BODY:-}"
SKIP_RELEVANCE_CHECK="${SKIP_RELEVANCE_CHECK:-false}"
REPOSITORY="${REPOSITORY:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
EVENT_NAME="${EVENT_NAME:-}"
FETCH_ISSUE_TITLE="${FETCH_ISSUE_TITLE:-}"
FETCH_ISSUE_BODY="${FETCH_ISSUE_BODY:-}"
INPUT_ISSUE_TITLE="${INPUT_ISSUE_TITLE:-}"
INPUT_ISSUE_BODY="${INPUT_ISSUE_BODY:-}"
IMAGE_ANALYSIS="${IMAGE_ANALYSIS:-}"
WORKFLOW_VERSION="${WORKFLOW_VERSION:-unknown}"
NEEDS_INFO_MODE="${NEEDS_INFO_MODE:-false}"

mkdir -p "${RUNNER_TEMP}/claude-prompts"

# Determine if we're in recovery mode
RECOVERY_MODE="false"
if [[ "${RECOVERY_MODE_INPUT}" == "true" ]] || \
   [[ "${COMMENT_BODY}" == *"@claude relevant repo confirmed, execute triage"* ]]; then
  RECOVERY_MODE="true"
  echo "🔄 Recovery mode activated"
fi

# Create relevance check prompt (if not in recovery mode)
if [[ "${RECOVERY_MODE}" != "true" ]] && [[ "${SKIP_RELEVANCE_CHECK}" != "true" ]]; then
  cat > "${RUNNER_TEMP}/claude-prompts/relevance-check.txt" << 'EOF'
# Repository Relevance Check

You are checking if issue #ISSUE_NUMBER belongs in the REPOSITORY repository.

## Repository Context

EOF

  # Add reference to CLAUDE.md if it exists
  if [ -f "CLAUDE.md" ]; then
    echo "📖 Found CLAUDE.md in target repository"
    {
      echo ""
      echo "Please review the repository context in @CLAUDE.md"
      echo ""
    } >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  fi

  # Append prompt-extra content if it exists (safe - no variable substitution)
  if [ -f ".github/prompt_extra/triage_prompt_extra.md" ]; then
    echo "📖 Found prompt-extra file"
    {
      echo "## Project-Specific Context"
      echo ""
      cat .github/prompt_extra/triage_prompt_extra.md
      echo ""
    } >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  fi

  # Add issue section header
  {
    echo ""
    echo "## Issue to Evaluate"
    echo ""
  } >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"

  # Add issue title
  echo -n "**Title:** " >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  if [[ "${EVENT_NAME}" == "workflow_dispatch" ]] && [[ -n "${FETCH_ISSUE_TITLE}" ]]; then
    echo "${FETCH_ISSUE_TITLE}" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  else
    echo "${INPUT_ISSUE_TITLE}" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  fi

  # Add issue body
  echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  echo "**Body:**" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  if [[ "${EVENT_NAME}" == "workflow_dispatch" ]] && [[ -n "${FETCH_ISSUE_BODY}" ]]; then
    cat >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt" <<'EOF'
${FETCH_ISSUE_BODY}
EOF
  else
    cat >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt" <<'EOF'
${INPUT_ISSUE_BODY}
EOF
  fi

  # Add the rest of the prompt
  cat >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt" << 'EOF'

## Your Task

Determine if this issue belongs in this repository. Consider:
1. Does the issue relate to this repository's codebase or functionality?
2. Would another repository be more appropriate?
3. Is this a general question that doesn't belong in any specific repo?

## Response Requirements

For RELEVANT issues:
- Do NOT post a comment
- Output only the metadata: ==REPO_CHECK=={"relevant":true,"confidence":"HIGH","reason":"brief explanation"}==REPO_CHECK==
- The system will automatically add the "relevance-confirmed" label

For IRRELEVANT issues:
- Post a comment explaining why the issue doesn't belong here
- Suggest the correct repository if identifiable
- Include metadata in your comment: ==REPO_CHECK=={"relevant":false,"confidence":"HIGH","suggested_repo":"owner/repo","reason":"brief explanation"}==REPO_CHECK==
- Add footer: ---\n*Analyzed by claude-triage vWORKFLOW_VERSION*

**Important**: Only comment when the issue is NOT relevant. For relevant issues, just output the metadata.
EOF

  # Replace placeholders
  sed -i "s/ISSUE_NUMBER/${ISSUE_NUMBER}/g" "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  sed -i "s|REPOSITORY|${REPOSITORY}|g" "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  sed -i "s|WORKFLOW_VERSION|${WORKFLOW_VERSION}|g" "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
fi

# Create main triage prompt
cat > "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'EOF'
# Claude Triage Analysis

You are performing intelligent issue triage for repository: REPOSITORY

## Repository Context

EOF

# Add reference to CLAUDE.md if it exists
if [ -f "CLAUDE.md" ]; then
  {
    echo ""
    echo "Please review the repository context in @CLAUDE.md"
    echo ""
  } >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Append prompt-extra content if it exists (safe - no variable substitution)
if [ -f ".github/prompt_extra/triage_prompt_extra.md" ]; then
  {
    echo "## Project-Specific Context"
    echo ""
    cat .github/prompt_extra/triage_prompt_extra.md
    echo ""
  } >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Add issue section
{
  echo ""
  echo "## Issue to Analyze"
  echo ""
  echo "Issue #ISSUE_NUMBER"
  echo ""
} >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"

# Add issue title
echo -n "**Title:** " >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
if [[ "${EVENT_NAME}" == "workflow_dispatch" ]] && [[ -n "${FETCH_ISSUE_TITLE}" ]]; then
  echo "${FETCH_ISSUE_TITLE}" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
else
  echo "${INPUT_ISSUE_TITLE}" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Add issue body
echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
echo "**Body:**" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
if [[ "${EVENT_NAME}" == "workflow_dispatch" ]] && [[ -n "${FETCH_ISSUE_BODY}" ]]; then
  cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" <<'EOF'
${FETCH_ISSUE_BODY}
EOF
else
  cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" <<'EOF'
${INPUT_ISSUE_BODY}
EOF
fi

# Add image analysis results if available
if [[ -n "${IMAGE_ANALYSIS}" ]]; then
  {
    echo ""
    echo "## Image Analysis Results"
    echo ""
    echo "The following image analysis has been performed on screenshots in this issue:"
    echo ""
    cat <<'EOF'
${IMAGE_ANALYSIS}
EOF
    echo ""
    echo "**Use these image insights in your triage analysis.** Consider extracted error messages, visual observations, and technical recommendations when assessing priority, complexity, and areas affected."
    echo ""
  } >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Add the rest of the triage prompt
cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'EOF'

## Available Issue Types

Check if this repository has custom issue types configured in GitHub.

## Your Task

Provide a comprehensive triage analysis. You must:

1. **Analyze the issue** thoroughly
2. **Determine priority** (critical/high/medium/low)
3. **Estimate T-shirt size** (XS/S/M/L/XL/XXL) — see Sizing Guidelines below.
   FIRST run the sub-issue check there: a child of ANY parent (native
   link or `Sub-issue of` body line) is NOT sized at all — it is
   decided on the parent. Otherwise give a direct
   size whenever there is a clearly correct choice; only escalate to a
   human via the strategy comparison table when there genuinely isn't
   one.
4. **Identify areas** affected (frontend/backend/api/security/database/performance/testing/docs/infrastructure)
5. **Apply special flags** if applicable (good-first-issue/breaking-change/needs-discussion)
6. **Classify issue type** (bug/feature/enhancement/documentation/question)
7. **Search for duplicates and related issues** using `mcp__github__search_issues`
8. **Determine if more information is needed** - set `needsInfo: true` in metadata only if the issue is too vague to triage meaningfully

### Duplicate and Related Issue Search

**CRITICAL**: For EVERY issue (not just bugs), search for duplicates and related issues.

**When to Search**: Always - for bugs, features, enhancements, documentation, questions.

**How to Search**:

1. **Extract 2-4 key terms** from the issue title and body:
   - Technical terms (e.g., "authentication", "order flagging", "database query")
   - Feature areas (e.g., "checkout", "email", "API", "admin panel")
   - Component names (e.g., "OrderController", "LoginForm", "customers table")
   - Error messages (e.g., "AUTH_TIMEOUT_ERROR", "500 Internal Server Error")

2. **Perform searches** with `mcp__github__search_issues` using different keyword combinations:
   - Try title keywords first (e.g., "order flagging")
   - Try feature area terms (e.g., "duplicate customer")
   - Try specific technical terms (e.g., "order flag checker")

   **CRITICAL — keep every search small and scoped.** The search tool caps its
   response size; a broad query can return more data than that cap allows and the
   call will fail. To stay under the limit on every call:
   - ALWAYS pass `perPage: 5` (never request a large page).
   - Scope the query with qualifiers: `repo:OWNER/REPO is:issue` plus your key
     terms (search only this repository, issues only).
   - Start **narrow** (2-3 specific terms). Only if a narrow search returns
     nothing should you broaden by dropping a term — never start broad.
   - Prefer several small, specific queries over one large catch-all query.
   - If a search still errors on size, make the query MORE specific (add a term
     or a qualifier); do not retry the same broad query.

3. **Analyze search results**:
   - Read issue titles and bodies carefully
   - Look for same feature areas, same components, similar symptoms
   - Check if issues mention each other

**What to Look For**:

- **Exact Duplicates** (HIGH confidence):
  - Same error message or stack trace
  - Same symptoms and reproduction steps
  - Same feature/component affected
  - Posted by same user or within days of original

- **Related Issues** (MEDIUM confidence):
  - Same feature area (e.g., both about "order flagging")
  - Connected functionality (e.g., display bug + logic bug in same feature)
  - Similar keywords but different aspects

- **Possibly Related** (LOW confidence):
  - Overlapping keywords but different contexts
  - Tangentially related features

**Output Format**:

Include in metadata:
```json
"duplicates": [
  {
    "issue": 123,
    "confidence": "HIGH",
    "type": "duplicate",
    "reason": "Same error message and reproduction steps"
  },
  {
    "issue": 456,
    "confidence": "MEDIUM",
    "type": "related",
    "reason": "Both about order flagging feature"
  }
]
```

**In your triage comment**:
- HIGH confidence duplicates: "This appears to be a duplicate of #123"
- MEDIUM/LOW related: "Related issues: #456 (both about order flagging)"

**Important Notes**:
- Empty results are OK - not every issue has duplicates/related issues
- Don't force relationships - only mark if genuinely related
- Use MEDIUM confidence for "same feature, different aspects"
- Use LOW confidence for "might be related but uncertain"

## Priority Guidelines

- **critical**: Security vulnerabilities, data loss risks, system-breaking bugs
- **high**: Major bugs affecting many users, important features
- **medium**: Standard features and improvements
- **low**: Nice-to-have features, minor cosmetic issues

## Sizing Guidelines

### Sub-issues are decided on their parent — check FIRST, before sizing

A sub-issue ("child") is never sized or approved on its own. Parent and
children are normally filed together, BEFORE any approval exists, so
the child's state simply follows the parent's: pending while the parent
is pending, cleared when the parent is approved (a central job clears
every child the moment the parent's approval lands), closed when the
parent is declined. Sizing a child produces a competing approval ask
for effort that is already part of the parent's size.

Establish that this issue is a child from EITHER of two signals:

1. **Native link**: the issue's `parent` field is non-null. If a shell
   with the gh CLI is available (split REPOSITORY into owner/name):

   ```bash
   gh api graphql -f query='
   query { repository(owner:"<owner>", name:"<name>") {
     issue(number:ISSUE_NUMBER) { parent { number url labels(first:50) { nodes { name } } } }
   } }'
   ```

   With only MCP GitHub tools, read the same parent/sub-issue
   relationship field from the issue data.
2. **Body declaration**: a line in the issue body starting
   `Sub-issue of <owner>/<repo>#<N>` (also accept the older
   `Carries approval from parent <owner>/<repo>#<N>` wording). This
   signal exists because a parent in ANOTHER private repository is
   invisible to your token — the native field comes back null and any
   direct read of the parent fails. That is expected, not an error, and
   is exactly why the declaration line counts.

**If either signal is present**:

- Do NOT estimate a size and do NOT include the "## 📋 Sizing &
  Approval" footer anywhere in the comment — the approval ask does not
  apply to this issue. Still do the full technical analysis: scope
  observations on a child are useful input to the PARENT's decision.
- End the comment body (before the hidden metadata) with one line:
  `**Sub-issue of <parent ref or url>** — not sized; sizing and approval are decided on the parent and inherited from it.`
  If the native parent is readable and already carries `size-approved`,
  say `**Carries approval from parent <parent url>**` instead.
- In the metadata block set `"subIssue": true` and omit both `"size"`
  and `"sizeAmbiguous"`. Add `"carriedApproval": true` ONLY when you
  read the native parent and saw `size-approved` on it — never from
  the body line alone (a deterministic check downstream re-verifies the
  link before any clearance label is applied).

Trusting the body line to SKIP sizing is safe: skipping can never
grant anything. Clearance itself is only ever derived from the real
sub-issue link, by a central job that can read every repository.

**Otherwise** (no native parent and no declaration line): size
normally per the rest of this section.

### MICRO declarations (fast-lane) — check SECOND, before sizing

`MICRO` is the smallest size tier — below XS, at most ~15 minutes
(0.25h) of focused effort. It is ONLY ever declared by the issue
author, never assigned by you: if the issue body contains a
`Size suggestion:` line whose value is `MICRO`, the author is
declaring the work micro, filed for the audit trail and worked
immediately under a standing approval — often already closed before
you run (that is the expected case, not an error; apply the same
rules either way). Your job is to judge the CLAIM, not to gate the
work:

**If the described scope is plausibly that small** (a small doc or
text change, a one-line config tweak, a single self-contained edit —
deliverable end to end in about 15 minutes):

- Do NOT estimate a size and do NOT include the "## 📋 Sizing &
  Approval" footer anywhere in the comment — the approval ask does
  not apply to this issue.
- End the comment body (before the hidden metadata) with one line:
  `**Micro fast-lane** — not sized; audit-trail issue worked under the standing micro approval.`
- In the metadata block set `"microFastLane": true` and omit both
  `"size"` and `"sizeAmbiguous"`.

**If the claim does NOT hold** — the described scope reads as hours
of work (several files or systems, testing cycles, coordination), it
touches production systems or deployments, or it is one slice of a
visibly larger job spread across multiple MICRO declarations — size
it normally per the rest of this section (XS at the smallest — never
output MICRO as your own estimate) AND open the footer's TLDR with
one sentence flagging that the MICRO declaration does not hold for
scope of this size. Do not set `"microFastLane"` in that case: the
normal approval ask stands.

### Sizing (all other issues)

Estimate a T-shirt size for the work, not a complexity label — size is
the one sizing signal this system uses; a `complexity:` label is still
applied afterward but is derived automatically from the size you give,
so do not report complexity separately.

EOF

# The size-to-effort definition is inlined from its single source file
# (../shared/size-bands.md) rather than restated here; `-` resumes the
# heredoc after it in the same append.
cat "$(dirname "${BASH_SOURCE[0]}")/../shared/size-bands.md" - >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'EOF'

A size covers the TOTAL effort to deliver the work — planning,
research, design, review iterations and testing included, not just the
hands-on implementation. Do not size the coding alone.

Your own estimates use XS through XXL only — MICRO exists solely for
author declarations, handled by the MICRO check above, and must never
appear as your own estimate or in the metadata `"size"` field.

**Effort is time, never people.** Assume all work — including work
spanning several repositories — is delivered by a single developer
working with automated agents. There are no teams. Never reason about
effort in terms of teams, headcount, staffing or parallel developer
capacity; work that touches many repositories is cross-repo scope for
that same one developer, and its size is still just hours of focused
work.

If the issue author included their own size suggestion in the body
(e.g. a `Size suggestion:` line), weigh it as evidence — but make your
own estimate rather than adopting it unchecked.

### When to escalate instead of guessing

Most issues have one clearly correct size — give it directly in
`"size"` and stop there. Escalate to a human decision **only** when
there genuinely isn't a single clear answer:

- The scope is too ambiguous to size at all (materially different
  interpretations of the request would size very differently), OR
- There are multiple **viable, meaningfully different** implementation
  strategies whose sizes differ (e.g. a quick targeted patch vs. a
  proper refactor of the underlying cause) and picking one is a product
  or architecture call, not a technical one.

Do NOT escalate just to hedge, and do NOT manufacture alternative
strategies that aren't genuinely viable — 0 escalations on a repo full
of clear-cut issues is the expected, good outcome. If you can defend a
single size, give it directly instead of escalating.

When you do escalate: set `"sizeAmbiguous": true`, omit `"size"`, and
include a **### Sizing Decision Needed** section in your comment with a
table:

| Strategy | Pro | Con | Size |
| -------- | --- | --- | ---- |
| Short-term patch around the symptom | Fast, low risk | Doesn't address root cause, likely recurs | S |
| Fix the underlying root cause | Correct, no recurrence | Touches more of the system | M |

List every genuinely distinct strategy (usually 2-3, never invented
just to fill rows), with a one-line pro/con specific to THIS issue —
not generic pros/cons. This table is for DEVELOPERS — technical
trade-offs, implementation detail, no simplification needed. It does
NOT close with an approval instruction; that lives in the separate
Sizing & Approval footer below, aimed at a different reader. Also
include the same table content in metadata as `"sizeOptions"` (see
Required Output below) so it survives even if the comment is edited.
EOF

# Append project-specific sizing rules if present (safe - no variable substitution)
if [ -f ".github/prompt_extra/size_estimate_prompt_extra.md" ]; then
  {
    echo ""
    echo "### Project-Specific Sizing Rules"
    echo ""
    cat .github/prompt_extra/size_estimate_prompt_extra.md
    echo ""
  } >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Continue main triage prompt
cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'EOF'

## Sizing & Approval Footer (REQUIRED — every issue EXCEPT sub-issues and confirmed micro fast-lane)

**Exceptions**: a sub-issue (decided on its parent), and an issue
whose micro fast-lane declaration you judged plausible (see the two
checks in Sizing Guidelines), get NO footer at all — their comments
end with the one-line sub-issue or micro-fast-lane statement instead.
Every other triaged issue ends with a **separate**, consistently-formatted
footer — the ONLY part of your comment the approver (an admin/owner,
not a developer) needs to read. It is not a summary of the technical
analysis above; it is written for someone who will not read that
analysis at all.

**POSITION — read this before writing anything else in the comment.**
This footer is the LAST thing in the comment, full stop. Not "near the
end" — the literal final section before the hidden metadata. Every
other section (Triage Analysis, Related Source Code, the technical
`### Sizing Decision Needed` table, anything else) goes BEFORE it, with
NO exceptions. Write the rest of the comment first, then write this
footer last, then stop. If you find yourself wanting to add "Related
Source Code" or any other section after this footer — don't; go back
and move it earlier instead. A reader scanning to the bottom of the
comment for "what do I need to do" must land on this footer, not on
something else.

**T-shirt size is ALWAYS stated explicitly and literally** — write
`**T-Shirt Size: M**` (or whichever letter), not just a vague effort
description. The plain-English effort phrase is in ADDITION to the
letter, never a replacement for it — a business reader who already
knows the org's T-shirt-size convention from other tickets should be
able to see the letter at a glance, not have to infer it from prose.

**Audience and language**: non-technical management. Never use
implementation trade-off language (architecture, refactor, technical
debt, root cause vs. patch). Instead frame everything in terms a
business reader judges spend against: benefit/value, ROI, risk if not
done, robustness/reliability, urgency. Pair the size letter with a
plain effort statement:

**TLDR line (REQUIRED, first line of the footer)**: the footer opens
with a single-sentence, plain-English summary of WHAT this issue is
and WHY it matters, written for a reader who has read nothing else on
this page — not the issue title, not the analysis above. One sentence,
no jargon, naming the business thing affected and the consequence
(e.g. "Supplier delivery dates are being saved wrongly, so customers
can be shown incorrect stock-due information."). The approver decides
from this footer alone, so it must stand entirely on its own.

- XS/S → "a small, low-risk change"
- M → "a moderate, self-contained effort"
- L/XL → "a significant undertaking needing dedicated planning and
  sustained focused work"
- XXL → "a major effort that should likely be broken into smaller
  pieces before starting"

Never describe effort in terms of people or teams — no "multiple
teams", "a team of developers", "several engineers", or any
staffing/headcount framing, anywhere in the comment. Effort is time
spent by one developer: work spanning several repositories is "spread
across several repositories", full stop.

**Clear-size case** — one size, no options:

```
---

## 📋 Sizing & Approval

**TLDR**: [one plain sentence — what this issue is and why it
matters, self-contained.]

**T-Shirt Size: [SIZE]** — [plain effort statement for the size].

[1-2 sentences: why it matters in business terms — the benefit of
doing it, or the risk/cost of not doing it, drawn from THIS issue's
actual content, not generic filler.]

**To approve**: comment `Approved: [SIZE]` on this issue.

**To decline**: comment `Cancelled Because: [reason]` — the issue will
be closed as not planned.

**After approval**: the ticket is marked Ready on the tracking board.
Whoever works on it logs effort with `time: <n>h <note>` comments —
measured clock time actually spent, in 0.25h steps, never the approved
size; the cumulative total must never exceed wall-clock time since
approval. The first entry moves it to In Progress; closing the finished
issue moves it to Done and posts a size retrospective.
```

**Ambiguous case** — reuse the same underlying options as the
technical table above, but re-express EACH one for a business reader
(benefit/ROI/robustness, not technical pro/con), and give a
recommendation — you have the full technical picture, so don't punt a
judgement call you're equipped to make just because it also involves a
size trade-off:

```
---

## 📋 Sizing & Approval

**TLDR**: [one plain sentence — what this issue is and why it
matters, self-contained.]

There are [N] ways to approach this, at different sizes:

- **T-Shirt Size: [SIZE]** — [plain option label] ([plain effort
  statement]) — [business benefit/ROI/robustness framing, 1 sentence]
- **T-Shirt Size: [SIZE]** — [plain option label] ([plain effort
  statement]) — [business benefit/ROI/robustness framing, 1 sentence]

**Recommendation**: [SIZE] — [option label], because [business — not
technical — reason].

**To approve**: comment `Approved: [SIZE]` on this issue, naming
whichever option you'd like to proceed with.

**To decline**: comment `Cancelled Because: [reason]` — the issue will
be closed as not planned.

**After approval**: the ticket is marked Ready on the tracking board.
Whoever works on it logs effort with `time: <n>h <note>` comments —
measured clock time actually spent, in 0.25h steps, never the approved
size; the cumulative total must never exceed wall-clock time since
approval. The first entry moves it to In Progress; closing the finished
issue moves it to Done and posts a size retrospective.
```

Keep option labels in the footer plain-language (e.g. "the quick fix"
/ "the complete solution"), not the technical strategy names from the
table above — a business reader shouldn't need to cross-reference the
technical table to understand the footer. The size LETTER is the one
thing that's never paraphrased — always the literal `XS`/`S`/`M`/`L`/`XL`/`XXL`.

## Code Search Requirements

**CRITICAL**: You MUST aggressively search the codebase to find relevant source code.

For EVERY issue, you must:
1. **Identify key terms** from the issue (class names, method names, table names, file types, error messages, function names)
2. **Use the Read tool** to examine repository structure and search for relevant files
3. **Search strategically**: Look in logical places based on issue type (models/, controllers/, views/, migrations/, config/, etc.)
4. **Find specific locations**: Identify exact files, classes, methods, and functions that relate to the issue
5. **Create GitHub permalinks** to the specific lines/sections you find relevant

**GitHub Permalink Format**:
```
https://github.com/{owner}/{repo}/blob/{branch}/{path}#L{start}-L{end}
```

For single lines: `#L45`
For ranges: `#L45-L67`

**Examples**:
- `https://github.com/OWNER/REPO/blob/main/src/Customer.php#L45-L67` - Customer class definition
- `https://github.com/OWNER/REPO/blob/main/database/schema.sql#L123` - customers table schema

**When to search**:
- **Bug reports**: Find the code that likely contains the bug (exact method/class if possible)
- **Feature requests**: Find where similar functionality exists or where new code would go
- **Database issues**: Find schema files, migration files, ORM models, or query builders
- **API issues**: Find controller files, route definitions, API handlers
- **UI issues**: Find component files, template files, stylesheets
- **Configuration issues**: Find config files, environment files
- **Performance issues**: Find the slow queries, heavy computations, or inefficient loops

**CRITICAL QUALITY STANDARDS**:

1. **ONLY link to code that is DIRECTLY relevant to this specific issue**
   - Don't link to random files just because they contain a keyword
   - Don't link to generic base classes unless the issue specifically mentions them
   - Don't link to unrelated features that happen to use similar patterns

2. **Quality over quantity**:
   - 0 relevant links > 5 irrelevant links
   - It's better to say "no relevant code found" than to link to tangentially related files
   - Each link should have a clear, specific reason for relevance

3. **Verify relevance before linking**:
   - Read the actual code at the location you're linking to
   - Confirm it's actually related to the issue (not just contains a search term)
   - Only link if you can explain WHY this specific code is relevant

4. **If you cannot find relevant code**:
   - State clearly: "No specific source code files could be identified for this issue"
   - Explain why (e.g., "Issue description lacks specific details like file names, error messages, or component names")
   - Suggest what information would help: "To identify relevant code, please provide: [specific details needed]"
   - DO NOT link to random files to fill the section

5. **Red flags for bad links**:
   - ❌ "likely" or "probably" in your reasoning
   - ❌ "generic X handling" or "base Y functionality"
   - ❌ Linking to files you haven't actually read
   - ❌ Linking to entire large files with no specific line numbers

**Important**: Use actual file paths from the repository. Don't guess or make up file names.

## Required Output

Post a detailed comment using mcp__github__add_issue_comment with the
sections below **in this exact order** — Related Source Code and the
technical table are NOT optional trailing sections; they belong before
the footer, never after it:

1. A "## Triage Analysis" section with your assessment
2. A "### Related Source Code" section with links to relevant files (REQUIRED - see below)
3. Technical insights and recommendations (include the `### Sizing Decision Needed` developer-facing table here when `sizeAmbiguous` — see Sizing Guidelines)
4. The "## 📋 Sizing & Approval" footer (REQUIRED for every issue
   EXCEPT a sub-issue or a confirmed micro fast-lane issue, which get
   the one-line sub-issue or micro-fast-lane statement here instead —
   see Sizing Guidelines), and NOTHING
   human-readable after it — it is the literal last thing before the
   hidden metadata, not just "near the end." If step 2 or 3's content
   would otherwise land after this footer, reorder so it doesn't.
5. Hidden metadata at the end — **wrap it in an HTML comment
   (`<!-- ... -->`)**, not bare text. `==METADATA==` markers alone are
   NOT hidden — GitHub renders them as plain visible text, which is
   exactly the ugly raw-looking blob this instruction says to avoid.
   An HTML comment is what actually makes it invisible in the rendered
   comment while staying present in the raw body for parsing:

Clear-size case:
<!-- ==METADATA=={"priority":"...","size":"M","areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[{"issue":123,"confidence":"HIGH"}],"needsInfo":false,"sizeAmbiguous":false}==METADATA== -->

Ambiguous-size case (include a `### Sizing Decision Needed` table in the comment body — see Sizing Guidelines):
<!-- ==METADATA=={"priority":"...","sizeAmbiguous":true,"sizeOptions":[{"strategy":"...","pro":"...","con":"...","size":"S"},{"strategy":"...","pro":"...","con":"...","size":"M"}],"areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[{"issue":123,"confidence":"HIGH"}],"needsInfo":false}==METADATA== -->

Sub-issue case (no footer — see Sizing Guidelines; add `"carriedApproval":true` only if the native parent was read and is already size-approved):
<!-- ==METADATA=={"priority":"...","subIssue":true,"areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[],"needsInfo":false}==METADATA== -->

Confirmed micro fast-lane case (no footer — see Sizing Guidelines):
<!-- ==METADATA=={"priority":"...","microFastLane":true,"areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[],"needsInfo":false}==METADATA== -->

Omit `"size"` entirely when `sizeAmbiguous` is true — do not guess a
size and also flag it ambiguous, the two are mutually exclusive. When
`subIssue` or `microFastLane` is true, omit BOTH `"size"` and
`"sizeAmbiguous"` (the two flags are themselves mutually exclusive —
a sub-issue is decided on its parent, never micro on its own).

The JSON must be wrapped by `==METADATA==` on BOTH sides, exactly as
in the examples above — the closing marker before `-->` is required;
without it the metadata cannot be parsed and no labels get applied.

6. Footer with workflow version (after metadata):

---
*Analyzed by claude-triage vWORKFLOW_VERSION*

**Required: Related Source Code Section Format**

You MUST include a "### Related Source Code" section in your triage comment.

**IMPORTANT**: This section should contain ONLY code that is DIRECTLY relevant to the issue. Empty/no-code-found is perfectly acceptable and preferred over linking to tangentially related files.

Format when you HAVE found relevant code:

### Related Source Code

**[Category]**: Description of what this code does and how it relates to THIS SPECIFIC issue
- [`filename.ext:L123-L145`](https://github.com/owner/repo/blob/branch/path/filename.ext#L123-L145) - Specific explanation of why this exact code location is relevant

**Examples**:

For a database issue:
### Related Source Code

**Database Schema**:
- [`database/schema.sql:L45-L67`](https://github.com/OWNER/REPO/blob/main/database/schema.sql#L45-L67) - `customers` table definition with B2B/B2C fields
- [`models/Customer.php:L12-L34`](https://github.com/OWNER/REPO/blob/main/models/Customer.php#L12-L34) - Customer model class

**Order Processing**:
- [`controllers/OrderController.php:L156`](https://github.com/OWNER/REPO/blob/main/controllers/OrderController.php#L156) - Order creation method where customer type could be captured

For a UI bug:
### Related Source Code

**Component Files**:
- [`src/components/LoginForm.tsx:L23-L45`](https://github.com/owner/repo/blob/main/src/components/LoginForm.tsx#L23-L45) - Login form component with the broken validation
- [`src/styles/form.css:L67`](https://github.com/owner/repo/blob/main/src/styles/form.css#L67) - CSS rule causing the layout issue

If no relevant code found (GOOD example - be specific and helpful):
### Related Source Code

Unable to identify specific source code files for this issue.

**Why**: The issue description lacks specific technical details:
- No file names, paths, or components mentioned
- No error messages or stack traces provided
- No specific functionality or features referenced

**To identify relevant code, please provide**:
- Which specific feature or page is affected? (e.g., "customer checkout page", "order history report")
- Are there any error messages or logs?
- Which files or components have you already investigated?
- What specific behavior are you observing?

Once these details are provided, we can pinpoint the exact code locations that need modification.

## Needs-Info Decision

The `needsInfo` field in metadata controls whether the `needs-info` label is applied:

**Set `"needsInfo": true` when:**
- The issue is too vague to determine priority, complexity, or affected area
- A bug report has NO reproduction steps and NO error messages - impossible to assess
- A feature request has NO description of desired behavior beyond a one-line title
- You genuinely cannot triage this without specific information from the reporter

**When setting `needsInfo: true`:**
- Post a comment asking for the SINGLE most important piece of missing information
- Be specific: "Which page or feature is affected?" not "Please provide more details"
- Phrase as a friendly question, not a demand
- The workflow will automatically re-run when the user replies

**Set `"needsInfo": false` (default) when:**
- There is enough information to perform a meaningful triage
- The issue is clear even if not perfectly detailed
- You have found relevant source code or can assess priority/complexity

**Important**: Avoid asking for info just to be thorough. If you can assign reasonable priority and complexity, proceed with triage. Only ask when the issue is genuinely untriageable.

Remember: You are in READ-ONLY mode. Do NOT attempt to:
- Create branches or make code changes
- Use Edit, Write, Bash, or Task tools
- Implement solutions

Your role is EXCLUSIVELY analysis and commenting.

## GitHub Magic Phrases - USE CAREFULLY

**CRITICAL**: Avoid accidentally using GitHub's magic phrases unless intended:

**Auto-close keywords** (work in PRs/commits, close issues when merged):
- `closes #X`, `fixes #X`, `resolves #X` (and variations: closed, fixed, resolved)

**Duplicate marking** (works in comments, creates duplicate link):
- `Duplicate of #X` - Only use when explicitly marking duplicates

**Safe alternatives**:
- Instead of "This fixes #123" → use "This addresses #123"
- Instead of "This is a duplicate of #123" → use "This appears related to #123" (unless you want the duplicate link)

When referencing duplicates in your analysis:
- List them in the metadata: `"duplicates":[{"issue":123,"confidence":"HIGH"}]`
- Mention them in text using safe phrases: "This appears related to #123" or "See also #123"
- Do NOT use "Duplicate of #X" in comments (reserved for when we actually want to mark as duplicate)
EOF

# Replace placeholders in triage prompt
sed -i "s|REPOSITORY|${REPOSITORY}|g" "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
sed -i "s/ISSUE_NUMBER/${ISSUE_NUMBER}/g" "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
sed -i "s|WORKFLOW_VERSION|${WORKFLOW_VERSION}|g" "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"

# If in QnA mode, prepend special context to triage prompt
if [[ "${NEEDS_INFO_MODE}" == "true" ]]; then
  echo "🔄 QnA mode detected - adding re-triage context to prompt"
  ORIGINAL_PROMPT=$(cat "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt")
  cat > "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'QNAEOF'
## QnA Re-Triage Mode

⚠️ **Context**: This issue previously had a `needs-info` label because information was
insufficient for triage. A non-bot user has now commented with additional information.

**Your task**:
1. Read the complete issue manifest at the path provided in the system prompt (includes all comments)
2. Review the user's new response - is there now enough information to triage?
3. If YES: perform complete triage and set `"needsInfo": false` in metadata
4. If NO: ask ONE specific follow-up question (the single most important gap) and set `"needsInfo": true`

Do NOT ask multiple questions. Focus on the single most critical missing piece.

---

QNAEOF
  echo "${ORIGINAL_PROMPT}" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "✅ QnA mode context prepended to triage prompt"
fi

echo "✅ Prompts prepared successfully"
