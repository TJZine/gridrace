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
    var conflictCount = 0
    var conflict: DailySyncConflict? = nil

    @State private var rawAppleNonce: String?
    @State private var editingProfile = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImportConfirmation = false
    @State private var showingConflictSheet = false
    @State private var actionTask: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Account/profile errors: the model mints `errorEvent` per error (even for
    // a repeated identical string), so focus follows the event, not the
    // message value. The banner itself never announces: focus is the sole
    // speech owner.
    @AccessibilityFocusState private var errorFocus: Int?
    #if DEBUG
    @State private var localEmail = ""
    @State private var localPassword = ""
    #endif

    var body: some View {
        List {
            if !model.isConfigured {
                Section { unavailableCard }
            } else if model.isSignedIn {
                signedInContent
            } else if model.isRestoring {
                Section {
                    ProgressView("Restoring account")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            } else {
                signedOutContent
            }

            if let error = model.errorMessage {
                Section { errorCard(error) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .tint(Color.ink)
        .environment(\.defaultMinListRowHeight, 44)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .sheet(isPresented: $showingConflictSheet) {
            if let conflict {
                ConflictResolutionSheet(
                    conflict: conflict,
                    useCloudAttempt: useCloudAttempt,
                    keepDeviceAttempt: keepDeviceAttempt
                )
            }
        }
        .alert("Delete your GridRace account?", isPresented: $showingDeleteConfirmation) {
            Button("Delete account", role: .destructive) { run { await model.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and synchronized GridRace data. This can't be undone.")
        }
        .sheet(isPresented: $showingImportConfirmation) {
            GuestHistoryImportSheet(
                importGuestHistory: importGuestHistory,
                skipGuestHistory: skipGuestHistory
            )
        }
        .onAppear {
            // Initial-entry path: an error already present when the screen
            // appears never triggers `onChange`, so focus it exactly once.
            if model.errorMessage != nil {
                errorFocus = model.errorEvent
            }
        }
        .onChange(of: model.errorEvent) { _, event in
            if model.errorMessage != nil {
                errorFocus = event
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            if message == nil {
                errorFocus = nil
            }
        }
        .onChange(of: conflictCount) { _, count in
            if count == 0 { showingConflictSheet = false }
        }
    }

    private var unavailableCard: some View {
        ContentUnavailableView(
            "Accounts unavailable",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Account configuration is missing. Daily Classic still works normally on this device.")
        )
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section("Account") {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .accessibilityHidden(true)
                Text("Keep your streak on every device")
                    .font(StampType.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Sign in to restore your Daily Classic history on your devices.")
                    .foregroundStyle(Color.secondaryInk)
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

                Text("Your email is never shown to other players.")
                    .font(StampType.caption)
                    .foregroundStyle(Color.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.card)

        #if DEBUG
        Section {
            DisclosureGroup("Local development sign in") {
                VStack(spacing: 12) {
                    TextField("Test user email", text: $localEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    SecureField("Test user password", text: $localPassword)
                        .textContentType(.password)
                    Button {
                        let email = localEmail
                        let password = localPassword
                        run { await model.signInForLocalTesting(email: email, password: password) }
                    } label: {
                        Text("Sign in to local Supabase")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(OutlinedInkButtonStyle())
                    .disabled(localEmail.isEmpty || localPassword.isEmpty || model.isWorking)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }
        }
        .listRowBackground(Color.card)
        #endif
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let profile = model.profile {
            Section("Profile") {
                VStack(spacing: 16) {
                    PlayerAvatarView(seed: model.avatarSeedDraft, size: 92)
                    if editingProfile || profile.needsSetup {
                        profileEditor(isInitialSetup: profile.needsSetup)
                    } else {
                        Text(profile.displayName)
                            .font(StampType.title2.bold())
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.secondaryInk)
                        privacyReassurance
                        Button { editingProfile = true } label: {
                            Text("Edit profile")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(OutlinedInkButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.card)

            if let syncMessage {
                Section("Sync") {
                    syncCard(syncMessage)
                }
                .listRowBackground(Color.card)
            }

            if canImportGuestHistory, importGuestHistory != nil {
                Section {
                    Button {
                        showingImportConfirmation = true
                    } label: {
                        Label("Add local Daily Classic history", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(InkButtonStyle())
                }
                .listRowBackground(Color.card)
            }
        } else {
            Section("Profile") {
                VStack(spacing: 14) {
                    if model.isLoadingProfile {
                        ProgressView()
                        Text("Loading your profile")
                    } else {
                        Text("Your profile is unavailable")
                    }
                    Button { run { await model.retryProfile() } } label: {
                        Text("Try again")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(OutlinedInkButtonStyle())
                    .disabled(model.isWorking || model.isLoadingProfile)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
            .listRowBackground(Color.card)
        }
        Section {
            Button { run { await model.signOut() } } label: {
                Text("Sign out")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("account-sign-out")
            .disabled(model.isWorking)
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text("Delete account")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("account-delete")
            .disabled(model.isWorking)
        }
        .listRowBackground(Color.card)
    }

    // Exact signed-in reassurance, shared by the viewing, initial-setup,
    // and editing states (only one state is visible at a time, so the single
    // definition never duplicates on screen).
    private var privacyReassurance: some View {
        Text("Your email is never shown to other players.")
            .font(StampType.caption)
            .foregroundStyle(Color.secondaryInk)
            .multilineTextAlignment(.center)
    }

    private func profileEditor(isInitialSetup: Bool) -> some View {
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout())
        return VStack(spacing: 14) {
            Text(isInitialSetup ? "Choose your player name" : "Edit profile")
                .font(StampType.title3.bold())
            privacyReassurance
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
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
            }
            Button { model.randomizeAvatar() } label: {
                Text("Shuffle avatar")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(OutlinedInkButtonStyle())
            .disabled(model.isWorking)
            actionLayout {
                if !isInitialSetup {
                    Button {
                        model.displayNameDraft = model.profile?.displayName ?? ""
                        model.avatarSeedDraft = model.profile?.avatarSeed ?? model.avatarSeedDraft
                        editingProfile = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    run {
                        await model.saveProfile()
                        if model.errorMessage == nil { editingProfile = false }
                    }
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(InkButtonStyle())
                .disabled(
                    model.isWorking
                        || PlayerProfile.normalizedDisplayName(model.displayNameDraft) == nil
                )
            }
        }
    }

    private func syncCard(_ message: String) -> some View {
        let statusLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            statusLayout {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.ink)
                    .accessibilityHidden(true)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let retrySync {
                    Button(action: retrySync) {
                        Text("Retry")
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(OutlinedInkButtonStyle())
                }
            }
            if conflict != nil, useCloudAttempt != nil, keepDeviceAttempt != nil {
                Button {
                    showingConflictSheet = true
                } label: {
                    Label("Review different attempts", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(OutlinedInkButtonStyle())
            }
        }
        .padding(16)
        .paperCard(cornerRadius: 12)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            // Focus target is the model-owned `errorEvent` (set once per
            // error by the body-level handlers above, never here).
            RaceErrorBanner(message: message)
                .accessibilityFocused($errorFocus, equals: model.errorEvent)
            Button { model.clearError() } label: {
                Text("Dismiss")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
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

private struct ConflictResolutionSheet: View {
    let conflict: DailySyncConflict
    let useCloudAttempt: (() -> Void)?
    let keepDeviceAttempt: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var headingFocus: Int?
    @State private var headingGeneration = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var boards: ConflictBoards {
        switch conflict {
        case .progress(_, let local, let cloud):
            ConflictBoards(
                localRows: local.acceptedGuesses.map(\.row),
                localDraft: local.draft,
                cloudRows: cloud.acceptedGuesses.map(\.row),
                cloudDraft: cloud.draft
            )
        case .completedResult(_, let local, let cloud):
            ConflictBoards(
                localRows: local.guesses.map(\.row),
                localDraft: "",
                cloudRows: cloud.guesses.map(\.row),
                cloudDraft: ""
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("These attempts differ. Choose which one to keep on this device.")
                        .font(StampType.title3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocus, equals: headingGeneration)

                    boardComparison

                    VStack(spacing: 10) {
                        if let useCloudAttempt {
                            Button {
                                useCloudAttempt()
                            } label: {
                                Text("Use synced attempt")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(InkButtonStyle())
                        }
                        if let keepDeviceAttempt {
                            Button {
                                keepDeviceAttempt()
                            } label: {
                                Text("Keep this device")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(OutlinedInkButtonStyle())
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.page)
            .navigationTitle("Resolve attempt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { focusHeading() }
        .onChange(of: conflict) { _, _ in focusHeading() }
    }

    @ViewBuilder
    private var boardComparison: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ConflictBoardCard(
                        title: "This device",
                        rows: boards.localRows,
                        draft: boards.localDraft
                    )
                    ConflictBoardCard(
                        title: "Synced account",
                        rows: boards.cloudRows,
                        draft: boards.cloudDraft
                    )
                }
                .padding(.vertical, 2)
            }
        } else {
            ConflictBoardComparison(boards: boards)
        }
    }

    private func focusHeading() {
        headingGeneration += 1
        headingFocus = headingGeneration
    }
}

private struct ConflictBoardComparison: View {
    let boards: ConflictBoards
    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = max(0, (proxy.size.width - 8) / 2)
            HStack(alignment: .top, spacing: 8) {
                ConflictBoardCard(
                    title: "This device",
                    rows: boards.localRows,
                    draft: boards.localDraft,
                    width: cardWidth
                )
                ConflictBoardCard(
                    title: "Synced account",
                    rows: boards.cloudRows,
                    draft: boards.cloudDraft,
                    width: cardWidth
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: proxy.size.width, alignment: .top)
            .background {
                GeometryReader { contentProxy in
                    Color.clear.preference(
                        key: ConflictBoardComparisonHeightKey.self,
                        value: contentProxy.size.height
                    )
                }
            }
        }
        // The HStack above is vertically fixed to the cards' intrinsic size;
        // this state only carries that measured result out of GeometryReader
        // so the following actions are laid out after the taller card.
        .frame(height: measuredHeight)
        .onPreferenceChange(ConflictBoardComparisonHeightKey.self) { height in
            guard height > 0, abs(height - measuredHeight) > 0.5 else { return }
            measuredHeight = height
        }
    }
}

private struct ConflictBoardComparisonHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GuestHistoryImportSheet: View {
    let importGuestHistory: (() -> Void)?
    let skipGuestHistory: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .accessibilityHidden(true)
                    Text("Add local Daily Classic history?")
                        .font(StampType.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("They join your personal history. Live races never count them.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        Button {
                            importGuestHistory?()
                            dismiss()
                        } label: {
                            Text("Add to account")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(InkButtonStyle())
                        Button {
                            skipGuestHistory?()
                            dismiss()
                        } label: {
                            Text("Not now")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(OutlinedInkButtonStyle())
                    }
                }
                .padding(24)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .background(Color.page)
            .navigationTitle("Daily history")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct ConflictBoards {
    let localRows: [GuessRow]
    let localDraft: String
    let cloudRows: [GuessRow]
    let cloudDraft: String
}

private struct ConflictBoardCard: View {
    let title: String
    let rows: [GuessRow]
    let draft: String
    var width: CGFloat?

    private let tileSpacing: CGFloat = 3
    private let horizontalPadding: CGFloat = 8
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tileSize: CGFloat? {
        guard let width else { return nil }
        return max(22, (width - horizontalPadding * 2 - tileSpacing * 4) / 5)
    }

    var body: some View {
        if let width {
            cardContent
                .frame(width: width)
                .paperCard(cornerRadius: 12)
                .accessibilityElement(children: .contain)
        } else {
            cardContent
                .paperCard(cornerRadius: 12)
                .accessibilityElement(children: .contain)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(StampType.heading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<6, id: \.self) { rowIndex in
                let row = rows.indices.contains(rowIndex) ? rows[rowIndex] : nil
                let word = row?.word ?? (rowIndex == rows.count ? draft : "")
                let letters = Array(word.uppercased())
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { column in
                        conflictTile(
                            letter: letters.indices.contains(column) ? letters[column] : nil,
                            feedback: row?.feedback.indices.contains(column) == true
                                ? row?.feedback[column] : nil,
                            isDraft: rowIndex == rows.count && !draft.isEmpty,
                            emptyLabel: "Empty tile, row \(rowIndex + 1), column \(column + 1)"
                        )
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func conflictTile(
        letter: Character?,
        feedback: Feedback?,
        isDraft: Bool,
        emptyLabel: String
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            TileView(
                letter: letter,
                feedback: feedback,
                isDraft: isDraft,
                emptyLabel: emptyLabel
            )
            .frame(minWidth: 44, minHeight: 44)
        } else {
            let tile = ConflictTileView(
                letter: letter,
                feedback: feedback,
                isDraft: isDraft,
                emptyLabel: emptyLabel
            )
            if let tileSize {
                tile.frame(width: tileSize, height: tileSize)
            } else {
                tile.frame(minWidth: 44, minHeight: 44)
            }
        }
    }
}

private struct ConflictTileView: View {
    let letter: Character?
    let feedback: Feedback?
    let isDraft: Bool
    let emptyLabel: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.highContrastFeedback) private var highContrastFeedback
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var letterColor: Color {
        switch feedback {
        case .correct: Color.feedbackLetter
        case .present: Color.present
        case .absent:
            highContrastFeedback || contrast == .increased
                ? Color.strengthenedAbsent
                : Color.absent
        case .none: Color.ink
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FeedbackSeal(feedback: feedback, isDraft: isDraft)
                VStack(spacing: 0) {
                    if let letter {
                        Text(String(letter).uppercased())
                            .font(.system(
                                size: max(12, proxy.size.width * 0.48),
                                weight: legibilityWeight == .bold || isDraft ? .black : .bold,
                                design: .serif
                            ))
                    }
                    if let feedback {
                        Image(systemName: feedback.symbolName)
                            .font(.system(
                                size: max(8, proxy.size.width * 0.22),
                                weight: .black
                            ))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(letterColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var accessibilityLabel: String {
        guard let letter else { return emptyLabel }
        if let feedback { return "Letter \(letter), \(feedback.accessibilityMeaning)." }
        return "Letter \(letter), draft."
    }
}
