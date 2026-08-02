import AppKit
import Foundation
import SwiftUI

@MainActor
final class VirtualDeviceViewModel: ObservableObject {
    @Published var images: [AndroidSystemImage] = []
    @Published var devices: [AndroidVirtualDevice] = []
    @Published var profiles: [AndroidHardwareProfile] = []
    @Published var skins: [AndroidSkin] = []
    @Published var isWorking = false
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var workingImageID: String?
    private let service = VirtualDeviceService()

    func refresh(_ configuration: VirtualDeviceConfiguration, forceRefresh: Bool = false) {
        skins = service.listSkins(configuration)
        perform(String.localizedKey("virtualDeviceStatusReadingSDK")) {
            async let images = self.service.listImages(configuration)
            async let devices = self.service.listAVDs(configuration, forceRefresh: forceRefresh)
            async let profiles = self.service.listHardwareProfiles(configuration)
            self.images = try await images
            self.devices = try await devices
            self.profiles = try await profiles
        }
    }

    func refreshDevices(_ configuration: VirtualDeviceConfiguration, forceRefresh: Bool = false) {
        perform(String.localizedKey("virtualDeviceStatusReadingSDK")) {
            self.devices = try await self.service.listAVDs(configuration, forceRefresh: forceRefresh)
        }
    }

    func install(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        workingImageID = image.id
        perform(String(format: String.localizedKey("virtualDeviceStatusInstalling"), image.displayName)) {
            try await self.service.installImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        } completion: { self.workingImageID = nil }
    }

    func uninstall(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        let usingDevices = devicesUsing(image, configuration: configuration)
        guard usingDevices.isEmpty else {
            errorMessage = String(
                format: String.localizedKey("virtualDeviceImageInUseError"),
                usingDevices.map(\.name).joined(separator: ", ")
            )
            return
        }
        workingImageID = image.id
        perform(String(format: String.localizedKey("virtualDeviceStatusUninstalling"), image.displayName)) {
            try await self.service.uninstallImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        } completion: { self.workingImageID = nil }
    }

    func devicesUsing(
        _ image: AndroidSystemImage,
        configuration: VirtualDeviceConfiguration
    ) -> [AndroidVirtualDevice] {
        devices.filter { device in
            let configuredImageID = service.options(for: device, configuration: configuration).systemImageID
            return AndroidSystemImage.canonicalID(configuredImageID) == image.canonicalID
        }
    }

    func create(
        name: String,
        image: String,
        profile: String?,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) {
        perform(String(format: String.localizedKey("virtualDeviceStatusCreating"), name)) {
            try await self.service.createAVD(
                name: name,
                image: image,
                profile: profile,
                options: options,
                configuration: configuration
            )
            self.devices = try await self.service.listAVDs(configuration, forceRefresh: true)
        }
    }

    func edit(
        _ device: AndroidVirtualDevice,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) {
        perform(String(format: String.localizedKey("virtualDeviceStatusUpdating"), device.name)) {
            try self.service.updateAVD(device, options: options, configuration: configuration)
            self.devices = try await self.service.listAVDs(configuration, forceRefresh: true)
        }
    }

    func options(for device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) -> VirtualDeviceOptions {
        service.options(for: device, configuration: configuration)
    }

    func prepareEditorResources(_ configuration: VirtualDeviceConfiguration) {
        skins = service.listSkins(configuration)
        Task {
            do {
                async let images = self.service.listImages(configuration)
                async let profiles = self.service.listHardwareProfiles(configuration)
                self.images = try await images
                self.profiles = try await profiles
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func addCustomSkin(_ url: URL, configuration: VirtualDeviceConfiguration) -> AndroidSkin? {
        let custom = service.listSkins(configuration, customDirectories: [url]).first { $0.isCustom }
        if let custom, !skins.contains(where: { $0.path == custom.path }) {
            skins.insert(custom, at: 0)
        }
        return custom
    }

    func delete(_ device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) {
        perform(String(format: String.localizedKey("virtualDeviceStatusDeleting"), device.name)) {
            try await self.service.deleteAVD(device.name, configuration: configuration)
            self.devices = try await self.service.listAVDs(configuration, forceRefresh: true)
        }
    }

    func toggle(_ device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) {
        perform(device.isRunning
            ? String(format: String.localizedKey("virtualDeviceStatusStopping"), device.name)
            : String(format: String.localizedKey("virtualDeviceStatusStarting"), device.name)) {
            if device.isRunning {
                try await self.service.stopAVD(device, configuration: configuration)
            } else {
                try await self.service.startAVD(device.name, configuration: configuration)
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            self.devices = try await self.service.listAVDs(configuration, forceRefresh: true)
        }
    }

    private func perform(
        _ status: String,
        operation: @escaping () async throws -> Void,
        completion: @escaping () -> Void = { }
    ) {
        guard !isWorking else { return }
        isWorking = true
        self.status = status
        errorMessage = nil
        Task {
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
            self.status = ""
            completion()
        }
    }
}
