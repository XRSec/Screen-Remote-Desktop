import SwiftUI

struct PhotosView: View {
    let isCompact: Bool
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Group {
                    if isCompact {
                        VStack(spacing: 10) {
                            PageSearchField(searchText: $searchText, searchPrompt: "photosSearchPrompt", expands: true)
                            photoFilter
                        }
                    } else {
                        HStack(spacing: 12) {
                            photoFilter
                            Spacer()
                            PageSearchField(searchText: $searchText, searchPrompt: "photosSearchPrompt", expands: false)
                        }
                    }
                }

                ContentUnavailableViewCompat(
                    icon: "photo.on.rectangle.angled",
                    title: "photosEmptyTitle",
                    detail: "photosEmptyDetail"
                )
                .frame(minHeight: 260)
            }
            .padding(isCompact ? 20 : 28)
        }
    }

    private var photoFilter: some View {
        HStack {
                    Picker("photosTitle", selection: .constant(0)) {
                        Text("photosRecent").tag(0)
                        Text("photosScreenshots").tag(1)
                        Text("photosCamera").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: isCompact ? 230 : 270)
                }
    }
}
