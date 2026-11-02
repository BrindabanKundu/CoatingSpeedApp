//
//  SpinData.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 19.09.2026.
//

import Foundation

struct SpinPoint: Identifiable, Equatable {

    let id: UUID

    var rpm: Double
    var thickness: Double

    init(
        id: UUID = UUID(),
        rpm: Double,
        thickness: Double
    ) {
        self.id = id
        self.rpm = rpm
        self.thickness = thickness
    }
}

struct RPMStatistics: Identifiable {

    let id = UUID()

    let rpm: Double
    let mean: Double
    let std: Double
}

struct RegressionResult {

    let slope: Double
    let intercept: Double

    let rpmMin: Double
    let rpmMax: Double
}
