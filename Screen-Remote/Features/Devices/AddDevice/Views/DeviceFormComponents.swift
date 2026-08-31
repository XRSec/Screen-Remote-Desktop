import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

struct DeviceFormSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String.localizedKey(title)).font(AppTypography.subheadline.weight(.semibold))
                if let subtitle = subtitle {
                    Text(String.localizedKey(subtitle)).font(AppTypography.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.leading, 3)
            VStack(spacing: 0) { content }
                .appCard(radius: AppRadius.small)
        }
    }
}

struct FormDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

struct FormTextRow: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            FormLabel(title: title, help: help)
            Spacer()
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 430)
        }
        .padding(14)
    }
}

struct FormSecureTextRow: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var placeholder: String
    var help: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            FormLabel(title: title, help: help)
            Spacer()
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 360)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("commonClear")
                .accessibilityLabel(Text("commonClear"))
            }
        }
        .padding(14)
    }
}

struct FormField: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormLabel(title: title, help: help)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

struct FormPickerRow<Content: View, Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder let content: Content
    let help: String?

    init(
        title: LocalizedStringKey, selection: Binding<Selection>, help: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.help = help
        self.content = content()
    }

    var body: some View {
        HStack {
            FormLabel(title: title, help: help)
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .frame(width: 150)
        }
        .padding(14)
    }
}

struct PresetValue: Hashable {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

struct PresetCustomRow: View {
    private static let customToken = "__custom__"

    let title: LocalizedStringKey
    @Binding var value: String
    let presets: [PresetValue]
    let customEnabled: Bool
    let units: [String]
    let fallback: String
    let help: String

    @State private var editingCustom: Bool
    @State private var customDigits: String
    @State private var customUnit: String

    init(
        title: LocalizedStringKey,
        value: Binding<String>,
        presets: [PresetValue],
        customEnabled: Bool,
        units: [String] = [],
        defaultUnit: String = "",
        fallback: String,
        help: String
    ) {
        self.title = title
        self._value = value
        self.presets = presets
        self.customEnabled = customEnabled
        self.units = units
        self.fallback = fallback
        self.help = help

        let current = value.wrappedValue
        let matchesPreset = presets.contains { $0.value.caseInsensitiveCompare(current) == .orderedSame }
        let selectedUnit = units.first { current.lowercased().hasSuffix($0.lowercased()) } ?? defaultUnit
        _editingCustom = State(initialValue: customEnabled && !current.isEmpty && !matchesPreset)
        _customDigits = State(initialValue: current.filter { $0.isNumber })
        _customUnit = State(initialValue: selectedUnit)
    }

    var body: some View {
        HStack(spacing: 12) {
            FormLabel(title: title, help: help)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 12)
            if editingCustom && customEnabled {
                HStack(spacing: 5) {
                    TextField("sessionCustomValue", text: $customDigits)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: units.isEmpty ? 105 : 78)
                        .onChange(of: customDigits) { next in
                            customDigits = next.filter { $0.isNumber }
                            updateCustomValue()
                        }
                    if !units.isEmpty {
                        Picker("", selection: $customUnit) {
                            ForEach(units, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 54)
                        .onChange(of: customUnit) { _ in updateCustomValue() }
                    }
                    Button {
                        editingCustom = false
                        customDigits = ""
                        value = fallback
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .help("sessionBackToPresets")
                    .accessibilityLabel(Text("sessionBackToPresets"))
                }
            } else {
                Picker(title, selection: pickerSelection) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset.label).tag(preset.value)
                    }
                    if customEnabled {
                        Text("sessionCustom").tag(Self.customToken)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(14)
        .onAppear {
            if !editingCustom && value.isEmpty && !presets.contains(where: { $0.value.isEmpty }) {
                value = fallback
            }
        }
        .onDisappear {
            if value.isEmpty { value = fallback }
        }
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                presets.contains(where: { $0.value.caseInsensitiveCompare(value) == .orderedSame })
                    ? value
                    : (presets.first?.value ?? fallback)
            },
            set: { next in
                if next == Self.customToken {
                    editingCustom = true
                    customDigits = ""
                    value = ""
                } else {
                    editingCustom = false
                    value = next
                }
            }
        )
    }

    private func updateCustomValue() {
        value = customDigits.isEmpty ? "" : customDigits + customUnit
    }
}

struct FormToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var help: String? = nil
    var enabled = true

    var body: some View {
        HStack {
            FormLabel(title: title, help: help)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().disabled(!enabled)
        }
            .toggleStyle(.switch)
            .padding(14)
    }
}

struct FormLabel: View {
    let title: LocalizedStringKey
    let help: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(AppTypography.body.weight(.medium))
            if let help {
                HelpPopoverButton(textKey: help)
            }
        }
    }
}

struct HelpPopoverButton: View {
    let textKey: String
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(AppTypography.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("sessionHelpButton")
        .accessibilityLabel(Text("sessionHelpButton"))
        .popover(isPresented: $presented, arrowEdge: .trailing) {
            Text(String.localizedKey(textKey))
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(AppSpacing.md)
        }
    }
}

struct FormNavigationRow: View {
    let title: LocalizedStringKey
    let value: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FormLabel(title: title, help: help)
                Spacer()
                Text(value).foregroundColor(.secondary).lineLimit(1)
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FormSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let help: String

    var body: some View {
        HStack(spacing: 10) {
            FormLabel(title: title, help: help)
            Slider(value: $value, in: 1...3, step: 0.1)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42)
        }
        .padding(14)
    }
}

struct DisplaySizeRow: View {
    @Binding var width: String
    @Binding var height: String
    @Binding var dpi: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormLabel(title: "sessionDisplaySize", help: "sessionHelpDisplaySize")
            HStack(spacing: 5) {
                metricField("sessionWidth", text: $width)
                Text("×").foregroundColor(.secondary)
                metricField("sessionHeight", text: $height)
                Text("@").foregroundColor(.secondary)
                metricField("DPI", text: $dpi)
                Button {
                    width = ""
                    height = ""
                    dpi = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("commonClear")
                .accessibilityLabel(Text("commonClear"))
                Button(action: synchronizeLocalDisplay) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("sessionSyncLocalDisplaySize")
                .accessibilityLabel(Text("sessionSyncLocalDisplaySize"))
            }
        }
        .padding(14)
    }

    private func synchronizeLocalDisplay() {
        guard let screen = NSScreen.main else { return }
        let scale = max(screen.backingScaleFactor, 1)
        width = String(Int((screen.frame.width * scale).rounded()))
        height = String(Int((screen.frame.height * scale).rounded()))
        dpi = String(Int((160 * scale).rounded()))
    }

    private func metricField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) { text.wrappedValue = $0.filter { $0.isNumber } }
    }
}

struct SessionGroupSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @Binding var selection: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("sessionSelectGroup").font(.headline)
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            List {
                Button {
                    selection.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "house.fill").foregroundColor(AppTheme.accent).frame(width: 22)
                        Text("sidebarAllDevices")
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark").foregroundColor(AppTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
                .accessibilityAddTraits(selection.isEmpty ? .isSelected : [])

                OutlineGroup(appState.groupTree(), children: \.children) { node in
                    groupRow(group: node.group)
                }
            }
        }
    }

    private func groupRow(group: DeviceGroup) -> some View {
        Button {
            if selection.contains(group.id) {
                selection.remove(group.id)
            } else {
                selection.insert(group.id)
            }
        } label: {
            HStack {
                Image(systemName: group.symbol).foregroundColor(AppTheme.accent).frame(width: 22)
                Text(group.name)
                Spacer()
                if selection.contains(group.id) {
                    Image(systemName: "checkmark").foregroundColor(AppTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .accessibilityAddTraits(selection.contains(group.id) ? .isSelected : [])
    }
}
