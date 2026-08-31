import SwiftUI

struct ScreenLayoutInspectorNodeOverlay: View {
    let snapshot: RemoteUiLayoutSnapshot

    var body: some View {
        GeometryReader { proxy in
            let viewport = snapshot.viewportBounds
            let scaleX = proxy.size.width / CGFloat(max(viewport.width, 1))
            let scaleY = proxy.size.height / CGFloat(max(viewport.height, 1))
            ZStack(alignment: .topLeading) {
                ForEach(Array(snapshot.nodes.enumerated()), id: \.offset) { _, node in
                    let frame = CGRect(
                        x: CGFloat(node.bounds.left - viewport.left) * scaleX,
                        y: CGFloat(node.bounds.top - viewport.top) * scaleY,
                        width: max(CGFloat(node.bounds.width) * scaleX, 1),
                        height: max(CGFloat(node.bounds.height) * scaleY, 1)
                    )
                    ScreenLayoutInspectorNodeView(
                        node: node,
                        allNodes: snapshot.nodes,
                        frame: frame,
                        availableWidth: proxy.size.width
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScreenLayoutInspectorToolbar: View {
    let isLoading: Bool
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onRefresh) {
                AppRefreshSymbol(isAnimating: isLoading)
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("commonRefresh")
            .accessibilityLabel(Text("commonRefresh"))

            Button(action: onClose) {
                Image(systemName: "xmark.circle")
                    .font(AppTypography.headline)
                    .foregroundColor(Color(red: 1, green: 59.0 / 255.0, blue: 48.0 / 255.0))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("commonClose")
            .accessibilityLabel(Text("commonClose"))
        }
        .padding(AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(
                    Color(
                        red: 44.0 / 255.0,
                        green: 44.0 / 255.0,
                        blue: 46.0 / 255.0
                    )
                    .opacity(234.0 / 255.0)
                )
        )
    }
}

private struct ScreenLayoutInspectorNodeView: View {
    let node: RemoteUiLayoutNode
    let allNodes: [RemoteUiLayoutNode]
    let frame: CGRect
    let availableWidth: CGFloat

    private var color: Color {
        guard node.enabled else { return .gray }
        switch node.kind {
        case .input: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .button: return Color(red: 0.39, green: 0.71, blue: 0.96)
        case .text: return Color(red: 1.00, green: 0.84, blue: 0.31)
        case .toggle: return Color(red: 1.00, green: 0.54, blue: 0.40)
        case .image: return Color(red: 0.73, green: 0.41, blue: 0.78)
        case .container: return Color(red: 0.56, green: 0.64, blue: 0.68)
        case .other: return Color(red: 0.88, green: 0.88, blue: 0.88)
        }
    }

    private var displayLabel: String {
        guard !node.label.isEmpty else { return "" }
        return node.enabled ? node.label : "\(node.label) [disabled]"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(color, lineWidth: node.focused ? 2 : 1)
                )
                .overlay(indicator)
                .frame(width: frame.width, height: frame.height)

            if !displayLabel.isEmpty,
               !shouldSuppressScreenLayoutNodeLabel(node, allNodes: allNodes) {
                Text(displayLabel)
                    .font(AppTypography.caption)
                    .foregroundColor(.black)
                    .lineLimit(3)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .frame(
                        width: min(max(frame.width, 16), max(16, availableWidth - frame.minX - 2)),
                        alignment: .leading
                    )
                    .background(RoundedRectangle(cornerRadius: AppRadius.xsmall).fill(color.opacity(0.88)))
                    .offset(x: 2, y: 2)
            }
        }
        .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder
    private var indicator: some View {
        if shouldRenderScreenLayoutToggle(node) {
            ScreenLayoutToggleIndicator(node: node)
                .padding(.leading, shouldAnchorScreenLayoutIndicator(node) ? min(max(frame.height * 0.12, 2), 10) : 0)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: shouldAnchorScreenLayoutIndicator(node) ? .leading : .center
                )
        } else if shouldRenderScreenLayoutArrow(node) {
            Image(systemName: "chevron.down")
                .font(AppTypography.caption.weight(.bold))
                .foregroundColor(color)
        }
    }
}

private struct ScreenLayoutToggleIndicator: View {
    let node: RemoteUiLayoutNode

    var body: some View {
        switch style {
        case .checkbox:
            Image(systemName: node.isEffectivelyChecked ? "checkmark.square.fill" : "square")
                .font(AppTypography.headline.weight(.semibold))
                .foregroundColor(node.isEffectivelyChecked ? .green : .gray)
        case .radio:
            Image(systemName: node.isEffectivelyChecked ? "largecircle.fill.circle" : "circle")
                .font(AppTypography.headline.weight(.semibold))
                .foregroundColor(node.isEffectivelyChecked ? .green : .gray)
        case .toggle:
            ZStack(alignment: node.isEffectivelyChecked ? .trailing : .leading) {
                Capsule().fill(node.isEffectivelyChecked ? Color.green : Color.gray).frame(width: 26, height: 16)
                Circle().fill(Color.white).frame(width: 10, height: 10).padding(.horizontal, 3)
            }
        }
    }

    private var style: ScreenLayoutToggleStyle {
        let className = node.shortClassName.lowercased()
        let resource = node.resourceId.lowercased()
        if className.contains("radio") || resource.contains(":id/rb_") || resource.contains("/rb_") {
            return .radio
        }
        if className.contains("switch") ||
            (className.contains("compoundbutton") && !className.contains("radio") && !className.contains("check")) ||
            resource.contains(":id/sb_") || resource.contains("/sb_") {
            return .toggle
        }
        return .checkbox
    }
}

private enum ScreenLayoutToggleStyle {
    case checkbox
    case radio
    case toggle
}

private func shouldRenderScreenLayoutArrow(_ node: RemoteUiLayoutNode) -> Bool {
    guard node.label.isEmpty,
          [.image, .other, .button].contains(node.kind) else { return false }
    let resource = node.resourceId.lowercased()
    return ["arrow", "dropdown", "expand", "chevron", "caret", "spinner", "region_image", "regionimage"]
        .contains { resource.contains($0) }
}

private func shouldRenderScreenLayoutToggle(_ node: RemoteUiLayoutNode) -> Bool {
    if node.kind == .toggle { return true }
    let resource = node.resourceId.lowercased()
    return node.kind == .container && node.clickable &&
        ["check", "checkbox", "confirm", "agree", "accept", "consent", "policy"]
            .contains { resource.contains($0) }
}

private func shouldAnchorScreenLayoutIndicator(_ node: RemoteUiLayoutNode) -> Bool {
    let hasInlineLabel = !node.text.isEmpty || !node.label.isEmpty || !node.contentDescription.isEmpty
    return node.checkable && hasInlineLabel && node.bounds.width > node.bounds.height
}

func shouldSuppressScreenLayoutNodeLabel(
    _ node: RemoteUiLayoutNode,
    allNodes: [RemoteUiLayoutNode]
) -> Bool {
    if [.text, .input].contains(node.kind) || node.labelSource == .text { return false }

    if let componentKey = node.componentKey,
       allNodes.contains(where: { other in
           other != node && other.componentKey == componentKey && !other.label.isEmpty &&
               other.labelSource != .resourceId
       }) {
        return true
    }

    if node.kind == .image, node.labelSource == .resourceId,
       allNodes.contains(where: { other in
           other != node && other.kind == .text && !other.label.isEmpty &&
               other.labelSource != .resourceId && other.packageName == node.packageName &&
               ((horizontalOverlap(node, other) >= 0.4 && verticalGap(node, other) <= 80 &&
                   likelySpecificStackedLabel(node, other)) ||
                (verticalOverlap(node, other) >= 0.4 && horizontalGap(node, other) <= 80))
       }) {
        return true
    }

    if let componentKey = node.componentKey, node.labelSource == .resourceId,
       allNodes.contains(where: { other in
           guard other != node, other.componentKey == componentKey, !other.label.isEmpty,
                 other.labelSource == .resourceId else { return false }
           return other.bounds.area() > node.bounds.area() ||
               (other.bounds.area() == node.bounds.area() && other.bounds.width > node.bounds.width) ||
               (other.bounds.area() == node.bounds.area() && other.bounds.width == node.bounds.width &&
                   other.resourceId < node.resourceId)
       }) {
        return true
    }

    let resource = node.resourceId.lowercased()
    if node.labelSource == .resourceId, node.kind == .container,
       ["layout_", "_group", "container"].contains(where: { resource.contains($0) }),
       allNodes.contains(where: { other in
           other != node && other.packageName == node.packageName && other.kind == .text &&
               !other.label.isEmpty && contains(node.bounds, other.bounds)
       }) {
        return true
    }

    if node.kind == .image, node.labelSource == .resourceId,
       allNodes.contains(where: { other in
           other != node && !other.label.isEmpty && other.labelSource != .resourceId &&
               other.packageName == node.packageName && other.bounds.area() >= node.bounds.area() &&
               overlapOverSmallerArea(node.bounds, other.bounds) >= 0.6
       }) {
        return true
    }

    if allNodes.contains(where: { other in
        other != node && other.kind == .text && !other.label.isEmpty &&
            other.packageName == node.packageName && verticalOverlap(node, other) >= 0.6 &&
            horizontalGap(node, other) <= 36
    }) {
        return true
    }

    if allNodes.contains(where: { other in
        other != node && other.kind == .text && !other.label.isEmpty &&
            other.labelSource != .resourceId && other.packageName == node.packageName &&
            horizontalOverlap(node, other) >= 0.6 && verticalGap(node, other) <= 48 &&
            likelySpecificStackedLabel(node, other)
    }) {
        return true
    }

    if allNodes.contains(where: { other in
        other != node && !other.label.isEmpty && other.labelSource != .resourceId &&
            other.packageName == node.packageName && other.bounds.area() >= node.bounds.area() &&
            contains(other.bounds, node.bounds)
    }) {
        return true
    }

    return allNodes.contains(where: { other in
        other != node && !other.label.isEmpty && other.labelSource != .resourceId &&
            other.packageName == node.packageName && other.bounds.area() >= node.bounds.area() &&
            overlapOverSmallerArea(node.bounds, other.bounds) >= 0.88
    })
}

private func likelySpecificStackedLabel(_ node: RemoteUiLayoutNode, _ text: RemoteUiLayoutNode) -> Bool {
    guard CGFloat(text.bounds.width) <= CGFloat(max(node.bounds.width, 1)) * 1.5 else { return false }
    let nodeCenter = CGFloat(node.bounds.left + node.bounds.right) / 2
    let textCenter = CGFloat(text.bounds.left + text.bounds.right) / 2
    return abs(nodeCenter - textCenter) <= CGFloat(max(node.bounds.width, 1)) * 0.25
}

private func verticalOverlap(_ nodeA: RemoteUiLayoutNode, _ nodeB: RemoteUiLayoutNode) -> CGFloat {
    let overlap = min(nodeA.bounds.bottom, nodeB.bounds.bottom) - max(nodeA.bounds.top, nodeB.bounds.top)
    return overlap > 0 ? CGFloat(overlap) / CGFloat(max(min(nodeA.bounds.height, nodeB.bounds.height), 1)) : 0
}

private func horizontalOverlap(_ nodeA: RemoteUiLayoutNode, _ nodeB: RemoteUiLayoutNode) -> CGFloat {
    let overlap = min(nodeA.bounds.right, nodeB.bounds.right) - max(nodeA.bounds.left, nodeB.bounds.left)
    return overlap > 0 ? CGFloat(overlap) / CGFloat(max(min(nodeA.bounds.width, nodeB.bounds.width), 1)) : 0
}

private func horizontalGap(_ nodeA: RemoteUiLayoutNode, _ nodeB: RemoteUiLayoutNode) -> Int {
    if nodeA.bounds.right < nodeB.bounds.left { return nodeB.bounds.left - nodeA.bounds.right }
    if nodeB.bounds.right < nodeA.bounds.left { return nodeA.bounds.left - nodeB.bounds.right }
    return 0
}

private func verticalGap(_ nodeA: RemoteUiLayoutNode, _ nodeB: RemoteUiLayoutNode) -> Int {
    if nodeA.bounds.bottom < nodeB.bounds.top { return nodeB.bounds.top - nodeA.bounds.bottom }
    if nodeB.bounds.bottom < nodeA.bounds.top { return nodeA.bounds.top - nodeB.bounds.bottom }
    return 0
}

private func contains(_ outer: RemoteUiLayoutBounds, _ inner: RemoteUiLayoutBounds) -> Bool {
    outer.left <= inner.left && outer.top <= inner.top &&
        outer.right >= inner.right && outer.bottom >= inner.bottom
}

private func overlapOverSmallerArea(
    _ boundsA: RemoteUiLayoutBounds,
    _ boundsB: RemoteUiLayoutBounds
) -> CGFloat {
    let width = min(boundsA.right, boundsB.right) - max(boundsA.left, boundsB.left)
    let height = min(boundsA.bottom, boundsB.bottom) - max(boundsA.top, boundsB.top)
    guard width > 0, height > 0 else { return 0 }
    let intersection = Int64(width) * Int64(height)
    return CGFloat(intersection) / CGFloat(max(min(boundsA.area(), boundsB.area()), 1))
}
