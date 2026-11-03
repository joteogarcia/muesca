import AppKit
import SwiftUI

// Aspecto fijo de Muesca: opaca, bordes redondeados,
// negra en reposo y teñida con los colores de la carátula cuando hay música.

enum Appearance {
    /// Degradado de fondo según la carátula (nil = negro).
    static func artworkGradient(_ palette: ArtworkPalette?) -> [Color]? {
        palette.map { $0.background.map { Color(nsColor: $0) } }
    }
}

struct IslandBackground: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        if let g = state.bgGradient {
            LinearGradient(colors: g, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.black
        }
    }
}
