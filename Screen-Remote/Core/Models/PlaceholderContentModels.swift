import AppKit
import Combine
import SwiftUI

struct PhoneApp: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    var badge: Int = 0
}

struct PhoneNotification: Identifiable {
    let id = UUID()
    let app: String
    let icon: String
    let color: Color
    let title: String
    let body: String
    let time: String
}

struct Conversation: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let preview: String
    let time: String
    let color: Color
    var unread: Bool = false
}
