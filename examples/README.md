# Lua Widget Examples

The app repository keeps small, self-contained Lua examples for learning and manual runtime checks.
Installable integrations are maintained in the
[official widgets repository](https://github.com/easybar-app/widgets) and discovered through the
[widget registry](https://github.com/easybar-app/registry).

## Lua discovery

EasyBar recursively loads regular `.lua` files below the configured widgets directory, excluding
reusable modules below `shared/`. Package-managed widgets are loaded separately from the managed
store and use their declared entrypoint.

Reusable modules loaded with `require(...)` should keep their top level side-effect-free. Installable
packages use explicit metadata so the package manager can distinguish widget entrypoints from
library exports.

## Assets

Use a file-relative path for an asset stored beside a widget:

```lua
easybar.asset("icon.svg")
```

Use `@/` for an asset relative to the configured widgets directory:

```lua
easybar.asset("@/assets/github.svg")
```

## Trying an example

Copy the selected `.lua` file into the configured widgets directory. For directory-based examples,
copy the complete directory so its README and assets stay beside the entrypoint. EasyBar discovers
the copied Lua files on the next widget reload.
