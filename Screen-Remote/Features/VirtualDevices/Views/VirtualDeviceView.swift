import AppKit
import Foundation
import SwiftUI

enum VirtualDeviceSheet: Identifiable {
    case create
    case edit(AndroidVirtualDevice)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let device): "edit-\(device.id)"
        }
    }
}

struct VirtualDeviceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = VirtualDeviceViewModel()
    @State private var tab = 0
    @State private var activeSheet: VirtualDeviceSheet?

    private var configuration: VirtualDeviceConfiguration {
        VirtualDeviceConfiguration(
            sdkRoot: appState.androidSDKRoot,
            androidCLIPath: appState.androidCLIPath,
            toolsPath: appState.commandLineToolsPath,
            emulatorPath: appState.emulatorPath,
            skinsPath: appState.skinsPath,
            avdHome: appState.avdHome
        )
    }

    private var isCompact: Bool {
        AppPresentationMetrics.preferredWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDevices
        ) < 600
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("virtualDeviceTitle", selection: $tab) {
                Text("virtualDeviceMyDevices").tag(0)
                Text("virtualDeviceSystemImages").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            if viewModel.isWorking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text(viewModel.status).font(.caption).foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if tab == 0 {
                virtualDevicesContent
            } else {
                SystemImagesView(viewModel: viewModel, configuration: configuration)
            }
        }
        .appPresentationWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDevices
        )
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
        .onAppear {
            viewModel.refresh(configuration)
            if appState.shouldOpenVirtualDeviceCreator {
                appState.shouldOpenVirtualDeviceCreator = false
                activeSheet = .create
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                VirtualDeviceEditorView(
                    viewModel: viewModel,
                    configuration: configuration,
                    device: nil,
                    initialOptions: VirtualDeviceOptions()
                )
                .environment(\.locale, appState.resolvedLocale)
            case .edit(let device):
                VirtualDeviceEditorView(
                    viewModel: viewModel,
                    configuration: configuration,
                    device: device,
                    initialOptions: viewModel.options(for: device, configuration: configuration)
                )
                .environment(\.locale, appState.resolvedLocale)
            }
        }
    }

    private var header: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitle
                    HStack(spacing: 10) {
                        headerActions
                    }
                }
                .padding(16)
            } else {
                HStack(spacing: 10) {
                    headerTitle
                    Spacer()
                    headerActions
                }
                .padding(22)
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("virtualDeviceTitle").font(.title2.bold())
            Text("virtualDeviceSubtitle").font(.subheadline).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if tab == 0 {
            Button {
                activeSheet = .create
            } label: {
                Label("virtualDeviceCreateAction", systemImage: "plus")
            }
            .disabled(viewModel.isWorking)
        }
        Spacer()
        Button { viewModel.refresh(configuration, forceRefresh: true) } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("virtualDeviceRefresh")
        .disabled(viewModel.isWorking)
        Button("commonDone") { presentationMode.wrappedValue.dismiss() }
    }

    private var virtualDevicesContent: some View {
        Group {
            if viewModel.devices.isEmpty && !viewModel.isWorking {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "iphone.gen3.slash")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(.secondary)
                    Text("virtualDeviceNoDevicesTitle").font(AppTypography.headline)
                    Text("virtualDeviceNoDevicesDetail")
                        .font(AppTypography.subheadline).foregroundColor(.secondary)
                    Button("virtualDeviceCreateAction") { activeSheet = .create }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(viewModel.devices) { device in
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: device.isRunning ? "play.circle.fill" : "iphone.gen3")
                                    .font(AppTypography.largeTitle)
                                    .foregroundColor(device.isRunning ? .green : AppTheme.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(device.name).font(AppTypography.headline)
                                        if device.isRunning {
                                            Text("virtualDeviceRunning")
                                                .font(AppTypography.caption2.weight(.semibold))
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Text(device.target.isEmpty ? device.path : device.target)
                                        .font(AppTypography.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button {
                                    activeSheet = .edit(device)
                                } label: {
                                    Label("commonEdit", systemImage: "slider.horizontal.3")
                                        .labelStyle(.iconOnly)
                                }
                                .help("commonEdit")
                                .disabled(device.isRunning || viewModel.isWorking)
                                Button {
                                    viewModel.toggle(device, configuration: configuration)
                                } label: {
                                    Label(
                                        device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart",
                                        systemImage: device.isRunning ? "stop.fill" : "play.fill"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .help(device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart")
                                .disabled(viewModel.isWorking)
                                Button {
                                    viewModel.delete(device, configuration: configuration)
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .disabled(device.isRunning || viewModel.isWorking)
                            }
                            .padding(AppSpacing.cardPadding)
                            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppTheme.line, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}
