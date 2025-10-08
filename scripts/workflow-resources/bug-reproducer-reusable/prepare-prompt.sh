#!/usr/bin/env bash
#
# Prepare Bug Reproduction Prompt for Claude
#
# This script creates a comprehensive prompt for Claude to reproduce bugs.
# It includes issue information, repository context, and task instructions.
#
# Required environment variables:
#   ISSUE_NUMBER - Issue number to reproduce
#   ISSUE_TITLE - Issue title
#   ISSUE_BODY - Issue body content
#   PROMPT_DIR - Directory to write prompt file to
#
# Output files:
#   ${PROMPT_DIR}/bug-reproduction.txt - Complete prompt for Claude
#

set -e

mkdir -p "$PROMPT_DIR"

# Create bug reproduction prompt template
cat > "$PROMPT_DIR/bug-reproduction.txt" << 'EOF'
# Bug Reproduction Task

You are tasked with creating automated tests that reproduce a bug reported in issue #ISSUE_NUMBER.

## Issue Information

**Title:** ISSUE_TITLE

**Description:**
EOF

# Add reference to CLAUDE.md if it exists
if [ -f "CLAUDE.md" ]; then
  echo "Please review the repository context in @CLAUDE.md" >> "$PROMPT_DIR/bug-reproduction.txt"
  echo "" >> "$PROMPT_DIR/bug-reproduction.txt"
fi

# Append prompt-extra content if it exists
if [ -f ".github/prompt_extra/bug_reproducer_prompt_extra.md" ]; then
  echo "## Project-Specific Context" >> "$PROMPT_DIR/bug-reproduction.txt"
  echo "" >> "$PROMPT_DIR/bug-reproduction.txt"
  cat .github/prompt_extra/bug_reproducer_prompt_extra.md >> "$PROMPT_DIR/bug-reproduction.txt"
  echo "" >> "$PROMPT_DIR/bug-reproduction.txt"
fi

# Add task instructions
cat >> "$PROMPT_DIR/bug-reproduction.txt" << 'EOF'

## Your Task

Create automated tests that reproduce this bug. Follow these steps:

### 1. Analyze the Bug Report
- Understand the bug description and expected vs actual behavior
- Identify affected code areas using Read, Glob, and Grep tools
- Review related code, tests, and documentation

### 2. Detect Test Framework
Automatically detect the test framework used in this repository:
- **Python**: pytest (pytest.ini, conftest.py, test_*.py)
- **JavaScript/TypeScript**: Jest, Mocha, Vitest (package.json, *.test.js, *.spec.ts)
- **Go**: go test (*_test.go files)
- **Rust**: cargo test (Cargo.toml, tests/ directory)
- **PHP**: PHPUnit (phpunit.xml, *Test.php)
- **Java**: JUnit (pom.xml, build.gradle, *Test.java)
- **Ruby**: RSpec (spec/ directory, *_spec.rb)

If no test framework is found, suggest one appropriate for the language.

### 3. Create Reproduction Tests
- Create a new test file in the appropriate location
- Write failing tests that demonstrate the bug
- Follow the repository's existing test patterns and conventions
- Include clear test names describing the bug
- Add comments explaining what the test validates

### 4. Document Your Work
- Create a clear commit message describing the reproduction tests
- Update the issue with a comment explaining:
  - What tests were created
  - Where they are located
  - How to run them
  - What behavior they demonstrate

### 5. Create Branch and Draft PR
- Create branch: `claude/bug-ISSUE_NUMBER-reproduce`
- Commit the test file(s)
- Open a draft PR with:
  - Title: "Bug Reproduction Tests: ISSUE_TITLE"
  - Body explaining the tests and linking to the issue
  - Mark as draft (not ready for merge)

## Available Tools

You have access to:
- **Read**: Read existing files and code
- **Write**: Create new test files
- **Edit**: Modify existing files if needed
- **Glob**: Find files by pattern
- **Grep**: Search for code patterns
- **Bash**: Run commands (install dependencies, run tests)
- **MCP GitHub Tools**:
  - `mcp__github__get_issue`: Fetch issue details
  - `mcp__github__add_issue_comment`: Post comments
  - `mcp__github__create_branch`: Create reproduction branch
  - `mcp__github__create_pull_request`: Open draft PR

## Timeout Handling

You have 30 minutes to complete this task. If you cannot finish:
- Comment on the issue with your progress
- Explain what you discovered and what tests you started
- Commit any work-in-progress code to the branch
- Provide guidance for manual completion

## Important Constraints

- **Tests should FAIL**: The tests demonstrate the bug, so they should fail
- **No bug fixes**: Do NOT attempt to fix the bug, only reproduce it
- **Follow conventions**: Match the repository's existing test structure
- **Clear documentation**: Explain everything clearly in comments and commit messages

## Success Criteria

✅ Created failing tests that reproduce the bug
✅ Tests are in appropriate location with proper naming
✅ Branch created with format: claude/bug-ISSUE_NUMBER-reproduce
✅ Draft PR opened with clear description
✅ Issue commented with test details and how to run them

Begin bug reproduction now.
EOF

# Replace placeholders - using sed carefully to avoid shell injection
sed -i "s/ISSUE_NUMBER/${ISSUE_NUMBER}/g" "$PROMPT_DIR/bug-reproduction.txt"

# For ISSUE_TITLE, we need to escape special characters
# Create a temporary file with the title
TITLE_TEMP=$(mktemp)
echo "$ISSUE_TITLE" > "$TITLE_TEMP"
# Use a more robust replacement method
awk -v title="$ISSUE_TITLE" '{gsub(/ISSUE_TITLE/, title)}1' "$PROMPT_DIR/bug-reproduction.txt" > "$PROMPT_DIR/bug-reproduction.txt.tmp"
mv "$PROMPT_DIR/bug-reproduction.txt.tmp" "$PROMPT_DIR/bug-reproduction.txt"
rm -f "$TITLE_TEMP"

# Append issue body directly (no shell expansion, no YAML escaping needed)
echo "" >> "$PROMPT_DIR/bug-reproduction.txt"
echo "$ISSUE_BODY" >> "$PROMPT_DIR/bug-reproduction.txt"

echo "✅ Prompt prepared successfully"
