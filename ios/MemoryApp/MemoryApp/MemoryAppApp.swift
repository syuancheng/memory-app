import SwiftUI

@main
struct MemoryAppApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
    }
}

struct AppShellView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            CardsHierarchyView()
                .tabItem {
                    Label("Cards", systemImage: "rectangle.stack.fill")
                }

            AIView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            MeView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }
        }
        .tint(AppSurface.accent)
    }
}
