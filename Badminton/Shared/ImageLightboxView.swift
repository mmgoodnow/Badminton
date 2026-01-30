import Kingfisher
import SwiftUI

struct ImageLightboxItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct ImageLightboxView: View {
    let item: ImageLightboxItem

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                imageView
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var imageView: some View {
        KFImage(item.url)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    scale = 1
                    lastScale = 1
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .padding()
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                } else {
                    lastOffset = offset
                }
            }
    }
}
