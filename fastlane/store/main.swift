// Composes Plumb App Store screenshots (US) at 1320 x 2868 (6.9" display, accepted by App Store Connect).
// Build: swiftc -O main.swift SVGPath.swift PMIcon.swift -o compose   (PMIcon/SVGPath copied from the app)
// Usage: ./compose <rawDir> <outDir>
import AppKit
import SwiftUI

let args = CommandLine.arguments
let rawDir = args[1], outDir = args[2]
let W: CGFloat = 1320, H: CGFloat = 2868

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
    }
}

struct Theme {
    let bg, ink, sub, accent, onAccent, grid, glow: Color
    let dark: Bool
    static let dark = Theme(bg: Color(hex: 0x0B0D0F), ink: Color(hex: 0xF1F4F3), sub: Color(hex: 0xA7B0B5),
                            accent: Color(hex: 0x52F2B8), onAccent: Color(hex: 0x03140D),
                            grid: .white.opacity(0.035), glow: Color(hex: 0x52F2B8).opacity(0.22), dark: true)
    static let light = Theme(bg: Color(hex: 0xF4F5F2), ink: Color(hex: 0x0E1113), sub: Color(hex: 0x545D63),
                             accent: Color(hex: 0x007A55), onAccent: .white,
                             grid: .black.opacity(0.045), glow: Color(hex: 0x52F2B8).opacity(0.30), dark: false)
}

/// A magnified piece of the screenshot, in raw pixels.
struct Zoom { let rect: CGRect; let width: CGFloat; let x: CGFloat; let y: CGFloat }

enum Layout {
    case standard(file: String, top: CGFloat = 760, width: CGFloat = 1080, tilt: Double = 0, zoom: Zoom? = nil)
    case icons
    case twoPhones(back: String, front: String)
    case paper(phone: String, paper: CGRect)
}

struct Slide {
    let layout: Layout
    let lead: String
    let accent: String
    let sub: String
    var pro = false
    var theme = Theme.dark
    var glow = UnitPoint(x: 0.5, y: 0.18)
}

let slides: [Slide] = [
    Slide(layout: .standard(file: "live", top: 760, width: 1040), lead: "Level anything.", accent: "Instantly.",
          sub: "A precision bubble level driven by your iPhone's motion sensors."),
    Slide(layout: .icons, lead: "Every measuring tool.", accent: "One app.",
          sub: "Twelve tools for the job site, the workshop and home.", glow: UnitPoint(x: 0.2, y: 0.12)),
    Slide(layout: .standard(file: "room", top: 760, width: 1040), lead: "Measure a whole room", accent: "in seconds.",
          sub: "Scan walls and corners to get a floor plan and area.", glow: UnitPoint(x: 0.8, y: 0.15)),
    Slide(layout: .standard(file: "photo", top: 760, width: 1040), lead: "Measure anything", accent: "in a photo.",
          sub: "Mark one known size and every other length is scaled from it."),
    Slide(layout: .standard(file: "protractor", top: 820, width: 1000, tilt: -6,
                            zoom: Zoom(rect: CGRect(x: 180, y: 420, width: 960, height: 380), width: 1120, x: 660, y: 2060)),
          lead: "Any angle.", accent: "At a glance.",
          sub: "Angle finder and protractor, from 0° to 180°.", glow: UnitPoint(x: 0.25, y: 0.2)),
    Slide(layout: .standard(file: "convert", top: 820, width: 1000,
                            zoom: Zoom(rect: CGRect(x: 60, y: 970, width: 1200, height: 480), width: 1180, x: 660, y: 2080)),
          lead: "Convert 160+ units.", accent: "Exactly.",
          sub: "15 categories, using exact NIST conversion factors.", glow: UnitPoint(x: 0.75, y: 0.15)),
    Slide(layout: .standard(file: "shapeC", top: 820, width: 1000,
                            zoom: Zoom(rect: CGRect(x: 60, y: 1100, width: 1200, height: 600), width: 1180, x: 660, y: 1990)),
          lead: "Area of any shape,", accent: "solved.",
          sub: "14 shapes with live diagrams, perimeter and the formula."),
    Slide(layout: .standard(file: "calc", top: 700), lead: "Builder math,", accent: "done for you.",
          sub: "Slope, area, volume, tile, paint and concrete.", glow: UnitPoint(x: 0.2, y: 0.15)),
    Slide(layout: .twoPhones(back: "projects", front: "project"), lead: "Every job,", accent: "organized.",
          sub: "Keep measurements and photos together by project.", glow: UnitPoint(x: 0.8, y: 0.2)),
    Slide(layout: .paper(phone: "report", paper: CGRect(x: 60, y: 370, width: 1200, height: 1290)),
          lead: "Share clean", accent: "PDF reports.",
          sub: "Measurements, methods and photos in one tidy PDF."),
]

struct Grid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let s: CGFloat = 66
        var x: CGFloat = 0; while x <= r.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: r.height)); x += s }
        var y: CGFloat = 0; while y <= r.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: r.width, y: y)); y += s }
        return p
    }
}

func load(_ f: String) -> NSImage { NSImage(contentsOfFile: "\(rawDir)/\(f).png")! }

func crop(_ img: NSImage, _ r: CGRect) -> NSImage {
    var rect = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    return NSImage(cgImage: cg.cropping(to: r)!, size: r.size)
}

struct Device: View {
    let image: NSImage
    let width: CGFloat
    let theme: Theme
    var body: some View {
        let screenW = width - 44
        let screenH = screenW * 2868 / 1320
        let radius: CGFloat = screenW * 0.135
        ZStack {
            RoundedRectangle(cornerRadius: radius + 22, style: .continuous)
                .fill(LinearGradient(colors: theme.dark ? [Color(hex: 0x4A5157), Color(hex: 0x1B1F22), Color(hex: 0x3A4045)]
                                                        : [Color(hex: 0xD9DDDA), Color(hex: 0x9EA5A1), Color(hex: 0xC9CECB)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: radius + 18, style: .continuous).fill(Color.black).padding(4)
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            RoundedRectangle(cornerRadius: radius + 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
        }
        .frame(width: width, height: screenH + 44)
        .shadow(color: .black.opacity(theme.dark ? 0.6 : 0.22), radius: 60, y: 40)
    }
}

/// Magnified callout card.
struct Callout: View {
    let image: NSImage
    let width: CGFloat
    let theme: Theme
    var body: some View {
        let h = width * image.size.height / image.size.width
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(theme.accent.opacity(0.9), lineWidth: 5))
            .shadow(color: .black.opacity(theme.dark ? 0.7 : 0.25), radius: 70, y: 40)
    }
}

struct IconTile: View {
    let icon: PMIconName
    let name: String
    let pro: Bool
    let theme: Theme
    var body: some View {
        VStack(spacing: 26) {
            PMIcon(icon, size: 120, stroke: 1.8)
                .foregroundStyle(theme.accent)
                .frame(width: 210, height: 210)
                .background(RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .fill(theme.dark ? Color(hex: 0x1E252A) : Color(hex: 0xE6F2EC)))
                .overlay(alignment: .topTrailing) {
                    if pro {
                        Text("PRO").font(.system(size: 26, weight: .heavy)).tracking(2)
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Capsule().fill(theme.accent))
                            .offset(x: 26, y: -16)
                    }
                }
            Text(name).font(.system(size: 46, weight: .semibold)).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 384, height: 400)
        .background(RoundedRectangle(cornerRadius: 56, style: .continuous)
            .fill(theme.dark ? Color(hex: 0x15191D) : .white))
        .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous)
            .strokeBorder(theme.dark ? Color(hex: 0x262E34) : Color(hex: 0xD2D8D3), lineWidth: 2))
    }
}

struct Page: View {
    let slide: Slide
    let index: Int
    var t: Theme { slide.theme }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg
            Grid().stroke(t.grid, lineWidth: 2)
            RadialGradient(colors: [t.glow, t.glow.opacity(0)], center: slide.glow, startRadius: 0, endRadius: 900)
            if t.dark { LinearGradient(colors: [.clear, t.bg.opacity(0.9)], startPoint: .center, endPoint: .bottom) }

            header
            content
        }
        .frame(width: W, height: H)
        .clipped()
    }

    var header: some View {
        VStack(spacing: 0) {
            if slide.pro {
                Text("PRO").font(.system(size: 40, weight: .heavy)).tracking(4)
                    .foregroundStyle(t.onAccent)
                    .padding(.horizontal, 28).frame(height: 66)
                    .background(Capsule().fill(t.accent))
                    .padding(.bottom, 34)
            } else {
                Spacer().frame(height: 100)
            }
            (Text(slide.lead + "\n").foregroundColor(t.ink) + Text(slide.accent).foregroundColor(t.accent))
                .font(.system(size: index == 0 ? 132 : 118, weight: .bold))
                .tracking(-2.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(slide.sub)
                .font(.system(size: 46))
                .foregroundColor(t.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .frame(maxWidth: 1060)
                .padding(.top, 34)
        }
        .padding(.top, 150)
        .frame(width: W)
    }

    @ViewBuilder var content: some View {
        switch slide.layout {
        case let .standard(file, top, width, tilt, zoom):
            let img = load(file)
            ZStack(alignment: .topLeading) {
                Device(image: img, width: width, theme: t)
                    .rotationEffect(.degrees(tilt))
                    .frame(width: W)
                    .padding(.top, top)
                if let z = zoom {
                    let c = Callout(image: crop(img, z.rect), width: z.width, theme: t)
                    c.position(x: z.x, y: z.y + z.width * z.rect.height / z.rect.width / 2)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
        case .icons:
            let items: [(PMIconName, String, Bool)] = [
                (.level, "Bubble Level", false), (.angle, "Angle Finder", false), (.protractor, "Protractor", false),
                (.compass, "Compass", false), (.ruler, "Ruler", false), (.surface, "Surface Level", false),
                (.ar, "AR Measure", false), (.room, "Room Scan", false), (.photoMarkers, "Photo Measure", false),
                (.converter, "Converter", false), (.shapes, "Shape Area", false), (.calculator, "Calculators", false),
            ]
            VStack(spacing: 40) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 36) {
                        ForEach(0..<3, id: \.self) { c in
                            let it = items[r * 3 + c]
                            IconTile(icon: it.0, name: it.1, pro: it.2, theme: t)
                        }
                    }
                }
                Text("Plus projects, history and PDF reports.")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(t.sub)
                    .padding(.top, 30)
            }
            .frame(width: W)
            .padding(.top, 760)
        case let .twoPhones(back, front):
            ZStack(alignment: .topLeading) {
                Device(image: load(back), width: 820, theme: t)
                    .rotationEffect(.degrees(-7))
                    .position(x: 400, y: 900 + 900)
                Device(image: load(front), width: 820, theme: t)
                    .rotationEffect(.degrees(5))
                    .position(x: 900, y: 1000 + 900)
            }
            .frame(width: W, height: H, alignment: .topLeading)
        case let .paper(phone, paper):
            let img = load(phone)
            ZStack(alignment: .topLeading) {
                Device(image: img, width: 900, theme: t)
                    .rotationEffect(.degrees(-6))
                    .position(x: 430, y: 1900)
                Image(nsImage: crop(img, paper)).resizable().interpolation(.high)
                    .frame(width: 1000, height: 1000 * paper.height / paper.width)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 70, y: 40)
                    .rotationEffect(.degrees(4))
                    .position(x: 760, y: 1250 + 1000 * paper.height / paper.width / 2)
            }
            .frame(width: W, height: H, alignment: .topLeading)
        }
    }
}

@MainActor func render() throws {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let names = ["live", "tools", "room", "photo", "angle", "convert", "shape", "calculators", "projects", "report"]
    for (i, s) in slides.enumerated() {
        let r = ImageRenderer(content: Page(slide: s, index: i))
        r.scale = 1
        guard let cg = r.cgImage else { print("render failed", i); continue }
        let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(s.theme.dark ? CGColor(srgbRed: 0.043, green: 0.051, blue: 0.059, alpha: 1)
                                      : CGColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        let name = String(format: "%02d-%@.png", i + 1, names[i])
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
        print("wrote", name)
    }
}
try MainActor.assumeIsolated { try render() }
