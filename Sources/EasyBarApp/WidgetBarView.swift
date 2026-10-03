import EasyBarKit
import EasyBarShared
import SwiftUI

/// Renders the top-level widget surfaces assigned to one logical bar region.
struct WidgetBarView: View {
  /// Shared runtime state that supplies the widget surfaces for this region.
  @ObservedObject var presentationModel: EasyBarPresentationModel

  /// Logical bar region rendered by this horizontal stack.
  let position: WidgetPosition

  var body: some View {
    HStack(spacing: 4) {
      ForEach(presentationModel.widgets(at: position)) { widget in
        widget.makeView()
      }
    }
  }
}
