import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Short, private natural-language summaries from Apple's on-device model
/// (iOS 26+, Apple Intelligence). Nothing leaves the device.
///
/// Surfaces read `text(for:)` — the cached model text for those facts, else
/// the deterministic fallback — and call `prepare(_:)` from `.task(id:)`.
/// The fallback renders immediately; the model's rephrasing replaces it when
/// it answers within `timeout`. On devices without the model, with Apple
/// Intelligence off, or with the setting off, only the fallback is ever shown.
@MainActor @Observable
final class OnDeviceSummaryService {
    static let shared = OnDeviceSummaryService()
    static let enabledKey = "onDeviceSummariesEnabled"

    typealias Generator = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    private struct Entry {
        let day: String
        let text: String
    }

    struct ModelUnavailable: Error {}

    private(set) var isEnabled: Bool
    private var generated: [String: Entry] = [:]
    @ObservationIgnored private var attempted: Set<String> = []
    private let defaults: UserDefaults
    private let modelAvailable: @Sendable () -> Bool
    private let generator: Generator
    private let timeout: Duration

    init(
        defaults: UserDefaults = .standard,
        modelAvailable: @escaping @Sendable () -> Bool = { OnDeviceSummaryService.systemModelAvailable() },
        timeout: Duration = .seconds(5),
        generator: @escaping Generator = { try await OnDeviceSummaryService.systemGenerate(instructions: $0, prompt: $1) }
    ) {
        self.defaults = defaults
        self.modelAvailable = modelAvailable
        self.timeout = timeout
        self.generator = generator
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Whether this device can run the model right now. Settings hides the
    /// toggle when it can't.
    var isSupported: Bool { modelAvailable() }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func text(for facts: OnDeviceSummaryEngine.Facts) -> String? {
        guard isEnabled, isSupported else { return facts.fallback }
        return generated[facts.cacheKey]?.text ?? facts.fallback
    }

    /// Asks the model once per facts/day. Failures, timeouts and outputs
    /// that fail `OnDeviceSummaryEngine.accept` leave the fallback in place.
    func prepare(_ facts: OnDeviceSummaryEngine.Facts) async {
        let key = facts.cacheKey
        guard isEnabled, isSupported, attempted.insert(key).inserted else { return }
        let prompt = OnDeviceSummaryEngine.prompt(for: facts)
        guard let output = await withTimeout(prompt: prompt),
              let text = OnDeviceSummaryEngine.accept(output, for: facts) else { return }
        generated = generated.filter { $0.value.day == facts.day }
        generated[key] = Entry(day: facts.day, text: text)
    }

    private func withTimeout(prompt: String) async -> String? {
        let generator = generator
        let limit = timeout
        let instructions = OnDeviceSummaryEngine.instructions
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await generator(instructions, prompt) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Foundation Models

    nonisolated static func systemModelAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    nonisolated static func systemGenerate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: OnDeviceSummaryDraft.self)
            return response.content.summary
        }
        #endif
        throw ModelUnavailable()
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct OnDeviceSummaryDraft {
    @Guide(description: "One or two short sentences restating only the given facts.")
    var summary: String
}
#endif
