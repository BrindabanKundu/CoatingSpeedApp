//
//  SpinCalculatorModel.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 19.09.2026.
//

import Foundation
import Combine

final class SpinCalculatorModel: ObservableObject {

    // Current input values
    @Published var rpm: Double = 1500
    @Published var thickness: Double = 120

    // Entered experimental data
    @Published var points: [SpinPoint] = []

    // Currently selected table row
    @Published var selectedID: UUID?

    // MARK: - Add

    func addEntry() {

        guard rpm > 0, thickness > 0 else {
            return
        }

        points.append(
            SpinPoint(
                rpm: rpm,
                thickness: thickness
            )
        )
    }


    // MARK: - Update

    func updateValues() {

        guard rpm > 0, thickness > 0 else {
            return
        }

        if let selectedID,
           let index = points.firstIndex(
               where: { $0.id == selectedID }
           ) {

            points[index].rpm = rpm
            points[index].thickness = thickness

        } else if !points.isEmpty {

            points[points.count - 1].rpm = rpm
            points[points.count - 1].thickness = thickness

        } else {

            points.append(
                SpinPoint(
                    rpm: rpm,
                    thickness: thickness
                )
            )
        }
    }


    // MARK: - Delete

    func deleteSelected() {

        guard let selectedID else {
            return
        }

        points.removeAll {
            $0.id == selectedID
        }

        self.selectedID = nil
    }


    // MARK: - Select

    func select(_ point: SpinPoint) {

        selectedID = point.id

        rpm = point.rpm
        thickness = point.thickness
    }
}


// MARK: - Log-Log Regression

enum RegressionError: LocalizedError {

    case notEnoughData
    case invalidData
    case zeroVariance

    var errorDescription: String? {

        switch self {

        case .notEnoughData:
            return "Add at least 2 data points before calculating."

        case .invalidData:
            return "RPM and thickness must both be greater than zero."

        case .zeroVariance:
            return "Regression cannot be calculated because all RPM values are identical."
        }
    }
}


extension SpinCalculatorModel {

    func calculateRegression() throws -> RegressionResult {

        // --------------------------------------------
        // 1. Check number of data points
        // --------------------------------------------

        guard points.count >= 2 else {
            throw RegressionError.notEnoughData
        }


        // --------------------------------------------
        // 2. Check that all values are positive
        // --------------------------------------------

        guard points.allSatisfy({
            $0.rpm > 0 && $0.thickness > 0
        }) else {
            throw RegressionError.invalidData
        }


        // --------------------------------------------
        // 3. Convert to logarithmic values
        // --------------------------------------------

        let logRPM = points.map {
            log10($0.rpm)
        }

        let logThickness = points.map {
            log10($0.thickness)
        }


        // --------------------------------------------
        // 4. Calculate averages
        // --------------------------------------------

        let meanX =
            logRPM.reduce(0, +)
            / Double(logRPM.count)

        let meanY =
            logThickness.reduce(0, +)
            / Double(logThickness.count)


        // --------------------------------------------
        // 5. Calculate slope
        //
        // m = Σ[(x-x̄)(y-ȳ)] / Σ[(x-x̄)²]
        // --------------------------------------------

        let numerator = zip(logRPM, logThickness)
            .map { x, y in
                (x - meanX) * (y - meanY)
            }
            .reduce(0, +)

        let denominator = logRPM
            .map { x in
                pow(x - meanX, 2)
            }
            .reduce(0, +)


        guard denominator != 0 else {
            throw RegressionError.zeroVariance
        }

        let slope =
            numerator / denominator


        // --------------------------------------------
        // 6. Calculate intercept
        //
        // b = ȳ - m*x̄
        // --------------------------------------------

        let intercept =
            meanY - slope * meanX


        // --------------------------------------------
        // 7. Determine measured RPM range
        // --------------------------------------------

        let rpmValues =
            points.map(\.rpm)

        guard let rpmMin = rpmValues.min(),
              let rpmMax = rpmValues.max()
        else {
            throw RegressionError.notEnoughData
        }


        // --------------------------------------------
        // 8. Return result
        // --------------------------------------------

        return RegressionResult(
            slope: slope,
            intercept: intercept,
            rpmMin: rpmMin,
            rpmMax: rpmMax
        )
    }
}


// MARK: - RPM Statistics

extension SpinCalculatorModel {

    func calculateStatistics() -> [RPMStatistics] {

        // Group all measurements by RPM
        let grouped = Dictionary(
            grouping: points,
            by: { $0.rpm }
        )

        // Process RPM values in ascending order
        return grouped.keys
            .sorted()
            .map { rpm in

                let thicknessValues =
                    grouped[rpm]!
                        .map(\.thickness)

                // ----------------------------
                // Mean
                // ----------------------------

                let mean =
                    thicknessValues.reduce(0, +)
                    / Double(thicknessValues.count)


                // ----------------------------
                // Sample standard deviation
                // ----------------------------

                let std: Double

                if thicknessValues.count > 1 {

                    let squaredDifferences =
                        thicknessValues.map {
                            pow($0 - mean, 2)
                        }

                    let variance =
                        squaredDifferences.reduce(0, +)
                        / Double(thicknessValues.count - 1)

                    std = sqrt(variance)

                } else {

                    // Same behavior as Python code
                    std = 0
                }


                return RPMStatistics(
                    rpm: rpm,
                    mean: mean,
                    std: std
                )
            }
    }
}
