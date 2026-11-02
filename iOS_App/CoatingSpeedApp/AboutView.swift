//
//  AboutView.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 26.09.2026.
//

import SwiftUI

struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    let onContinue: (() -> Void)?

    init(onContinue: (() -> Void)? = nil) {
        self.onContinue = onContinue
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "2.0"
    }

    var body: some View {

        VStack(spacing: 0) {

            // HEADER

            HStack {

                Text("About Spin Calculator")
                    .font(.system(size: 25, weight: .bold))     //24

                Spacer()

                // Show Done only when opened
                // from the information button.

                if onContinue == nil {

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)


            // ILLUSTRATION AND DESCRIPTION

            ScrollView {

                VStack(spacing: 20) {

                    Image("SpinCoatingProcess")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440)
                        .padding(.top, 20)

                    Text("Spin Coating Process")
                        .font(
                            .system(
                                size: 23,
                                weight: .semibold
                            )
                        )

                    Text(
                        "A liquid formulation is dispensed onto a rotating substrate. Centrifugal forces spread the liquid, producing a thin, uniform coating."
                    )
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                    Text("Version \(appVersion)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        }

        // START BUTTON ON WELCOME SCREEN

        .safeAreaInset(edge: .bottom, spacing: 0) {

            if let onContinue {

                Button(action: onContinue) {

                    HStack(spacing: 10) {

                        Text("Start Calculator")

                        Image(systemName: "arrow.right")
                    }
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    Color(
                        red: 51.0 / 255.0,
                        green: 123.0 / 255.0,
                        blue: 246.0 / 255.0
                    )
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Color(uiColor: .systemBackground)
                )
            }
        }

        .background(
            Color(uiColor: .systemBackground)
        )
    }
}

#Preview {
    AboutView(onContinue: {})
}
