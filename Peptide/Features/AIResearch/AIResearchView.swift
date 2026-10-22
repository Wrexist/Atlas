import SwiftUI

/// Chat surface for the on-demand peptide research assistant. Backed by
/// `AIResearchService` (Anthropic Messages API via the configured
/// proxy) with substring-RAG over the bundled peptide database for
/// citation-grounded answers.
///
/// Pro-gated entry point: surfaced from `PeptideListView` and from a
/// floating action button on Home for users with `storeService.isProUser`.
/// Free tier sees the upsell sheet.
struct AIResearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @State private var input: String = ""
    @State private var isStreaming = false
    @State private var errorText: String?
    /// In-flight Anthropic request. Cancelled on send (so a new
    /// question doesn't double-bill) and on disappear (closing the
    /// chat sheet shouldn't keep a 30s call alive against the
    /// proxy quota).
    @State private var inflight: Task<Void, Never>?
    /// Incremented on every `send()`. A stream task only clears
    /// `isStreaming` if its generation still matches — otherwise a
    /// cancelled task's `defer` would flip the flag false while a
    /// newer stream is still running.
    @State private var streamGeneration = 0
    /// The last prompt that hit an error, kept around so the Retry button on
    /// the alert can re-send it without making the user retype.
    @State private var lastFailedPrompt: String?
    @State private var transcript: [AIResearchService.Turn] = []
    @State private var showConsent = false
    /// True while the transcript is scrolled to (or near) its end. Streamed
    /// chunks only auto-follow then, so scrolling up to re-read an earlier
    /// answer isn't yanked back down on every token.
    @State private var isPinnedToBottom = true
    /// Bumped on each send, for the send haptic.
    @State private var sendCount = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                disclaimer
                transcriptScroll
                composer
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Research Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startNewChat()
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                    }
                    .disabled(transcript.isEmpty)
                }
            }
            .appSensoryFeedback(.impact(weight: .light), trigger: sendCount)
            .onDisappear {
                // Stop any in-flight Anthropic call when the sheet
                // closes — otherwise a 30-second response keeps
                // billing the proxy for a question the user
                // abandoned.
                inflight?.cancel()
                inflight = nil
            }
            .sheet(isPresented: $showConsent, onDismiss: sendIfConsented) {
                AIConsentSheet(whatIsSent: "Your messages in this chat, including earlier ones in the conversation.")
                    .liquidGlassPresentation()
            }
            .alert(
                "Couldn't reach the assistant",
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                if let prompt = lastFailedPrompt {
                    Button("Retry") {
                        errorText = nil
                        lastFailedPrompt = nil
                        input = prompt
                        send()
                    }
                }
                Button("Dismiss", role: .cancel) {
                    lastFailedPrompt = nil
                }
            } message: {
                Text(errorText ?? "Something went wrong reaching the research assistant. Check your connection and try again.")
            }
        }
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(11, weight: .semibold))
            Text("Educational only. Not medical advice.")
                .font(AppFont.caption2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .background {
            Rectangle()
                .fill(AppColor.surfaceSecondary.opacity(0.4))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppColor.glassBorder)
                        .frame(height: 0.5)
                }
        }
    }

    // MARK: - Transcript

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if transcript.isEmpty {
                        emptyState
                            .padding(.top, Spacing.xl)
                    } else {
                        ForEach(transcript) { turn in
                            TurnBubble(turn: turn, isStreaming: isStreaming && turn.id == transcript.last?.id)
                                .id(turn.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .appAnimation(AppAnimation.springSnappy, value: transcript.count)
                .padding(Spacing.lg)
                // iPad cap so chat bubbles don't stretch into an
                // unreadably wide column (Phase 5.8 partial).
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - Spacing.xxxxl
            } action: { _, pinned in
                isPinnedToBottom = pinned
            }
            .onChange(of: transcript.count) { _, _ in
                // A new turn is the user's own send: always bring it in.
                guard let last = transcript.last else { return }
                AppAnimation.with(AppAnimation.fadeIn) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            // Follow the streaming text — chunks grow the last turn without
            // changing `transcript.count` — but only while the reader is
            // already at the bottom.
            .onChange(of: transcript.last?.content) { _, _ in
                guard isPinnedToBottom, let last = transcript.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Ask about training, nutrition, recovery, or a compound you track.")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            Text("Mention a compound by name and the assistant will pull half-life, dosage range, mechanism, and citations from your bundled database before answering.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(Self.suggestedPrompts.enumerated()), id: \.element) { index, prompt in
                    Button {
                        input = prompt
                        send()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(AppFont.scaled(13, weight: .semibold))
                                .foregroundStyle(AppColor.accentLight)
                                .accessibilityHidden(true)
                            Text(prompt)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(Spacing.md)
                        .insetRowBackground(cornerRadius: Spacing.smallCornerRadius)
                    }
                    .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                    .staggeredAppear(index: index)
                }
            }
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: Spacing.sm) {
            GlassTextField(
                placeholder: "Ask about a compound, protocol, or study…",
                text: $input,
                icon: nil,
                axis: .vertical,
                focus: $inputFocused
            )
            .lineLimit(1...5)

            // Doubles as Stop while an answer streams, so a long reply can
            // be cut short without closing the sheet.
            Button {
                if isStreaming {
                    inflight?.cancel()
                } else {
                    send()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(AppFont.scaled(32, weight: .semibold))
                    .foregroundStyle(isStreaming || canSend ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .disabled(!isStreaming && !canSend)
            .accessibilityLabel(isStreaming ? "Stop answer" : "Send question")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background { GlassBarBackground() }
        .overlay(alignment: .top) {
            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }
        // Nothing leaves the device until the user has agreed to share it
        // with Anthropic. The prompt stays in `input` so it sends as soon
        // as they tap Allow.
        guard AIDataConsent.isGranted else {
            input = prompt
            showConsent = true
            return
        }

        sendCount += 1
        let userTurn = AIResearchService.Turn(role: .user, content: prompt)
        transcript.append(userTurn)
        input = ""
        isStreaming = true
        streamGeneration += 1
        let generation = streamGeneration

        let priorHistory = Array(transcript.dropLast()) // exclude the user turn we just appended
        let database = dataStore.peptideDatabase

        // Empty assistant turn — chunks land into this turn's content
        // as the SSE stream arrives, so the bubble animates token-by-
        // token instead of popping in fully formed.
        let assistantTurn = AIResearchService.Turn(role: .assistant, content: "")
        transcript.append(assistantTurn)

        // Cancel any in-flight stream from a previous question so the
        // user can fire off a new prompt without waiting and without
        // having stale tokens land in the new bubble (main-side fix).
        inflight?.cancel()
        inflight = Task { @MainActor in
            // Only clear isStreaming if this is still the current
            // stream — a superseding send() owns the flag otherwise.
            defer { if generation == streamGeneration { isStreaming = false } }
            let stream = AIResearchService.shared.replyStream(
                history: priorHistory,
                newUserPrompt: prompt,
                in: database
            )
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    if let idx = transcript.lastIndex(where: { $0.id == assistantTurn.id }) {
                        transcript[idx].content.append(chunk)
                    }
                }
                // Empty stream (proxy returned 200 but nothing parseable)
                // — surface a friendly error instead of leaving a blank
                // bubble sitting in the transcript.
                if let idx = transcript.lastIndex(where: { $0.id == assistantTurn.id }),
                   transcript[idx].content.isEmpty {
                    transcript.remove(at: idx)
                    errorText = AIResearchService.ChatError.invalidResponse.errorDescription
                    lastFailedPrompt = prompt
                }
            } catch is CancellationError {
                // User fired a new question or closed the sheet — drop
                // the partially-streamed placeholder silently, no alert.
                if let idx = transcript.lastIndex(where: { $0.id == assistantTurn.id }),
                   transcript[idx].content.isEmpty {
                    transcript.remove(at: idx)
                }
            } catch {
                // Drop the empty placeholder before showing the alert so
                // the user doesn't see a half-rendered assistant bubble.
                if let idx = transcript.lastIndex(where: { $0.id == assistantTurn.id }),
                   transcript[idx].content.isEmpty {
                    transcript.remove(at: idx)
                }
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastFailedPrompt = prompt
                Haptics.error()
            }
        }
    }

    private func sendIfConsented() {
        if AIDataConsent.isGranted { send() }
    }

    private func startNewChat() {
        inflight?.cancel()
        inflight = nil
        AppAnimation.with(AppAnimation.springSnappy) {
            transcript = []
        }
        input = ""
    }

    private static let suggestedPrompts: [String] = [
        "How does sleep affect HRV recovery?",
        "How much protein do I need for hypertrophy?",
        "What does the research say about BPC-157 half-life?",
    ]
}

// MARK: - Bubble

private struct TurnBubble: View {
    let turn: AIResearchService.Turn
    /// True while this turn's reply is still streaming. Until the first
    /// token lands the bubble carries the typing indicator instead of
    /// rendering as an empty rounded rect.
    var isStreaming = false

    var body: some View {
        HStack(alignment: .top) {
            if turn.role == .assistant {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle().fill(AppColor.accentPrimary.opacity(0.18))
                    }
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: Spacing.xl)
            }

            bubbleContent
                .padding(Spacing.md)
                // The user's own turns take the tinted glass so the two
                // speakers read apart at a glance.
                .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: turn.role == .user)
                .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)

            if turn.role == .user {
                Image(systemName: "person.fill")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle().fill(AppColor.surfaceElevated)
                    }
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: Spacing.xl)
            }
        }
        // One stop per turn that says who is speaking.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let speaker = turn.role == .user ? "You" : "Assistant"
        let body = isStreaming && turn.content.isEmpty ? "typing" : turn.content
        return "\(speaker): \(body)"
    }

    /// Claude answers in Markdown; render inline emphasis, code and links
    /// rather than printing the `**` and `[](…)` syntax. Falls back to the
    /// raw text if a half-streamed chunk doesn't parse.
    private var renderedContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: turn.content, options: options))
            ?? AttributedString(turn.content)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isStreaming && turn.content.isEmpty {
            TypingIndicator()
        } else {
            Text(renderedContent)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentLight)
                .textSelection(.enabled)
        }
    }
}

/// Three dots that pulse in turn while the first token is on its way.
/// Static under Reduce Motion.
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                dot(index)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is typing")
    }

    @ViewBuilder
    private func dot(_ index: Int) -> some View {
        let circle = Circle()
            .fill(AppColor.textSecondary)
            .frame(width: 6, height: 6)
        if reduceMotion {
            circle
        } else {
            circle.phaseAnimator([0, 1, 2]) { view, phase in
                view
                    .scaleEffect(phase == index ? 1.3 : 1)
                    .opacity(phase == index ? 1 : 0.4)
            } animation: { _ in
                AppAnimation.quick
            }
        }
    }
}
