import AppKit
import SwiftUI

/// Removes AppKit safe-area insets from the full-width bar content.
final class BarHostingView<Content: View>: NSHostingView<Content> {
  override var safeAreaInsets: NSEdgeInsets {
    .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  override var safeAreaRect: NSRect {
    bounds
  }
}
