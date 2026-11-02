//
//  ShapePrint.swift
//  Plumb
//
//  A4 print page for a shape calculation: diagram, inputs, results and formulas on light paper.
//

import SwiftUI
import UIKit

struct ShapePrintPage: View {
    static let size = CGSize(width: 595, height: 842)

    var kind: ShapeKind
    var measure: CircleMeasure
    var values: [String: Double]
    var labelText: (String) -> String
    var inputs: [String]
    var results: [String]
    var formulas: [String]
    var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(kind.name) area")
                    .font(.system(size: 26, weight: .bold))
                Text(date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                    .font(.system(size: 12))
                    .foregroundStyle(PM.Colors.reportSecondary)
            }
            PM.Colors.reportRule.frame(height: 2)

            ShapeDiagramView(kind: kind, measure: measure, values: values, labelText: labelText, lineWidth: 2, inset: 48)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(PM.Colors.reportTableLine, lineWidth: 1))

            section("INPUTS", inputs)
            section("RESULTS", results)
            section("FORMULA", formulas, mono: true)

            Spacer(minLength: 0)
            Text("Calculated with Plumb. Results are estimates for planning.")
                .font(.system(size: 10))
                .foregroundStyle(PM.Colors.reportSecondary)
        }
        .foregroundStyle(PM.Colors.reportInk)
        .padding(48)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func section(_ title: String, _ lines: [String], mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(PM.Colors.reportRule)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            PM.Colors.reportTableLine.frame(height: 1)
        }
    }
}

enum ShapePrinter {
    /// One-page A4 PDF of the print page (vector text).
    static func pdf(_ page: ShapePrintPage) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: ShapePrintPage.size)
        let info: [CFString: Any] = [kCGPDFContextTitle: "\(page.kind.name) area", kCGPDFContextCreator: "Plumb"]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return nil }
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(ShapePrintPage.size)
        ctx.beginPDFPage(nil)
        renderer.render { _, draw in draw(ctx) }
        ctx.endPDFPage()
        ctx.closePDF()
        return data.length > 0 ? data as Data : nil
    }
}
