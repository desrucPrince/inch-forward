//
//  DataModels.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//


import SwiftData
import SwiftUI

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var title: String
    var G_description: String?
    var estimatedTimeToComplete: TimeInterval?
    var createdAt: Date
    var isCompleted: Bool
    var completionDate: Date?

    // ADJUSTMENT 2: Non-optional arrays with empty defaults
    @Relationship(deleteRule: .cascade, inverse: \Move.goal)
    var moves: [Move] = []

    @Relationship(deleteRule: .cascade, inverse: \DailyProgress.goal)
    var dailyProgresses: [DailyProgress] = []

    init(id: UUID = UUID(), 
         title: String = "", 
         G_description: String? = nil, 
         estimatedTimeToComplete: TimeInterval? = nil, 
         createdAt: Date = Date(), 
         isCompleted: Bool = false,
         completionDate: Date? = nil,
         moves: [Move] = [], // Initialized as empty
         dailyProgresses: [DailyProgress] = []) { // Initialized as empty
        self.id = id
        self.title = title
        self.G_description = G_description
        self.estimatedTimeToComplete = estimatedTimeToComplete
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.moves = moves
        self.dailyProgresses = dailyProgresses
    }

    // ADJUSTMENT 4: Current Move Helper
    var todaysRecommendedMove: Move? {
        // First check if there's a specific move marked as default
        if let defaultMove = moves.first(where: { $0.isDefaultMove }) {
            return defaultMove
        }
        // Otherwise, if no specific default, return the first available move as a general recommendation
        return moves.first
    }
    
    // Additional helper that might be useful for determining if a new "today's move" needs to be set
    var lastProgressDate: Date? {
        dailyProgresses.sorted(by: { $0.date > $1.date }).first?.date
    }
}

@Model
final class Move {
    @Attribute(.unique) var id: UUID
    var title: String
    var M_description: String?
    var estimatedDuration: TimeInterval // In seconds
    var category: MoveCategory
    var isDefaultMove: Bool // Is this a primary suggested move for its goal?

    var goal: Goal?

    init(id: UUID = UUID(), 
         title: String = "", 
         M_description: String? = nil, 
         estimatedDuration: TimeInterval = 300, // Default 5 mins
         category: MoveCategory = .planning, 
         isDefaultMove: Bool = false,
         goal: Goal? = nil) {
        self.id = id
        self.title = title
        self.M_description = M_description
        self.estimatedDuration = estimatedDuration
        self.category = category
        self.isDefaultMove = isDefaultMove
        self.goal = goal
    }

    // ADJUSTMENT 3: TimeInterval Display Helper
    var displayDuration: String {
        let totalSeconds = Int(estimatedDuration)
        let minutes = totalSeconds / 60
        // let seconds = totalSeconds % 60 // If you want to show seconds too
        // For simplicity, just minutes:
        if minutes < 1 {
            return "<1 min" // Or handle very short durations differently
        }
        return "\(minutes) min"
    }
}

// MoveCategory enum remains the same
enum MoveCategory: String, CaseIterable, Codable {
    case writing, planning, organizing, learning, creating, reflecting
}

@Model
final class DailyProgress {
    @Attribute(.unique) var id: UUID
    var date: Date
    var wasSkipped: Bool
    var notes: String?
    var goal: Goal?
    var moveCompleted: Move? // This is the actual Move object that was completed

    init(id: UUID = UUID(), 
         date: Date = Date(), 
         wasSkipped: Bool = false, 
         notes: String? = nil, 
         goal: Goal? = nil, 
         moveCompleted: Move? = nil) {
        self.id = id
        self.date = date
        self.wasSkipped = wasSkipped
        self.notes = notes
        self.goal = goal
        self.moveCompleted = moveCompleted
    }
}

// AppReminderPreference struct remains unchanged - good for UserDefaults
struct AppReminderPreference: Codable {
    var enabled: Bool = true
    var preferredTimeOfDayComponents: DateComponents?
    var reminderInterval: TimeInterval? = 3600
}
