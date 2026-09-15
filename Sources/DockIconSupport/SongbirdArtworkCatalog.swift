import Foundation

public enum SongbirdArtworkCatalog {
    public struct Variant: Sendable {
        public let name: String
        public let background: UInt32
        public let accent: UInt32
    }

    public static let dockVariants: [Variant] = [
        .init(name: "dock-icon-blue-outline", background: 0x202831, accent: 0x58B9E8),
        .init(name: "dock-icon-blue-vinyl", background: 0x1C2635, accent: 0x80C8EC),
        .init(name: "dock-icon-gonzo-light", background: 0xE9E0CD, accent: 0xA88030),
        .init(name: "dock-icon-gonzo-dark", background: 0x302B24, accent: 0xC49A45),
        .init(name: "dock-icon-pink-lacquer", background: 0xEEDDE1, accent: 0xAD6179),
        .init(name: "dock-icon-pink-burgundy", background: 0x39252E, accent: 0xCC829B),
        .init(name: "dock-icon-pink-terrazzo", background: 0xDDD0D5, accent: 0x945A75),
        .init(name: "dock-icon-bowie-silver-blue", background: 0xCED6DF, accent: 0x587EA8),
        .init(name: "dock-icon-bowie-prism", background: 0x28333E, accent: 0x9BA8CE),
        .init(name: "dock-icon-dove-pearl", background: 0xE8E5DE, accent: 0x8D918C),
        .init(name: "dock-icon-dove-marble", background: 0xD1D4D2, accent: 0x777F7A),
        .init(name: "dock-icon-silverwing-frame", background: 0xC5CCD3, accent: 0x627B92),
        .init(name: "dock-icon-silverwing-graphite", background: 0x282D32, accent: 0xA0ABB4),
        .init(name: "dock-icon-music-light-lacquer", background: 0xECE5E3, accent: 0xB15E58),
        .init(name: "dock-icon-music-dark-red", background: 0x302426, accent: 0xD37872),
        .init(name: "dock-icon-purple-rim", background: 0x302839, accent: 0xAC87CB),
        .init(name: "dock-icon-purple-neon", background: 0x27232F, accent: 0xBD9AD9),
        .init(name: "dock-icon-nightingale-glow", background: 0x263638, accent: 0x89C1BC),
        .init(name: "dock-icon-nightingale-glass", background: 0xCEDFDF, accent: 0x5B969C),
        .init(name: "dock-icon-blackbird-graphite", background: 0x25282C, accent: 0xAAB0B8),
        .init(name: "dock-icon-blackbird-amber", background: 0x2D2925, accent: 0xD6974D),
    ]

    public static let resourceNames = Set(dockVariants.map(\.name))
}
