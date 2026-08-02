import Foundation
import SwiftUI

private let deviceInfoColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let deviceInfoGridMaxWidth: CGFloat = 914

struct DeviceInfoSection: View {
    let group: DeviceInfoGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title).font(.headline).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundColor(.secondary)
                        Spacer(minLength: 20)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    if index != group.rows.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .appCard()
        }
    }
}
