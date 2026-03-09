//
//  Item.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
