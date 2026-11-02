//
//  ShapesView.swift
//  Plumb
//
//  Shape Area: a grid of shapes, each opening a calculator for area and perimeter.
//

import SwiftUI

struct ShapesView: View {
    @Environment(Router.self) private var router

    private let columns = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PMTopBar(title: "Shape Area", topPadding: 0, horizontalPadding: 0, leading: {
                    IconCircleButton(icon: .back, label: "Back", stroke: 2) { router.pop() }
                }) {
                    TopBarPlaceholder()
                }
                Text("Area and perimeter for \(ShapeKind.allCases.count) shapes. Every result shows its formula.")
                    .font(.pmBody)
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Grid (not LazyVGrid) so tiles in a row share the tallest height.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: ShapeKind.allCases.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { i in
                                if start + i < ShapeKind.allCases.count {
                                    tile(ShapeKind.allCases[start + i])
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 56 + 1 - PM.Board.statusBar)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(PM.Colors.background.ignoresSafeArea())
    }

    /// The calculator's starting values, so each tile shows the shape it opens with.
    private static func defaults(_ kind: ShapeKind) -> [String: Double] {
        var out: [String: Double] = [:]
        for i in kind.inputs() { if let v = ShapeNumber.parse(i.defaultValue) { out[i.symbol] = v } }
        return out
    }

    private func tile(_ kind: ShapeKind) -> some View {
        Button { router.push(.shape(kind)) } label: {
            VStack(alignment: .center, spacing: 10) {
                ShapeDiagramView(kind: kind, values: Self.defaults(kind), lineWidth: 1.8, inset: 6, showGuides: false)
                    .frame(width: 72, height: 52)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: PM.Radius.iconWell, style: .continuous).fill(PM.Colors.iconWell))
                VStack(alignment: .center, spacing: 3) {
                    Text(kind.name)
                        .font(.pm(14, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(kind.hint)
                        .font(.pm(12))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 148, maxHeight: .infinity, alignment: .top)
            .pmCard()
        }
        .buttonStyle(.pmPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.name) area and perimeter")
        .accessibilityAddTraits(.isButton)
    }
}
