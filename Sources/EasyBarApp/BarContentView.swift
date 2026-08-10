import EasyBarKit
import EasyBarShared
import SwiftUI

/// Root SwiftUI view of the customizable EasyBar window.
struct BarContentView: View {
  @ObservedObject var presentationModel: EasyBarPresentationModel
  private let globalBarFont = Font.custom("Symbols Nerd Font Mono", size: 13)

  var body: some View {
    let style = presentationModel.barStyle

    HStack(spacing: 8) {
      WidgetBarView(presentationModel: presentationModel, position: .left)

      Spacer(minLength: 0)

      WidgetBarView(presentationModel: presentationModel, position: .center)

      Spacer(minLength: 0)

      WidgetBarView(presentationModel: presentationModel, position: .right)
    }
    .font(globalBarFont)
    .padding(.horizontal, style.paddingX)
    .frame(
      maxWidth: .infinity,
      minHeight: style.height,
      maxHeight: style.height,
      alignment: .center
    )
    .background(style.background)
    .overlay(alignment: .bottom) {
      if style.drawsBorder {
        Rectangle()
          .fill(style.border)
          .frame(height: 1)
      }
    }
    .foregroundStyle(style.text)
    .ignoresSafeArea()
  }

}
