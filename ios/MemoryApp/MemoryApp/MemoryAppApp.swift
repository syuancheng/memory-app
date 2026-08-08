import SwiftUI

@main
struct MemoryAppApp: App {
    @StateObject private var session = AuthSessionStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isCheckingSession {
                    LaunchLoadingView()
                } else if session.isAuthenticated {
                    AppShellView()
                } else {
                    AuthView()
                }
            }
            .environmentObject(session)
            .task {
                await session.restoreSession()
            }
        }
    }
}

struct AppShellView: View {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppSurface.floating)
        appearance.shadowColor = UIColor(AppSurface.line)

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(AppSurface.muted)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppSurface.muted)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppSurface.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppSurface.accent)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = false
    }

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
        .toolbarBackground(AppSurface.floating, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Cardly")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                ProgressView()
                    .tint(AppSurface.accent)
            }
        }
    }
}
