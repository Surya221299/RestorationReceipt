//
//  SparklesAnimationView.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import SwiftUI

struct SparklesAnimationView: View {
    private let items: [SparkleConfig] = [
        SparkleConfig(size: 72, delay: 0.00, rotate: false, ax: 0.50, ay: 0.20),
        SparkleConfig(size: 28, delay: 0.70, rotate: false, ax: 0.82, ay: 0.14),
        SparkleConfig(size: 20, delay: 1.00, rotate: false, ax: 0.22, ay: 0.18),
        SparkleConfig(size: 32, delay: 0.90, rotate: false, ax: 0.55, ay: 0.78),
        SparkleConfig(size: 18, delay: 1.30, rotate: false, ax: 0.10, ay: 0.56),
        SparkleConfig(size: 24, delay: 1.10, rotate: false, ax: 0.68, ay: 0.36),
        SparkleConfig(size: 48, delay: 0.40, rotate: true,  ax: 0.16, ay: 0.44),
        SparkleConfig(size: 60, delay: 0.20, rotate: true,  ax: 0.82, ay: 0.58),
        SparkleConfig(size: 44, delay: 0.60, rotate: true,  ax: 0.20, ay: 0.74),
        SparkleConfig(size: 80, delay: 0.15, rotate: true,  ax: 0.14, ay: 0.90),
        SparkleConfig(size: 56, delay: 0.30, rotate: true,  ax: 0.80, ay: 0.82),
        SparkleConfig(size: 38, delay: 0.50, rotate: true,  ax: 0.48, ay: 0.50),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(items) { cfg in
                    SparkleItem(config: cfg)
                        .position(
                            x: geo.size.width  * cfg.ax,
                            y: geo.size.height * cfg.ay
                        )
                }
            }
        }
    }
}

// MARK: - Sparkle Config

struct SparkleConfig: Identifiable {
    let id = UUID()
    let size: CGFloat
    let delay: Double
    let rotate: Bool
    let ax: CGFloat
    let ay: CGFloat
}

// MARK: - Sparkle Item

struct SparkleItem: View {
    let config: SparkleConfig

    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = 0.0

    private var pulseDuration: Double {
        0.8 + (1.0 - Double(config.size) / 80.0) * 0.6
    }

    private var peakOpacity: Double {
        0.70 + (Double(config.size) / 80.0) * 0.30
    }

    var body: some View {
        Image(systemName: "sparkle")
            .resizable()
            .scaledToFit()
            .frame(width: config.size, height: config.size)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.97, blue: 0.40),
                        Color(red: 1.0, green: 0.72, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.yellow.opacity(0.90), radius: config.size * 0.25)
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    Animation
                        .easeInOut(duration: pulseDuration)
                        .repeatForever(autoreverses: true)
                        .delay(config.delay)
                ) {
                    scale   = 1.0
                    opacity = peakOpacity
                }

                if config.rotate {
                    let rotateDuration = 2.0 + (Double(config.size) / 60.0) * 1.0
                    withAnimation(
                        Animation
                            .linear(duration: rotateDuration)
                            .repeatForever(autoreverses: false)
                            .delay(config.delay)
                    ) {
                        rotation = 360
                    }
                }
            }
    }
}

