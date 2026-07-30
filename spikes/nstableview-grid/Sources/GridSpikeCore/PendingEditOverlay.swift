import Foundation

public struct PendingEditLimits: Equatable, Sendable {
  public let maximumCells: Int
  public let maximumBytes: Int

  public init(maximumCells: Int = 10_000, maximumBytes: Int = 16 * 1_024 * 1_024) throws {
    guard maximumCells > 0 else {
      throw PendingEditError.invalidLimit("maximumCells must be positive")
    }
    guard maximumBytes > 0 else {
      throw PendingEditError.invalidLimit("maximumBytes must be positive")
    }
    self.maximumCells = maximumCells
    self.maximumBytes = maximumBytes
  }
}

public enum PendingEditState: String, Equatable, Sendable {
  case pending
  case stale
}

public struct PendingEdit<Value: Sendable>: Sendable {
  public let originalValue: Value
  public let proposedValue: Value
  public let sourceVersion: UInt64
  public let state: PendingEditState

  public init(
    originalValue: Value,
    proposedValue: Value,
    sourceVersion: UInt64,
    state: PendingEditState = .pending
  ) {
    self.originalValue = originalValue
    self.proposedValue = proposedValue
    self.sourceVersion = sourceVersion
    self.state = state
  }

  public func markingStale() -> PendingEdit<Value> {
    PendingEdit(
      originalValue: originalValue,
      proposedValue: proposedValue,
      sourceVersion: sourceVersion,
      state: .stale
    )
  }
}

public struct PendingEditInventory: Equatable, Sendable {
  public let cellCount: Int
  public let byteCount: Int
  public let maximumCells: Int
  public let maximumBytes: Int
  public let rejectedAdmissionCount: UInt64
}

public enum PendingEditError: Error, Equatable, Sendable {
  case invalidLimit(String)
  case invalidByteCost(Int)
  case capacityExceeded(
    attemptedCells: Int,
    maximumCells: Int,
    attemptedBytes: Int,
    maximumBytes: Int
  )
}

/// Bounded, process-only overlay for unapplied cell edits.
///
/// This actor is intentionally independent from `BoundedPageCache`. It never
/// silently evicts an edit: admission over either limit is rejected while all
/// existing edits remain intact. This spike has no API that can apply an edit
/// to a database.
public actor PendingEditOverlay<Key: Hashable & Sendable, Value: Sendable> {
  private struct StoredEdit: Sendable {
    let edit: PendingEdit<Value>
    let byteCount: Int
  }

  private let limits: PendingEditLimits
  private let byteCost: @Sendable (PendingEdit<Value>) -> Int
  private var edits: [Key: StoredEdit] = [:]
  private var currentBytes = 0
  private var rejectedAdmissionCount: UInt64 = 0

  public init(
    limits: PendingEditLimits,
    byteCost: @escaping @Sendable (PendingEdit<Value>) -> Int
  ) {
    self.limits = limits
    self.byteCost = byteCost
  }

  public func edit(for key: Key) -> PendingEdit<Value>? {
    edits[key]?.edit
  }

  public func contains(_ key: Key) -> Bool {
    edits[key] != nil
  }

  @discardableResult
  public func set(_ edit: PendingEdit<Value>, for key: Key) throws -> PendingEditInventory {
    let newBytes = byteCost(edit)
    guard newBytes >= 0 else {
      throw PendingEditError.invalidByteCost(newBytes)
    }

    let existingBytes = edits[key]?.byteCount ?? 0
    let attemptedCells = edits[key] == nil ? edits.count + 1 : edits.count
    let attemptedBytes = currentBytes - existingBytes + newBytes
    guard attemptedCells <= limits.maximumCells, attemptedBytes <= limits.maximumBytes else {
      rejectedAdmissionCount &+= 1
      throw PendingEditError.capacityExceeded(
        attemptedCells: attemptedCells,
        maximumCells: limits.maximumCells,
        attemptedBytes: attemptedBytes,
        maximumBytes: limits.maximumBytes
      )
    }

    edits[key] = StoredEdit(edit: edit, byteCount: newBytes)
    currentBytes = attemptedBytes
    return inventory()
  }

  @discardableResult
  public func markStale(_ key: Key) -> Bool {
    guard let stored = edits[key] else {
      return false
    }
    edits[key] = StoredEdit(edit: stored.edit.markingStale(), byteCount: stored.byteCount)
    return true
  }

  @discardableResult
  public func rollback(_ key: Key) -> PendingEdit<Value>? {
    guard let removed = edits.removeValue(forKey: key) else {
      return nil
    }
    currentBytes -= removed.byteCount
    return removed.edit
  }

  public func rollbackAll() {
    edits.removeAll(keepingCapacity: false)
    currentBytes = 0
  }

  public func snapshot() -> [Key: PendingEdit<Value>] {
    edits.mapValues(\.edit)
  }

  public func inventory() -> PendingEditInventory {
    PendingEditInventory(
      cellCount: edits.count,
      byteCount: currentBytes,
      maximumCells: limits.maximumCells,
      maximumBytes: limits.maximumBytes,
      rejectedAdmissionCount: rejectedAdmissionCount
    )
  }
}
