import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case analyzing
        case ready(TaskAnalysis)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastPromise: String = ""

    private let service: AIService

    init(service: AIService = OpenAICompatibleService()) {
        self.service = service
    }

    func submit(promise: String) async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastPromise = trimmed
        state = .analyzing
        do {
            let result = try await service.analyzeTask(trimmed)
            state = .ready(result)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    func reset() {
        state = .idle
        lastPromise = ""
    }
}
