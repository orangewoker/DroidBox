import SwiftUI

@main
struct DroidBoxApp: App {
    @State private var environment = AppEnvironment()
    var body: some Scene {
        WindowGroup {
            RootView().environment(environment).onOpenURL { environment.open($0) }
        }
    }
}

