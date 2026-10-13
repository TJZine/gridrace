import SwiftUI

/// Navigation is saved independently of authentication. Every Join button names
/// the currently ready profile and code; reopening and signing in grant no consent.
struct LiveInvitationView: View {
    @Bindable var invitations: LiveInvitationCoordinator
    var app: DailyAccountCoordinator?
    let resolveRace: () -> Void
    let joined: () -> Void
    @State private var showsAccount = false
    @State private var confirmsDiscard = false
    @AccessibilityFocusState private var noticeFocused: Bool

    private var ready: Bool {
        guard let app else { return false }
        return app.live.phase != .needsSignIn && app.account.isSignedIn && app.account.profile != nil && !app.account.needsProfileSetup
            && !app.account.isWorking && !app.account.isLoadingProfile && app.account.authRecovery == nil
    }
    private var unresolved: Bool {
        guard let app else { return false }
        return app.live.pendingIntent != nil || app.live.hasPendingStart || app.live.isCommandInFlight
            || app.live.phase == .storageUnavailable || app.live.serviceNeedsUpdate
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.page.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if invitations.storageFailed || invitations.cleanupBlocked {
                            NoticeCard(subject: "Invitation", title: "Invitation needs attention",
                                       message: "Retry or discard the saved invitation. Your saved race is unchanged.") {
                                Button("Retry") { invitations.retry() }.buttonStyle(InkButtonStyle())
                                Button("Discard invitation", role: .destructive) { confirmsDiscard = true }
                                    .buttonStyle(OutlinedInkButtonStyle())
                            }
                        } else if invitations.configurationRejectsPending {
                            NoticeCard(subject: "Invitation", title: "Invitation unavailable in this build",
                                       message: "Use the saved code \(invitations.pending?.code ?? "") in Live race, or discard this invitation.") {
                                Button("Discard invitation", role: .destructive) { confirmsDiscard = true }
                                    .buttonStyle(OutlinedInkButtonStyle())
                            }
                        } else if invitations.invalidLink {
                            NoticeCard(subject: "Invitation", title: "This link isn't supported",
                                       message: "Use the six-character room code from your friend.") {
                                Button("Done") { invitations.invalidLink = false; invitations.isPresented = false }
                                    .buttonStyle(InkButtonStyle())
                            }
                        } else if let replacement = invitations.replacement {
                            NoticeCard(subject: "Invitation", title: "Replace your invitation?",
                                       message: "Keep \(invitations.pending?.code ?? "your code"), or save \(replacement.code).") {
                                Button("Keep current") { invitations.keepCurrent() }.buttonStyle(InkButtonStyle())
                                Button("Replace invitation") { invitations.replace() }.buttonStyle(OutlinedInkButtonStyle())
                            }
                        } else if let pending = invitations.visiblePending {
                            ScorecardSeal(title: pending.code)
                                .accessibilityLabel("Invitation code \(pending.code.map(String.init).joined(separator: " "))")
                            if let app, ready {
                                let confirmation = invitations.confirmation(for: app)
                                let name = app.account.profile?.displayName ?? "your player"
                                NoticeCard(subject: "Invitation", title: "Join as \(name)?",
                                           message: unresolved ? "Resolve your saved race first. This invitation stays saved."
                                           : app.live.hasSavedMatch ? "Joining \(pending.code) switches your selected race."
                                           : "Join room \(pending.code) with this account.") {
                                    if unresolved {
                                        Button("Resolve saved race", action: resolveRace).buttonStyle(InkButtonStyle())
                                    } else {
                                        Button(app.live.hasSavedMatch ? "Switch race and join" : "Join \(pending.code)") {
                                            // Re-read the value and account at the intent boundary. No old-sheet consent survives replacement.
                                            guard invitations.visiblePending == pending, ready, !unresolved else { return }
                                            guard let confirmation, invitations.join(confirmation, app: app) else { return }
                                            joined()
                                        }.buttonStyle(InkButtonStyle())
                                    }
                                    Button("Keep invitation") { invitations.isPresented = false }.buttonStyle(OutlinedInkButtonStyle())
                                }
                            } else {
                                NoticeCard(subject: "Account", title: app == nil ? "Invitation saved" : "Sign in to join",
                                           message: app == nil ? "Open GridRace again when it's available. No race has been joined."
                                           : "Your invitation is saved. Finish signing in and choose a player name before joining.") {
                                    if app != nil {
                                        Button("Open Account") { showsAccount = true }.buttonStyle(InkButtonStyle())
                                    }
                                    Button("Keep invitation") { invitations.isPresented = false }.buttonStyle(OutlinedInkButtonStyle())
                                }
                            }
                            Button(role: .destructive) { confirmsDiscard = true } label: {
                                Text("Discard invitation").frame(maxWidth: .infinity, minHeight: 44)
                            }
                        } else {
                            NoticeCard(subject: "Invitation", title: "No invitation saved", message: "You can still enter a room code in Live race.") {
                                Button("Done") { invitations.isPresented = false }.buttonStyle(InkButtonStyle())
                            }
                        }
                    }.accessibilityElement(children: .contain).accessibilityFocused($noticeFocused)
                        .frame(maxWidth: 620).padding(20).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Invitation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { invitations.isPresented = false } } }
        }
        .foregroundStyle(Color.ink).tint(Color.ink)
        .confirmationDialog("Discard invitation?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard invitation", role: .destructive) { invitations.discard() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your saved race is unchanged.") }
        .sheet(isPresented: $showsAccount) {
            if let app {
                NavigationStack {
                    AccountView(model: app.account, syncMessage: app.syncMessage,
                                retrySync: app.showsRetry ? { app.retrySync() } : nil)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showsAccount = false } } }
                }.foregroundStyle(Color.ink).tint(Color.ink)
            }
        }
        .onChange(of: ready) { _, value in if value { showsAccount = false; noticeFocused = true } }
        .onChange(of: invitations.visiblePending) { _, _ in noticeFocused = true }
        .onChange(of: invitations.needsAttention) { _, _ in noticeFocused = true }
        .onAppear { noticeFocused = true }
    }
}
