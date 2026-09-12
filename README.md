# EasyBar

![EasyBar screenshot](https://easybar.dev/assets/bar.png)

EasyBar is a lightweight, scriptable macOS status bar built with SwiftUI and Lua. It combines native
widgets with custom Lua widgets and integrates with AeroSpace.

## Features

- Native widgets for Spaces, apps, system status, calendar, and more
- Scriptable Lua widgets with events, popups, groups, and context menus
- Installable Lua widgets and libraries from the official package registry
- Shared Inbox with unread state, grouping, Markdown, and widget actions
- File-based TOML themes and comment-preserving configuration updates
- AeroSpace integration and separate calendar and network helper agents
- Menu-bar controller and CLI for runtime control and diagnostics

See more screenshots in the [EasyBar overview](https://easybar.dev/products/easybar/) and the
[built-in widget guides](https://easybar.dev/products/easybar/configuration/builtins/).

## Requirements

- macOS 14 Sonoma or newer
- [Homebrew](https://brew.sh/) for installation
- AeroSpace 0.21.0 or newer when using AeroSpace-backed widgets

## Installation

```bash
brew tap easybar-app/tap
brew install --cask easybar-app/tap/easybar
open -a EasyBar
```

See the [installation guide](https://easybar.dev/products/easybar/installation/) for upgrades,
verification, and removal.

## Documentation

The full documentation is available at [easybar.dev](https://easybar.dev/).

- [Quick start](https://easybar.dev/products/easybar/quick-start/)
- [Configuration](https://easybar.dev/products/easybar/configuration/overview/)
- [Themes](https://easybar.dev/products/easybar/configuration/themes/)
- [Lua widgets](https://easybar.dev/lua/overview/)
- [Widget packages](https://easybar.dev/widget-store/overview/)
- [Runtime and troubleshooting](https://easybar.dev/products/easybar/runtime/troubleshooting/)
- [Development](https://easybar.dev/internals/development/)

## Development helpers

The Makefile uses [dev-tools](https://github.com/gi8lino/dev-tools) v0.7.0 for help and
semantic-version tagging. The bootstrap is committed in `bin/dev-tools.mk`; Make downloads
modules and helpers into the ignored `bin/.dev-tools/` cache on first use. This requires
`curl` and network access initially, and Python 3 to run the helpers.

Run `make help` for available targets. `make tag`, `tag-patch`, `tag-minor`, and `tag-major`
remain aliases for the shared `current`, `patch`, `minor`, and `major` targets. The shared
helper selects the highest stable semantic-version tag in the repository and creates
lightweight tags. `make push-tags` aliases `push` and pushes all local tags only; push
commits separately with `git push`.

## License

Licensed under the [Apache License 2.0](./LICENSE).
