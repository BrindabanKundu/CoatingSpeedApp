//
//  ContentView.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 21.09.2026.
//

import UIKit
import SwiftUI
import Foundation


// =============================================================
// TARGET ANALYSIS RESULT
// =============================================================

struct TargetAnalysis {

    let thickness: Double
    let rpm: Double

    let suggestionRPM: Int

    let isInsideMeasuredRange: Bool
}


// =============================================================
// DATA PASSED TO PLOT
// =============================================================

struct PlotData: Identifiable {

    let id = UUID()

    let points: [SpinPoint]
    let regression: RegressionResult
    let statistics: [RPMStatistics]

    let target: TargetAnalysis?
}


// =============================================================
// MAIN VIEW
// =============================================================

struct ContentView: View {
    
    @StateObject private var model = SpinCalculatorModel()
    
    @State private var rpmText = "1500"
    @State private var thicknessText = "120"
    
    @State private var targetThicknessText = "100"
    
    @State private var plotData: PlotData?
    
    @State private var plotError: String?
    
    @State private var showAbout = false
    
    private let actionBlue = Color(
        red: 51 / 255,
        green: 123 / 255,
        blue: 246 / 255     //246
    )
    
    
    var body: some View {

        NavigationView {

            ScrollViewReader { proxy in

                ScrollView(
                    .vertical,
                    showsIndicators: true
                ) {

                    VStack(spacing: 6) {    //8

                        // =================================================
                        // TITLE + ABOUT BUTTON
                        // =================================================

                        HStack(spacing: 8) {

                            Text("Spin Calculator")
                                .font(.system(size: 34, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 0)

                            Button {
                                showAbout = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 25))
                                    .foregroundStyle(
                                        Color(
                                            red: 51.0 / 255.0,
                                            green: 123.0 / 255.0,
                                            blue: 246.0 / 255.0
                                        )
                                    )
                            }
                            .accessibilityLabel("About Spin Calculator")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)

                        // =================================================
                        // EXISTING CALCULATOR CONTROLS
                        // =================================================

                        inputSection
                            .padding(.bottom, 8)  //20 Extra gap after Thickness slider

                        actionButtons

                        targetSection

                        dataTable
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .top
                    )
                }

                // =================================================
                // AUTOMATICALLY SHOW NEWEST ROW
                // =================================================

                .onChange(of: model.points.count) { oldCount, newCount in

                    guard let lastID = model.points.last?.id else {
                        return
                    }

                    withAnimation {
                        proxy.scrollTo(
                            lastID,
                            anchor: .bottom
                        )
                    }
                }

                .toolbar(.hidden, for: .navigationBar)


                // =================================================
                // KEYBOARD DONE BUTTON
                // =================================================

                .toolbar {

                    ToolbarItemGroup(
                        placement: .keyboard
                    ) {

                        Spacer()

                        Button("Done") {

                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                        }
                        //.fontWeight(.semibold)
                        .font(.system(size: 17, weight: .semibold))
                    }
                }
                .navigationViewStyle(StackNavigationViewStyle())


                // =================================================
                // SLIDER → TEXT SYNCHRONIZATION
                // =================================================

                .onChange(of: model.rpm) { oldValue, newValue in
                    rpmText = "\(Int(newValue))"
                }

                .onChange(of: model.thickness) { oldValue, newValue in
                    thicknessText = "\(Int(newValue))"
                }


                // =================================================
                // PLOT SHEET
                // =================================================

                .sheet(
                    item: $plotData
                ) { data in

                    PlotView(
                        points:
                            data.points,

                        regression:
                            data.regression,

                        statistics:
                            data.statistics,

                        target:
                            data.target
                    )
                }

                // =================================================
                // ABOUT SCREEN
                // =================================================

                .sheet(isPresented: $showAbout) {
                    AboutView()
                }


                // =================================================
                // ERROR ALERT
                // =================================================

                .alert(
                    "Calculation Error",

                    isPresented: Binding(

                        get: {

                            plotError != nil
                        },

                        set: { showing in

                            if !showing {

                                plotError = nil
                            }
                        }
                    )
                ) {

                    Button("OK") {

                        plotError = nil
                    }

                } message: {

                    Text(
                        plotError
                        ?? "Unknown calculation error."
                    )
                }
            }
        }
        .navigationViewStyle(
            StackNavigationViewStyle()
        )
    }
    
    
    // =========================================================
    // INPUT SECTION
    // =========================================================
    
    private var inputSection: some View {

        VStack(spacing: -8) {       //8 // Gap between the two slider groups

            InputPanelView(
                title: "Coating Speed [rpm]",
                value: $model.rpm,
                textValue: $rpmText,
                range: 1000...6000
            )

            InputPanelView(
                title: "Thickness [nm]",
                value: $model.thickness,
                textValue: $thicknessText,
                range: 40...200
            )
        }
        //.padding(.vertical, 0)
    }
    
    
    // =========================================================
    // ADD / UPDATE / DELETE BUTTONS
    // =========================================================
    
    private var actionButtons: some View {
        
        HStack(spacing: 12) {        //6
            
            Button("Add") {
                model.addEntry()
            }
            .foregroundColor(actionBlue)
            .lineLimit(1)
            
            Button("Update") {     //"Update Selected"
                model.updateValues()
            }
            .foregroundColor(actionBlue)
            .lineLimit(1)
            //.minimumScaleFactor(0.75)
            
            Button(
                "Delete",
                role: .destructive
            ) {
                model.deleteSelected()
            }
            .lineLimit(1)
            
            Button("Plot") {
                createPlot()
            }
            .foregroundColor(actionBlue)
            .lineLimit(1)
        }
        .font(
            .system(
                size: 19,       //15, 17
                weight: .semibold
            )
        )
        .buttonStyle(.bordered)
        .padding(.bottom, 8)
    }
    
    
    // =========================================================
    // TARGET THICKNESS SECTION
    // =========================================================
    
    private var targetSection: some View {
        
        HStack(spacing: 5) {        //7
            
            Text("Target Thickness")
                .font(
                    .system(
                        size: 16,   //15
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                //.minimumScaleFactor(0.8)
            
            
            TextField(
                "100",
                text: $targetThicknessText
            )
            .font(.system(size: 16, weight: .semibold))    //17
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(width: 50)
            
            // Only numbers + one decimal separator
            .onChange(of: targetThicknessText) { oldValue, newValue in

                var filtered = ""
                var separatorUsed = false

                for character in newValue {

                    if character.isNumber {
                        filtered.append(character)

                    } else if (character == "." || character == ",")
                                && !separatorUsed {

                        filtered.append(character)
                        separatorUsed = true
                    }
                }

                if filtered != newValue {
                    targetThicknessText = filtered
                }
            }
            
            
            Text("nm")
                .font(.system(size: 16,     //15
                              weight: .semibold
                             )
                )
            
            
            Button("Target & Plot") {
                
                createTargetPlot()
            }
            .buttonStyle(.borderedProminent)
            .font(
                .system(size: 16,   //15
                        weight: .semibold
                       )
            )
            .lineLimit(1)
            //.minimumScaleFactor(0.8)
        }
        .padding(.bottom, 8)        //Vertical gap between Target Thickness and Coating Speed [rpm]
        .frame(
            maxWidth: .infinity
        )
    }
    
    
    
    // =========================================================
    // CREATE NORMAL PLOT
    // =========================================================
    
    private func createPlot() {
        
        do {
            
            let regression =
            try model
                .calculateRegression()
            
            
            let statistics =
            model
                .calculateStatistics()
            
            
            guard
                regression.slope.isFinite,
                regression.intercept.isFinite,
                regression.rpmMin.isFinite,
                regression.rpmMax.isFinite
            else {
                
                plotError =
                "Regression produced an invalid numeric value."
                
                return
            }
            
            
            plotData =
            PlotData(
                
                points:
                    model.points,
                
                regression:
                    regression,
                
                statistics:
                    statistics,
                
                target:
                    nil
            )
            
            
        } catch {
            
            plotError =
            error.localizedDescription
        }
    }
    
    
    // =========================================================
    // CREATE TARGET PLOT
    // =========================================================
    
    private func createTargetPlot() {
        
        // -----------------------------------------------------
        // Accept:
        //
        // 100.5
        // 100,5
        // -----------------------------------------------------
        
        let normalizedText =
        targetThicknessText
            .replacingOccurrences(
                of: ",",
                with: "."
            )
        
        
        guard
            let targetThickness =
                Double(
                    normalizedText
                ),
            
                targetThickness.isFinite,
            
                targetThickness > 0
        else {
            
            plotError =
            "Please enter a valid positive target thickness."
            
            return
        }
        
        
        do {
            
            // -------------------------------------------------
            // REGRESSION
            // -------------------------------------------------
            
            let regression =
            try model
                .calculateRegression()
            
            
            let statistics =
            model
                .calculateStatistics()
            
            
            guard
                regression.slope.isFinite,
                regression.intercept.isFinite
            else {
                
                plotError =
                "Regression produced an invalid numeric value."
                
                return
            }
            
            
            // -------------------------------------------------
            // ZERO SLOPE PROTECTION
            // -------------------------------------------------
            
            guard
                abs(
                    regression.slope
                )
                    >
                    1e-12
            else {
                
                plotError =
                "Target RPM cannot be calculated because the fitted slope is zero."
                
                return
            }
            
            
            // -------------------------------------------------
            // TARGET RPM
            //
            // log10(T)
            // =
            // slope * log10(RPM)
            // + intercept
            //
            // therefore:
            //
            // log10(RPM)
            // =
            // (log10(T) - intercept)
            // / slope
            // -------------------------------------------------
            
            let logTargetThickness =
            log10(
                targetThickness
            )
            
            
            let logTargetRPM =
            (
                logTargetThickness
                -
                regression.intercept
            )
            /
            regression.slope
            
            
            guard
                logTargetRPM.isFinite
            else {
                
                plotError =
                "Target RPM calculation produced an invalid value."
                
                return
            }
            
            
            let targetRPM =
            pow(
                10.0,
                logTargetRPM
            )
            
            
            guard
                targetRPM.isFinite,
                targetRPM > 0
            else {
                
                plotError =
                "The calculated target RPM is outside the numeric range."
                
                return
            }
            
            
            // -------------------------------------------------
            // MEASURED RPM RANGE
            // -------------------------------------------------
            
            let rpmValues =
            model.points
                .map(
                    \.rpm
                )
            
            
            guard
                let rpmMin =
                    rpmValues.min(),
                
                    let rpmMax =
                    rpmValues.max()
            else {
                
                plotError =
                "No coating-speed data are available."
                
                return
            }
            
            
            // -------------------------------------------------
            // ROUND TARGET RPM TO NEAREST 100
            // -------------------------------------------------
            
            let roundedRPM =
            (
                targetRPM
                /
                100.0
            )
            .rounded(
                .toNearestOrEven
            )
            *
            100.0
            
            
            guard
                roundedRPM
                    <
                    Double(
                        Int.max
                        -
                        1000
                    )
            else {
                
                plotError =
                "The calculated target RPM is too large to display."
                
                return
            }
            
            
            // -------------------------------------------------
            // SUGGESTION LOGIC
            // -------------------------------------------------
            
            let suggestionRPM: Int
            
            
            if roundedRPM
                <= rpmMin {
                
                suggestionRPM =
                Int(
                    roundedRPM
                    -
                    200.0
                )
            }
            
            
            else if roundedRPM
                        >= rpmMax {
                
                suggestionRPM =
                Int(
                    roundedRPM
                    +
                    200.0
                )
            }
            
            
            else {
                
                suggestionRPM =
                Int(
                    roundedRPM
                )
            }
            
            
            // -------------------------------------------------
            // TARGET INSIDE MEASURED RPM RANGE?
            // -------------------------------------------------
            
            let insideMeasuredRange =
            targetRPM
            >= rpmMin
            &&
            targetRPM
            <= rpmMax
            
            
            // -------------------------------------------------
            // TARGET RESULT
            // -------------------------------------------------
            
            let target =
            TargetAnalysis(
                
                thickness:
                    targetThickness,
                
                rpm:
                    targetRPM,
                
                suggestionRPM:
                    suggestionRPM,
                
                isInsideMeasuredRange:
                    insideMeasuredRange
            )
            
            
            // -------------------------------------------------
            // OPEN PLOT
            // -------------------------------------------------
            
            plotData =
            PlotData(
                
                points:
                    model.points,
                
                regression:
                    regression,
                
                statistics:
                    statistics,
                
                target:
                    target
            )
            
            
        } catch {
            
            plotError =
            error.localizedDescription
        }
    }
    
    
    // =========================================================
    // DATA TABLE
    //
    // The whole calculator screen scrolls together.
    // =========================================================

    private var dataTable: some View {

        VStack(spacing: 0) {

            // =================================================
            // TABLE HEADER
            // =================================================

            HStack(spacing: 8) {

                Text("Coating Speed [rpm]")
                    .font(
                        .system(
                            size: 17,   //17
                            weight: .semibold   //.bold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(
                        maxWidth: .infinity
                    )

                Text("Thickness [nm]")
                    .font(
                        .system(
                            size: 17,   //17
                            weight: .semibold   //.bold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(
                        maxWidth: .infinity
                    )
            }
            .padding(.vertical, 7)      //7
            .padding(.horizontal, 4)
            .background(
                Color.yellow.opacity(0.25)
            )


            Divider()


            // =================================================
            // DATA ROWS
            // =================================================

            LazyVStack(spacing: 0) {

                ForEach(
                    Array(
                        model.points.enumerated()
                    ),
                    id: \.element.id
                ) { index, point in

                    SpinDataRowView(
                        point: point,
                        index: index,
                        isSelected:
                            model.selectedID
                        == point.id
                    ) {

                        model.select(point)

                        rpmText =
                        "\(Int(point.rpm))"

                        thicknessText =
                        "\(Int(point.thickness))"
                    }
                    .id(point.id)


                    Divider()
                }
            }
            .frame(
                maxWidth: .infinity
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .top
        )
    }
}

// =============================================================
// INPUT PANEL
// =============================================================

struct InputPanelView: View {

    let title: String

    @Binding var value: Double
    @Binding var textValue: String

    let range: ClosedRange<Double>

    @FocusState private var isEditing: Bool

    var body: some View {

        VStack(spacing: 2) {       //12, 6

            // =========================================
            // TITLE AND INPUT FIELD
            // =========================================

            HStack(spacing: 12) {       //12

                Text(title)
                    .font(.system(size: 26, weight: .bold))     //22
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)       //0.85
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                TextField("", text: $textValue)
                    .font(.system(size: 22, weight: .semibold))     //22, .semibold
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)      //100
                    .focused($isEditing)

                    .onChange(of: textValue) { oldValue, newValue in

                        let digitsOnly = newValue.filter {
                            $0.isNumber
                        }

                        if digitsOnly != newValue {
                            textValue = digitsOnly
                            return
                        }

                        guard
                            !digitsOnly.isEmpty,
                            let number = Double(digitsOnly)
                        else {
                            return
                        }

                        if range.contains(number) {
                            value = number
                        }
                    }

                    .onChange(of: isEditing) { oldValue, editing in

                        if !editing {
                            finishEditing()
                        }
                    }
            }

            // =========================================
            // SLIDER BELOW THE INPUT FIELD
            // =========================================

            Slider(
                value: $value,
                in: range,
                step: 1
            )
            .tint(
                Color(
                    red: 51.0 / 255.0,
                    green: 123.0 / 255.0,
                    blue: 246.0 / 255.0
                )
            )
        }
        .padding(.vertical, 4)      //6, 2
    }

    
    // =============================================
    // FINISH INPUT EDITING
    // =============================================

    private func finishEditing() {

        guard let number = Double(textValue),
              number.isFinite else {

            textValue = String(Int(value))
            return
        }

        let clamped = min(
            max(number, range.lowerBound),
            range.upperBound
        )

        value = clamped
        textValue = String(Int(clamped))
    }
}


// =============================================================
// TABLE ROW
// =============================================================

struct SpinDataRowView: View {

    let point:
        SpinPoint

    let index:
        Int

    let isSelected:
        Bool

    let onSelect:
        () -> Void


    var body: some View {

        Button {

            onSelect()

        } label: {

            HStack {

                Text(
                    "\(Int(point.rpm))"
                )

                .frame(
                    maxWidth:
                        .infinity
                )


                Text(
                    "\(Int(point.thickness))"
                )

                .frame(
                    maxWidth:
                        .infinity
                )
            }

            .padding(
                .vertical,
                7          //10
            )

            .background(
                rowBackground
            )

            .contentShape(
                Rectangle()
            )
        }

        .buttonStyle(
            .plain
        )
    }


    // =========================================================
    // ALTERNATING ROW BACKGROUND
    // =========================================================

    private var rowBackground:
        Color {

        if isSelected {

            return
                Color.blue
                    .opacity(
                        0.25
                    )
        }


        if index % 2 == 0 {

            return
                Color.gray
                    .opacity(
                        0.12
                    )
        }


        return
            Color.clear
    }
}

//#Preview {
//    ContentView()
//}
