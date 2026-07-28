import SwiftUI

struct HomeView: View {
    @State private var subjects: [AppSubject] = []
    @State private var showingSubjects = false
    @State private var showingMe = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("lastReviewSummary") private var lastReviewSummary = "No sessions yet"

    private var dueCount: Int {
        subjects.reduce(0) { $0 + $1.dueCount }
    }

    var body: some View {
        ZStack {
            ScreenBackground(homeStyle: true)

            GeometryReader { proxy in
                ZStack {
                    Button {
                        showingMe = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Text("S")
                                .font(AppFont.medium(17))
                                .foregroundStyle(Theme.text)
                                .frame(width: 46, height: 46)
                                .background(.white.opacity(0.72))
                                .clipShape(Circle())
                                .shadow(color: Theme.text.opacity(0.12), radius: 30, y: 12)

                            Circle()
                                .fill(Color(hex: 0xFF6B45))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                                .offset(x: -3, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: 49, y: 82)

                    Button {
                        showingSubjects = true
                    } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Today")
                                    .font(AppFont.medium(13))
                                    .foregroundStyle(Theme.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Theme.greenSoft.opacity(0.92))
                                    .clipShape(Capsule())

                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Text("\(dueCount)")
                                        .font(AppFont.medium(38))
                                        .foregroundStyle(Theme.red)
                                    Text("due")
                                        .font(AppFont.medium(17))
                                        .foregroundStyle(Theme.text.opacity(0.78))
                                }

                                Text(lastReviewSummary)
                                    .font(AppFont.regular(12))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Theme.green)
                                .frame(width: 44, height: 44)
                                .background(Theme.green.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 26)
                        .frame(width: proxy.size.width - 56, height: 118)
                        .background(.white.opacity(0.76))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.52), lineWidth: 1)
                        )
                        .shadow(color: Theme.text.opacity(0.14), radius: 55, y: 22)
                    }
                    .buttonStyle(.plain)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.627)

                    if isLoading {
                        ProgressView()
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.79)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.regular(13))
                            .foregroundStyle(Theme.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.80)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSubjects) {
            SubjectPickerView(subjects: subjects)
        }
        .fullScreenCover(isPresented: $showingMe) {
            MeView {
                showingMe = false
            }
        }
        .task {
            await loadSubjects()
        }
        .onChange(of: showingSubjects) { _, isPresented in
            if !isPresented {
                Task {
                    await loadSubjects()
                }
            }
        }
    }

    private func loadSubjects() async {
        isLoading = true
        errorMessage = nil
        do {
            subjects = try await APIClient.shared.listSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
