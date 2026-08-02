import AppKit
import Foundation
import SwiftUI

struct VirtualDeviceEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: VirtualDeviceViewModel
    let configuration: VirtualDeviceConfiguration
    let device: AndroidVirtualDevice?

    @State private var name: String
    @State private var profile = ""
    @State private var options: VirtualDeviceOptions
    @State private var selectedSkinPath: String

    init(
        viewModel: VirtualDeviceViewModel,
        configuration: VirtualDeviceConfiguration,
        device: AndroidVirtualDevice?,
        initialOptions: VirtualDeviceOptions
    ) {
        self.viewModel = viewModel
        self.configuration = configuration
        self.device = device
        _name = State(initialValue: device?.name ?? "")
        _options = State(initialValue: initialOptions)
        _selectedSkinPath = State(initialValue: initialOptions.skinPath)
    }

    private var isEditing: Bool { device != nil }
    private var availableSkins: [AndroidSkin] {
        viewModel.skins.filter { $0.formFactor == options.formFactor }
    }
    private var installedImages: [AndroidSystemImage] {
        viewModel.images.filter { image in
            guard image.isInstalled else { return false }
            switch options.formFactor {
            case .tablet: return image.formFactor == .tablet || image.formFactor == .phone
            default: return image.formFactor == options.formFactor
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "virtualDeviceEditTitle" : "virtualDeviceCreateTitle")
                        .font(.title2.bold())
                    Text("virtualDeviceEditorSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Label("virtualDeviceCLIBacked", systemImage: "terminal")
                    .font(.caption).foregroundColor(AppTheme.accent)
            }
            .padding(22)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editorSection(number: 1, title: "virtualDeviceTypeSection") {
                        HStack(spacing: 10) {
                            ForEach([VirtualDeviceFormFactor.phone, .tablet, .tv]) { factor in
                                Button {
                                    applyFormFactor(factor)
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: factor.icon).font(.system(size: 24))
                                        Text(factor.localizationKey).font(.caption.weight(.medium))
                                    }
                                    .foregroundColor(options.formFactor == factor ? AppTheme.accent : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(options.formFactor == factor ? AppTheme.accent.opacity(0.11) : Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(options.formFactor == factor ? AppTheme.accent : AppTheme.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    editorSection(number: 2, title: "virtualDeviceSkinSection") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: String.localizedKey("virtualDeviceSkinCount"), availableSkins.count))
                                .font(.caption).foregroundColor(.secondary)
                            HStack {
                                Button("virtualDeviceOpenSkinsFolder") { revealSkinsFolder() }
                                Button("virtualDeviceAddCustomSkin") { chooseCustomSkin() }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                            ForEach(availableSkins) { skin in
                                SkinCard(skin: skin, isSelected: selectedSkinPath == skin.path) {
                                    selectSkin(skin)
                                }
                            }
                        }
                    }

                    editorSection(number: 3, title: "virtualDeviceSystemSection") {
                        if isEditing {
                            HStack {
                                Image(systemName: "shippingbox.fill").foregroundColor(AppTheme.accent)
                                Text(options.systemImageID.isEmpty ? device?.target ?? "" : options.systemImageID)
                                    .font(.system(size: 11, design: .monospaced)).lineLimit(2)
                            }
                            Text("virtualDeviceSystemImmutable")
                                .font(.caption2).foregroundColor(.secondary)
                        } else if installedImages.isEmpty {
                            Label("virtualDeviceNoCompatibleInstalledImages", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else {
                            Picker("virtualDeviceSystemImage", selection: $options.systemImageID) {
                                Text("virtualDevicePleaseSelect").tag("")
                                ForEach(installedImages) { image in
                                    Text(image.displayName).tag(image.id)
                                }
                            }
                        }
                    }

                    editorSection(number: 4, title: "virtualDeviceParametersSection") {
                        VStack(spacing: 11) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 120), spacing: 14)],
                                spacing: 11
                            ) {
                                LabeledIntegerField(title: "virtualDeviceRAM", value: $options.ramMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceCPUCores", value: $options.cpuCores, suffix: "")
                                LabeledIntegerField(title: "virtualDeviceStorage", value: $options.storageMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceHeap", value: $options.heapMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceWidth", value: $options.width, suffix: "px")
                                LabeledIntegerField(title: "virtualDeviceHeight", value: $options.height, suffix: "px")
                                LabeledIntegerField(title: "virtualDeviceDensity", value: $options.density, suffix: "dpi")
                                LabeledIntegerField(title: "virtualDeviceSDCard", value: $options.sdCardMB, suffix: "MB")
                            }
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 155), spacing: 18)],
                                alignment: .leading,
                                spacing: 11
                            ) {
                                Picker("virtualDeviceGPU", selection: $options.gpuMode) {
                                    Text("virtualDeviceGPUAuto").tag("auto")
                                    Text("virtualDeviceGPUHost").tag("host")
                                    Text("virtualDeviceGPUSoftware").tag("swiftshader_indirect")
                                    Text("virtualDeviceGPUOff").tag("off")
                                }
                                Picker("virtualDeviceBootMode", selection: $options.bootMode) {
                                    ForEach(VirtualDeviceBootMode.allCases) { mode in
                                        Text(mode.localizationKey).tag(mode)
                                    }
                                }
                                Picker("virtualDeviceCamera", selection: $options.cameraBack) {
                                    Text("virtualDeviceCameraEmulated").tag("emulated")
                                    Text("virtualDeviceCameraWebcam").tag("webcam0")
                                    Text("virtualDeviceCameraNone").tag("none")
                                }
                            }
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 145), spacing: 20)],
                                alignment: .leading,
                                spacing: 9
                            ) {
                                Toggle("virtualDeviceKeyboard", isOn: $options.keyboard)
                                Toggle("virtualDeviceAudioInput", isOn: $options.audioInput)
                                Toggle("virtualDeviceAudioOutput", isOn: $options.audioOutput)
                                Toggle("virtualDeviceShowFrame", isOn: $options.showDeviceFrame)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }

                    editorSection(number: 5, title: "virtualDeviceIdentitySection") {
                        TextField("virtualDeviceDeviceName", text: $name)
                            .disabled(isEditing)
                        Picker("virtualDeviceHardwareProfile", selection: $profile) {
                            Text("virtualDeviceDefault").tag("")
                            ForEach(viewModel.profiles) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                .padding(22)
            }

            Divider()
            HStack {
                Button("commonCancel") { presentationMode.wrappedValue.dismiss() }
                Spacer()
                Button(isEditing ? "commonSave" : "commonCreate") {
                    save()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .appPresentationWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDeviceEditor
        )
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && (isEditing || !options.systemImageID.isEmpty)
    }

    @ViewBuilder
    private func editorSection<Content: View>(
        number: Int,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption2.bold()).foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(AppTheme.accent))
                Text(title).font(.headline)
            }
            content()
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }

    private func applyFormFactor(_ factor: VirtualDeviceFormFactor) {
        options.formFactor = factor
        selectedSkinPath = ""
        options.skinName = ""
        options.skinPath = ""
        options.systemImageID = ""
        switch factor {
        case .phone:
            options.width = 1_080; options.height = 2_400; options.density = 420
        case .tablet:
            options.width = 1_600; options.height = 2_560; options.density = 320
        case .tv:
            options.width = 1_920; options.height = 1_080; options.density = 320
        default: break
        }
    }

    private func selectSkin(_ skin: AndroidSkin) {
        selectedSkinPath = skin.path
        options.skinName = URL(fileURLWithPath: skin.path).lastPathComponent
        options.skinPath = skin.path
        if let width = skin.displayWidth { options.width = width }
        if let height = skin.displayHeight { options.height = height }
    }

    private func chooseCustomSkin() {
        let panel = NSOpenPanel()
        panel.title = String.localizedKey("virtualDeviceChooseSkinFolder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let skin = viewModel.addCustomSkin(url, configuration: configuration) else { return }
            options.formFactor = skin.formFactor
            selectSkin(skin)
        }
    }

    private func revealSkinsFolder() {
        let root = configuration.skinsPath.isEmpty
            ? URL(fileURLWithPath: configuration.sdkRoot.isEmpty
                ? AndroidSDKLocator.defaultSDKRoot.path : configuration.sdkRoot)
                .appendingPathComponent("skins", isDirectory: true)
            : URL(fileURLWithPath: configuration.skinsPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func save() {
        if let device {
            viewModel.edit(device, options: options, configuration: configuration)
        } else {
            viewModel.create(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                image: options.systemImageID,
                profile: profile.isEmpty ? nil : profile,
                options: options,
                configuration: configuration
            )
        }
    }
}

private struct SkinCard: View {
    let skin: AndroidSkin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let previewPath = skin.previewPath,
                       let image = NSImage(contentsOfFile: previewPath) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: skin.formFactor.icon)
                            .resizable().scaledToFit().padding(18)
                    }
                }
                .frame(height: 72)
                .foregroundColor(.secondary)
                Text(skin.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(skin.detail).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? AppTheme.accent : AppTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LabeledIntegerField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 4) {
                TextField("", value: $value, formatter: integerFormatter)
                    .textFieldStyle(.roundedBorder)
                if !suffix.isEmpty { Text(suffix).font(.caption2).foregroundColor(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }
}
