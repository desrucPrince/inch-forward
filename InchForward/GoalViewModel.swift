//
//  GoalViewModel.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//

import SwiftUI
import SwiftData
import UserNotifications // For ReminderManager

// (Your DataModels: Goal, Move, DailyProgress, MoveCategory, AppReminderPreference go here or in a separate file)
// (Your SuggestionEngine and ReminderManager classes go here or in separate files)

@MainActor // Ensure UI updates happen on the main thread
class GoalViewModel: ObservableObject {
    @Published var currentGoal: Goal?
    @Published var todaysMove: Move?
    @Published var dailyState: DailyMoveState = .loading // Start with a loading state
    @Published var alternativeMoves: [Move] = []
    @Published var isLoading: Bool = true // General loading indicator

    enum DailyMoveState {
        case loading
        case noGoal
        case pending      // No action taken today for the current move
        case completed    // Move completed today
        case skipped      // Move skipped today
        case later(Date)  // Postponed until specific time (primarily UI state)
    }

    private var modelContext: ModelContext
//    private let suggestionEngine = SuggestionEngine() // Assuming you have this
//    private let reminderManager = ReminderManager()   // Assuming you have this

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadTodaysSituation() async {
        isLoading = true
        dailyState = .loading

        // 1. Get the active goal (simplistic: first non-completed, oldest created)
        // In a real app, you might have a more sophisticated way to define "current"
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\Goal.createdAt, order: .forward)]
        )

        do {
            let goals = try modelContext.fetch(descriptor)
            currentGoal = goals.first
        } catch {
            print("Error fetching goals: \(error)")
            currentGoal = nil
            dailyState = .noGoal
            isLoading = false
            return
        }

        guard let goal = currentGoal else {
            dailyState = .noGoal
            isLoading = false
            return
        }

        // 2. Check for today's progress
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // Efficiently find today's progress for the current goal
        let todaysProgress = goal.dailyProgresses.first(where: {
            calendar.isDate($0.date, inSameDayAs: todayStart)
        })

        // 3. Determine state and move based on progress
        if let progress = todaysProgress {
            if progress.wasSkipped {
                dailyState = .skipped
                todaysMove = progress.moveCompleted // A skipped move might still have a reference to what *was* skipped
            } else if let completedMove = progress.moveCompleted {
                dailyState = .completed
                todaysMove = completedMove
            } else {
                // This case (progress entry exists but not skipped and no move) shouldn't ideally happen
                // Default to pending and try to set a move
                dailyState = .pending
                determineDefaultOrSuggestMove(for: goal)
            }
        } else {
            // No progress entry for today
            dailyState = .pending
            determineDefaultOrSuggestMove(for: goal)
        }
        isLoading = false
    }

    private func determineDefaultOrSuggestMove(for goal: Goal) {
        self.todaysMove = goal.todaysRecommendedMove // This property handles the nil case if no moves or no default
        
        refreshAlternativeMoves(for: goal, excluding: self.todaysMove)

        if self.todaysMove == nil && goal.moves.isEmpty {
             // No moves defined for the goal yet, could suggest creating one or use LLM
            // Task { await generateMoveOptions(for: goal) } // Optionally auto-generate
        }
    }

    // Helper function to refresh alternative moves
    private func refreshAlternativeMoves(for goal: Goal, excluding excludedMove: Move?) {
        self.alternativeMoves = goal.moves.filter { $0.id != excludedMove?.id }
    }

    // Helper function to record daily progress
    private func recordDailyProgress(goal: Goal, move: Move?, wasSkipped: Bool) {
        let progress = DailyProgress(date: Date(), wasSkipped: wasSkipped, goal: goal, moveCompleted: move)
        modelContext.insert(progress)
        // SwiftData auto-saves often, but explicit save can be good for critical operations
        // try? modelContext.save()
    }

    func markMoveAsDone() {
        guard let goal = currentGoal, let move = todaysMove else { return }
        recordDailyProgress(goal: goal, move: move, wasSkipped: false)
        dailyState = .completed
        // Optionally: Check if goal is completed based on some criteria
        // Optionally: Set up next day's move or clear `todaysMove` to show a "day complete" message
    }

    func markAsSkipped() {
        guard let goal = currentGoal else { return }
        recordDailyProgress(goal: goal, move: todaysMove, wasSkipped: true)
        dailyState = .skipped
    }


    func postponeMove(for interval: TimeInterval = 3600) { // Default 1 hour
        guard let move = todaysMove else { return }
//        reminderManager.scheduleReminder(for: move, in: interval)
        // UI state update, actual persistence of "postponed" is via the reminder
        // You could create a "skipped" DailyProgress entry to mark that an action was taken.
        // For simplicity, we'll just update UI state and rely on the notification.
        let postponeDate = Date().addingTimeInterval(interval)
        dailyState = .later(postponeDate) // For UI feedback
        print("Move postponed. Reminder set for \(postponeDate).")
    }

    func prepareForSwap() async {
        guard let goal = currentGoal else {
            alternativeMoves = []
            return
        }

        // Use the helper function to refresh alternatives
        refreshAlternativeMoves(for: goal, excluding: todaysMove)

        // Optionally, supplement or replace with LLM suggestions
        // This is a good place for UX decisions: always LLM? only if few existing?
        // For now, just use existing moves. If you want LLM:
        /*
        do {
            let llmSuggestions = try await suggestionEngine.generateAlternativeMoves(for: goal, currentProgress: goal.dailyProgresses, modelContext: modelContext)
            // Combine or replace:
            alternativeMoves.append(contentsOf: llmSuggestions.filter { existingAltId in !alternativeMoves.contains(where: { $0.id == existingAltId.id })})
            if alternativeMoves.isEmpty && !llmSuggestions.isEmpty {
                 todaysMove = llmSuggestions.first // If no move was set, pick first from LLM
                 alternativeMoves = Array(llmSuggestions.dropFirst())
            }
        } catch {
            print("Error generating LLM suggestions: \(error)")
        }
        */
         if alternativeMoves.isEmpty && todaysMove == nil && !goal.moves.isEmpty {
            // If no current move and alternatives became empty (e.g. only 1 move existed)
            // And there are some moves in the goal, offer them.
            alternativeMoves = goal.moves
        }
    }

    func updateTodaysMove(with newMove: Move) {
        todaysMove = newMove
        dailyState = .pending // Reset to pending as a new move is selected
        // Update alternative moves to not include the new 'todaysMove'
        if let goal = currentGoal {
            refreshAlternativeMoves(for: goal, excluding: newMove)
        }
    }
}
