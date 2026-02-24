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
    echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
    echo "Please review the repository context in @CLAUDE.md" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
    echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  fi

  # Append prompt-extra content if it exists (safe - no variable substitution)
  if [ -f ".github/prompt_extra/triage_prompt_extra.md" ]; then
    echo "📖 Found prompt-extra file"
    echo "## Project-Specific Context" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
    echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
    cat .github/prompt_extra/triage_prompt_extra.md >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
    echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  fi

  # Add issue section header
  echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  echo "## Issue to Evaluate" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/relevance-check.txt"

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
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "Please review the repository context in @CLAUDE.md" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Append prompt-extra content if it exists (safe - no variable substitution)
if [ -f ".github/prompt_extra/triage_prompt_extra.md" ]; then
  echo "## Project-Specific Context" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  cat .github/prompt_extra/triage_prompt_extra.md >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Add issue section
echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
echo "## Issue to Analyze" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
echo "Issue #ISSUE_NUMBER" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"

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
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "## Image Analysis Results" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "The following image analysis has been performed on screenshots in this issue:" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" <<'EOF'
${IMAGE_ANALYSIS}
EOF
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "**Use these image insights in your triage analysis.** Consider extracted error messages, visual observations, and technical recommendations when assessing priority, complexity, and areas affected." >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
  echo "" >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt"
fi

# Add the rest of the triage prompt
cat >> "${RUNNER_TEMP}/claude-prompts/triage-analysis.txt" << 'EOF'

## Available Issue Types

Check if this repository has custom issue types configured in GitHub.

## Your Task

Provide a comprehensive triage analysis. You must:

1. **Analyze the issue** thoroughly
2. **Determine priority** (critical/high/medium/low)
3. **Assess complexity** (trivial/simple/moderate/complex)
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

## Complexity Guidelines

- **trivial**: One-line fixes, typos (<1 hour)
- **simple**: Small, well-defined changes (1-4 hours)
- **moderate**: Multi-file changes, some complexity (1-3 days)
- **complex**: Architecture changes, significant effort (3+ days)

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
- `https://github.com/BallicomDev/example/blob/main/src/Customer.php#L45-L67` - Customer class definition
- `https://github.com/BallicomDev/example/blob/main/database/schema.sql#L123` - customers table schema

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

Post a detailed comment using mcp__github__add_issue_comment with:

1. A "## Triage Analysis" section with your assessment
2. A "### Related Source Code" section with links to relevant files (REQUIRED - see below)
3. Technical insights and recommendations
4. Hidden metadata at the end:

==METADATA=={"priority":"...","complexity":"...","areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[{"issue":123,"confidence":"HIGH"}],"needsInfo":false}==METADATA==

5. Footer with workflow version (after metadata):

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
- [`database/schema.sql:L45-L67`](https://github.com/BallicomDev/example/blob/main/database/schema.sql#L45-L67) - `customers` table definition with B2B/B2C fields
- [`models/Customer.php:L12-L34`](https://github.com/BallicomDev/example/blob/main/models/Customer.php#L12-L34) - Customer model class

**Order Processing**:
- [`controllers/OrderController.php:L156`](https://github.com/BallicomDev/example/blob/main/controllers/OrderController.php#L156) - Order creation method where customer type could be captured

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
