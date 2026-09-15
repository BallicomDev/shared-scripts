<!-- AGENT_RULES_START -->

## Reading from GitHub

Never fetch a github.com URL over HTTP. Parse it for owner, repository
and number, then use the `gh` CLI or the API instead. A plain fetch
returns the logged-OUT page: no comments, no diff, and nothing at all
for a private repository.

## Referencing an issue, pull request or run

Write every reference as a full
`https://github.com/<owner>/<repo>/issues/<number>` URL. Never a bare
`#123`, an `<owner>/<repo>#123`, or a `GH-123`.

- A bare `#123` resolves against whatever repository the text is READ
  in, so the same sentence means a different issue in a commit message,
  a linked document, a chat paste or a comment on another repository —
  and it resolves to the wrong one silently rather than failing.
- `<owner>/<repo>#123` is unambiguous but only becomes a link on GitHub;
  anywhere else it is dead text.
- A full URL is unambiguous everywhere, and GitHub still renders it as
  the short `<owner>/<repo>#123` form in a comment, so nothing is lost.
- If you do not know whether a number is an issue or a pull request,
  write `/issues/<number>`: GitHub redirects that to `/pull/<number>`.
  The reverse is not true.

This applies to bodies, comments, commit messages and descriptions
alike, including a link to a file or a line — use a commit-pinned
permalink for those.

Never pair a closing keyword (`fixes`, `closes`, `resolves`, and the
rest) with a reference in a commit message or description: it closes the
target automatically on merge, with a full URL just as with a short
reference.

<!-- AGENT_RULES_END -->
