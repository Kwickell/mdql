# Hostile input

Inline script: </script><script>window.__pwned = 1</script>

Image with a handler: <img src="x" onerror="window.__pwned = 2">

A link that runs code: <a href="javascript:window.__pwned=3">click</a>

A stylesheet from elsewhere: <link rel="stylesheet" href="https://example.com/a.css">

A DNS prefetch, which no content security policy stops:
<link rel="dns-prefetch" href="//tracker.example.com">
<link rel="preconnect" href="https://tracker.example.com">

A redirect: <meta http-equiv="refresh" content="0;url=https://example.com/">

A frame: <iframe src="https://example.com/"></iframe>

A base tag: <base href="https://example.com/">

An object: <object data="https://example.com/x.swf"></object>

A form that posts somewhere: <form action="https://example.com/collect"><input name="a"></form>

A remote image: ![tracker](https://example.com/pixel.png)

Still fine: <kbd>⌘</kbd> and <details><summary>a summary</summary>hidden text</details>

- [x] task lists must survive
- [ ] and keep their checkboxes
