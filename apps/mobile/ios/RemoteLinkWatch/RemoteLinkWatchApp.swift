import SwiftUI

@main
struct RemoteLinkWatchApp: App {
    /// One link for the life of the app.
    ///
    /// The `WCSession` singleton takes a single delegate, so a second instance
    /// would silently take over from the first and the surviving view would
    /// stop hearing about reachability. Held here, above every view, so there
    /// is only ever one.
    @StateObject private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            TrackpadView()
                .environmentObject(link)
        }
    }
}
