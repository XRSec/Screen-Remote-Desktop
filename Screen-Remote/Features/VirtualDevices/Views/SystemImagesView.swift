import AppKit
import Foundation
import SwiftUI

struct SystemImagesView: View {
    @ObservedObject var viewModel: VirtualDeviceViewModel
    let configuration: VirtualDeviceConfiguration
    @State private var searchText = ""
    @State private var formFactor = "all"
    @State private var apiCategory = "all"
    @State private var service = "all"
    @State private var imagePendingRemoval: AndroidSystemImage?

    private var apiCategories: [String] {
        Array(Set(viewModel.images.map(\.apiCategory).filter { !$0.isEmpty })).sorted {
            (Int($0) ?? 0) > (Int($1) ?? 0)
        }
    }

    private var filteredImages: [AndroidSystemImage] {
        viewModel.images.filter { image in
            let matchesSearch = searchText.isEmpty
                || image.displayName.localizedCaseInsensitiveContains(searchText)
                || image.id.localizedCaseInsensitiveContains(searchText)
            let matchesFormFactor = formFactor == "all" || image.formFactor.rawValue == formFactor
            let matchesAPI = apiCategory == "all" || image.apiCategory == apiCategory
            let matchesService = service == "all" || image.service.rawValue == service
            return matchesSearch && matchesFormFactor && matchesAPI && matchesService
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    TextField("virtualDeviceImageSearch", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("commonClear")
                        .accessibilityLabel(Text("commonClear"))
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: AppRadius.small).fill(Color.primary.opacity(0.055)))

                HStack(spacing: 8) {
                    FilterPicker(title: "virtualDeviceFilterFormFactor", selection: $formFactor) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(VirtualDeviceFormFactor.allCases) { value in
                            Text(value.localizationKey).tag(value.rawValue)
                        }
                    }
                    FilterPicker(title: "virtualDeviceFilterAPI", selection: $apiCategory) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(apiCategories, id: \.self) { Text("API \($0)").tag($0) }
                    }
                    FilterPicker(title: "virtualDeviceFilterService", selection: $service) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(AndroidImageService.allCases) { value in
                            Text(value.localizationKey).tag(value.rawValue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: String.localizedKey("virtualDeviceImageCount"), filteredImages.count))
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            if filteredImages.isEmpty && !viewModel.isWorking {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("virtualDeviceNoMatchingImages").font(AppTypography.headline)
                    Text("virtualDeviceNoMatchingImagesDetail")
                        .font(AppTypography.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        imageSection(
                            title: "virtualDeviceInstalledSection",
                            icon: "checkmark.circle.fill",
                            images: filteredImages.filter(\.isInstalled)
                        )
                        imageSection(
                            title: "virtualDeviceAvailableSection",
                            icon: "arrow.down.circle",
                            images: filteredImages.filter { !$0.isInstalled }
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
            }
        }
        .alert(item: $imagePendingRemoval) { image in
            Alert(
                title: Text("virtualDeviceRemoveImageConfirmationTitle"),
                message: Text(String(
                    format: String.localizedKey("virtualDeviceRemoveImageConfirmationMessage"),
                    image.displayName
                )),
                primaryButton: .destructive(Text("virtualDeviceRemove")) {
                    viewModel.uninstall(image, configuration: configuration)
                },
                secondaryButton: .cancel(Text("commonCancel"))
            )
        }
    }

    @ViewBuilder
    private func imageSection(
        title: LocalizedStringKey,
        icon: String,
        images: [AndroidSystemImage]
    ) -> some View {
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        let usingDevices = viewModel.devicesUsing(image, configuration: configuration)
                        SystemImageRow(
                            image: image,
                            isWorking: viewModel.workingImageID == image.id,
                            isInteractionDisabled: viewModel.isWorking,
                            usageDescription: usingDevices.isEmpty ? nil : String(
                                format: String.localizedKey("virtualDeviceImageInUseHelp"),
                                usingDevices.map(\.name).joined(separator: ", ")
                            ),
                            action: {
                                if image.isInstalled {
                                    imagePendingRemoval = image
                                } else {
                                    viewModel.install(image, configuration: configuration)
                                }
                            }
                        )
                        if index < images.count - 1 { Divider().padding(.leading, 48) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppTheme.line, lineWidth: 1))
            }
        }
    }
}

struct FilterPicker<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Picker(title, selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SystemImageRow: View {
    let image: AndroidSystemImage
    let isWorking: Bool
    let isInteractionDisabled: Bool
    let usageDescription: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: image.formFactor.icon)
                .font(AppTypography.headline)
                .foregroundColor(image.isInstalled ? .green : AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.055)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(image.displayName).font(AppTypography.body.weight(.medium))
                Text(image.description).font(AppTypography.caption2).foregroundColor(.secondary).lineLimit(1)
                Text(image.id).font(AppTypography.monospacedCaption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if image.isInstalled {
                Label("virtualDeviceInstalled", systemImage: "checkmark.circle.fill")
                    .font(AppTypography.caption).foregroundColor(.green)
            }
            if let usageDescription {
                Image(systemName: "lock.fill")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .help(usageDescription)
                    .accessibilityLabel(Text(usageDescription))
            }
            if isWorking {
                ProgressView().scaleEffect(0.7).frame(width: 48)
            } else {
                Button(image.isInstalled ? "virtualDeviceRemove" : "virtualDeviceDownload", action: action)
                    .disabled(isInteractionDisabled || isWorking || usageDescription != nil)
                    .help(usageDescription ?? "")
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 68)
    }
}
