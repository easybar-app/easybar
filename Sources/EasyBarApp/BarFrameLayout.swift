import AppKit

/// Computes the custom bar frame independently from AppKit window creation.
enum BarFrameLayout {
  /// Returns a full-screen-width rectangle anchored to the supplied top edge.
  static func frame(in screenFrame: NSRect, topEdge: CGFloat, height: CGFloat) -> NSRect {
    NSRect(
      x: screenFrame.minX,
      y: topEdge - height,
      width: screenFrame.width,
      height: height
    )
  }
}
