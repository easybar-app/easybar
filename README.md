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

See more screenshots in the [documentation](https://easybar.dev/).

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

## License

Licensed under the [Apache License 2.0](./LICENSE).
