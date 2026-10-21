# Contributing

Thanks for helping make Espanso Snippets Manager better! Bug reports, ideas and pull requests are all welcome.

## Questions and ideas

Ask in [Discussions](https://github.com/gilikarn/Espanso-Snippets-Manager/discussions). That keeps Issues for confirmed bugs and agreed work.

## Reporting a problem

[Open an issue](https://github.com/gilikarn/Espanso-Snippets-Manager/issues/new/choose). It helps a lot if you include:

- your OS and how you installed the app;
- the output of `server.ps1 -PrintConfig` (Windows) or `server.py --print-config` (macOS/Linux);
- a small snippet file that shows the problem. Please remove anything personal first.

## Making changes

```sh
git clone https://github.com/gilikarn/Espanso-Snippets-Manager.git
cd Espanso-Snippets-Manager
npm install
npx playwright install chromium
npm test
```

How the project is laid out:

| Path | What it is |
|---|---|
| `src/index.html` | The whole editor UI: plain HTML, CSS and JavaScript, no framework |
| `src/server.ps1` | Local helper for Windows (Windows PowerShell 5.1 and PowerShell 7) |
| `src/server.py` | Local helper for macOS and Linux (Python 3.8+, standard library only) |
| `install/` | Install and uninstall scripts |
| `scripts/build.mjs` | Inlines js-yaml and the version into the page, copies everything to `dist/` |
| `tests/` | Helper tests (Python and PowerShell), browser tests (Playwright), sample Espanso files |

Guidelines:

- **Keep both helpers in sync.** They implement the same API (`/api/files`, `/api/file`, `/api/status`, `/api/quit`, `/api/openfolder`). If you change one, change the other and their tests.
- **No new runtime dependencies.** The app must keep working with what ships with the OS (PowerShell on Windows, Python on macOS/Linux) and offline.
- **PowerShell files stay ASCII.** Windows PowerShell 5.1 misreads BOM-less UTF-8, and CI checks for this.
- **Never lose user data.** Anything the editor doesn't understand must survive a save. Add a fixture and a test when you touch serialization.
- **Run `npm test`** before opening a pull request. CI also runs the PowerShell tests on Windows and the installers on all three systems.
- **Screenshots** in the README come from `npm run screenshots`, using the sample files only.

## Releasing (maintainers)

1. Update `version` in `package.json` and add a section to `CHANGELOG.md`.
2. Commit, then tag: `git tag v1.2.3 && git push --tags`.
3. The *Release* workflow builds the archives and publishes the GitHub release. The install one-liners always fetch the latest release.

## Be kind

Be respectful and assume good intent. Harassment or personal attacks aren't welcome anywhere in this project.
