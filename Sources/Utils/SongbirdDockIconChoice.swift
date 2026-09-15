import Foundation

public enum SongbirdDockIconChoice: String, CaseIterable, Identifiable, Sendable {
    case blueOutline
    case blueVinyl
    case gonzoLight
    case gonzoDark
    case pinkLacquer
    case pinkBurgundy
    case pinkTerrazzo
    case bowieSilverBlue
    case bowiePrism
    case dovePearl
    case doveMarble
    case silverwingFrame
    case silverwingGraphite
    case musicLightLacquer
    case musicDarkRed
    case purpleRim
    case purpleNeon
    case nightingaleGlow
    case nightingaleGlass
    case blackbirdGraphite
    case blackbirdAmber
    case terminalAmber

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blueOutline: return "Outline"
        case .blueVinyl: return "Vinyl"
        case .gonzoLight: return "Light"
        case .gonzoDark: return "Dark"
        case .pinkLacquer: return "Lacquer"
        case .pinkBurgundy: return "Burgundy"
        case .pinkTerrazzo: return "Terrazzo"
        case .bowieSilverBlue: return "Silver Blue"
        case .bowiePrism: return "Prism"
        case .dovePearl: return "Pearl"
        case .doveMarble: return "Marble"
        case .silverwingFrame: return "Silver Frame"
        case .silverwingGraphite: return "Graphite"
        case .musicLightLacquer: return "Red Lacquer"
        case .musicDarkRed: return "Red on Black"
        case .purpleRim: return "Violet Rim"
        case .purpleNeon: return "Neon"
        case .nightingaleGlow: return "Night Glow"
        case .nightingaleGlass: return "Aqua Glass"
        case .blackbirdGraphite: return "Graphite"
        case .blackbirdAmber: return "Amber"
        case .terminalAmber: return "Amber Bird"
        }
    }

    public var resourceName: String {
        switch self {
        case .blueOutline: return "dock-icon-blue-outline"
        case .blueVinyl: return "dock-icon-blue-vinyl"
        case .gonzoLight: return "dock-icon-gonzo-light"
        case .gonzoDark: return "dock-icon-gonzo-dark"
        case .pinkLacquer: return "dock-icon-pink-lacquer"
        case .pinkBurgundy: return "dock-icon-pink-burgundy"
        case .pinkTerrazzo: return "dock-icon-pink-terrazzo"
        case .bowieSilverBlue: return "dock-icon-bowie-silver-blue"
        case .bowiePrism: return "dock-icon-bowie-prism"
        case .dovePearl: return "dock-icon-dove-pearl"
        case .doveMarble: return "dock-icon-dove-marble"
        case .silverwingFrame: return "dock-icon-silverwing-frame"
        case .silverwingGraphite: return "dock-icon-silverwing-graphite"
        case .musicLightLacquer: return "dock-icon-music-light-lacquer"
        case .musicDarkRed: return "dock-icon-music-dark-red"
        case .purpleRim: return "dock-icon-purple-rim"
        case .purpleNeon: return "dock-icon-purple-neon"
        case .nightingaleGlow: return "dock-icon-nightingale-glow"
        case .nightingaleGlass: return "dock-icon-nightingale-glass"
        case .blackbirdGraphite: return "dock-icon-blackbird-graphite"
        case .blackbirdAmber: return "dock-icon-blackbird-amber"
        case .terminalAmber: return "dock-icon-blackbird-amber"
        }
    }
}

public extension SongbirdThemeID {
    var dockIconChoices: [SongbirdDockIconChoice] {
        switch self {
        case .blueMonday:
            return [.blueOutline, .blueVinyl]
        case .gonzo:
            return [.gonzoLight, .gonzoDark]
        case .pinkMartini:
            return [.pinkLacquer, .pinkBurgundy, .pinkTerrazzo]
        case .bowie:
            return [.bowieSilverBlue, .bowiePrism]
        case .dove:
            return [.dovePearl, .doveMarble]
        case .silverwing:
            return [.silverwingFrame, .silverwingGraphite]
        case .musicLight:
            return [.musicLightLacquer]
        case .musicDark:
            return [.musicDarkRed]
        case .purpleRain:
            return [.purpleRim, .purpleNeon]
        case .nightingale:
            return [.nightingaleGlow, .nightingaleGlass]
        case .blackbird:
            return [.blackbirdGraphite, .blackbirdAmber]
        case .terminal:
            return []
        default:
            return []
        }
    }

    var defaultDockIconChoice: SongbirdDockIconChoice? {
        dockIconChoices.first
    }
}
