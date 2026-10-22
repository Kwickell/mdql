# Markdown Quick Look

A Quick Look preview and thumbnail extension for macOS. Press space on a `.md`
file in Finder and read it as a document instead of as source.


## What it renders

- CommonMark and GitHub-flavoured Markdown: tables, task lists, strikethrough,
  footnotes, definition lists, abbreviations, `==highlight==`, sub and sup
- Syntax highlighting for fenced code (highlight.js, automatic language detection)
- Mermaid diagrams: flowcharts, sequence, pie, gantt, state, ER, xychart
- LaTeX maths, inline and display, through KaTeX
- GitHub and Obsidian callouts: `> [!NOTE]`, `> [!WARNING]`, `> [!CAUTION]`, …
- Obsidian wiki links, `[[Page]]` and `[[Page|alias]]`, and `![[image.png]]` embeds
- YAML front matter, shown as a header panel rather than as a wall of dashes
- Images next to the file; anything it cannot read is marked in place
- Light and dark, following the appearance of the window it draws into
- Finder thumbnails of the first page

## Install

    make install

That builds `MarkdownQuickLook.app`, copies it to `/Applications` and registers
both extensions. `make uninstall` removes it again. The app itself only hosts
the extensions and tells you where the Quick Look settings live.

Bundle identifier and signing identity are overridable:

    MDQL_BUNDLE_ID=com.example.MarkdownQuickLook MDQL_SIGN_IDENTITY="Developer ID Application: …" make install

## Privacy

A preview makes no network requests. The page's content security policy names
no `http` or `https` source of any kind, so a remote image or stylesheet in a
markdown file is blocked rather than fetched, and every asset is served by the
extension over a private `mdql:` scheme.

Raw HTML in a markdown file is parsed into an inert document and stripped of
`script`, `link`, `meta`, `base`, `iframe`, `object` and `embed`, plus event
handler attributes and `javascript:` URLs, before it is adopted into the page.
A `<link rel="dns-prefetch">` would otherwise leak a lookup no policy can stop.
Scripts are allowed by nonce alone, so a `.js` file sitting next to the
markdown cannot be loaded even if something did inject a tag.

The extensions do hold `com.apple.security.network.client`. WebKit refuses to
load anything at all in a sandboxed app extension without it, including local
content over a custom scheme. The policy above is what actually keeps a preview
offline; the entitlement is the price of using a web view here.

## Layout

    Sources/MarkdownQuickLookCore/   shared: decoding, page building, routing, the web renderer
    Extensions/Preview/              QLPreviewingController
    Extensions/Thumbnail/            QLThumbnailProvider
    App/                             the bundle the extensions live in
    Resources/                       preview.html, style.css, render.js, vendor/
    CLI/                             mdql-render, writes a page to a folder
    Probe/                           mdql-probe, renders and reports what the DOM contains
    QLCheck/                         mdql-qlcheck, renders through the installed extension

Markdown is parsed in the web view, not in Swift. `Resources/render.js` loads
only the engines a given file needs, so a plain note never pays for Mermaid's
2.5 MB.

## Working on it

    make test        # unit tests
    make probe       # render fixtures/kitchen-sink.md and report what the DOM holds
    make build       # build the app bundle
    make vendor      # refresh the JavaScript engines (needs node and the network)

`mdql-probe` is the useful one: it renders through the real web view and prints
counts of what came out, so a change that silently breaks diagrams or maths
shows up as a number.

Watch what the installed extensions are doing:

    log stream --level debug --predicate 'subsystem == "com.kimwickell.MarkdownQuickLook"'

Render times and failures go there. Anything derived from the document itself,
such as file names, requested paths and page error messages, is logged as
private and shows up as `<private>` unless you have enabled private data
logging. For content-level debugging use `mdql-probe`, which prints everything.

## Vendored engines

`Resources/vendor/` holds markdown-it and its plugins, highlight.js, KaTeX,
markdown-it-texmath and Mermaid, pinned by version in `tools/vendor.sh` and
listed with hashes in `Resources/vendor/MANIFEST.txt`. They are committed, so a
build needs neither node nor the network.
