import Foundation
import Observation

/// Конвертер включённого плагина: скрипт и id, под которым он зарегистрирован.
struct ConverterEntry {
    let script: PluginScript
    let id: String
    let name: String
}

/// Конвертеры в карточках, как в Spotlight: строка → результат первого конвертера,
/// который её узнал. Запросы — с задержкой 150 мс после ввода, устаревшие
/// отбрасываются, последние ответы кэшируются. Конвертер, трижды подряд не
/// ответивший вовремя, выключается вместе с плагином.
@Observable
final class ConverterService {
    static let shared = ConverterService()

    private static let enabledKey = "converters.enabled"
    static let debounce: Duration = .milliseconds(150)
    static let localTimeout: Duration = .milliseconds(300)
    static let networkTimeout: Duration = .seconds(3)
    static let maxLineLength = 200
    private static let cacheLimit = 50
    private static let strikeLimit = 3

    /// Settings → Plugins → Converters.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored var converters: [ConverterEntry] = [] {
        didSet { cache = [:]; cacheOrder = [] }
    }
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cache: [String: String?] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var strikes: [String: Int] = [:]
    /// Плагин перестал отвечать — менеджер его выключает.
    @ObservationIgnored var onUnresponsive: (String) -> Void = { _ in }

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Результат для строки или nil. Новый запрос отменяет ждущий старый: в
    /// `completion` приходит ответ только на последний запрос.
    func request(_ line: String, debounce: Duration = ConverterService.debounce, completion: @escaping (String?) -> Void) {
        generation += 1
        let current = generation
        // «12*3 =» — конвертер видит выражение без хвостового «=».
        var input = line.trimmingCharacters(in: .whitespaces)
        if input.hasSuffix("=") { input = String(input.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard isEnabled, !converters.isEmpty, !input.isEmpty, input.count <= Self.maxLineLength else {
            return completion(nil)
        }
        if let cached = cache[input] { return completion(cached) }

        Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard current == generation else { return }
            let result = await firstResult(for: input)
            remember(result, for: input)
            guard current == generation else { return }
            completion(result)
        }
    }

    /// Отменить ждущий запрос (каретка ушла со строки).
    func cancel() { generation += 1 }

    private func firstResult(for input: String) async -> String? {
        for entry in converters {
            let timeout = entry.script.usesNetwork ? Self.networkTimeout : Self.localTimeout
            switch await Self.convert(input, with: entry, timeout: timeout) {
            case .value(let text):
                strikes[entry.script.pluginID] = 0
                if let text { return text }
            case .timedOut:
                let count = (strikes[entry.script.pluginID] ?? 0) + 1
                strikes[entry.script.pluginID] = count
                if count >= Self.strikeLimit {
                    strikes[entry.script.pluginID] = 0
                    onUnresponsive(entry.script.pluginID)
                }
            }
        }
        return nil
    }

    private nonisolated enum Outcome: Sendable { case value(String?), timedOut }

    /// Ответ скрипта или «не успел» — что раньше.
    private static func convert(_ input: String, with entry: ConverterEntry, timeout: Duration) async -> Outcome {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            entry.script.convert(input, with: entry.id) { once.resume(.value($0)) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(.timedOut)
            }
        }
    }

    /// Continuation отдаётся ровно один раз — ответ и таймаут соревнуются.
    private nonisolated final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<Outcome, Never>?
        private let lock = NSLock()
        init(_ continuation: CheckedContinuation<Outcome, Never>) { self.continuation = continuation }
        func resume(_ outcome: Outcome) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: outcome)
        }
    }

    private func remember(_ result: String?, for input: String) {
        if cache[input] == nil { cacheOrder.append(input) }
        cache[input] = .some(result)
        if cacheOrder.count > Self.cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    // MARK: - Что вставлять

    /// Хвост, который допишется к строке по Tab (и который виден серым):
    /// `12*3` → ` = 36`, `12*3 =` → ` 36`, `12*3 = ` → `36`.
    static func suffix(for line: String, result: String) -> String {
        if line.hasSuffix("= ") { return result }
        if line.hasSuffix("=") { return " " + result }
        if line.hasSuffix(" ") { return "= " + result }
        return " = " + result
    }
}
