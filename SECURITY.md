# Security

## How the app protects your files

Espanso Snippets Manager runs a small helper on your computer that serves the editor page and reads and writes your Espanso match files.

- **Local only.** It listens on `localhost` and rejects any request whose `Host` header isn't `localhost:<port>` (or `127.0.0.1:<port>`). This blocks DNS-rebinding attacks from websites.
- **No cross-site writes.** Every request that changes something must carry a custom `X-Editor` header. Browsers don't let other websites send that header without a CORS preflight, and the helper never approves preflights.
- **Confined to the match folder.** File names are checked segment by segment. Only `.yml`/`.yaml` files inside Espanso's `match` folder can be read or written. `match/packages` is off limits.
- **Recoverable.** Every save first copies the previous version to a backup folder, then writes atomically (temporary file, then rename).
- **Nothing leaves your machine.** No network requests, no analytics. The YAML library is bundled into the page.
- **Short-lived.** The helper stops when the editor window closes, or after 8 hours without activity.

The helper doesn't use authentication tokens. Any program already running as your user can read and write your Espanso files anyway, so it adds no access that such a program lacks.

## Reporting a vulnerability

Please **don't** open a public issue. Use GitHub's private [security advisory form](https://github.com/gilikarn/Espanso-Snippets-Manager/security/advisories/new) instead. You'll get a response as soon as possible. Fixes are released as a new version with credit to the reporter, unless you prefer otherwise.
