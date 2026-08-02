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
            }
            .onDisappear {
                // Stop any in-flight Anthropic call when the sheet
                // closes — otherwise a 30-second response keeps
                // billing the proxy for a question the user
                // abandoned.
                inflight?.cancel()
                inflight = nil
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "stethoscope")
                .font(AppFont.scaled(11, weight: .semibold))
            Text("Educational only. Not medical advice.")
                .font(AppFont.caption)
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
                            TurnBubble(turn: turn)
                                .id(turn.id)
                        }
                    }

                    if isStreaming {
                        loadingBubble
                    }
                }
                .padding(Spacing.lg)
                // iPad cap so chat bubbles don't stretch into an
                // unreadably wide column (Phase 5.8 partial).
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: transcript.count) { _, _ in
                guard let last = transcript.last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            // Also follow the streaming text: chunks append to the
            // last turn's `content` without changing `transcript.count`,
            // so without this the view wouldn't scroll while a long
            // answer streams in — only at the next turn boundary.
            .onChange(of: transcript.last?.content) { _, _ in
                guard let last = transcript.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Ask anything about peptide research.")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            Text("Mention a compound by name and the assistant will pull half-life, dosage range, mechanism, and citations from your bundled database before answering.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Self.suggestedPrompts, id: \.self) { prompt in
                    Button {
                        input = prompt
                        inputFocused = true
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(AppFont.scaled(13, weight: .semibold))
                                .foregroundStyle(AppColor.accentLight)
                            Text(prompt)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .fill(AppColor.surfaceSecondary.opacity(0.6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Spacing.md)
        }
    }

    private var loadingBubble: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().scaleEffect(0.7).tint(AppColor.accentLight)
            Text("Thinking…")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask about a compound, stack, or study…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(canSend ? AppColor.accentPrimary : AppColor.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !isStreaming
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }

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

    private static let suggestedPrompts: [String] = [
        "What does the research say about BPC-157 half-life?",
        "Are there contraindications between Semaglutide and Tirzepatide?",
        "Summarize the mechanism of CJC-1295 + Ipamorelin.",
    ]
}

// MARK: - Bubble

private struct TurnBubble: View {
    let turn: AIResearchService.Turn

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
            } else {
                Spacer(minLength: Spacing.xl)
            }

            Text(turn.content)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(turn.role == .user
                            ? AppColor.accentPrimary.opacity(0.18)
                            : AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(
                                    turn.role == .user
                                        ? AppColor.accentPrimary.opacity(0.4)
                                        : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        }
                }
                .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
                .textSelection(.enabled)

            if turn.role == .user {
                Image(systemName: "person.fill")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle().fill(AppColor.surfaceElevated)
                    }
            } else {
                Spacer(minLength: Spacing.xl)
            }
        }
    }
}
