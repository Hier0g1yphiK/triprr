//
//  Schema.swift
//  triprr
//
//  Versioned SwiftData schema and migration plan. Shipping a versioned schema
//  from the start means the out-of-scope features (accounts, sync, documents,
//  etc.) can be added later via lightweight migration without data loss.
//

import Foundation
import SwiftData

/// Version 1 of the Triprr schema: the MVP model graph.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self,
            Destination.self,
            Flight.self,
            Stay.self,
            Booking.self,
            Activity.self,
            Note.self,
            LinkItem.self,
        ]
    }
}

/// Migration plan across schema versions. Only V1 ships today; future versions
/// append stages here.
nonisolated enum TriprrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// The current schema used to build model containers.
nonisolated let currentSchema = Schema(versionedSchema: SchemaV1.self)
