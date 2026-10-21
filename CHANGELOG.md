# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-21

### Added
- Snippet editor for Espanso match files: searchable list, multi-shortcut snippets, expand-when options (`word`, `left_word`, `right_word`), case propagation, Markdown/HTML output, search-bar label and search terms.
- Insert menu for the cursor position (`$|$`), date and time variables and the clipboard.
- "Try it" box that simulates expansion, including unsaved changes.
- Duplicate-shortcut warnings across files and one-click merging of snippets with identical text.
- Safe saving: a backup before every save, atomic writes, conflict detection when a file changed elsewhere, and advanced entries (regex, forms, shell variables) kept untouched.
- Support for subfolders in the match folder and creating new files.
- Local helpers for Windows (PowerShell) and macOS/Linux (Python), localhost only.
- Installers for Windows, macOS and Linux, plus uninstallers.

[Unreleased]: https://github.com/gilikarn/Espanso-Snippets-Manager/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/gilikarn/Espanso-Snippets-Manager/releases/tag/v1.0.0
