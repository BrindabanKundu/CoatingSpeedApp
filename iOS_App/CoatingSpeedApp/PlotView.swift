//
//  PlotView.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 21.09.2026.
//

import SwiftUI
import Foundation
import UIKit

// The exported image is shared as a PNG file.
private struct PlotExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PlotExportError: Identifiable {
    let id = UUID()
    let message: String
}

private struct PlotPNGShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}


struct PlotView: View {
    
    let points: [SpinPoint]
    let regression: RegressionResult
    let statistics: [RPMStatistics]
    let target: TargetAnalysis?

    // Used for a clean, full-size PNG without buttons or the current zoom.
    private let exportRendering: Bool

    init(
        points: [SpinPoint],
        regression: RegressionResult,
        statistics: [RPMStatistics],
        target: TargetAnalysis?,
        exportRendering: Bool = false
    ) {
        self.points = points
        self.regression = regression
        self.statistics = statistics
        self.target = target
        self.exportRendering = exportRendering
    }

    @State private var exportedFile: PlotExportFile?
    @State private var exportError: PlotExportError?

    @Environment(\.presentationMode)
    private var presentationMode
    
    // =========================================================
    // ZOOM / PAN STATE
    // =========================================================
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    
    private let minimumZoom: CGFloat = 1.0
    private let maximumZoom: CGFloat = 5.0
    
    // =========================================================
    // HELPERS
    // =========================================================
    
    private func finite(_ value: Double) -> Bool {
        value.isFinite
    }
    
    
    private func tickText(_ value: Double) -> String {
        
        guard value.isFinite else {
            return ""
        }
        
        if abs(value) < 1_000_000_000 {
            return "\(Int(value.rounded()))"
        }
        
        return String(
            format: "%.2g",
            value
        )
    }
    
    
    private func displayNumber(_ value: Double) -> String {
        
        guard value.isFinite else {
            return "—"
        }
        
        if abs(
            value - value.rounded()
        ) < 0.000001 {
            
            return "\(Int(value.rounded()))"
        }
        
        return String(
            format: "%.1f",
            value
        )
    }
    
    
    // =========================================================
    // DYNAMIC LABEL SPACING
    // =========================================================
    
    private func labelInterval(
        tickCount: Int,
        availableLength: CGFloat,
        minimumSpacing: CGFloat
    ) -> Int {
        
        guard tickCount > 0 else {
            return 1
        }
        
        let maximumLabelCount =
        max(
            2,
            Int(
                availableLength
                / minimumSpacing
            )
        )
        
        let interval =
        Int(
            ceil(
                Double(tickCount)
                / Double(maximumLabelCount)
            )
        )
        
        return max(
            1,
            interval
        )
    }
    
    
    // =========================================================
    // RESET ZOOM
    // =========================================================
    
    private func resetZoom() {
        
        zoomScale = 1.0
        lastZoomScale = 1.0
        
        panOffset = .zero
        lastPanOffset = .zero
    }
    
    
    // =========================================================
    // KEEP PAN INSIDE PLOT AREA
    // =========================================================
    
    private func clampedOffset(
        _ offset: CGSize,
        in size: CGSize,
        scale: CGFloat
    ) -> CGSize {
        
        guard scale > 1.0 else {
            return .zero
        }
        
        // The plot occupies the Canvas minus its original margins:
        // left 75 + right 25, top 25 + bottom 75.
        let plotWidth = max(0, size.width - 100)
        let plotHeight = max(0, size.height - 100)

        let maxX = plotWidth * (scale - 1.0) / 2.0
        let maxY = plotHeight * (scale - 1.0) / 2.0
        
        return CGSize(
            
            width:
                min(
                    max(
                        offset.width,
                        -maxX
                    ),
                    maxX
                ),
            
            height:
                min(
                    max(
                        offset.height,
                        -maxY
                    ),
                    maxY
                )
        )
    }
    
    
    // =========================================================
    // EXPORT THE FULL, UNZOOMED GRAPH AS A HIGH-RESOLUTION PNG
    // (The exported copy has no toolbar or buttons.)
    // =========================================================

    @MainActor
    private func exportPNG() {
        let imageSize = CGSize(width: 720, height: 1000)
        let printablePlot = PlotView(
            points: points,
            regression: regression,
            statistics: statistics,
            target: target,
            exportRendering: true
        )
        .frame(width: imageSize.width, height: imageSize.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let image: UIImage?
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: printablePlot)
            renderer.scale = 4.0
            renderer.proposedSize = ProposedViewSize(imageSize)
            image = renderer.uiImage
        } else {
            // Keep export available for the project's iOS 15.6 target.
            let hostingController = UIHostingController(rootView: printablePlot)
            hostingController.view.backgroundColor = .white
            hostingController.view.bounds = CGRect(origin: .zero, size: imageSize)
            hostingController.view.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = 4.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
            image = renderer.image { renderContext in
                // Snapshot the separate, unzoomed plot, never the on-screen toolbar.
                if !hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                ) {
                    hostingController.view.layer.render(in: renderContext.cgContext)
                }
            }
        }

        guard let png = image?.pngData() else {
            exportError = PlotExportError(message: "The plot image could not be generated.")
            return
        }

        do {
            let filename = "CoatingSpeedPlot_\(UUID().uuidString.prefix(8)).png"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try png.write(to: url, options: .atomic)
            exportedFile = PlotExportFile(url: url)
        } catch {
            exportError = PlotExportError(message: error.localizedDescription)
        }
    }

    // =========================================================
    // BODY
    // =========================================================
    
    var body: some View {
        
        let validPoints =
        points.filter {
            
            finite($0.rpm)
            &&
            finite($0.thickness)
            &&
            $0.rpm > 0
            &&
            $0.thickness > 0
        }
        
        
        let validStatistics =
        statistics.filter {
            
            finite($0.rpm)
            &&
            finite($0.mean)
            &&
            finite($0.std)
            &&
            $0.rpm > 0
            &&
            $0.mean > 0
            &&
            $0.std >= 0
        }
        
        
        VStack(spacing: 8) {
            
            // =================================================
            // TITLE
            // =================================================
            
            if let target {
                
                Text(
                    "Analysis — Target: "
                    + displayNumber(
                        target.thickness
                    )
                    + " nm"
                )
                //.font(.headline)
                .font(
                    .system(
                        size: 26,
                        weight: .bold
                    )
                )
                .padding(.top, 8)       //8
                
            } else {
                
                Text(
                    "Coating Speed vs Thickness"
                )
                //.font(.headline)
                .font(
                    .system(
                        size: 26,
                        weight: .bold
                    )
                )
                .padding(.top, 8)       //8
            }
            
            
            // =================================================
            // GRAPH
            // =================================================
            
            GeometryReader { geometry in
                
                ZStack {
                    
                    Canvas { context, size in
                        
                        guard
                            !validPoints.isEmpty,
                            finite(regression.slope),
                            finite(regression.intercept),
                            finite(regression.rpmMin),
                            finite(regression.rpmMax),
                            regression.rpmMin > 0,
                            regression.rpmMax >
                                regression.rpmMin
                        else {
                            return
                        }
                        
                        
                        // =================================================
                        // FITTED CURVE
                        // =================================================
                        
                        let fitCount = 300
                        
                        var fitPoints: [SpinPoint] = []
                        
                        
                        for i in 0..<fitCount {
                            
                            let fraction =
                            Double(i)
                            /
                            Double(fitCount - 1)
                            
                            
                            let rpm =
                            regression.rpmMin
                            +
                            fraction
                            *
                            (
                                regression.rpmMax
                                -
                                regression.rpmMin
                            )
                            
                            
                            guard
                                finite(rpm),
                                rpm > 0
                            else {
                                continue
                            }
                            
                            
                            let exponent =
                            regression.slope
                            *
                            log10(rpm)
                            +
                            regression.intercept
                            
                            
                            guard
                                finite(exponent)
                            else {
                                continue
                            }
                            
                            
                            let thickness =
                            pow(
                                10.0,
                                exponent
                            )
                            
                            
                            guard
                                finite(thickness),
                                thickness > 0
                            else {
                                continue
                            }
                            
                            
                            fitPoints.append(
                                SpinPoint(
                                    rpm: rpm,
                                    thickness: thickness
                                )
                            )
                        }
                        
                        
                        // =================================================
                        // RPM VALUES FOR AXIS RANGE
                        // =================================================
                        
                        var rpmValues =
                        validPoints.map(\.rpm)
                        
                        
                        if let target,
                           target.rpm.isFinite,
                           target.rpm > 0 {
                            
                            rpmValues.append(
                                target.rpm
                            )
                        }
                        
                        
                        guard
                            let rawRPMMin =
                                rpmValues.min(),
                            
                                let rawRPMMax =
                                rpmValues.max()
                        else {
                            return
                        }
                        
                        
                        // =================================================
                        // THICKNESS VALUES FOR AXIS RANGE
                        // =================================================
                        
                        var allThicknessValues =
                        validPoints.map(
                            \.thickness
                        )
                        
                        
                        allThicknessValues.append(
                            contentsOf:
                                fitPoints.map(
                                    \.thickness
                                )
                        )
                        
                        
                        for stat in validStatistics {
                            
                            let low =
                            stat.mean
                            -
                            stat.std
                            
                            
                            let high =
                            stat.mean
                            +
                            stat.std
                            
                            
                            if low.isFinite,
                               low > 0 {
                                
                                allThicknessValues.append(
                                    low
                                )
                            }
                            
                            
                            if high.isFinite,
                               high > 0 {
                                
                                allThicknessValues.append(
                                    high
                                )
                            }
                        }
                        
                        
                        if let target,
                           target.thickness.isFinite,
                           target.thickness > 0 {
                            
                            allThicknessValues.append(
                                target.thickness
                            )
                        }
                        
                        
                        guard
                            let rawThicknessMin =
                                allThicknessValues.min(),
                            
                                let rawThicknessMax =
                                allThicknessValues.max()
                        else {
                            return
                        }
                        
                        
                        // =================================================
                        // AXIS LIMITS
                        // =================================================
                        
                        let rpmAxisMin =
                        max(
                            0,
                            
                            (
                                rawRPMMin / 100.0
                            )
                            .rounded(
                                .toNearestOrEven
                            )
                            * 100.0
                            - 200.0
                        )
                        
                        
                        let rpmAxisMax =
                        (
                            rawRPMMax / 100.0
                        )
                        .rounded(
                            .toNearestOrEven
                        )
                        * 100.0
                        + 200.0
                        
                        
                        let thicknessAxisMin =
                        max(
                            0,
                            
                            (
                                rawThicknessMin / 10.0
                            )
                            .rounded(
                                .toNearestOrEven
                            )
                            * 10.0
                            - 10.0
                        )
                        
                        
                        let thicknessAxisMax =
                        (
                            rawThicknessMax / 10.0
                        )
                        .rounded(
                            .toNearestOrEven
                        )
                        * 10.0
                        + 10.0
                        
                        
                        guard
                            rpmAxisMax > rpmAxisMin,
                            thicknessAxisMax >
                                thicknessAxisMin
                        else {
                            return
                        }
                        
                        
                        // =================================================
                        // PLOT GEOMETRY
                        // =================================================
                        
                        let marginLeft: CGFloat = 75
                        let marginRight: CGFloat = 25
                        let marginTop: CGFloat = 25
                        let marginBottom: CGFloat = 75
                        
                        
                        let plotWidth =
                        size.width
                        -
                        marginLeft
                        -
                        marginRight
                        
                        
                        let plotHeight =
                        size.height
                        -
                        marginTop
                        -
                        marginBottom
                        
                        
                        guard
                            plotWidth > 0,
                            plotHeight > 0,
                            plotWidth.isFinite,
                            plotHeight.isFinite
                        else {
                            return
                        }
                        
                        
                        let rpmRange =
                        rpmAxisMax
                        -
                        rpmAxisMin
                        
                        
                        let thicknessRange =
                        thicknessAxisMax
                        -
                        thicknessAxisMin
                        
                        
                        guard
                            rpmRange.isFinite,
                            thicknessRange.isFinite,
                            rpmRange > 0,
                            thicknessRange > 0
                        else {
                            return
                        }
                        
                        
                        // =================================================
                        // DATA-COORDINATE ZOOM
                        // =================================================

                        // Change the visible RPM/thickness ranges instead of
                        // enlarging the already-rendered Canvas. Every pinch
                        // now draws fresh curves, points and text at native
                        // display resolution.
                        let scale = exportRendering
                            ? 1.0
                            : min(max(Double(zoomScale), 1.0), 5.0)
                        let visibleRPMRange = rpmRange / scale
                        let visibleThicknessRange = thicknessRange / scale

                        let horizontalPan = exportRendering
                            ? 0.0
                            : Double(panOffset.width)
                        let verticalPan = exportRendering
                            ? 0.0
                            : Double(panOffset.height)

                        let visibleRPMMin = rpmAxisMin
                            + (rpmRange - visibleRPMRange) / 2.0
                            - horizontalPan * visibleRPMRange / Double(plotWidth)
                        let visibleRPMMax = visibleRPMMin + visibleRPMRange

                        // Positive downward dragging moves the viewed data
                        // window upward in thickness coordinates.
                        let visibleThicknessMin = thicknessAxisMin
                            + (thicknessRange - visibleThicknessRange) / 2.0
                            + verticalPan * visibleThicknessRange / Double(plotHeight)
                        let visibleThicknessMax = visibleThicknessMin + visibleThicknessRange

                        guard visibleRPMMin.isFinite,
                              visibleRPMMax.isFinite,
                              visibleThicknessMin.isFinite,
                              visibleThicknessMax.isFinite,
                              visibleRPMRange > 0,
                              visibleThicknessRange > 0 else {
                            return
                        }

                        // No outer Canvas magnification now, so all of your
                        // existing, customized font and marker sizes remain
                        // unchanged on screen at every zoom level.
                        let appearanceScale: CGFloat = 1.0

                        // =================================================
                        // GRID TICK SPACING
                        // =================================================

                        // Pick human-friendly tick spacing when zoomed. At 1x
                        // the original step and tick origin are preserved.
                        func niceTickStep(_ requested: Double) -> Double {
                            guard requested.isFinite, requested > 0 else {
                                return 1
                            }
                            let power = pow(10.0, floor(log10(requested)))
                            let unit = requested / power
                            let multiple: Double
                            if unit <= 1 { multiple = 1 }
                            else if unit <= 2 { multiple = 2 }
                            else if unit <= 5 { multiple = 5 }
                            else { multiple = 10 }
                            return multiple * power
                        }

                        let rpmTickStep: Double
                        let thicknessTickStep: Double
                        let rpmTickStart: Double
                        let thicknessTickStart: Double

                        if scale <= 1.001 {
                            rpmTickStep = max(
                                200.0,
                                ceil(rpmRange / 80.0 / 200.0) * 200.0
                            )
                            thicknessTickStep = max(
                                10.0,
                                ceil(thicknessRange / 80.0 / 10.0) * 10.0
                            )
                            rpmTickStart = rpmAxisMin
                            thicknessTickStart = thicknessAxisMin
                        } else {
                            rpmTickStep = niceTickStep(
                                max(200.0 / scale, visibleRPMRange / 80.0)
                            )
                            thicknessTickStep = niceTickStep(
                                max(10.0 / scale, visibleThicknessRange / 80.0)
                            )
                            rpmTickStart = ceil(visibleRPMMin / rpmTickStep)
                                * rpmTickStep
                            thicknessTickStart = ceil(
                                visibleThicknessMin / thicknessTickStep
                            ) * thicknessTickStep
                        }

                        // A tiny tolerance avoids dropping a tick that falls
                        // exactly on the far border due to floating-point error.
                        let rpmTicks = Array(
                            stride(
                                from: rpmTickStart,
                                through: visibleRPMMax + rpmTickStep * 1e-9,
                                by: rpmTickStep
                            )
                        )
                        let thicknessTicks = Array(
                            stride(
                                from: thicknessTickStart,
                                through: visibleThicknessMax + thicknessTickStep * 1e-9,
                                by: thicknessTickStep
                            )
                        )

                        // =================================================
                        // DYNAMIC LABEL DENSITY
                        // =================================================
                        
                        let xLabelInterval =
                        labelInterval(
                            tickCount:
                                rpmTicks.count,
                            
                            availableLength:
                                plotWidth,
                            
                            minimumSpacing:
                                65
                        )
                        
                        
                        let yLabelInterval =
                        labelInterval(
                            tickCount:
                                thicknessTicks.count,
                            
                            availableLength:
                                plotHeight,
                            
                            minimumSpacing:
                                35
                        )
                        
                        
                        // =================================================
                        // DATA → SCREEN
                        // =================================================
                        
                        func pointToScreen(
                            rpm: Double,
                            thickness: Double
                        ) -> CGPoint? {
                            
                            
                            guard
                                rpm.isFinite,
                                thickness.isFinite
                            else {
                                return nil
                            }
                            
                            
                            let xFraction =
                            (
                                rpm
                                -
                                visibleRPMMin
                            )
                            /
                            visibleRPMRange
                            
                            
                            let yFraction =
                            (
                                thickness
                                -
                                visibleThicknessMin
                            )
                            /
                            visibleThicknessRange
                            
                            
                            guard
                                xFraction.isFinite,
                                yFraction.isFinite
                            else {
                                return nil
                            }
                            
                            
                            let x =
                            marginLeft
                            +
                            CGFloat(xFraction)
                            *
                            plotWidth
                            
                            
                            let y =
                            marginTop
                            +
                            plotHeight
                            -
                            CGFloat(yFraction)
                            *
                            plotHeight
                            
                            
                            guard
                                x.isFinite,
                                y.isFinite
                            else {
                                return nil
                            }
                            
                            
                            return CGPoint(
                                x: x,
                                y: y
                            )
                        }
                        
                        
                        // =================================================
                        // WHITE BACKGROUND
                        // =================================================
                        
                        context.fill(
                            
                            Path(
                                CGRect(
                                    x: 0,
                                    y: 0,
                                    width: size.width,
                                    height: size.height
                                )
                            ),
                            
                            with: .color(
                                .white
                            )
                        )
                        
                        
                        // =================================================
                        // GRID
                        // =================================================
                        
                        let gridColor =
                        Color.gray.opacity(
                            0.28
                        )
                        
                        
                        // Vertical grid lines
                        
                        for rpm in rpmTicks {
                            
                            let fraction =
                            (
                                rpm
                                -
                                visibleRPMMin
                            )
                            /
                            visibleRPMRange
                            
                            
                            let x =
                            marginLeft
                            +
                            CGFloat(fraction)
                            *
                            plotWidth
                            
                            
                            guard x.isFinite else {
                                continue
                            }
                            
                            
                            var line = Path()
                            
                            
                            line.move(
                                to: CGPoint(
                                    x: x,
                                    y: marginTop
                                )
                            )
                            
                            
                            line.addLine(
                                to: CGPoint(
                                    x: x,
                                    y:
                                        marginTop
                                    +
                                    plotHeight
                                )
                            )
                            
                            
                            context.stroke(
                                line,
                                with: .color(
                                    gridColor
                                ),
                                lineWidth: 0.7 / appearanceScale
                            )
                        }
                        
                        
                        // Horizontal grid lines
                        
                        for thickness in
                                thicknessTicks {
                            
                            let fraction =
                            (
                                thickness
                                -
                                visibleThicknessMin
                            )
                            /
                            visibleThicknessRange
                            
                            
                            let y =
                            marginTop
                            +
                            plotHeight
                            -
                            CGFloat(fraction)
                            *
                            plotHeight
                            
                            
                            guard y.isFinite else {
                                continue
                            }
                            
                            
                            var line = Path()
                            
                            
                            line.move(
                                to: CGPoint(
                                    x: marginLeft,
                                    y: y
                                )
                            )
                            
                            
                            line.addLine(
                                to: CGPoint(
                                    x:
                                        marginLeft
                                    +
                                    plotWidth,
                                    y: y
                                )
                            )
                            
                            
                            context.stroke(
                                line,
                                with: .color(
                                    gridColor
                                ),
                                lineWidth: 0.7 / appearanceScale
                            )
                        }
                        
                        
                        // =================================================
                        // AXES
                        // =================================================
                        
                        let plotRect = CGRect(
                            x: marginLeft,
                            y: marginTop,
                            width: plotWidth,
                            height: plotHeight
                        )
                        
                        let borderPath = Path(plotRect)

                        // A separate drawing context prevents points and
                        // error bars outside the zoomed viewport from spilling
                        // into the tick labels or surrounding interface.
                        var dataContext = context
                        dataContext.clip(to: borderPath)
                        
                        // Border is drawn once, after the scientific data,
                        // so it stays unobstructed while panning or zooming.
                        
                        
                        // =================================================
                        // TICK LABELS
                        // =================================================
                        
                        let tickFont =
                        Font.system(
                            size: 15 / appearanceScale,     //14
                            weight: .medium
                        )
                        
                        
                        // X-axis labels
                        
                        for (index, rpm)
                                in rpmTicks.enumerated() {
                            
                            guard
                                index
                                    %
                                    xLabelInterval
                                    ==
                                    0
                            else {
                                continue
                            }
                            
                            
                            let fraction =
                            (
                                rpm
                                -
                                visibleRPMMin
                            )
                            /
                            visibleRPMRange
                            
                            
                            let x =
                            marginLeft
                            +
                            CGFloat(fraction)
                            *
                            plotWidth
                            
                            
                            guard x.isFinite else {
                                continue
                            }
                            
                            
                            context.draw(
                                
                                Text(
                                    tickText(rpm)
                                )
                                .font(tickFont)
                                .foregroundColor(
                                    .black
                                ),
                                
                                at: CGPoint(
                                    x: x,
                                    
                                    y:
                                        marginTop
                                    +
                                    plotHeight
                                    +
                                    18
                                ),
                                
                                anchor: .top
                            )
                        }
                        
                        
                        // Y-axis labels
                        
                        for (index, thickness)
                                in thicknessTicks.enumerated() {
                            
                            guard
                                index
                                    %
                                    yLabelInterval
                                    ==
                                    0
                            else {
                                continue
                            }
                            
                            
                            let fraction =
                            (
                                thickness
                                -
                                visibleThicknessMin
                            )
                            /
                            visibleThicknessRange
                            
                            
                            let y =
                            marginTop
                            +
                            plotHeight
                            -
                            CGFloat(fraction)
                            *
                            plotHeight
                            
                            
                            guard y.isFinite else {
                                continue
                            }
                            
                            
                            context.draw(
                                
                                Text(
                                    tickText(
                                        thickness
                                    )
                                )
                                .font(tickFont)
                                .foregroundColor(
                                    .black
                                ),
                                
                                at: CGPoint(
                                    x:
                                        marginLeft
                                    -
                                    10,
                                    
                                    y: y
                                ),
                                
                                anchor: .trailing
                            )
                        }
                        
                        
                        // =================================================
                        // X-AXIS TITLE
                        // =================================================
                        
                        context.draw(
                            
                            Text(
                                "Coating speed [rpm]"
                            )
                            .font(
                                .system(
                                    size: 17 / appearanceScale,
                                    weight: .medium
                                )
                            )
                            .foregroundColor(
                                .black
                            ),
                            
                            at: CGPoint(
                                
                                x:
                                    marginLeft
                                +
                                plotWidth / 2,
                                
                                y:
                                    marginTop
                                +
                                plotHeight
                                +
                                50
                            ),
                            
                            anchor: .center
                        )
                        
                        
                        // =================================================
                        // Y-AXIS TITLE
                        // =================================================
                        
                        context.drawLayer {
                            layerContext in
                            
                            
                            let centerX:
                            CGFloat = 18
                            
                            
                            let centerY =
                            marginTop
                            +
                            plotHeight / 2
                            
                            
                            layerContext.translateBy(
                                x: centerX,
                                y: centerY
                            )
                            
                            
                            layerContext.rotate(
                                by: .degrees(-90)
                            )
                            
                            
                            layerContext.draw(
                                
                                Text(
                                    "Thickness [nm]"
                                )
                                .font(
                                    .system(
                                        size: 17 / appearanceScale,
                                        weight: .medium
                                    )
                                )
                                .foregroundColor(
                                    .black
                                ),
                                
                                at: .zero,
                                
                                anchor: .center
                            )
                        }
                        
                        
                        // =================================================
                        // FITTED CURVE
                        // =================================================
                        
                        if fitPoints.count >= 2 {
                            
                            var fitPath = Path()
                            
                            var started = false
                            
                            
                            for point in fitPoints {
                                
                                guard
                                    let p =
                                        pointToScreen(
                                            rpm:
                                                point.rpm,
                                            
                                            thickness:
                                                point.thickness
                                        )
                                else {
                                    continue
                                }
                                
                                
                                if started {
                                    
                                    fitPath.addLine(
                                        to: p
                                    )
                                    
                                } else {
                                    
                                    fitPath.move(
                                        to: p
                                    )
                                    
                                    started = true
                                }
                            }
                            
                            
                            if started {
                                
                                dataContext.stroke(
                                    
                                    fitPath,
                                    
                                    with: .color(
                                        Color.gray.opacity(
                                            0.9
                                        )
                                    ),
                                    
                                    style:
                                        StrokeStyle(
                                            lineWidth: 1.5 / appearanceScale,
                                            lineCap: .butt,
                                            lineJoin: .miter,
                                            dash: [10 / appearanceScale, 4 / appearanceScale]
                                        )
                                )
                            }
                        }
                        
                        
                        // =================================================
                        // ERROR BARS
                        //
                        // Mean square marker has been removed.
                        // =================================================
                        
                        for stat in validStatistics {
                            
                            guard
                                let topPoint =
                                    pointToScreen(
                                        rpm:
                                            stat.rpm,
                                        
                                        thickness:
                                            stat.mean
                                        +
                                        stat.std
                                    ),
                                
                                    let bottomPoint =
                                    pointToScreen(
                                        rpm:
                                            stat.rpm,
                                        
                                        thickness:
                                            max(
                                                stat.mean
                                                -
                                                stat.std,
                                                
                                                thicknessAxisMin
                                            )
                                    )
                            else {
                                continue
                            }
                            
                            
                            // Vertical error line
                            
                            var errorLine =
                            Path()
                            
                            
                            errorLine.move(
                                to: bottomPoint
                            )
                            
                            
                            errorLine.addLine(
                                to: topPoint
                            )
                            
                            
                            dataContext.stroke(
                                errorLine,
                                with: .color(
                                    Color.gray.opacity(
                                        0.9
                                    )
                                ),
                                lineWidth: 1.5 / appearanceScale
                            )
                            
                            
                            // Error-bar caps
                            
                            let capWidth:
                            CGFloat = 6 / appearanceScale
                            
                            
                            var topCap = Path()
                            
                            
                            topCap.move(
                                to: CGPoint(
                                    x:
                                        topPoint.x
                                    -
                                    capWidth,
                                    
                                    y:
                                        topPoint.y
                                )
                            )
                            
                            
                            topCap.addLine(
                                to: CGPoint(
                                    x:
                                        topPoint.x
                                    +
                                    capWidth,
                                    
                                    y:
                                        topPoint.y
                                )
                            )
                            
                            
                            dataContext.stroke(
                                topCap,
                                with: .color(
                                    Color.gray.opacity(
                                        0.9
                                    )
                                ),
                                lineWidth: 1.5 / appearanceScale
                            )
                            
                            
                            var bottomCap =
                            Path()
                            
                            
                            bottomCap.move(
                                to: CGPoint(
                                    x:
                                        bottomPoint.x
                                    -
                                    capWidth,
                                    
                                    y:
                                        bottomPoint.y
                                )
                            )
                            
                            
                            bottomCap.addLine(
                                to: CGPoint(
                                    x:
                                        bottomPoint.x
                                    +
                                    capWidth,
                                    
                                    y:
                                        bottomPoint.y
                                )
                            )
                            
                            
                            dataContext.stroke(
                                bottomCap,
                                with: .color(
                                    Color.gray.opacity(
                                        0.9
                                    )
                                ),
                                lineWidth: 1.5 / appearanceScale
                            )
                        }
                        
                        
                        // =================================================
                        // RAW EXPERIMENTAL POINTS
                        // =================================================
                        
                        for point in validPoints {
                            
                            guard
                                let p =
                                    pointToScreen(
                                        rpm:
                                            point.rpm,
                                        
                                        thickness:
                                            point.thickness
                                    )
                            else {
                                continue
                            }
                            
                            
                            // The outer Canvas is magnified by zoomScale;
                            // dividing here keeps blue markers at 10 pt.
                            let radius:
                            CGFloat = 8 / appearanceScale       //5
                            
                            
                            let circle =
                            Path(
                                ellipseIn:
                                    CGRect(
                                        x:
                                            p.x
                                        -
                                        radius,
                                        
                                        y:
                                            p.y
                                        -
                                        radius,
                                        
                                        width:
                                            radius
                                        *
                                        2,
                                        
                                        height:
                                            radius
                                        *
                                        2
                                    )
                            )
                            
                            
                            dataContext.fill(
                                circle,
                                with: .color(
                                    Color.blue.opacity(
                                        0.85
                                    )
                                )
                            )
                            
                            
                        }
                        
                        
                        // =================================================
                        // TARGET SQUARE
                        //
                        // BLACK:
                        // target thickness is within experimentally
                        // measured thickness range.
                        //
                        // RED:
                        // target thickness is outside experimentally
                        // measured thickness range.
                        // =================================================
                        
                        if let target,
                           
                            let targetPoint =
                            pointToScreen(
                                rpm:
                                    target.rpm,
                                
                                thickness:
                                    target.thickness
                            ) {
                            
                            
                            // ---------------------------------------------
                            // Experimental thickness range
                            // ---------------------------------------------
                            
                            let measuredThicknessValues =
                            validPoints.map(
                                \.thickness
                            )
                            
                            
                            let measuredThicknessMin =
                            measuredThicknessValues.min()
                            ??
                            target.thickness
                            
                            
                            let measuredThicknessMax =
                            measuredThicknessValues.max()
                            ??
                            target.thickness
                            
                            
                            // ---------------------------------------------
                            // Is target thickness inside measured range?
                            // ---------------------------------------------
                            
                            let targetInsideMeasuredThickness =
                            target.thickness
                            >=
                            measuredThicknessMin
                            &&
                            target.thickness
                            <=
                            measuredThicknessMax
                            
                            
                            // ---------------------------------------------
                            // Square color
                            // ---------------------------------------------
                            
                            let targetColor: Color =
                            targetInsideMeasuredThickness
                            ?
                                .black
                            :
                                .red
                            
                            
                            // ---------------------------------------------
                            // Draw target square
                            // ---------------------------------------------
                            
                            // Target remains 20 pt wide at every zoom level.
                            let targetSquareSize:
                            CGFloat = 10 / appearanceScale
                            
                            
                            let targetRect =
                            CGRect(
                                
                                x:
                                    targetPoint.x
                                -
                                targetSquareSize,
                                
                                y:
                                    targetPoint.y
                                -
                                targetSquareSize,
                                
                                width:
                                    targetSquareSize
                                *
                                2,
                                
                                height:
                                    targetSquareSize
                                *
                                2
                            )
                            
                            
                            let targetPath =
                            Path(
                                targetRect
                            )
                            
                            
                            dataContext.fill(
                                targetPath,
                                
                                with: .color(
                                    targetColor.opacity(
                                        0.50    //0.85
                                    )
                                )
                            )
                            
                            
                            dataContext.stroke(
                                targetPath,
                                
                                with: .color(
                                    .white
                                ),
                                
                                lineWidth: 1.5 / appearanceScale
                            )
                        }
                        
                        
                        // =================================================
                        // Restore the original full black rectangular frame.
                        context.stroke(
                            borderPath,
                            with: .color(.black),
                            lineWidth: 2.0 / appearanceScale
                        )

                        // TARGET MESSAGE
                        // =================================================
                        
                        if let target {
                            
                            let messageX =
                            marginLeft
                            +
                            plotWidth
                            -
                            10
                            
                            
                            let messageY =
                            marginTop
                            +
                            12
                            
                            
                            if target
                                .isInsideMeasuredRange {
                                
                                
                                context.draw(
                                    
                                    Text(
                                        "Coating speed = "
                                        +
                                        "\(Int(target.rpm))"
                                        +
                                        " rpm"
                                    )
                                    .font(
                                        .system(
                                            size: 20 / appearanceScale,     //16, 18
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundColor(
                                        .black
                                    ),
                                    
                                    at: CGPoint(
                                        x: messageX,
                                        y: messageY
                                    ),
                                    
                                    anchor:
                                            .topTrailing
                                )
                                
                                
                                context.draw(
                                    
                                    Text(
                                        "Thickness = "
                                        +
                                        displayNumber(
                                            target.thickness
                                        )
                                        +
                                        " nm"
                                    )
                                    .font(
                                        .system(
                                            size: 20 / appearanceScale,     //16
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundColor(
                                        .black
                                    ),
                                    
                                    at: CGPoint(
                                        x: messageX,
                                        
                                        y:
                                            messageY
                                        +
                                        36      //26
                                    ),
                                    
                                    anchor:
                                            .topTrailing
                                )
                                
                                
                            } else {
                                
                                
                                context.draw(
                                    
                                    Text(
                                        "Coat another substrate"
                                    )
                                    .font(
                                        .system(
                                            size: 20 / appearanceScale,     //16
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundColor(
                                        .red
                                    ),
                                    
                                    at: CGPoint(
                                        x: messageX,
                                        y: messageY
                                    ),
                                    
                                    anchor:
                                            .topTrailing
                                )
                                
                                
                                context.draw(
                                    
                                    Text(
                                        "with "
                                        +
                                        "\(target.suggestionRPM)"
                                        +
                                        " rpm"
                                    )
                                    .font(
                                        .system(
                                            size: 20 / appearanceScale,     //16
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundColor(
                                        .red
                                    ),
                                    
                                    at: CGPoint(
                                        x: messageX,
                                        
                                        y:
                                            messageY
                                        +
                                        30      //24
                                    ),
                                    
                                    anchor:
                                            .topTrailing
                                )
                                
                                
                                context.draw(
                                    
                                    Text(
                                        "Thickness = "
                                        +
                                        displayNumber(
                                            target.thickness
                                        )
                                        +
                                        " nm"
                                    )
                                    .font(
                                        .system(
                                            size: 20 / appearanceScale,     //16
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundColor(
                                        .red
                                    ),
                                    
                                    at: CGPoint(
                                        x: messageX,
                                        
                                        y:
                                            messageY
                                        +
                                        62      //52
                                    ),
                                    
                                    anchor:
                                            .topTrailing
                                )
                            }
                        }


                        // =================================================
                        // LEGEND
                        // =================================================

                        let legendX = marginLeft + 12 / appearanceScale
                        let legendWidth: CGFloat = 180 / appearanceScale
                        let legendRowHeight: CGFloat = 22 / appearanceScale
                        let legendPadding: CGFloat = 9 / appearanceScale
                        let legendRowCount: CGFloat = target == nil ? 3 : 4
                        let legendHeight =
                            legendPadding * 2
                            + legendRowHeight * legendRowCount
                        // Lower-left, clear of the target result at the top-right.
                        let legendY = marginTop + plotHeight
                            - legendHeight - 12 / appearanceScale

                        let legendRect = CGRect(
                            x: legendX,
                            y: legendY,
                            width: legendWidth,
                            height: legendHeight
                        )

                        let legendBackground =
                            Path(
                                roundedRect: legendRect,
                                cornerRadius: 7 / appearanceScale
                            )

                        context.fill(
                            legendBackground,
                            with: .color(
                                Color.white.opacity(0.88)
                            )
                        )

                        context.stroke(
                            legendBackground,
                            with: .color(
                                Color.gray.opacity(0.45)
                            ),
                            lineWidth: 1 / appearanceScale
                        )

                        let symbolX =
                            legendX + 16 / appearanceScale

                        let textX =
                            legendX + 34 / appearanceScale

                        let legendFont =
                            Font.system(
                                size: 15 / appearanceScale,     //13
                                weight: .medium
                            )

                        func legendRowY(_ row: Int) -> CGFloat {
                            legendY
                            + legendPadding
                            + legendRowHeight * CGFloat(row)
                            + legendRowHeight / 2
                        }

                        // Experimental data — blue circle
                        let experimentalY = legendRowY(0)
                        let experimentalRadius: CGFloat =
                            4.5 / appearanceScale

                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: symbolX - experimentalRadius,
                                    y: experimentalY - experimentalRadius,
                                    width: experimentalRadius * 2,
                                    height: experimentalRadius * 2
                                )
                            ),
                            with: .color(.blue)
                        )

                        context.draw(
                            Text("Experimental data")
                                .font(legendFont)
                                .foregroundColor(.black),
                            at: CGPoint(
                                x: textX,
                                y: experimentalY
                            ),
                            anchor: .leading
                        )

                        // Regression fit — dashed gray line
                        let fitY = legendRowY(1)
                        var legendFitLine = Path()
                        legendFitLine.move(
                            to: CGPoint(
                                x: symbolX - 9 / appearanceScale,
                                y: fitY
                            )
                        )
                        legendFitLine.addLine(
                            to: CGPoint(
                                x: symbolX + 9 / appearanceScale,
                                y: fitY
                            )
                        )

                        context.stroke(
                            legendFitLine,
                            with: .color(
                                Color.gray.opacity(0.9)
                            ),
                            style: StrokeStyle(
                                lineWidth: 1.5 / appearanceScale,
                                dash: [6 / appearanceScale, 3 / appearanceScale]
                            )
                        )

                        context.draw(
                            Text("Regression fit")
                                .font(legendFont)
                                .foregroundColor(.black),
                            at: CGPoint(
                                x: textX,
                                y: fitY
                            ),
                            anchor: .leading
                        )

                        // Mean ± standard deviation — error-bar symbol
                        let errorY = legendRowY(2)
                        let errorHalfHeight: CGFloat =
                            7 / appearanceScale
                        let errorCapHalfWidth: CGFloat =
                            5 / appearanceScale

                        var legendErrorBar = Path()
                        legendErrorBar.move(
                            to: CGPoint(
                                x: symbolX,
                                y: errorY - errorHalfHeight
                            )
                        )
                        legendErrorBar.addLine(
                            to: CGPoint(
                                x: symbolX,
                                y: errorY + errorHalfHeight
                            )
                        )
                        legendErrorBar.move(
                            to: CGPoint(
                                x: symbolX - errorCapHalfWidth,
                                y: errorY - errorHalfHeight
                            )
                        )
                        legendErrorBar.addLine(
                            to: CGPoint(
                                x: symbolX + errorCapHalfWidth,
                                y: errorY - errorHalfHeight
                            )
                        )
                        legendErrorBar.move(
                            to: CGPoint(
                                x: symbolX - errorCapHalfWidth,
                                y: errorY + errorHalfHeight
                            )
                        )
                        legendErrorBar.addLine(
                            to: CGPoint(
                                x: symbolX + errorCapHalfWidth,
                                y: errorY + errorHalfHeight
                            )
                        )

                        context.stroke(
                            legendErrorBar,
                            with: .color(
                                Color.gray.opacity(0.9)
                            ),
                            lineWidth: 1.5 / appearanceScale
                        )

                        context.draw(
                            Text("Mean ± stDev")
                                .font(legendFont)
                                .foregroundColor(.black),
                            at: CGPoint(
                                x: textX,
                                y: errorY
                            ),
                            anchor: .leading
                        )

                        // Target — square appears only for target analysis
                        if let target {
                            let targetY = legendRowY(3)

                            let measuredThicknessValues =
                                validPoints.map(\.thickness)

                            let measuredThicknessMin =
                                measuredThicknessValues.min()
                                ?? target.thickness

                            let measuredThicknessMax =
                                measuredThicknessValues.max()
                                ?? target.thickness

                            let targetInsideMeasuredThickness =
                                target.thickness >= measuredThicknessMin
                                &&
                                target.thickness <= measuredThicknessMax

                            let legendTargetColor: Color =
                                targetInsideMeasuredThickness
                                ? .black
                                : .red

                            let legendTargetHalfSize: CGFloat =
                                5 / appearanceScale

                            let legendTargetRect = CGRect(
                                x: symbolX - legendTargetHalfSize,
                                y: targetY - legendTargetHalfSize,
                                width: legendTargetHalfSize * 2,
                                height: legendTargetHalfSize * 2
                            )

                            context.fill(
                                Path(legendTargetRect),
                                with: .color(
                                    legendTargetColor.opacity(0.50)
                                )
                            )

                            context.draw(
                                Text("Target")
                                    .font(legendFont)
                                    .foregroundColor(.black),
                                at: CGPoint(
                                    x: textX,
                                    y: targetY
                                ),
                                anchor: .leading
                            )
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                // The Canvas is re-rendered using the visible data ranges.
                // Do not use scaleEffect/offset: those pixelate the plot.
                .clipped()
                .contentShape(Rectangle())

                // =================================================
                // DRAG TO PAN (only when zoomed)
                // =================================================
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoomScale > 1.0 else {
                                panOffset = .zero
                                return
                            }

                            let proposedOffset = CGSize(
                                width: lastPanOffset.width + value.translation.width,
                                height: lastPanOffset.height + value.translation.height
                            )

                            panOffset = clampedOffset(
                                proposedOffset,
                                in: geometry.size,
                                scale: zoomScale
                            )
                        }
                        .onEnded { _ in
                            lastPanOffset = panOffset
                        }
                )

                // =================================================
                // PINCH TO ZOOM
                // =================================================
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let proposedScale = lastZoomScale * value
                            let newScale = min(
                                max(proposedScale, minimumZoom),
                                maximumZoom
                            )

                            zoomScale = newScale
                            panOffset = clampedOffset(
                                lastPanOffset,
                                in: geometry.size,
                                scale: newScale
                            )
                        }
                        .onEnded { value in
                            let proposedScale = lastZoomScale * value
                            let newScale = min(
                                max(proposedScale, minimumZoom),
                                maximumZoom
                            )

                            zoomScale = newScale
                            panOffset = clampedOffset(
                                panOffset,
                                in: geometry.size,
                                scale: newScale
                            )

                            lastZoomScale = newScale
                            lastPanOffset = panOffset

                            if newScale <= 1.001 {
                                resetZoom()
                            }
                        }
                )

                // =================================================
                // DOUBLE TAP: 1× ↔ 5×
                // =================================================
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        if zoomScale < maximumZoom - 0.001 {
                            zoomScale = maximumZoom
                            lastZoomScale = maximumZoom
                            panOffset = .zero
                            lastPanOffset = .zero
                        } else {
                            resetZoom()
                        }
                    }
                }

                // =================================================
                // RESET ZOOM AFTER ROTATION
                // =================================================
                .onChange(of: geometry.size) { oldSize, newSize in
                    resetZoom()
                }

                .layoutPriority(1)
            }

            // A fixed-size, unzoomed copy is rendered only when exporting.
            .frame(
                width: exportRendering ? 720 : nil,
                height: exportRendering ? 960 : nil
            )

            // =================================================
            // EXPORT PNG + RESET ZOOM + CLOSE
            // =================================================
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !exportRendering {
                    HStack(spacing: 10) {
                        Button("Export PNG") {
                            exportPNG()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 51.0 / 255, green: 123.0 / 255, blue: 246.0 / 255))

                        Button("Reset Zoom") {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                resetZoom()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(zoomScale <= 1.001 && panOffset == .zero)

                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.system(size: 17,             //14
                                  weight: .semibold)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            .background(Color.white)
            .sheet(item: $exportedFile) { item in
                PlotPNGShareSheet(url: item.url)
            }
            .alert(item: $exportError) { error in
                Alert(
                    title: Text("Export Failed"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

