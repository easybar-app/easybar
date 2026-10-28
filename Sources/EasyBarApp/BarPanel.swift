import AppKit

/// Borderless non-activating panel used for the customizable EasyBar window.
final class BarPanel: NSPanel {
  /// Produces the context menu for a right-click, optionally including developer actions.
  var contextMenuProvider: ((Bool) -> NSMenu)?

  /// Keeps the bar from becoming the active key window.
  override var canBecomeKey: Bool {
    false
  }

  /// Prevents the bar from becoming the application's main window.
  override var canBecomeMain: Bool {
    false
  }

  /// Preserves the explicitly calculated full-width frame instead of applying AppKit constraints.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }

  /// Opens the shared bar context menu and exposes developer items while Shift is held.
  override func rightMouseUp(with event: NSEvent) {
    let showDeveloperSection = event.modifierFlags.contains(.shift)

    guard let menu = contextMenuProvider?(showDeveloperSection), let targetView = contentView else {
      super.rightMouseUp(with: event)
      return
    }

    NSMenu.popUpContextMenu(menu, with: event, for: targetView)
  }
}
