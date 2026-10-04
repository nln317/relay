import Messages
import RelayAnalytics
import RelayCore
import RelayGames
import RelayMessages
import RelayUI
import SwiftUI
import UIKit

/// Thin adapter between the Messages framework and `ConversationController`.
/// All decisions live in RelayMessages (unit tested on Linux); this class only
/// translates callbacks and builds `MSMessage`s.
final class MessagesViewController: MSMessagesAppViewController {
    private let model = ExtensionModel()
    private var hosting: UIHostingController<ExtensionRootView>?
    /// One MSSession per match, so each move replaces the previous bubble.
    private var sessions: [MatchID: MSSession] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        model.perform = { [weak self] request in self?.handle(request) }
        let hosting = UIHostingController(rootView: ExtensionRootView(model: model))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    // MARK: Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        model.analytics.record(.extensionOpen(presentation: Self.presentation(presentationStyle)))
        model.presentationStyle = presentationStyle
        show(conversation.selectedMessage, in: conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        show(message, in: conversation)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        let opened = Self.opened(message, in: conversation)
        if let screen = model.controller.received(opened, currentMatch: model.currentMatchID) {
            model.screen = screen
        }
    }

    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        model.controller.didStartSending(url: message.url)
        // Refresh from the ledger so the screen moves from "ready to send" to "their move".
        if model.currentMatchID != nil {
            model.screen = model.controller.screen(for: OpenedMessage(url: message.url, senderIsLocal: true, isPending: false))
        }
    }

    override func didCancelSending(_ message: MSMessage, conversation: MSConversation) {
        super.didCancelSending(message, conversation: conversation)
        model.controller.didCancelSending(url: message.url)
        show(conversation.selectedMessage, in: conversation)
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        model.presentationStyle = presentationStyle
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        // Nothing to flush: the ledger is written synchronously on every change,
        // because resign callbacks must return quickly.
    }

    private func show(_ message: MSMessage?, in conversation: MSConversation) {
        if let message, let session = message.session, let url = message.url,
           let snapshot = try? GameDecoders.decode(url) {
            sessions[snapshot.matchID] = session
        }
        model.screen = model.controller.screen(for: message.map { Self.opened($0, in: conversation) })
    }

    // MARK: Requests from the UI

    private func handle(_ request: ExtensionModel.Request) {
        switch request {
        case .expand:
            if presentationStyle != .expanded { requestPresentationStyle(.expanded) }
        case .insert(let outgoing):
            insert(outgoing)
        }
    }

    private func insert(_ outgoing: OutgoingMessage) {
        guard let conversation = activeConversation else {
            model.insertFailed("Messages isn't ready yet. Try again.")
            return
        }
        let session = sessions[outgoing.snapshot.matchID] ?? MSSession()
        sessions[outgoing.snapshot.matchID] = session

        let layout = MSMessageTemplateLayout()
        layout.caption = outgoing.caption.caption
        layout.subcaption = outgoing.caption.subcaption
        switch outgoing.snapshot {
        case .fourInARow(let snapshot):
            layout.image = BubbleImageRenderer.image(for: snapshot.match)
        }

        let message = MSMessage(session: session)
        message.url = outgoing.url
        message.layout = layout
        message.summaryText = outgoing.caption.summaryText
        message.accessibilityLabel = outgoing.caption.accessibilityLabel

        model.isWorking = true
        conversation.insert(message) { [weak self] error in
            // The completion handler runs on a background queue.
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.model.isWorking = false
                if let failure {
                    self.model.insertFailed("Couldn't add the move to the message box (\(failure)).")
                    return
                }
                self.model.controller.didInsert(outgoing)
                self.model.markInserted(outgoing)
                // Collapse so the compose field and its send button are visible.
                self.requestPresentationStyle(.compact)
            }
        }
    }

    // MARK: Helpers

    private static func opened(_ message: MSMessage, in conversation: MSConversation) -> OpenedMessage {
        OpenedMessage(
            url: message.url,
            senderIsLocal: message.senderParticipantIdentifier == conversation.localParticipantIdentifier,
            isPending: message.isPending
        )
    }

    private static func presentation(_ style: MSMessagesAppPresentationStyle) -> AnalyticsEvent.Presentation {
        switch style {
        case .compact: .compact
        case .expanded: .expanded
        case .transcript: .transcript
        @unknown default: .unknown
        }
    }
}
