import AppKit
import SwiftUI

/// Removes AppKit safe-area insets from the full-width bar content.
final class BarHostingView<Content: View>: NSHostingView<Content> {
  /// Disables the host view's safe-area insets so the bar fills its panel.
  override var safeAreaInsets: NSEdgeInsets {
    .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  /// Uses the full host bounds for safe-area layout.
  override var safeAreaRect: NSRect {
    bounds
  }
}
