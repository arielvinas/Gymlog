//
//  MaratonLiveActivityBundle.swift
//  MaratonLiveActivity (Widget Extension)
//
//  Punto de entrada de la extensión. Solo expone la Live Activity de la sesión
//  de gimnasio en vivo.
//

import WidgetKit
import SwiftUI

@main
struct MaratonLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        GuidedSessionLiveActivity()
    }
}
