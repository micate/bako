import Foundation

enum AppResources {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()
}
