import AppKit
import Foundation

struct ManagedAndroidApp: Identifiable, Codable, Equatable {
    let packageName: String
    let name: String
    let isEnabled: Bool
    let isSystem: Bool
    let versionCode: Int64
    let lastUpdateTime: Int64
    let iconFileName: String?

    var id: String { packageName }
}

struct DeviceAppActionResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct DeviceAppDetail: Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let usesMonospacedFont: Bool
    }

    let id = UUID()
    let app: ManagedAndroidApp
    let title: String
    let rows: [Row]
}
