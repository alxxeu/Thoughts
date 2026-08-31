// CardView.swift
import SwiftUI

struct CardView: View {
    @Bindable var card: Card

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 24)
                    .cursor(.closedHand)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                card.position.x += value.translation.width
                                card.position.y += value.translation.height
                            }
                    )

                TextEditor(text: $card.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray.opacity(0.5))
                .padding(8)
                .cursor(.resizeLeftRight)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            card.size.width = max(150, card.size.width + value.translation.width)
                            card.size.height = max(100, card.size.height + value.translation.height)
                        }
                )
        }
        .frame(width: card.size.width, height: card.size.height)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}
