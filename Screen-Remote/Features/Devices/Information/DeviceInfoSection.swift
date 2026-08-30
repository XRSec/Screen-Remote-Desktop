import Foundation
import SwiftUI

private let deviceInfoColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let deviceInfoGridMaxWidth: CGFloat = 914

struct DeviceInfoSection: View {
    let group: DeviceInfoGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(AppTypography.subheadline.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.bottom, AppSpacing.sm)
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundColor(.secondary)
                        Spacer(minLength: 20)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(AppTypography.body)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    if index != group.rows.count - 1 { Divider().padding(.leading, AppSpacing.md) }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
        }
    }
}
