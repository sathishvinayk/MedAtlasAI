//  main.swift
//  SilentGlass
//  Created by Sathishvinayk on 12/07/25.
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

app.setActivationPolicy(.regular)

app.run()
