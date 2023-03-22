//
//  Lottie.swift
//  iOS Swiss Army Knife
//
//  Created by Vinicius Egidio on 2023-03-20.
//

import Foundation
import Lottie
import SwiftUI

public struct Lottie: UIViewRepresentable {
    private let name: String
    private let contentMode: UIView.ContentMode
    private let loopMode: LottieLoopMode

    public init(
        name: String,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        loopMode: LottieLoopMode = .loop
    ) {
        self.name = name
        self.contentMode = contentMode
        self.loopMode = loopMode
    }

    public func makeUIView(context _: UIViewRepresentableContext<Lottie>) -> UIView {
        let view = UIView(frame: .zero)
        let animationView = LottieAnimationView()
        let animation = LottieAnimation.asset(name)

        animationView.animation = animation
        animationView.contentMode = contentMode
        animationView.loopMode = loopMode
        animationView.play()
        animationView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        return view
    }

    public func updateUIView(_: UIViewType, context _: Context) {}
}
