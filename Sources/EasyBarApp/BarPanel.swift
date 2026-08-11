import AppKit

/// Borderless non-activating panel used for the customizable EasyBar window.
final class BarPanel: NSPanel {
  var contextMenuProvider: ((Bool) -> NSMenu)?

  override var canBecomeKey: Bool {
    false
  }

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
