import SwiftUI

@main
struct MemoryAppApp: App {
    @StateObject private var session = AuthSessionStore()

    init() {
        // NavBar 与 TabBar 的外观在此统一注入（Components.swift）。
        // 各屏不再各自 .toolbar(.hidden) + 自绘导航 —— 收敛 #1 的前提。
        AppAppearance.configure()
    }

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

private enum AppTab: Hashable {
    case home, cards, ai, me
}

struct AppShellView: View {
    @EnvironmentObject private var session: AuthSessionStore
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: AppIcon.tabHome)
                }

            CardsHierarchyView()
                .tag(AppTab.cards)
                .tabItem {
                    Label("Cards", systemImage: AppIcon.tabCards)
                }

            AIView()
                .tag(AppTab.ai)
                .tabItem {
                    Label("AI", systemImage: AppIcon.tabAI)
                }

            MeView()
                .tag(AppTab.me)
                .tabItem {
                    Label("Me", systemImage: AppIcon.tabMe)
                }
        }
        .tint(AppColor.primary)
        .background(AppColor.surfaceBase.ignoresSafeArea())
        // 刚注册的账号提示设置密码；可跳过，跳过后不再弹。
        .sheet(isPresented: $session.shouldOfferPasswordSetup) {
            SetPasswordView(isOnboarding: true)
                .environmentObject(session)
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            AppColor.surfaceBase
                .ignoresSafeArea()

            VStack(spacing: AppSpace.md) {
                Text("Cardly")
                    .appText(AppType.display)

                ProgressView()
                    .tint(AppColor.primary)
            }
        }
    }
}
