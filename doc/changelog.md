# Writing the changelog

`CHANGELOG.md` is the operator-facing release notes. It ships inside the container
and is served at `/admin/changelog`, so it is read by people running ComputeStacks,
not by people developing it. `rake generate_changelog` renders it to
`CHANGELOG.html` during the image build (`Dockerfile`).

## Entry format

One bullet per change, newest release section first:

```markdown
## v9.7.6

- [FIX] **Bold one-line summary of what changed.** Then prose: what an operator
  saw, why it happened, and what is different now.
```

Four tags, and the tag must lead the entry text: `[FEATURE]`, `[FIX]`, `[CHANGE]`,
`[DEPRECATED]`. The renderer turns each into a coloured badge. A literal `[FIX]`
inside a code fence is left alone.

Entries are prose, not commit subjects. Describe the symptom in terms the operator
experienced ("the admin dashboard returned a gateway error"), then the cause, then
the fix. Naming a class or method is fine where it is the clearest way to say it.

**Length.** Around 1,000 characters is the working norm and reads fine as a single
paragraph. Past roughly 1,500, split it — see below. One entry once reached 4,888
characters in a single paragraph and was unreadable in the browser.

## The renderer is Redcarpet, not CommonMark

`GitHub::Markup` picks the first markdown implementation it can load, and this
project has only **Redcarpet** (`commonmarker` and `kramdown` are not in the
bundle). Two consequences that will bite you, both verified against Redcarpet
3.6.1:

**Continuation paragraphs need a 4-space indent.** Two spaces is valid CommonMark
and does the wrong thing here — Redcarpet closes the list and emits the paragraph
as a sibling of it, which also picks up the release-trailer styling by mistake.

```markdown
- [FEATURE] **Lead sentence.** First paragraph.

    Second paragraph, indented four spaces.

    Third paragraph.
```

**Do not nest a sub-list inside an entry.** Redcarpet closes the outer list when
the nested list ends, so anything after it silently falls out of the entry. Use
bold-led paragraphs instead of sub-bullets:

```markdown
    **The first exception is …** prose.

    **The second is off unless you ask for it.** prose.
```

A release containing one multi-paragraph entry renders that release's whole list
as a *loose* list — every `<li>` in it gets wrapped in `<p>`. That is expected;
`app/assets/stylesheets/changelog.scss` is written so loose and tight sections end
up with the same rhythm (0.8em between paragraphs within an entry, 1.4em between
entries).

## Release trailers

A standalone paragraph after a release's list — not indented, so it is a sibling of
the `<ul>` — renders as a set-apart callout. Use it for instructions to the
operator, not for another change:

```markdown
**This is an ordinary upgrade** — `cstacks upgrade`, no migrations and no
node-side changes.
```

## Presentation belongs in CSS

`lib/tasks/generate_changelog.rake` produces semantic HTML and the tag badges, and
nothing else. Styling lives in `app/assets/stylesheets/changelog.scss`, which is
picked up automatically by `application.scss`'s `require_tree .`.

The task used to strip every `<p>` and set `list-unstyled` on the list, which left
each release as one unbroken wall of text. Don't add presentation back into it.

## Version sync

Three places have to agree at release time:

| Where | What |
| --- | --- |
| `VERSION` | `9.7.6` |
| `CHANGELOG.md` | the newest `## v9.7.6` heading |
| `.gitlab-ci.yml` | `CS_MINOR_VERSION: "9.7"`, `CS_MAJOR_VERSION: "9"` |

`rake version:check` verifies these, and `generate_changelog` invokes it. They
drifted before it existed: `CS_MINOR_VERSION` sat at `9.4` through the 9.5, 9.6 and
9.7 releases, so `:9.4` was the moving docker tag for all three.

The check is split across two places, because `.dockerignore` keeps `.gitlab-ci.yml`
out of the build context — the task cannot see it from inside the image:

- `rake version:check` always compares `VERSION` against the newest `## vX.Y.Z`
  heading, and compares the tag variables **only when `.gitlab-ci.yml` is readable**
  (locally, and in `just build`'s context). It says which of the two it did.
- The `build` CI job re-checks the tag variables against `VERSION` in the shell,
  before `docker build`, where both are available.

It is fine for `CHANGELOG.md` to run **ahead** of `VERSION` while a release is being
written — entries accumulate under the next version's heading, and `VERSION` is
bumped as the release act. The check only runs at image build time (the `build` CI
job never runs on a push), so ordinary development is unaffected. `SKIP_VERSION_CHECK=1`
escapes it.

## Previewing locally

`CHANGELOG.html` is gitignored and only generated during the image build, so
`/admin/changelog` shows `Error!: No such file or directory` in a fresh checkout
until you build it once:

```
bundle exec rake generate_changelog
```

Then open `/admin/changelog` (port 3005 in dev). Re-run it after every edit to
`CHANGELOG.md` — the page reads the generated HTML, not the markdown.
