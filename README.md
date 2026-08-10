# EasyBar

EasyBar is the customizable full-width macOS top bar frontend powered by
[`easybar-kit`](../easybar-kit).

EasyBar owns only the customizable top-bar presentation. Lua execution, widget rendering, events,
popups, context menus, themes, inbox state, package management, and system integrations are provided
by EasyBarKit. The sibling `easybar-native` frontend consumes the same shared runtime.

## Repository layout

```text
../easybar-kit      shared runtime/widget framework
../easybar          this customizable top-bar frontend
../easybar-native   native NSStatusItem frontend
../widgets          shared Lua packages
```

The Swift package expects `../easybar-kit` to exist next to this checkout for local development.

## Build

```bash
make build
make test
make check
```

To run from a source checkout:

```bash
make run
```

`make run` builds EasyBarKit's `EasyBarLuaRuntime` helper first and links it into this checkout's
debug build directory, matching the runtime discovery behavior used by EasyBarKit.

Install a release build and the shared CLI, runtime, and helper agents into `~/.local/bin` with:

```bash
make install-local
```

Override the destination with `LOCAL_BIN_DIR=/path/to/bin`.

## Presentation boundary

This repository owns only the custom-bar surface:

- `BarPanel`: the non-activating full-width AppKit panel.
- `BarWindowController`: screen placement and lifecycle.
- `BarContentView`: left/center/right layout and bar background styling.

Everything rendered inside those slots comes from `EasyBarPresentationModel` in EasyBarKit.
