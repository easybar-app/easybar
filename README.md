# EasyBar

EasyBar is the customizable full-width macOS top bar frontend powered by
[`easybar-kit`](../easybar-kit).

EasyBar owns the customizable top-bar presentation and application packaging. Lua execution, widget
rendering, events, popups, context menus, themes, inbox state, package management, and system
integrations are provided by EasyBarKit. The sibling `easybar-native` frontend consumes the same
shared runtime.

## Repository layout

```text
../easybar-kit      shared runtime/widget framework and support executables
../easybar          this customizable top-bar frontend and release packaging
../easybar-native   native NSStatusItem frontend
../widgets          shared Lua packages
```

The normal Swift package dependency uses the released EasyBarKit version from `Package.swift`.
Local source-tree commands such as `make run` and `make install-local` use the sibling
`../easybar-kit` checkout so both repositories can be tested together.

## Build and test

```bash
make build
make test
make check
```

`make check` also validates the Homebrew cask and helper-agent formula generator used by releases.

To run directly from source:

```bash
make run
```

`make run` builds EasyBarKit's `EasyBarLuaRuntime` helper first and exposes it to EasyBar's debug
build directory.

## Install the current checkout

Install a complete local development build with:

```bash
make install-local
```

The local build contains:

```text
~/Applications/EasyBar.app
~/.local/bin/easybar
~/Library/Application Support/EasyBar/Agents/EasyBarCalendarAgent.app
~/Library/Application Support/EasyBar/Agents/EasyBarNetworkAgent.app
~/Library/LaunchAgents/io.github.gi8lino.easybar.local.*.plist
```

The build receives a Git-derived version containing both the EasyBar and EasyBarKit commits, for
example:

```text
0.53.2-dev.a1b2c3d4.kit.e5f6a7b8
```

If either checkout has staged, unstaged, or untracked changes, the version ends in `-dirty`.
Inspect it before installing with:

```bash
make print-local-version
```

Local bundles are ad-hoc signed and are not notarized. After copying the app, helper agents, and
CLI into their install destinations, the installer removes `com.apple.quarantine` and verifies that
the attribute is gone before starting the agents or launching EasyBar.

Override the default locations or architecture when needed:

```bash
make install-local LOCAL_INSTALL_ARCH=universal
make install-local LOCAL_APP_DIR=/Applications
make install-local LOCAL_BIN_DIR=/usr/local/bin
make install-local EASYBAR_KIT_ROOT=/path/to/easybar-kit
```

Remove the standalone installation and restore the Homebrew agent service states recorded before
the first local install with:

```bash
make uninstall-local
```

## Release packaging

Build the same release artifacts produced by GitHub Actions with:

```bash
make release ARCH=universal VERSION=0.54.0
```

The release produces:

```text
dist/EasyBar-0.54.0.zip
dist/EasyBarCalendarAgent-0.54.0.zip
dist/EasyBarNetworkAgent-0.54.0.zip
```

A pushed `v*` tag runs the release workflow on macOS, verifies the repository, builds and uploads
all three archives to the GitHub release, and then dispatches `update-homebrew-cask.yml`. That
workflow downloads the immutable release archives, calculates their SHA-256 values, updates the
EasyBar cask plus the calendar/network agent formulae in `easybar-app/homebrew-tap`, and commits the
changes with `HOMEBREW_TAP_TOKEN`.

The Homebrew definitions also remove `com.apple.quarantine` from the downloaded EasyBar app, CLI,
and helper-agent bundles because the published artifacts are currently ad-hoc signed rather than
notarized.

## Presentation boundary

This repository owns only the custom-bar surface:

- `BarPanel`: the non-activating full-width AppKit panel.
- `BarWindowController`: screen placement and lifecycle.
- `BarContentView`: left/center/right layout and bar background styling.

Everything rendered inside those slots comes from `EasyBarPresentationModel` in EasyBarKit.
