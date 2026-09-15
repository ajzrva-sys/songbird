import SwiftUI

/// Shared gradient background used by the player bar and sidebar titlebar cap
/// so they read as one continuous themed band at the top of the window.
///
/// Renders only the background gradient and an aligned bottom edge line.
/// Does not own traffic lights, drag regions, or interactive controls.
public struct SongbirdTopChromeBackground: View {
    public let chrome: SongbirdChromePalette
    public let edgeColor: Color
    public let treatment: SongbirdFeatherTreatment
    /// Whether the user has Reduce Transparency enabled.
    public var reduceTransparency: Bool = false

    public init(
        chrome: SongbirdChromePalette,
        edgeColor: Color,
        treatment: SongbirdFeatherTreatment = .standard,
        reduceTransparency: Bool = false
    ) {
        self.chrome = chrome
        self.edgeColor = edgeColor
        self.treatment = treatment
        self.reduceTransparency = reduceTransparency
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [chrome.highlight, chrome.base, chrome.shadow],
                startPoint: .top,
                endPoint: .bottom
            )
            if !reduceTransparency {
                ChromeGrainTexture(isDark: chromeLuminance < 0.5)
                    .allowsHitTesting(false)
            }
            if treatment.usesLayeredChrome {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.38))
                        .frame(height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color(red: 0.36, green: 0.10, blue: 0.21).opacity(0.48))
                        .frame(height: 1)
                    Rectangle()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            if treatment.usesBlueMondayChrome {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.62))
                        .frame(height: 1)
                    Spacer()
                    Rectangle()
                        .fill(SongbirdThemePalette.blueMondayAccent.opacity(0.64))
                        .frame(height: 1)
                }
                .allowsHitTesting(false)
            }
            if treatment.usesGonzoChrome {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.50))
                        .frame(height: 1)
                    Spacer()
                    Rectangle()
                        .fill(SongbirdThemePalette.gonzoAccent.opacity(0.55))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            if treatment.usesPurpleChrome {
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(SongbirdThemePalette.purpleRainAccent.opacity(0.60))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            // Bottom 1px edge to visually separate chrome from content below.
            VStack {
                Spacer()
                Rectangle()
                    .fill(edgeColor)
                    .frame(height: 1)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            if treatment.usesTerminalChrome {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(SongbirdThemePalette.terminalAccent.opacity(0.78))
                        .frame(height: 1)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var chromeLuminance: CGFloat {
        let ns = NSColor(chrome.base).usingColorSpace(.deviceRGB) ?? NSColor(chrome.base)
        return 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
    }
}

/// Procedural grain texture overlay for the chrome. Uses a Canvas to draw
/// a subtle noise pattern that gives the chrome a more tactile, metallic feel.
/// Respects Reduce Transparency by not rendering.
private struct ChromeGrainTexture: View {
    let isDark: Bool

    private var grainOpacity: Double {
        isDark ? 0.04 : 0.025
    }

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            for y in stride(from: 0, to: size.height, by: step) {
                for x in stride(from: 0, to: size.width, by: step) {
                    // Simple deterministic pseudo-random based on position
                    let hash = (Int(x * 7 + y * 13) &* 2654435761) & 0xFFFF
                    let brightness = Double(hash % 256) / 255.0
                    let alpha = brightness * grainOpacity
                    let rect = CGRect(x: x, y: y, width: step, height: step)
                    context.fill(
                        Path(rect),
                        with: .color(Color.white.opacity(alpha))
                    )
                }
            }
        }
        .blendMode(.overlay)
    }
}
