import Foundation

enum RemoteUiLayoutParser {
    static func parse(_ xml: String) throws -> [RemoteUiLayoutNode] {
        try parseSnapshot(xml).nodes
    }

    static func parseSnapshot(_ xml: String) throws -> RemoteUiLayoutSnapshot {
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RemoteUiLayoutSnapshot(
                viewportBounds: RemoteUiLayoutBounds(left: 0, top: 0, right: 1, bottom: 1),
                nodes: [],
            )
        }

        let rootElement = try parseXmlRoot(xml)

        guard let rootElement else {
            return RemoteUiLayoutSnapshot(
                viewportBounds: RemoteUiLayoutBounds(left: 0, top: 0, right: 1, bottom: 1),
                nodes: [],
            )
        }

        let nodes = parseNodes(from: rootElement)
        let sortedNodes = postProcess(nodes: nodes)
        let viewportBounds = findRootNodeElement(from: rootElement)
            .flatMap { parseBounds($0.attributes["bounds"] ?? "") }
            ?? inferViewportBounds(nodes: sortedNodes)

        return RemoteUiLayoutSnapshot(viewportBounds: viewportBounds, nodes: sortedNodes)
    }

    private static func parseNodes(from element: ParsedXmlNode) -> [RemoteUiLayoutNode] {
        var nodes: [RemoteUiLayoutNode] = []
        traverse(
            element: element,
            out: &nodes,
            inheritedComponentKey: nil,
            inAgreementGroup: false,
        )
        return nodes
    }

    private static func traverse(
        element: ParsedXmlNode?,
        out: inout [RemoteUiLayoutNode],
        inheritedComponentKey: String?,
        inAgreementGroup: Bool,
    ) {
        guard let element else {
            return
        }

        let childNodeElements = element.children.filter { $0.name == "node" }
        guard element.name == "node" else {
            childNodeElements.forEach { child in
                traverse(
                    element: child,
                    out: &out,
                    inheritedComponentKey: inheritedComponentKey,
                    inAgreementGroup: false,
                )
            }
            return
        }

        let currentComponentKey = deriveComponentKey(
            element,
            inheritedComponentKey: inheritedComponentKey,
        )
        let descendantSummary = summarizeDescendants(from: element)
        if let node = parseNode(
            element: element,
            isLeaf: childNodeElements.isEmpty,
            componentKey: currentComponentKey,
            descendantSummary: descendantSummary,
            inAgreementGroup: inAgreementGroup,
        ), shouldRender(node) {
            out.append(node)
        }

        let childrenAreInAgreementGroup = hasDirectAgreementLabel(element)
        childNodeElements.forEach { child in
            traverse(
                element: child,
                out: &out,
                inheritedComponentKey: currentComponentKey,
                inAgreementGroup: childrenAreInAgreementGroup,
            )
        }
    }

    private static func parseXmlRoot(_ xml: String) throws -> ParsedXmlNode? {
        let xml = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = xml.data(using: .utf8) else {
            return nil
        }

        let builder = XmlNodeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if let error = parser.parserError {
                throw RemoteUiLayoutParsingError.invalidXml(error)
            }
            return nil
        }
        return builder.rootNode
    }

    private static func findRootNodeElement(from element: ParsedXmlNode?) -> ParsedXmlNode? {
        guard let element else {
            return nil
        }
        if element.name == "node" {
            return element
        }
        return element.children.compactMap { findRootNodeElement(from: $0) }.first
    }

    private static func parseNode(
        element: ParsedXmlNode,
        isLeaf: Bool,
        componentKey: String?,
        descendantSummary: DescendantSummary,
        inAgreementGroup: Bool,
    ) -> RemoteUiLayoutNode? {
        guard let bounds = parseBounds(element.attributes["bounds"] ?? "") else {
            return nil
        }

        let className = (element.attributes["class"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let packageName = (element.attributes["package"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceId = (element.attributes["resource-id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalizeLabel(element.attributes["text"] ?? "")
        let contentDescription = normalizeLabel(element.attributes["content-desc"] ?? "")
        let password = parseBool(element.attributes["password"])
        let clickable = parseBool(element.attributes["clickable"])
        let focusable = parseBool(element.attributes["focusable"])
        let checkable = parseBool(element.attributes["checkable"])
        let enabled = parseBool(element.attributes["enabled"], defaultValue: true)
        let selected = parseBool(element.attributes["selected"])
        let kind = classifyNode(
            className: className,
            resourceId: resourceId,
            contentDescription: contentDescription,
            bounds: bounds,
            clickable: clickable,
            focusable: focusable,
            checkable: checkable,
            inAgreementGroup: inAgreementGroup,
            descendantSummary: descendantSummary,
        )
        let parsedLabel = buildLabel(
            kind: kind,
            text: text,
            contentDescription: contentDescription,
            resourceId: resourceId,
            password: password,
            descendantSummary: descendantSummary,
        )

        return RemoteUiLayoutNode(
            bounds: bounds,
            label: parsedLabel.text,
            labelSource: parsedLabel.source,
            componentKey: componentKey,
            kind: kind,
            packageName: packageName,
            className: className,
            resourceId: resourceId,
            text: text,
            contentDescription: contentDescription,
            isLeaf: isLeaf,
            clickable: clickable,
            enabled: enabled,
            focusable: focusable,
            focused: parseBool(element.attributes["focused"]),
            checkable: checkable,
            checked: parseBool(element.attributes["checked"]),
            selected: selected,
            scrollable: parseBool(element.attributes["scrollable"]),
            password: password,
            visibleToUser: parseBool(element.attributes["visible-to-user"], defaultValue: true),
            hasInputDescendant: descendantSummary.hasInput,
            hasTextDescendant: descendantSummary.hasText,
            hasButtonDescendant: descendantSummary.hasButton,
            hasCheckIndicatorDescendant: descendantSummary.hasCheckIndicator,
        )
    }

    private static func parseBool(_ raw: String?, defaultValue: Bool = false) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return defaultValue
        }
        return trimmed.lowercased() == "true"
    }

    private static func deriveComponentKey(
        _ element: ParsedXmlNode,
        inheritedComponentKey: String?,
    ) -> String? {
        let clickable = parseBool(element.attributes["clickable"])
        let focusable = parseBool(element.attributes["focusable"])
        if !clickable && !focusable {
            return inheritedComponentKey
        }

        let packageName = (element.attributes["package"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceId = (element.attributes["resource-id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let className = (element.attributes["class"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bounds = (element.attributes["bounds"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let identity: String
        if !resourceId.isEmpty {
            identity = resourceId
        } else if !className.isEmpty {
            identity = className
        } else {
            identity = "node"
        }
        return "\(packageName)|\(identity)|\(bounds)"
    }

    private static func shouldRender(_ node: RemoteUiLayoutNode) -> Bool {
        if !node.visibleToUser || !node.bounds.hasArea() {
            return false
        }

        if shouldIgnoreSystemNode(node) {
            return false
        }

        let hasSemanticContent = !node.label.isEmpty || !node.text.isEmpty || !node.contentDescription.isEmpty
        let isInterestingLeaf = node.isLeaf && (node.kind == .text || node.kind == .button || node.kind == .toggle)
        let isUsefulImageLeaf =
            node.isLeaf &&
            node.kind == .image &&
            (16...160).contains(node.bounds.width) &&
            (16...160).contains(node.bounds.height)
        let isInteractiveLeaf =
            node.isLeaf &&
            (node.clickable || node.focusable || node.checkable || node.scrollable)
        let isSemanticContainer =
            node.kind == .container &&
            node.hasInputDescendant &&
            (node.hasTextDescendant || node.hasButtonDescendant)
        let isLabeledInteractiveContainer =
            node.kind == .container &&
            !node.label.isEmpty &&
            (node.clickable || node.focusable)
        let isCustomCheckContainer =
            node.kind == .container &&
            node.clickable &&
            looksLikeCheckableContainer(node)

        if node.kind == .input || node.kind == .toggle ||
            isSemanticContainer ||
            isLabeledInteractiveContainer ||
            isCustomCheckContainer ||
            (hasSemanticContent && node.kind != .container) ||
            isInterestingLeaf ||
            isUsefulImageLeaf ||
            isInteractiveLeaf {
            return true
        }

        return false
    }

    private static func shouldIgnoreSystemNode(_ node: RemoteUiLayoutNode) -> Bool {
        let resourceName =
            node.resourceId
                .split(separator: "/")
                .last?
                .split(separator: ":")
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""

        if IGNORED_RESOURCE_NAMES.contains(resourceName) {
            return true
        }

        if shouldIgnoreDecorativeIndicatorNode(node, resourceName: resourceName) {
            return true
        }

        let shortClassName = node.className.split(separator: ".").last?.lowercased() ?? node.className.lowercased()
        return IGNORED_CLASS_NAMES.contains(shortClassName)
    }

    private static func shouldIgnoreDecorativeIndicatorNode(
        _ node: RemoteUiLayoutNode,
        resourceName: String,
    ) -> Bool {
        if node.kind != .image {
            return false
        }
        if !node.text.isEmpty || !node.contentDescription.isEmpty {
            return false
        }
        if !node.isLeaf {
            return false
        }

        let looksLikeCheckIndicator =
            resourceName.contains("confirm") ||
            resourceName.contains("check") ||
            resourceName.contains("tick")
        let isSmallIndicator = node.bounds.width <= 80 && node.bounds.height <= 80
        return looksLikeCheckIndicator && isSmallIndicator
    }

    private static func looksLikeCheckableContainer(_ node: RemoteUiLayoutNode) -> Bool {
        let lowered = node.resourceId.lowercased()
        return lowered.contains("check") ||
            lowered.contains("checkbox") ||
            lowered.contains("confirm") ||
            lowered.contains("agree") ||
            lowered.contains("accept") ||
            lowered.contains("consent") ||
            lowered.contains("policy") ||
            node.hasCheckIndicatorDescendant
    }

    private static func classifyNode(
        className: String,
        resourceId: String,
        contentDescription: String,
        bounds: RemoteUiLayoutBounds,
        clickable: Bool,
        focusable: Bool,
        checkable: Bool,
        inAgreementGroup: Bool,
        descendantSummary: DescendantSummary,
    ) -> RemoteUiLayoutNodeKind {
        let shortName = className.split(separator: ".").last ?? ""

        if shortName.contains("EditText") ||
            shortName.contains("TextInput") ||
            shortName.contains("AutoComplete") {
            return .input
        }

        if checkable ||
            shortName.contains("CompoundButton") ||
            shortName.contains("CheckBox") ||
            shortName.contains("Switch") ||
            shortName.contains("Toggle") ||
            shortName.contains("RadioButton") {
            return .toggle
        }

        if looksLikeSemanticToggle(
            className: className,
            resourceId: resourceId,
            contentDescription: contentDescription,
            bounds: bounds,
            clickable: clickable,
            focusable: focusable,
            inAgreementGroup: inAgreementGroup,
        ) {
            return .toggle
        }

        if shortName.contains("Button") ||
            shortName.contains("Chip") {
            return .button
        }

        if shortName.contains("Image") {
            return .image
        }

        if shortName.contains("TextView") ||
            shortName.contains("Text") {
            return .text
        }

        if looksLikeCustomToggleView(
            className: className,
            resourceId: resourceId,
            bounds: bounds,
            clickable: clickable,
            focusable: focusable,
        ) {
            return .toggle
        }

        if looksLikeCustomButton(
            resourceId: resourceId,
            bounds: bounds,
            clickable: clickable,
            descendantSummary: descendantSummary,
        ) {
            return .button
        }

        if shortName.contains("Layout") ||
            shortName.contains("ViewGroup") ||
            shortName.contains("RecyclerView") ||
            shortName.contains("ListView") ||
            shortName.contains("ScrollView") ||
            shortName.contains("WebView") {
            return .container
        }

        return .other
    }

    private static func looksLikeSemanticToggle(
        className: String,
        resourceId: String,
        contentDescription: String,
        bounds: RemoteUiLayoutBounds,
        clickable: Bool,
        focusable: Bool,
        inAgreementGroup: Bool,
    ) -> Bool {
        let width = bounds.width
        let height = bounds.height
        guard (16...200).contains(width), (16...200).contains(height) else {
            return false
        }

        let larger = CGFloat(max(width, height))
        let smaller = CGFloat(max(1, min(width, height)))
        if larger / smaller > 3.2 {
            return false
        }

        let loweredResource = resourceId.lowercased()
        let loweredDescription = contentDescription.lowercased()
        let hasToggleResource =
            loweredResource.contains(":id/scb_") ||
            loweredResource.contains("/scb_") ||
            loweredResource.contains("checkbox") ||
            loweredResource.contains("check_box") ||
            loweredResource.contains("protocol_checkbox") ||
            loweredResource.contains("confirm_container") ||
            loweredResource.contains("agree") ||
            loweredResource.contains("consent") ||
            loweredResource.contains("toggle") ||
            loweredResource.contains("radio")
        let hasToggleDescription =
            loweredDescription.contains("勾选") ||
            loweredDescription.contains("复选") ||
            loweredDescription.contains("已选中") ||
            loweredDescription.contains("未选中") ||
            loweredDescription.contains("同意协议") ||
            loweredDescription.contains("checkbox") ||
            loweredDescription.contains("checked") ||
            loweredDescription.contains("unchecked") ||
            loweredDescription.contains("selected") ||
            loweredDescription.contains("unselected")

        if hasToggleResource || hasToggleDescription {
            return clickable || focusable || !contentDescription.isEmpty
        }

        let shortName = className.split(separator: ".").last ?? ""
        let canBeAgreementIndicator =
            shortName.contains("Image") ||
            shortName.contains("Button") ||
            shortName.caseInsensitiveCompare("View") == .orderedSame
        return inAgreementGroup &&
            canBeAgreementIndicator &&
            (clickable || focusable) &&
            width <= 96 &&
            height <= 96
    }

    private static func looksLikeCustomButton(
        resourceId: String,
        bounds: RemoteUiLayoutBounds,
        clickable: Bool,
        descendantSummary: DescendantSummary,
    ) -> Bool {
        if !clickable || descendantSummary.primaryLabel == nil {
            return false
        }
        if bounds.width < 180 || !(60...240).contains(bounds.height) {
            return false
        }

        let loweredResource = resourceId.lowercased()
        return loweredResource.contains("button") ||
            loweredResource.contains("_btn") ||
            loweredResource.contains("btn_") ||
            loweredResource.contains("login") ||
            loweredResource.contains("submit") ||
            loweredResource.contains("continue") ||
            loweredResource.contains("next") ||
            loweredResource.contains("verify") ||
            loweredResource.contains("confirm")
    }

    private static func looksLikeCustomToggleView(
        className: String,
        resourceId: String,
        bounds: RemoteUiLayoutBounds,
        clickable: Bool,
        focusable: Bool,
    ) -> Bool {
        if !clickable && !focusable {
            return false
        }

        let shortName = className.split(separator: ".").last ?? ""
        guard shortName.caseInsensitiveCompare("View") == .orderedSame else {
            return false
        }

        let loweredResourceId = resourceId.lowercased()
        let matchesToggleResource =
            loweredResourceId.contains(":id/scb_") ||
            loweredResourceId.contains("/scb_") ||
            loweredResourceId.contains("check") ||
            loweredResourceId.contains("toggle") ||
            loweredResourceId.contains("switch") ||
            loweredResourceId.contains("radio")
        if !matchesToggleResource {
            return false
        }

        let width = bounds.width
        let height = bounds.height
        if !(16...96).contains(width) || !(16...96).contains(height) {
            return false
        }

        let larger = CGFloat(max(width, height))
        let smaller = CGFloat(max(1, min(width, height)))
        return larger / smaller <= 1.8
    }

    private static func buildLabel(
        kind: RemoteUiLayoutNodeKind,
        text: String,
        contentDescription: String,
        resourceId: String,
        password: Bool,
        descendantSummary: DescendantSummary,
    ) -> ParsedLabel {
        let sanitizedText = sanitizePrimaryLabel(text, kind: kind)
        if !sanitizedText.isEmpty {
            return ParsedLabel(text: String(sanitizedText.prefix(48)), source: .text)
        }

        let sanitizedContentDescription = sanitizePrimaryLabel(contentDescription, kind: kind)
        if !sanitizedContentDescription.isEmpty {
            return ParsedLabel(text: String(sanitizedContentDescription.prefix(48)), source: .contentDescription)
        }

        if kind == .input || kind == .button, let descendantLabel = descendantSummary.primaryLabel {
            return ParsedLabel(text: String(descendantLabel.text.prefix(48)), source: descendantLabel.source)
        }

        let resourceName = resourceId
            .split(separator: "/")
            .last?
            .split(separator: ":")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !resourceName.isEmpty && !isObfuscatedResourceName(resourceName) && shouldUseResourceFallback(kind) {
            if isArrowLikeResourceName(resourceName) && (kind == .image || kind == .other || kind == .button) {
                return ParsedLabel(text: "", source: .fallback)
            }
            let humanized = humanizeResourceName(String(resourceName))
            if isMeaningfulFallbackLabel(humanized) {
                return ParsedLabel(text: String(humanized.prefix(48)), source: .resourceId)
            }
        }

        if password {
            return ParsedLabel(text: "Password", source: .fallback)
        }

        return ParsedLabel(text: "", source: .fallback)
    }

    private static func sanitizePrimaryLabel(_ rawLabel: String, kind: RemoteUiLayoutNodeKind) -> String {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return ""
        }

        if isPrivateUseGlyphLabel(label) {
            return ""
        }

        if kind == .button && isKeyboardLikeButtonLabel(label) {
            return label
        }

        let lowered = label.lowercased()
        if GENERIC_LABELS.contains(lowered) || (SYMBOL_ONLY_LABELS.contains(label) && kind != .text && kind != .input && kind != .button) {
            return ""
        }

        if (kind == .toggle || kind == .image || kind == .other) && (label.count <= 1 || isSuspiciousShortCodeLabel(label)) {
            return ""
        }

        return label
    }

    private static func shouldUseResourceFallback(_ kind: RemoteUiLayoutNodeKind) -> Bool {
        kind == .input || kind == .text || kind == .button || kind == .image
    }

    private static func isMeaningfulFallbackLabel(_ label: String) -> Bool {
        let lowered = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !lowered.isEmpty &&
            !GENERIC_LABELS.contains(lowered) &&
            !isSuspiciousShortCodeLabel(label)
    }

    private static func isObfuscatedResourceName(_ resourceName: String) -> Bool {
        let lowered = resourceName.lowercased()
        return lowered == "obfuscated" ||
            lowered.contains("resource_name_obfuscated") ||
            lowered.contains("resource-name-obfuscated")
    }

    private static func isPrivateUseGlyphLabel(_ label: String) -> Bool {
        let visibleCharacters = label.filter { !$0.isWhitespace }
        guard !visibleCharacters.isEmpty else {
            return false
        }

        return visibleCharacters.allSatisfy { character in
            character.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 0xE000 && scalar.value <= 0xF8FF
            }
        }
    }

    private static func humanizeResourceName(_ resourceName: String) -> String {
        let normalized =
            replaceRegex(
                CAMEL_CASE_REGEX,
                in: resourceName,
                withTemplate: "$1 $2",
            )
        let normalizedWithSeparators = replaceRegex(
            RESOURCE_SEPARATOR_REGEX,
            in: normalized,
            withTemplate: " ",
        )

        let tokens = normalizedWithSeparators
            .replacingOccurrences(of: "  ", with: " ")
            .split { $0 == " " }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let meaningfulTokens = tokens.filter { !COMMON_RESOURCE_GENERIC_TOKENS.contains($0.lowercased()) }
        if !tokens.isEmpty && meaningfulTokens.isEmpty {
            return ""
        }

        let effectiveTokens = meaningfulTokens.isEmpty ? tokens : meaningfulTokens
        let mapped = effectiveTokens.map { token -> String in
            switch token.lowercased() {
            case "qq":
                return "QQ"
            case "wx":
                return "WX"
            case "wechat":
                return "WeChat"
            case "alipay":
                return "Alipay"
            case "tb":
                return "TB"
            case "onekey":
                return "OneKey"
            case "ctid":
                return "CTID"
            default:
                return token.replacingFirstCharacterLowercaseWithUppercase()
            }
        }
        return mapped.joined(separator: " ")
    }

    private static func isArrowLikeResourceName(_ resourceName: String) -> Bool {
        let lowered = resourceName.lowercased()
        return lowered.contains("arrow") ||
            lowered.contains("dropdown") ||
            lowered.contains("expand") ||
            lowered.contains("chevron") ||
            lowered.contains("caret") ||
            lowered.contains("spinner") ||
            lowered.contains("region_image") ||
            lowered.contains("regionimage")
    }

    private static func parseBounds(_ rawBounds: String) -> RemoteUiLayoutBounds? {
        let trimmedBounds = rawBounds.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmedBounds.startIndex..., in: trimmedBounds)
        guard let match = BOUNDS_REGEX.firstMatch(
            in: trimmedBounds,
            options: [],
            range: range,
        ), match.numberOfRanges == 5 else {
            return nil
        }

        var values: [Int] = []
        for index in 1...4 {
            let valueRange = match.range(at: index)
            guard let range = Range(valueRange, in: trimmedBounds) else {
                return nil
            }
            values.append(Int(trimmedBounds[range]) ?? 0)
        }

        return RemoteUiLayoutBounds(
            left: values[0],
            top: values[1],
            right: values[2],
            bottom: values[3],
        )
    }

    private static func postProcess(nodes: [RemoteUiLayoutNode]) -> [RemoteUiLayoutNode] {
        let sorted = nodes.sorted {
            let priorityLeft = nodePriority($0)
            let priorityRight = nodePriority($1)
            if priorityLeft != priorityRight {
                return priorityLeft > priorityRight
            }
            if $0.bounds.area() != $1.bounds.area() {
                return $0.bounds.area() > $1.bounds.area()
            }
            return false
        }

        var kept: [RemoteUiLayoutNode] = []
        for candidate in sorted {
            if !kept.contains(where: { isRedundant(candidate: candidate, existing: $0) }) {
                kept.append(candidate)
            }
        }
        return kept.sorted { $0.bounds.area() > $1.bounds.area() }
    }

    private static func isRedundant(candidate: RemoteUiLayoutNode, existing: RemoteUiLayoutNode) -> Bool {
        let overlapRatio = overlapOverSmallerArea(a: candidate.bounds, b: existing.bounds)
        if overlapRatio < 0.88 {
            return false
        }

        let candidateNormalized = normalizeForComparison(candidate.label)
        let existingNormalized = normalizeForComparison(existing.label)
        if !candidateNormalized.isEmpty && candidateNormalized == existingNormalized {
            return true
        }

        if existing.kind == .container &&
            candidate.kind == .container &&
            existing.label.isEmpty &&
            candidate.label.isEmpty &&
            candidate.bounds.area() <= existing.bounds.area() {
            return true
        }

        if existing.labelSource == .text && candidate.labelSource != .text && candidate.kind != .toggle {
            return true
        }

        if (existing.kind == .text || existing.kind == .input) &&
            (candidate.kind == .button || candidate.kind == .image || candidate.kind == .other) {
            return true
        }

        return false
    }

    private static func overlapOverSmallerArea(a: RemoteUiLayoutBounds, b: RemoteUiLayoutBounds) -> Float {
        let intersectionLeft = max(a.left, b.left)
        let intersectionTop = max(a.top, b.top)
        let intersectionRight = min(a.right, b.right)
        let intersectionBottom = min(a.bottom, b.bottom)
        if intersectionRight <= intersectionLeft || intersectionBottom <= intersectionTop {
            return 0.0
        }

        let intersectionArea = Int64(intersectionRight - intersectionLeft) * Int64(intersectionBottom - intersectionTop)
        let smallerArea = min(a.area(), b.area()).coerceAtLeast(1)
        return Float(intersectionArea) / Float(smallerArea)
    }

    private static func normalizeForComparison(_ label: String) -> String {
        replaceRegex(
            WHITESPACE_REGEX,
            in: label.lowercased(),
            withTemplate: "",
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nodePriority(_ node: RemoteUiLayoutNode) -> Int {
        let sourceScore: Int
        switch node.labelSource {
        case .text:
            sourceScore = 40
        case .contentDescription:
            sourceScore = 30
        case .resourceId:
            sourceScore = 20
        case .fallback:
            sourceScore = 10
        }

        let kindScore: Int
        switch node.kind {
        case .input:
            kindScore = 12
        case .toggle:
            kindScore = 11
        case .button:
            kindScore = 10
        case .text:
            kindScore = 7
        case .image:
            kindScore = 3
        case .other:
            kindScore = 2
        case .container:
            kindScore = 1
        }

        return sourceScore + kindScore
    }

    private static func inferViewportBounds(nodes: [RemoteUiLayoutNode]) -> RemoteUiLayoutBounds {
        guard let first = nodes.min(by: { $0.bounds.left < $1.bounds.left }) else {
            return RemoteUiLayoutBounds(left: 0, top: 0, right: 1, bottom: 1)
        }

        let top = nodes.min(by: { $0.bounds.top < $1.bounds.top })?.bounds.top ?? first.bounds.top
        let right = nodes.max(by: { $0.bounds.right < $1.bounds.right })?.bounds.right ?? first.bounds.right
        let bottom = nodes.max(by: { $0.bounds.bottom < $1.bounds.bottom })?.bounds.bottom ?? first.bounds.bottom
        return RemoteUiLayoutBounds(left: first.bounds.left, top: top, right: right, bottom: bottom)
    }

    private static func normalizeLabel(_ rawValue: String) -> String {
        replaceRegex(
            WHITESPACE_REGEX,
            in: rawValue,
            withTemplate: " ",
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDescendantChildren(_ element: ParsedXmlNode) -> [ParsedXmlNode] {
        element.children.filter { $0.name == "node" }
    }

    private static func summarizeDescendants(from element: ParsedXmlNode) -> DescendantSummary {
        var hasInput = false
        var hasText = false
        var hasButton = false
        var hasCheckIndicator = false
        var firstTextLabel: ParsedLabel?
        var firstContentDescriptionLabel: ParsedLabel?

        parseDescendantChildren(element).forEach { child in
            let childClassName = (child.attributes["class"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let childKind = classifyDescendantKind(className: childClassName)
            switch childKind {
            case .input:
                hasInput = true
            case .text:
                hasText = true
            case .button:
                hasButton = true
            default:
                break
            }

            let childText = normalizeLabel(child.attributes["text"] ?? "")
            let childContentDescription = normalizeLabel(child.attributes["content-desc"] ?? "")
            let sanitizedChildText = sanitizePrimaryLabel(childText, kind: childKind)
            let sanitizedChildContentDescription = sanitizePrimaryLabel(childContentDescription, kind: childKind)

            if firstTextLabel == nil && !sanitizedChildText.isEmpty {
                firstTextLabel = ParsedLabel(text: sanitizedChildText, source: .text)
            }
            if firstContentDescriptionLabel == nil && !sanitizedChildContentDescription.isEmpty {
                firstContentDescriptionLabel = ParsedLabel(
                    text: sanitizedChildContentDescription,
                    source: .contentDescription,
                )
            }

            let childResourceId = (child.attributes["resource-id"] ?? "").lowercased()
            let loweredChildDescription = childContentDescription.lowercased()
            let shortName = childClassName.split(separator: ".").last ?? ""
            if childResourceId.contains("check") ||
                childResourceId.contains("checkbox") ||
                childResourceId.contains("confirm") ||
                childResourceId.contains("tick") ||
                shortName.contains("CheckBox") ||
                shortName.contains("Toggle") ||
                loweredChildDescription.contains("勾选") ||
                loweredChildDescription.contains("已选中") ||
                loweredChildDescription.contains("未选中") {
                hasCheckIndicator = true
            }

            let childSummary = summarizeDescendants(from: child)
            hasInput = hasInput || childSummary.hasInput
            hasText = hasText || childSummary.hasText
            hasButton = hasButton || childSummary.hasButton
            hasCheckIndicator = hasCheckIndicator || childSummary.hasCheckIndicator

            if firstTextLabel == nil {
                firstTextLabel = childSummary.firstTextLabel
            }
            if firstContentDescriptionLabel == nil {
                firstContentDescriptionLabel = childSummary.firstContentDescriptionLabel
            }
        }

        return DescendantSummary(
            hasInput: hasInput,
            hasText: hasText,
            hasButton: hasButton,
            hasCheckIndicator: hasCheckIndicator,
            firstTextLabel: firstTextLabel,
            firstContentDescriptionLabel: firstContentDescriptionLabel,
        )
    }

    private static func classifyDescendantKind(className: String) -> RemoteUiLayoutNodeKind {
        let shortName = className.split(separator: ".").last ?? ""
        if shortName.contains("EditText") ||
            shortName.contains("TextInput") ||
            shortName.contains("AutoComplete") {
            return .input
        }

        if shortName.contains("CompoundButton") ||
            shortName.contains("CheckBox") ||
            shortName.contains("Switch") ||
            shortName.contains("Toggle") ||
            shortName.contains("RadioButton") {
            return .toggle
        }

        if shortName.contains("Button") || shortName.contains("Chip") {
            return .button
        }

        if shortName.contains("Image") {
            return .image
        }
        if shortName.contains("Text") {
            return .text
        }

        return .other
    }

    private static func hasDirectAgreementLabel(_ element: ParsedXmlNode) -> Bool {
        parseDescendantChildren(element).contains { child in
            isAgreementLabel(child.attributes["text"] ?? "") ||
                isAgreementLabel(child.attributes["content-desc"] ?? "")
        }
    }

    private static func isAgreementLabel(_ value: String) -> Bool {
        let normalized = normalizeLabel(value).lowercased()
        return normalized.contains("阅读并同意") ||
            normalized.contains("已阅读并同意") ||
            normalized.contains("服务协议") ||
            normalized.contains("用户协议") ||
            normalized.contains("隐私政策") ||
            normalized.contains("个人信息保护") ||
            normalized.contains("privacy policy") ||
            normalized.contains("terms of service")
    }

    private static func isSuspiciousShortCodeLabel(_ label: String) -> Bool {
        if label.unicodeScalars.contains(where: { scalar in 0x4E00...0x9FFF ~= scalar.value }) {
            return false
        }

        let tokens = label
            .lowercased()
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return false
        }

        if tokens.count >= 2 {
            return tokens.allSatisfy { token in
                token.count <= 4 && token.contains(where: { $0.isLetter })
            }
        }

        return tokens.first!.count <= 3 && tokens.first!.contains(where: { $0.isLetter })
    }

    private static func isKeyboardLikeButtonLabel(_ label: String) -> Bool {
        let set: Set<String> = ["删除", "退格", "完成", "确定", "下一步", "ABC", "123"]
        if (label.count == 1 && (label.first?.isNumber == true || [".", ",", "*", "#"].contains(label))) || set.contains(label) {
            return true
        }
        return false
    }

    private static func replaceRegex(_ expression: NSRegularExpression, in text: String, withTemplate template: String) -> String {
        expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template,
        )
    }

    private static let BOUNDS_REGEX = try! NSRegularExpression(pattern: #"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"#)
    private static let WHITESPACE_REGEX = try! NSRegularExpression(pattern: #"\s+"#)
    private static let CAMEL_CASE_REGEX = try! NSRegularExpression(pattern: "([a-z])([A-Z])")
    private static let RESOURCE_SEPARATOR_REGEX = try! NSRegularExpression(pattern: #"[_\-.]+"#)
    private static let COMMON_RESOURCE_GENERIC_TOKENS: Set<String> = [
        "btn", "iv", "img", "icon", "layout", "view", "container", "item", "tv", "et", "ll", "rl", "fl",
        "ali", "user", "guide", "image", "navigation", "bar", "label", "labels", "group", "small",
    ]
    private static let GENERIC_LABELS: Set<String> = [
        "divider", "separator", "icon", "image", "background", "lottie", "animation", "button",
        "toggle", "checkbox", "radio", "switch", "view", "layout", "container", "prefix", "suffix",
        "start", "end", "left", "right",
    ]
    private static let SYMBOL_ONLY_LABELS: Set<String> = ["✓", "✔", "☑", "√", "v", "V"]
    private static let IGNORED_RESOURCE_NAMES: Set<String> =
        ["navigationbarbackground", "statusbarbackground", "navigationbarframe", "navbarbackground"]
    private static let IGNORED_CLASS_NAMES: Set<String> =
        ["navigationbarbackground", "statusbarbackground"]

}

private final class ParsedXmlNode {
    let name: String
    let attributes: [String: String]
    var children: [ParsedXmlNode] = []

    init(name: String, attributes: [String: String], children: [ParsedXmlNode] = []) {
        self.name = name
        self.attributes = attributes
        self.children = children
    }
}

private final class XmlNodeBuilder: NSObject, XMLParserDelegate {
    private(set) var rootNode: ParsedXmlNode?
    private var nodeStack: [ParsedXmlNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:],
    ) {
        let node = ParsedXmlNode(name: elementName, attributes: attributeDict, children: [])
        nodeStack.last?.children.append(node)
        if rootNode == nil {
            rootNode = node
        }
        nodeStack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = nodeStack.popLast()
    }
}

private struct ParsedLabel {
    let text: String
    let source: RemoteUiLayoutLabelSource
}

private struct DescendantSummary {
    let hasInput: Bool
    let hasText: Bool
    let hasButton: Bool
    let hasCheckIndicator: Bool
    let firstTextLabel: ParsedLabel?
    let firstContentDescriptionLabel: ParsedLabel?

    var primaryLabel: ParsedLabel? {
        firstTextLabel ?? firstContentDescriptionLabel
    }
}

private extension String {
    func replacingFirstCharacterLowercaseWithUppercase() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

private extension Int64 {
    func coerceAtLeast(_ minimum: Int64) -> Int64 {
        Swift.max(self, minimum)
    }
}

private enum RemoteUiLayoutParsingError: Error {
    case invalidXml(Error)
}
