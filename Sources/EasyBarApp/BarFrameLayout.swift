import AppKit

/// Computes the custom bar frame independently from AppKit window creation.
enum BarFrameLayout {
  /// Returns a full-width rectangle anchored to the top of the supplied screen area.
  static func frame(in baseFrame: NSRect, height: CGFloat) -> NSRect {
    NSRect(
      x: baseFrame.minX,
      y: baseFrame.maxY - height,
      width: baseFrame.width,
      height: height
    )
  }
}
