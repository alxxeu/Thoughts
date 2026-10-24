import SwiftUI
#if DIRECT
import Sparkle

/// Сборка вне App Store (GitHub, Homebrew, сайт): обновления ставит Sparkle —
/// лента appcast.xml в релизах GitHub, см. scripts/release-direct.sh.
enum DirectUpdater {
    static let controller = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
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
    var body: some View {
        SettingsRowButton(title: "Check for Updates\u{2026}") {
            DirectUpdater.controller.checkForUpdates(nil)
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
