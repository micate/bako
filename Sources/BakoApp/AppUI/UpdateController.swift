import Combine
import Foundation
import Sparkle

enum AppUpdateStatus: Equatable {
    case unavailable
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed(message: String)
}

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var status: AppUpdateStatus = .unavailable
    @Published private var updaterAllowsChecks = false

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: AnyCancellable?

    var currentVersion: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    var canCheckForUpdates: Bool {
        status != .checking && updaterAllowsChecks
    }

    override init() {
        super.init()

        guard Self.hasValidUpdateConfiguration else {
            status = .unavailable
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.updaterAllowsChecks = canCheck
            }
        controller.startUpdater()
        status = .idle
    }

    func checkForUpdates() {
        guard let updaterController, updaterController.updater.canCheckForUpdates else { return }
        status = .checking
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain && nsError.code == 1001 { // SUNoUpdateError
            status = .upToDate
        } else {
            status = .failed(message: error.localizedDescription)
        }
    }

    private static var hasValidUpdateConfiguration: Bool {
        guard
            let feedValue = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feedValue),
            feedURL.scheme?.lowercased() == "https",
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }
}
