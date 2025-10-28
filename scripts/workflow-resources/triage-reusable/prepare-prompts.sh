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
7. **Search for duplicates** if it's a bug report

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

## Required Output

Post a detailed comment using mcp__github__add_issue_comment with:

1. A "## Triage Analysis" section with your assessment
2. Technical insights and recommendations
3. Hidden metadata at the end:

==METADATA=={"priority":"...","complexity":"...","areas":["..."],"specialFlags":["..."],"issueType":"...","duplicates":[{"issue":123,"confidence":"HIGH"}]}==METADATA==

4. Footer with workflow version (after metadata):

---
*Analyzed by claude-triage vWORKFLOW_VERSION*

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

echo "✅ Prompts prepared successfully"
