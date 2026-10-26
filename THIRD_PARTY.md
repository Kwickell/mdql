# Third party software

mdql renders Markdown with existing engines rather than its own parser. They
are vendored under `Resources/vendor/` and shipped inside the app bundle, so a
build needs neither node nor the network.

Each licence text is in `Resources/vendor/licenses/`. Versions are pinned in
`tools/vendor.sh` and the file hashes are listed in
`Resources/vendor/MANIFEST.txt`.

| Package | Version | Licence | What it does |
|---|---|---|---|
| [markdown-it](https://github.com/markdown-it/markdown-it) | 14.1.0 | MIT | Parses the Markdown |
| [markdown-it-footnote](https://github.com/markdown-it/markdown-it-footnote) | 4.0.0 | MIT | Footnotes |
| [markdown-it-deflist](https://github.com/markdown-it/markdown-it-deflist) | 3.0.0 | MIT | Definition lists |
| [markdown-it-mark](https://github.com/markdown-it/markdown-it-mark) | 4.0.0 | MIT | `==highlight==` |
| [markdown-it-sub](https://github.com/markdown-it/markdown-it-sub) | 2.0.0 | MIT | `~subscript~` |
| [markdown-it-sup](https://github.com/markdown-it/markdown-it-sup) | 2.0.0 | MIT | `^superscript^` |
| [markdown-it-abbr](https://github.com/markdown-it/markdown-it-abbr) | 2.0.0 | MIT | Abbreviations |
| [markdown-it-task-lists](https://github.com/revin/markdown-it-task-lists) | 2.1.1 | ISC | Task list checkboxes |
| [markdown-it-texmath](https://github.com/goessner/markdown-it-texmath) | 1.0.0 | MIT | Claims `$…$` during parsing |
| [KaTeX](https://github.com/KaTeX/KaTeX) | 0.16.11 | MIT | Renders the maths |
| [Mermaid](https://github.com/mermaid-js/mermaid) | 11.4.1 | MIT | Renders the diagrams |
| [highlight.js](https://github.com/highlightjs/highlight.js) | 11.11.1 | BSD-3-Clause | Syntax highlighting |

The highlight.js browser bundle and its two themes come from
[cdnjs](https://cdnjs.com/libraries/highlight.js); the npm package is unpacked
only to collect the licence that covers them.

To refresh them all, run `make vendor`. It needs node and the network, and it
fails rather than continuing if a package ships no licence file.
