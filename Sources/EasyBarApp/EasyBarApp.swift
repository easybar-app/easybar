import EasyBarKit

/// Process entry point for the customizable EasyBar frontend.
@main
enum EasyBarAppMain {
  static let identity = EasyBarApplicationIdentity(
    displayName: "EasyBar",
    processName: "easybar",
    loggerLabel: "easybar",
    logFileName: "easybar.out",
    defaultConfigRelativePath: ".config/easybar/config.toml",
    defaultRuntimeRelativePath: ".local/state/easybar/runtime",
    builtInSurfacePolicy: .all
  )

  /// Starts the shared runtime with the customizable full-width window surface.
  @MainActor
  static func main() {
    EasyBarApplication.run(identity: identity) { context in
      BarWindowController(context: context)
    }
  }
}
