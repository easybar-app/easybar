import EasyBarKit
import EasyBarShared
import SwiftUI

/// Renders the top-level widget surfaces assigned to one logical bar region.
struct WidgetBarView: View {
  @ObservedObject var presentationModel: EasyBarPresentationModel
  let position: WidgetPosition

  var body: some View {
    HStack(spacing: 4) {
      ForEach(presentationModel.widgets(at: position)) { widget in
        widget.makeView()
      }
    }
  }
}
