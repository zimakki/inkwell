# Live Reload

Save the file in your editor. The preview updates instantly — no refresh,
no build step.

Inkwell watches your markdown files via native filesystem notifications
(`fsevents` on macOS, `inotify` on Linux) and pushes re-rendered HTML to
the browser over a WebSocket connection the moment the bytes hit disk.

In diff mode, block-level changes get highlighted in place so you can see
exactly what changed and accept each edit with a single click.
