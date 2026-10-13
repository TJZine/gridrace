import SwiftUI

struct LiveRematchPresentation: Equatable {
    let title: String
    let message: String
    let actions: [LiveRematchAction]
    static func map(snapshot: LiveMatchSnapshot, actions: [LiveRematchAction], resolving: Bool) -> Self? {
        guard snapshot.match.status == .completed, let rematch = snapshot.rematch else { return nil }
        let selfID = snapshot.members.first(where: \.isSelf)?.id
        let opponent = snapshot.members.first(where: { !$0.isSelf })?.displayName ?? "your opponent"
        let rounds = snapshot.match.roundCount == 1 ? "1 round" : "\(snapshot.match.roundCount) rounds"
        let sameRace = "\(rounds), same players. The host starts a fresh lobby."
        let title: String
        let message: String
        switch rematch.state {
        case .eligible:
            title = "Race again?"; message = sameRace
        case .offered:
            if selfID.map(rematch.consentingMemberIDs.contains) == true {
                title = "Waiting for \(opponent)"; message = "Your rematch offer is open. You can cancel it."
            } else {
                title = "\(opponent) wants a rematch"; message = sameRace
            }
        case .closed:
            switch rematch.reason {
            case .cancelled: title = "Rematch cancelled"
            case .declined: title = "Rematch declined"
            case .participationChanged: title = "A player changed races"
            default: title = "Rematch closed"
            }
            message = actions.contains(.offer) ? "Offer again for fresh consent from both players." : "This rematch is no longer available."
        case .expired:
            title = "Rematch window ended"; message = "Start a new race and invite your friend when you're ready."
        case .unavailable:
            title = "Rematch unavailable"
            message = rematch.reason == .accountDeleted ? "A player left GridRace. These results stay saved."
                : rematch.reason == .featureDisabled ? "Rematches are unavailable right now. Your results stay saved."
                : "These results can't start another race."
        case .accepted:
            title = rematch.successorAvailable ? "Rematch accepted" : "Rematch lobby unavailable"
            message = !rematch.successorAvailable ? "A player left before the next race started. These results stay saved."
                : rematch.selectedElsewhere ? "Resume to confirm switching to the rematch lobby."
                : "Opening your new lobby. The host starts the race."
        }
        return Self(title: title, message: resolving ? "Confirming your choice. Your results stay saved." : message,
                    actions: resolving ? [] : actions)
    }
    static func title(_ action: LiveRematchAction, state: LiveRematchState) -> String {
        switch action {
        case .offer: state == .closed ? "Offer again" : "Rematch"
        case .accept: "Accept rematch"
        case .cancel: "Cancel offer"
        case .decline: "Decline"
        }
    }
}

struct LiveRematchView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    @AccessibilityFocusState private var noticeFocused: Bool
    private var presentation: LiveRematchPresentation? {
        LiveRematchPresentation.map(snapshot: snapshot, actions: session.availableRematchActions,
                                    resolving: session.isCommandInFlight || session.pendingIntent != nil)
    }
    var body: some View {
        if let presentation, let rematch = snapshot.rematch {
            NoticeCard(subject: "Rematch", title: presentation.title, message: presentation.message,
                       kind: presentation.actions.isEmpty ? .information : .action) {
                ForEach(presentation.actions, id: \.rawValue) { action in
                    Button(LiveRematchPresentation.title(action, state: rematch.state)) { session.performRematch(action) }
                        .buttonStyle(OutlinedInkButtonStyle()).frame(minHeight: 44)
                }
                if rematch.state == .accepted && rematch.successorAvailable && session.phase == .recovering {
                    ProgressView("Opening lobby")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityFocused($noticeFocused)
            // Focus owns speech once per meaningful state/action change. Clock ticks
            // do not create announcements or locally close a server offer.
            .onChange(of: presentation) { _, _ in noticeFocused = true }
            .onAppear { noticeFocused = true }
        }
    }
}
