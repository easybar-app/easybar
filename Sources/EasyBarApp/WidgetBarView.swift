import EasyBarKit
import EasyBarShared
import SwiftUI

/// Renders the top-level widget surfaces assigned to one logical bar region.
struct WidgetBarView: View {
  /// Shared runtime state that supplies the widget surfaces for this region.
  @ObservedObject var presentationModel: EasyBarPresentationModel

  /// Logical bar region rendered by this horizontal stack.
  let position: WidgetPosition

  /// Draws the widgets assigned to this bar position in runtime order.
  var body: some View {
    HStack(spacing: 4) {
      ForEach(presentationModel.widgets(at: position)) { widget in
        widget.makeView()
      }
    }
  }
}
