import AppKit
import EasyBarKit
import EasyBarShared
import SwiftUI

/// Hosts the customizable top-edge EasyBar panel.
@MainActor
final class BarWindowController: NSWindowController, EasyBarSurfaceController {
  private let context: EasyBarSurfaceContext
  private let presentationModel: EasyBarPresentationModel
  private let hostingView: BarHostingView<AnyView>

  init(context: EasyBarSurfaceContext) {
    self.context = context
    self.presentationModel = context.presentationModel

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let frame = Self.makeFrame(for: screen, style: context.presentationModel.barStyle)

    context.logger.debug(
      "bar window initial",
      .field("target_frame", NSStringFromRect(frame))
    )

    let contentView = AnyView(
      BarContentView(presentationModel: context.presentationModel)
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
    window.setContentSize(frame.size)
    window.minSize = frame.size
    window.maxSize = frame.size

    let hostingView = BarHostingView(rootView: contentView)
    hostingView.frame = NSRect(origin: .zero, size: frame.size)
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView
    window.setFrame(frame, display: false)

    self.hostingView = hostingView

    super.init(window: window)

    window.contextMenuProvider = { showDeveloperSection in
      context.makeBarContextMenu(showDeveloperSection: showDeveloperSection)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func reloadLayout() {
    guard let window else {
      context.logger.warn("bar window reloadLayout skipped because window is unavailable")
      return
    }

    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let frame = Self.makeFrame(for: screen, style: presentationModel.barStyle)

    hostingView.rootView = AnyView(
      BarContentView(presentationModel: presentationModel)
    )
    window.setFrame(frame, display: true)
    window.setContentSize(frame.size)
    window.minSize = frame.size
    window.maxSize = frame.size
    hostingView.frame = NSRect(origin: .zero, size: frame.size)
  }

  func present() {
    guard let window else {
      context.logger.warn("bar window present skipped because window is unavailable")
      return
    }

    window.setFrame(window.frame, display: true)
    window.orderFrontRegardless()
  }

  func hide() {
    window?.orderOut(nil)
  }

  func stop() {
    window?.orderOut(nil)
    close()
  }

  private static func makeFrame(
    for screen: NSScreen,
    style: EasyBarPresentationModel.BarStyle
  ) -> NSRect {
    let baseFrame = style.extendBehindNotch ? screen.frame : screen.visibleFrame

    return BarFrameLayout.frame(in: baseFrame, height: style.height)
  }
}
