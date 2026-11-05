//
//  Device.swift
//  Plumb
//
//  The device word used in on-screen copy, so iPad users never read "your iPhone".
//

import UIKit

enum Device {
    /// "iPad" on iPad, otherwise "iPhone".
    static var name: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}
