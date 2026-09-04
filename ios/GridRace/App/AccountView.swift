import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Bindable var model: AccountModel
    var syncMessage: String?
    var retrySync: (() -> Void)?
    var canImportGuestHistory = false
    var importGuestHistory: (() -> Void)?
    var skipGuestHistory: (() -> Void)?
    var useCloudAttempt: (() -> Void)?
    var keepDeviceAttempt: (() -> Void)?

    @State private var rawAppleNonce: String?
    @State private var editingProfile = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImportConfirmation = false
    @State private var actionTask: Task<Void, Never>?
    // U-06: conflict choice -> focus conflict heading (no duplicate announce).
    @AccessibilityFocusState private var conflictFocused: Bool
    #if DEBUG
    @State private var localEmail = ""
    @State private var localPassword = ""
    #endif

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    if !model.isConfigured {
                        unavailableCard
                    } else if model.isRestoring {
                        ProgressView("Restoring account")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if model.isSignedIn {
                        signedInContent
                    } else {
                        signedOutContent
                    }

                    if let error = model.errorMessage {
                        errorCard(error)
                    }
                }
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .alert("Delete your GridRace account?", isPresented: $showingDeleteConfirmation) {
            Button("Delete account", role: .destructive) { run { await model.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and synchronized GridRace data. This can't be undone.")
        }
        .alert("Add local Daily Classic history?", isPresented: $showingImportConfirmation) {
            Button("Add to account") { importGuestHistory?() }
            Button("Not now", role: .cancel) { skipGuestHistory?() }
        } message: {
            Text("Your local results will be saved as personal history. They won't count as verified competitive results.")
        }
    }

    private var unavailableCard: some View {
        ContentUnavailableView(
            "Accounts unavailable",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Account configuration is missing. Daily Classic still works normally on this device.")
        )
    }

    private var signedOutContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.raceIndigo)
                .accessibilityHidden(true)
            Text("Save and sync your progress")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Keep playing without an account, or sign in to restore your Daily Classic history on your devices.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                do {
                    let nonce = try AppleNonce.generate()
                    rawAppleNonce = nonce
                    request.nonce = AppleNonce.sha256(nonce)
                } catch {
                    rawAppleNonce = nil
                    model.noncePreparationFailed()
                }
            } onCompletion: { result in
                handleAppleAuthorization(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(model.isWorking)
            .accessibilityHint("Signs in to save and synchronize your personal GridRace progress")

            #if DEBUG
            DisclosureGroup("Local development sign in") {
                VStack(spacing: 12) {
                    TextField("Test user email", text: $localEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    SecureField("Test user password", text: $localPassword)
                        .textContentType(.password)
                    Button("Sign in to local Supabase") {
                        let email = localEmail
                        let password = localPassword
                        run { await model.signInForLocalTesting(email: email, password: password) }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(localEmail.isEmpty || localPassword.isEmpty || model.isWorking)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }
            #endif
        }
        .padding(24)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let profile = model.profile {
            VStack(spacing: 18) {
                PlayerAvatarView(seed: model.avatarSeedDraft, size: 92)
                if editingProfile || profile.needsSetup {
                    profileEditor(isInitialSetup: profile.needsSetup)
                } else {
                    Text(profile.displayName)
                        .font(.title2.bold())
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("Your email is never shown to other players.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Edit profile") { editingProfile = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.raceLine, lineWidth: 1.5)
            }

            if let syncMessage {
                syncCard(syncMessage)
            }

            if canImportGuestHistory, importGuestHistory != nil {
                Button {
                    showingImportConfirmation = true
                } label: {
                    Label("Add local Daily Classic history", systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(spacing: 12) {
                Button("Sign out") { run { await model.signOut() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isWorking)
                Button("Delete account", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(model.isWorking)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 14) {
                ProgressView()
                Text("Loading your profile")
                Button("Try again") { run { await model.retryProfile() } }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isWorking)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private func profileEditor(isInitialSetup: Bool) -> some View {
        VStack(spacing: 14) {
            Text(isInitialSetup ? "Choose your player name" : "Edit profile")
                .font(.title3.bold())
            TextField("Player name", text: $model.displayNameDraft)
                .textInputAutocapitalization(.words)
                .textContentType(.nickname)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("Use 2 to 16 letters, numbers, spaces, apostrophes, or hyphens")
            // Enabled state and message derive from the single authoritative
            // `PlayerProfile.normalizedDisplayName` validator; no second ruleset.
            if PlayerProfile.normalizedDisplayName(model.displayNameDraft) == nil {
                Text("Use 2–16 letters, numbers, spaces, apostrophes, or hyphens.")
                    .font(.callout)
                    .foregroundStyle(Color.raceDanger)
                    .multilineTextAlignment(.center)
            }
            Button("Try another avatar") { model.randomizeAvatar() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(model.isWorking)
            HStack {
                if !isInitialSetup {
                    Button("Cancel") {
                        model.displayNameDraft = model.profile?.displayName ?? ""
                        model.avatarSeedDraft = model.profile?.avatarSeed ?? model.avatarSeedDraft
                        editingProfile = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button("Save") {
                    run {
                        await model.saveProfile()
                        if model.errorMessage == nil { editingProfile = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(
                    model.isWorking
                        || PlayerProfile.normalizedDisplayName(model.displayNameDraft) == nil
                )
            }
        }
    }

    private func syncCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.raceIndigo)
                    .accessibilityHidden(true)
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityFocused($conflictFocused)
                if let retrySync {
                    Button("Retry", action: retrySync)
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                }
            }
            if let useCloudAttempt, let keepDeviceAttempt {
                VStack(spacing: 8) {
                    Button("Use synced attempt", action: useCloudAttempt)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    Button("Keep this device", action: keepDeviceAttempt)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(16)
        .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            if useCloudAttempt != nil { conflictFocused = true }
        }
        .onChange(of: useCloudAttempt == nil) { _, isNil in
            // Assign (not only set) so a reappearing conflict refires focus.
            conflictFocused = !isNil
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            RaceErrorBanner(message: message)
            Button("Dismiss") { model.clearError() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            rawAppleNonce = nil
            model.appleAuthorizationFailed(error)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = rawAppleNonce
            else {
                rawAppleNonce = nil
                model.noncePreparationFailed()
                return
            }
            rawAppleNonce = nil
            run { await model.signInWithApple(idToken: idToken, rawNonce: nonce) }
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await operation() }
    }
}

/// Explicit per-index avatar background swatch. Fixed sRGB values keep white
/// symbols at >=3:1 in both appearances.
struct AvatarSwatch: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct PlayerAvatarView: View {
    let seed: String
    var size: CGFloat = 56

    /// Frozen seed-to-symbol mapping. Do not reorder or remove entries:
    /// persisted seeds must resolve to the same symbol.
    static let avatarSymbols = [
        "hare.fill", "tortoise.fill", "bird.fill", "fish.fill",
        "ladybug.fill", "pawprint.fill", "leaf.fill", "bolt.fill"
    ]

    /// Explicit per-index backgrounds, each >=3:1 against white.
    static let avatarSwatches = [
        AvatarSwatch(red: 0.239, green: 0.200, blue: 0.580),
        AvatarSwatch(red: 0.051, green: 0.420, blue: 0.470),
        AvatarSwatch(red: 0.698, green: 0.227, blue: 0.122),
        AvatarSwatch(red: 0.478, green: 0.310, blue: 0.639),
        AvatarSwatch(red: 0.651, green: 0.141, blue: 0.310),
        AvatarSwatch(red: 0.357, green: 0.357, blue: 0.839),
        AvatarSwatch(red: 0.541, green: 0.353, blue: 0.000),
        AvatarSwatch(red: 0.200, green: 0.255, blue: 0.333),
    ]

    static func paletteIndex(for seed: String) -> Int {
        seed.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % avatarSymbols.count }
    }

    var body: some View {
        let index = Self.paletteIndex(for: seed)
        Image(systemName: Self.avatarSymbols[index])
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.avatarSwatches[index].color, in: Circle())
            .accessibilityLabel("Generated player avatar")
    }
}
