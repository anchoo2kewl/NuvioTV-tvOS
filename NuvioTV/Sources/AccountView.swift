import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            AccountBackdrop()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    Header(title: "Account", subtitle: "Sign in to Nuvio and sync your content to this Apple TV.")

                    if authStore.isSignedIn {
                        ConnectedAccountPanel()
                    } else {
                        HStack(alignment: .top, spacing: 26) {
                            SignInPanel()
                            TvLoginPanel()
                        }
                    }

                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: 1180, alignment: .leading)
                    }
                }
                .padding(.leading, 150)
                .padding(.trailing, 64)
                .padding(.top, 76)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .focusSection()
        }
        .ignoresSafeArea()
    }
}

private struct SignInPanel: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        AccountPanel(title: "Email login", subtitle: "Use your Nuvio account to pull synced content.") {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Email", text: $authStore.email)
                    .accountTextField()
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $authStore.password)
                    .accountTextField()
                    .textContentType(.password)

                HStack(spacing: 16) {
                    Button("Sign in and sync") {
                        authStore.signIn()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authStore.isLoading)

                    if authStore.isLoading {
                        ProgressView()
                    }
                }
            }
            .focusSection()
        }
    }
}

private struct TvLoginPanel: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        AccountPanel(title: "Phone login", subtitle: "Start TV login, open the URL on your phone, then approve the code.") {
            VStack(alignment: .leading, spacing: 18) {
                if let login = authStore.tvLogin {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(login.webURL)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text("Code: \(login.code)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))

                        Text(authStore.tvLoginStatus ?? "Waiting for approval.")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .padding(20)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("No active TV login session.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.66))
                }

                HStack(spacing: 16) {
                    Button(authStore.tvLogin == nil ? "Start TV login" : "Restart TV login") {
                        authStore.startTvLogin()
                    }
                    .buttonStyle(.bordered)

                    Button("Check status") {
                        authStore.pollTvLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authStore.tvLogin == nil)
                }
            }
            .focusSection()
        }
    }
}

private struct ConnectedAccountPanel: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        AccountPanel(title: "Connected", subtitle: authStore.session?.email ?? authStore.session?.userId ?? "Nuvio account") {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Button("Sync now") {
                        authStore.sync()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh session") {
                        authStore.refreshSessionIfPossible()
                    }
                    .buttonStyle(.bordered)

                    Button("Sign out") {
                        authStore.signOut()
                    }
                    .buttonStyle(.bordered)
                }

                SyncedAccountStats()
            }
            .focusSection()
        }
    }
}

private struct SyncedAccountStats: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        if let overview = authStore.overview {
            VStack(alignment: .leading, spacing: 12) {
                Text("Synced data")
                    .font(.headline)
                Text("\(overview.profiles.count) profiles, \(overview.totalLibraryItems) library items, \(overview.totalWatchProgress) progress records, \(overview.totalWatchedItems) watched items.")
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }
}

private struct AccountPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(width: 560, alignment: .leading)
        .padding(30)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct AccountBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                    Color(red: 0.07, green: 0.10, blue: 0.14),
                    .black
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            Image("app_logo_mark")
                .resizable()
                .scaledToFit()
                .frame(width: 520)
                .opacity(0.09)
                .offset(x: 520, y: -140)

            LinearGradient(
                colors: [.black.opacity(0.95), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private extension View {
    func accountTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.title3)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
