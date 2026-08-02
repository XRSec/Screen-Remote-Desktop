import SwiftUI

struct DeviceAppDetailView: View {
    @Environment(\.presentationMode) private var presentationMode
    let detail: DeviceAppDetail
    let icon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 72, height: 1)
                Text(detail.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(AppTheme.surface)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Group {
                            if let icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                            } else {
                                AppIconTile(symbol: "app.fill", color: .appIndigo, size: 64)
                            }
                        }
                        .frame(width: 64, height: 64)

                        Text(detail.app.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(detail.app.packageName)
                            .font(.appCaptionMonospaced)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .appTextSelectionEnabled()
                    }
                    .frame(width: 300)

                    VStack(spacing: 0) {
                        ForEach(Array(detail.rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(row.value)
                                    .font(valueFont(for: row))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .appTextSelectionEnabled()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)

                            if index < detail.rows.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .frame(width: 300)
                    .appCard(radius: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .background(AppTheme.background)
        }
        .frame(width: 450, height: 640)
    }

    private func valueFont(for row: DeviceAppDetail.Row) -> Font {
        row.usesMonospacedFont ? .appCaptionMonospaced : .body
    }
}
