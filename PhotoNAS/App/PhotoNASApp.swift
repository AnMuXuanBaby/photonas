import SwiftUI

@main
struct PhotoNASApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
