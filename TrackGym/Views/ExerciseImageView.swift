import SwiftUI

struct ExerciseImageView: View {
    let exercise: Exercise
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let urlString = exercise.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderIcon
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderIcon: some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: exercise.muscleGroup.icon)
                .foregroundStyle(.secondary)
        }
    }
}
