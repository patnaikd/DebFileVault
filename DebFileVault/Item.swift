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
    var id: UUID
    var createdAt: Date
    var modifiedAt: Date

    // AES-256-GCM encrypted title (UTF-8 bytes)
    var encryptedTitle: Data
    // 12-byte GCM nonce for title — fresh random value generated on each save
    var titleNonce: Data

    // AES-256-GCM encrypted content (UTF-8 bytes)
    var encryptedContent: Data
    // 12-byte GCM nonce for content — fresh random value generated on each save
    var contentNonce: Data

    init(
        encryptedTitle: Data,
        titleNonce: Data,
        encryptedContent: Data,
        contentNonce: Data
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.encryptedTitle = encryptedTitle
        self.titleNonce = titleNonce
        self.encryptedContent = encryptedContent
        self.contentNonce = contentNonce
    }
}
