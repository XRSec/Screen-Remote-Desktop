import Foundation

struct RemoteUiLayoutBounds: Equatable {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    var width: Int { max(0, right - left) }
    var height: Int { max(0, bottom - top) }

    func hasArea() -> Bool {
        width > 0 && height > 0
    }

    func area() -> Int64 {
        Int64(width) * Int64(height)
    }
}

enum RemoteUiLayoutNodeKind {
    case input
    case button
    case text
    case toggle
    case image
    case container
    case other
}

enum RemoteUiLayoutLabelSource {
    case text
    case contentDescription
    case resourceId
    case fallback
}

struct RemoteUiLayoutNode: Equatable {
    let bounds: RemoteUiLayoutBounds
    let label: String
    let labelSource: RemoteUiLayoutLabelSource
    let componentKey: String?
    let kind: RemoteUiLayoutNodeKind
    let packageName: String
    let className: String
    let resourceId: String
    let text: String
    let contentDescription: String
    let isLeaf: Bool
    let clickable: Bool
    let enabled: Bool
    let focusable: Bool
    let focused: Bool
    let checkable: Bool
    let checked: Bool
    let selected: Bool
    let scrollable: Bool
    let password: Bool
    let visibleToUser: Bool
    let hasInputDescendant: Bool
    let hasTextDescendant: Bool
    let hasButtonDescendant: Bool
    let hasCheckIndicatorDescendant: Bool

    var shortClassName: String {
        className
            .split(separator: ".")
            .last
            .map(String.init) ?? className
    }

    var isEffectivelyChecked: Bool {
        if checked || selected {
            return true
        }

        let stateDescription = contentDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let explicitlyUnchecked =
            stateDescription.contains("未选中") ||
            stateDescription.contains("未选择") ||
            stateDescription.contains("未勾选") ||
            stateDescription.contains("unchecked") ||
            stateDescription.contains("unselected") ||
            stateDescription.contains("not checked") ||
            stateDescription.contains("not selected")
        if explicitlyUnchecked {
            return false
        }

        return stateDescription.contains("已选中") ||
            stateDescription.contains("已勾选") ||
            stateDescription.contains("checked") ||
            stateDescription.contains("selected")
    }
}

struct RemoteUiLayoutSnapshot: Equatable {
    var viewportBounds: RemoteUiLayoutBounds
    let nodes: [RemoteUiLayoutNode]
}
