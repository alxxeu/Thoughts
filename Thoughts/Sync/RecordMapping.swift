import CloudKit

/// Как доска лежит в iCloud: приватная база, своя зона `Board`, запись на
/// каждую карточку (`Card`, recordName = UUID карточки) и на каждый из 9
/// Spaces (`Workspace`, recordName = "workspace-<slot>" — слоты
/// фиксированы, поэтому на двух Mac не появятся дубли одного Space).
///
/// Все пользовательские поля — в `encryptedValues`: они шифруются
/// end-to-end ключами из iCloud Keychain пользователя, ни Apple, ни
/// разработчик их не видят. Запросы по ним не нужны — CKSyncEngine забирает
/// изменения целиком.
enum RecordMapping {
    static let containerIdentifier = "iCloud.com.alxeu.Thoughts"
    static let zoneID = CKRecordZone.ID(zoneName: "Board", ownerName: CKCurrentUserDefaultName)

    static let cardType = "Card"
    static let workspaceType = "Workspace"
    private static let workspacePrefix = "workspace-"
    static let schemaVersion: Int64 = 1

    /// Лимит записи CloudKit — 1 МБ; с запасом под остальные поля.
    static let maxFormattingDataSize = 800_000

    // MARK: - IDs

    static func recordID(forCard id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    static func recordID(forWorkspace slot: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: workspacePrefix + String(slot), zoneID: zoneID)
    }

    enum Target: Equatable {
        case card(UUID)
        case workspace(Int)
    }

    static func target(of recordID: CKRecord.ID) -> Target? {
        let name = recordID.recordName
        if name.hasPrefix(workspacePrefix), let slot = Int(name.dropFirst(workspacePrefix.count)) {
            return .workspace(slot)
        }
        return UUID(uuidString: name).map(Target.card)
    }

    // MARK: - Card

    /// - Parameter base: запись с сохранёнными системными полями (change
    ///   tag) — без неё сервер счёл бы правку созданием новой записи.
    static func record(for card: CardRecord, base: CKRecord?) -> CKRecord {
        let record = base ?? CKRecord(recordType: cardType, recordID: recordID(forCard: card.id))
        let values = record.encryptedValues
        values["schemaVersion"] = schemaVersion
        values["workspaceSlot"] = Int64(card.workspaceSlot)
        values["text"] = card.text
        if let data = card.formattingData, data.count <= maxFormattingDataSize {
            values["formattingData"] = data
        } else {
            if card.formattingData != nil {
                print("iCloud sync: formatting of card \(card.id) is too large, sending plain text only")
            }
            values["formattingData"] = nil
        }
        values["x"] = card.x
        values["y"] = card.y
        values["width"] = card.width
        values["height"] = card.height
        values["raisedAt"] = card.raisedAt
        values["tagColor"] = card.tagColor
        values["privacyMode"] = card.privacyMode
        values["isAIGenerated"] = Int64(card.isAIGenerated ? 1 : 0)
        values["contentModifiedAt"] = card.contentModifiedAt
        values["geometryModifiedAt"] = card.geometryModifiedAt
        values["metaModifiedAt"] = card.metaModifiedAt
        return record
    }

    static func cardRecord(from record: CKRecord) -> CardRecord? {
        guard record.recordType == cardType,
              case .card(let id) = target(of: record.recordID) else { return nil }
        let values = record.encryptedValues
        guard let slot = values["workspaceSlot"] as? Int64, (1...9).contains(slot),
              let text = values["text"] as? String,
              let x = values["x"] as? Double, let y = values["y"] as? Double,
              let width = values["width"] as? Double, let height = values["height"] as? Double else {
            return nil
        }
        return CardRecord(
            id: id,
            workspaceSlot: Int(slot),
            text: text,
            formattingData: values["formattingData"] as? Data,
            x: x,
            y: y,
            width: width,
            height: height,
            raisedAt: values["raisedAt"] as? Date ?? Card.unknownDate,
            tagColor: values["tagColor"] as? String,
            privacyMode: values["privacyMode"] as? String ?? CardPrivacyMode.none.rawValue,
            isAIGenerated: (values["isAIGenerated"] as? Int64 ?? 0) != 0,
            contentModifiedAt: values["contentModifiedAt"] as? Date ?? Card.unknownDate,
            geometryModifiedAt: values["geometryModifiedAt"] as? Date ?? Card.unknownDate,
            metaModifiedAt: values["metaModifiedAt"] as? Date ?? Card.unknownDate
        )
    }

    // MARK: - Workspace

    static func record(for workspace: WorkspaceRecord, base: CKRecord?) -> CKRecord {
        let record = base ?? CKRecord(recordType: workspaceType, recordID: recordID(forWorkspace: workspace.slot))
        let values = record.encryptedValues
        values["schemaVersion"] = schemaVersion
        values["slot"] = Int64(workspace.slot)
        values["name"] = workspace.name
        values["isProtected"] = Int64(workspace.isProtected ? 1 : 0)
        values["modifiedAt"] = workspace.modifiedAt
        return record
    }

    static func workspaceRecord(from record: CKRecord) -> WorkspaceRecord? {
        guard record.recordType == workspaceType,
              case .workspace(let slot) = target(of: record.recordID), (1...9).contains(slot) else { return nil }
        let values = record.encryptedValues
        return WorkspaceRecord(
            slot: slot,
            name: values["name"] as? String ?? Workspace.defaultName(forSlot: slot),
            isProtected: (values["isProtected"] as? Int64 ?? 0) != 0,
            modifiedAt: values["modifiedAt"] as? Date ?? Card.unknownDate
        )
    }
}
