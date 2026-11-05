import SwiftUI
import Observation
#if DIRECT
import Sparkle
#endif

/// Новая версия, о которой узнал Sparkle (только DMG-сборка; в App Store всегда nil):
/// по ней SpaceToolbar показывает плашку, а Settings — точку у вкладки About.
@Observable
final class UpdateNotice {
    static let shared = UpdateNotice()
    private static let dismissedKey = "update.dismissedVersion"

    var availableVersion: String?
    private var dismissedVersion = UserDefaults.standard.string(forKey: dismissedKey)

    /// Версия, про которую плашку уже закрыли (✕): точка в Settings остаётся, плашка нет.
    var isBannerVisible: Bool {
        availableVersion != nil && availableVersion != dismissedVersion
    }

    func dismissBanner() {
        dismissedVersion = availableVersion
        UserDefaults.standard.set(availableVersion, forKey: Self.dismissedKey)
    }
}

#if DIRECT
/// Сборка вне App Store (GitHub, Homebrew, сайт): обновления ставит Sparkle —
/// лента appcast.xml в релизах GitHub, см. scripts/release-direct.sh.
enum DirectUpdater {
    private final class Delegate: NSObject, SPUUpdaterDelegate {
        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            Task { @MainActor in UpdateNotice.shared.availableVersion = item.displayVersionString }
        }
        func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
            Task { @MainActor in UpdateNotice.shared.availableVersion = nil }
        }
    }

    private static let delegate = Delegate()
    static let controller = SPUStandardUpdaterController(updaterDelegate: delegate, userDriverDelegate: nil)

    static func checkForUpdates() { controller.checkForUpdates(nil) }
}
#endif

/// Обновления ставит App Store — свой механизм обновлений там запрещён
/// (правило 2.4.5). Здесь только узнаём версию в App Store и ведём на
/// страницу приложения.
nonisolated enum AppStoreVersion {
    struct Release {
        let version: String
        let pageURL: URL
    }

    static func latest(bundleID: String) async throws -> Release? {
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Response: Decodable {
            struct Result: Decodable {
                let version: String
                let trackViewUrl: URL
            }
            let results: [Result]
        }
        return try JSONDecoder().decode(Response.self, from: data).results.first
            .map { Release(version: $0.version, pageURL: $0.trackViewUrl) }
    }

    /// 1.10 новее 1.9, 1.4.2 новее 1.4.
    static func isNewer(_ version: String, than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }
}

#if DIRECT
struct CheckForUpdatesRow: View {
    @State private var checksAutomatically = DirectUpdater.controller.updater.automaticallyChecksForUpdates
    @State private var downloadsAutomatically = DirectUpdater.controller.updater.automaticallyDownloadsUpdates

    var body: some View {
        SettingsRowButton(title: "Check for Updates\u{2026}") {
            DirectUpdater.controller.checkForUpdates(nil)
        }
        Toggle("Check for updates automatically", isOn: $checksAutomatically)
            .onChange(of: checksAutomatically) { _, value in
                DirectUpdater.controller.updater.automaticallyChecksForUpdates = value
                if !value { downloadsAutomatically = false }
            }
        Toggle("Download updates automatically", isOn: $downloadsAutomatically)
            .disabled(!checksAutomatically)
            .onChange(of: downloadsAutomatically) { _, value in
                DirectUpdater.controller.updater.automaticallyDownloadsUpdates = value
            }
    }
}
#else
struct CheckForUpdatesRow: View {
    private enum Status {
        case idle, checking, upToDate, failed
        case available(AppStoreVersion.Release)
    }

    @State private var status = Status.idle

    var body: some View {
        Button(action: tap) {
            HStack {
                Text(title)
                Spacer()
                if case .checking = status {
                    ProgressView().controlSize(.small)
                } else if case .available = status {
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                } else if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if case .available(let release) = status { return "Update to \(release.version) in the App Store" }
        return "Check for Updates"
    }

    private var detail: String? {
        switch status {
        case .upToDate: "You\u{2019}re up to date"
        case .failed: "Couldn\u{2019}t check"
        default: nil
        }
    }

    private func tap() {
        switch status {
        case .checking:
            return
        case .available(let release):
            NSWorkspace.shared.open(release.pageURL)
        default:
            status = .checking
            Task {
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                do {
                    let release = try await AppStoreVersion.latest(bundleID: Bundle.main.bundleIdentifier ?? "")
                    if let release, AppStoreVersion.isNewer(release.version, than: current) {
                        status = .available(release)
                    } else {
                        status = .upToDate
                    }
                } catch {
                    status = .failed
                }
            }
        }
    }
}
#endif
