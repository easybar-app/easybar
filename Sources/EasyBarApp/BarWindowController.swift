import AppKit
import EasyBarKit
import EasyBarShared
import SwiftUI

/// Hosts the customizable top-edge EasyBar panel.
@MainActor
final class BarWindowController: NSWindowController, EasyBarSurfaceController {
  private let context: EasyBarSurfaceContext
  private let presentationModel: EasyBarPresentationModel

  /// Creates the fixed top-edge window for one shared EasyBar surface context.
  init(context: EasyBarSurfaceContext) {
    self.context = context
    self.presentationModel = context.presentationModel

    guard let screen = Self.preferredScreen() else {
      preconditionFailure("EasyBar requires an available display")
    }
    let frame = Self.makeFrame(for: screen, style: context.presentationModel.barStyle)

    context.logger.debug(
      "bar window initial",
      .field("target_frame", NSStringFromRect(frame))
    )

    let window = BarPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    window.level = .statusBar
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.hidesOnDeactivate = false
    window.isFloatingPanel = true
    window.becomesKeyOnlyIfNeeded = false
    window.isMovable = false
    window.isMovableByWindowBackground = false
    window.collectionBehavior = [
      .canJoinAllSpaces,
      .stationary,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]

    let hostingView = BarHostingView(
      rootView: BarContentView(presentationModel: context.presentationModel)
    )
    hostingView.frame = NSRect(origin: .zero, size: frame.size)
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView

    Self.apply(frame: frame, to: window, display: false)

    super.init(window: window)

    window.contextMenuProvider = { showDeveloperSection in
      context.makeBarContextMenu(showDeveloperSection: showDeveloperSection)
    }
  }

  /// Storyboard decoding is unsupported because the bar is assembled programmatically.
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  /// Reapplies screen-dependent bar geometry after presentation settings change.
  func reloadLayout() {
    guard let window else {
      context.logger.warn("bar window reloadLayout skipped because window is unavailable")
      return
    }

    guard let screen = Self.preferredScreen(for: window) else {
      context.logger.warn("bar window reloadLayout skipped because no display is available")
      return
    }
    let frame = Self.makeFrame(for: screen, style: presentationModel.barStyle)

    Self.apply(frame: frame, to: window, display: true)
  }

  /// Presents the bar above normal application windows without activating it.
  func present() {
    guard let window else {
      context.logger.warn("bar window present skipped because window is unavailable")
      return
    }

    window.orderFrontRegardless()
  }

  /// Removes the bar from the screen while preserving its window state.
  func hide() {
    window?.orderOut(nil)
  }

  /// Closes the bar window and releases its AppKit resources.
  func stop() {
    (window as? BarPanel)?.contextMenuProvider = nil
    window?.orderOut(nil)
    close()
  }

  /// Returns the window's display or the current system fallback display.
  private static func preferredScreen(for window: NSWindow? = nil) -> NSScreen? {
    window?.screen ?? NSScreen.main ?? NSScreen.screens.first
  }

  /// Applies a fixed panel frame without retaining constraints from the previous bar height.
  private static func apply(frame: NSRect, to window: NSWindow, display: Bool) {
    window.minSize = frame.size
    window.maxSize = frame.size
    window.setFrame(frame, display: display)
  }

  /// Computes the screen frame used by the current bar appearance.
  private static func makeFrame(
    for screen: NSScreen,
    style: EasyBarPresentationModel.BarStyle
  ) -> NSRect {
    let topEdge = style.extendBehindNotch ? screen.frame.maxY : screen.visibleFrame.maxY

    return BarFrameLayout.frame(
      in: screen.frame,
      topEdge: topEdge,
      height: style.height
    )
  }
}
