//
//  GoalViewModel.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//

import SwiftUI
import SwiftData
import UserNotifications // For ReminderManager
import AIProxy // For Gemini integration

// Data Models (Goal, Move, DailyProgress, MoveCategory) are assumed to be in a separate file
// like DataModels.swift and included in the project.
// AIServiceConfig.swift is also assumed to be in the project, providing the global 'geminiService'.

// This struct is used to decode the JSON response for move suggestions from Gemini
struct GeminiMoveSuggestion: Decodable, Identifiable {
    var id = UUID() // For identifiable lists in UI before converting to a full Move object
    var title: String
    var description: String // This will map to Move.M_description
    
    // Custom decoding to handle potential JSON structure variations
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        // id is generated automatically
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, description
    }
    
    // Additional initializer for manual creation
    init(title: String, description: String) {
        self.title = title
        self.description = description
    }
}

@MainActor // Ensures UI updates happen on the main thread
class GoalViewModel: ObservableObject {
    // MARK: - Published Properties for UI Updates
    @Published var currentGoal: Goal?
    @Published var todaysMove: Move?
    @Published var dailyState: DailyMoveState = .loading // Initial state
    @Published var alternativeMoves: [Move] = [] // Persisted alternative moves for the current goal
    @Published var isLoading: Bool = true // General loading indicator for async operations

    // Properties for AI-generated suggestions
    @Published var aiSuggestions: [GeminiMoveSuggestion] = [] // Suggestions fetched from Gemini
    @Published var aiError: String? // To display errors from the AI service to the user

    // Defines the state of the daily move interaction
    enum DailyMoveState {
        case loading      // Data is being fetched
        case noGoal       // No active goal found
        case pending      // A move is selected for today, but no action (complete/skip) taken yet
        case completed    // Today's move has been marked as completed
        case skipped      // Today's move has been marked as skipped
        case later(Date)  // Move postponed until a specific time (primarily a UI state for now)
    }

    // MARK: - Private Properties
    private var modelContext: ModelContext
    // private let reminderManager = ReminderManager() // Uncomment if you have a ReminderManager class

    // The 'geminiService' instance is expected to be provided globally
    // from your AIServiceConfig.swift file.

    // MARK: - Initialization
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Initial data load can be triggered here or by the view (e.g., .task on view appearance)
        // Task { await loadTodaysSituation() }
    }

    // MARK: - Core Logic
    func loadTodaysSituation() async {
        isLoading = true
        dailyState = .loading
        aiError = nil      // Clear previous AI errors
        aiSuggestions = [] // Clear previous AI suggestions

        // Fetch the active goal (simplistic: first non-completed, oldest created)
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\Goal.createdAt, order: .forward)]
        )

        do {
            let goals = try modelContext.fetch(descriptor)
            currentGoal = goals.first
        } catch {
            print("Error fetching goals: \(error.localizedDescription)")
            currentGoal = nil // Ensure it's nil on error
            dailyState = .noGoal
            isLoading = false
            return
        }

        guard let goal = currentGoal else {
            dailyState = .noGoal
            isLoading = false
            return
        }

        // Check for today's progress for the current goal
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        let todaysProgress = goal.dailyProgresses.first(where: {
            calendar.isDate($0.date, inSameDayAs: todayStart)
        })

        // Determine state and move based on progress
        if let progress = todaysProgress {
            if progress.wasSkipped {
                dailyState = .skipped
                todaysMove = progress.moveCompleted // A skipped move might still reference what *was* skipped
            } else if let completedMove = progress.moveCompleted {
                dailyState = .completed
                todaysMove = completedMove
            } else {
                // Progress entry exists but not skipped and no move - shouldn't ideally happen
                dailyState = .pending
                await determineDefaultOrSuggestMove(for: goal)
            }
        } else {
            // No progress entry for today
            dailyState = .pending
            await determineDefaultOrSuggestMove(for: goal)
        }
        isLoading = false
    }

    private func determineDefaultOrSuggestMove(for goal: Goal) async {
        self.todaysMove = goal.todaysRecommendedMove // Uses the computed property from your Goal model

        refreshAlternativeMoves(for: goal, excluding: self.todaysMove) // Refresh alternatives based on initial todaysMove

        // If no recommended move from the goal and no moves exist at all, try to generate some
        if self.todaysMove == nil && goal.moves.isEmpty {
            print("No moves found for goal '\(goal.title)'. Attempting to generate initial suggestions...")
            await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)
            
            // Automatically adopt the first suggestion if available
            if let firstSuggestion = aiSuggestions.first {
                print("Automatically adopting first suggestion: \(firstSuggestion.title)")
                adoptAISuggestionAsNewMove(firstSuggestion, forGoal: goal, setAsTodaysMove: true)
            }
            
            // After attempting to adopt an AI suggestion, check if todaysMove is still nil.
            // This handles the case where goal.todaysRecommendedMove might have returned nil initially,
            // and we need to ensure the adopted AI move is set as the current move.
            if self.todaysMove == nil, let adoptedMove = goal.moves.first(where: { $0.title == aiSuggestions.first?.title }) {
                 self.todaysMove = adoptedMove
                 self.dailyState = .pending // Ensure the state is pending for the new move
            }
            
            // Refresh alternatives again in case a new move was adopted and set as todaysMove
            refreshAlternativeMoves(for: goal, excluding: self.todaysMove)
        }
    }

    // Helper to refresh the list of alternative persisted moves
    private func refreshAlternativeMoves(for goal: Goal, excluding excludedMove: Move?) {
        self.alternativeMoves = goal.moves.filter { $0.id != excludedMove?.id }
    }

    // Records daily progress in SwiftData
    private func recordDailyProgress(goal: Goal, move: Move?, wasSkipped: Bool) {
        let progress = DailyProgress(date: Date(), wasSkipped: wasSkipped, goal: goal, moveCompleted: move)
        modelContext.insert(progress)
        // SwiftData auto-saves. Explicit save can be used for critical operations or before UI changes
        // that depend on this save.
        // try? modelContext.save()
    }

    // MARK: - User Actions
    func markMoveAsDone() {
        guard let goal = currentGoal, let move = todaysMove else {
            print("Error: Cannot mark move as done. No current goal or move.")
            return
        }
        recordDailyProgress(goal: goal, move: move, wasSkipped: false)
        dailyState = .completed
        // Optionally: Check if goal is completed, set up next day's move, etc.
    }

    func markAsSkipped() {
        guard let goal = currentGoal else {
            print("Error: Cannot mark as skipped. No current goal.")
            return
        }
        recordDailyProgress(goal: goal, move: todaysMove, wasSkipped: true) // Pass todaysMove even if nil
        dailyState = .skipped
    }

    func postponeMove(for interval: TimeInterval = 3600) { // Default 1 hour
        guard todaysMove != nil else {
            print("Cannot postpone, no current 'todaysMove' is set.")
            return
        }
        // If using ReminderManager:
        // if let move = todaysMove {
        //     reminderManager.scheduleReminder(for: move, in: interval)
        // }
        let postponeDate = Date().addingTimeInterval(interval)
        dailyState = .later(postponeDate) // Update UI state
        print("Move postponed. Reminder set for \(postponeDate).")
    }

    // Prepares for swapping the current move, fetching AI suggestions for alternatives
    func prepareForSwap() async {
        guard let goal = currentGoal else {
            alternativeMoves = []
            aiSuggestions = [] // Clear suggestions if no goal
            return
        }
        aiError = nil      // Clear previous AI error
        aiSuggestions = [] // Clear previous suggestions before fetching new ones

        refreshAlternativeMoves(for: goal, excluding: todaysMove) // Show existing persisted alternatives

        print("Preparing for swap. Attempting to generate alternative move suggestions for goal '\(goal.title)'...")
        await generateAndProcessMoveSuggestions(for: goal, promptType: .alternativeMoves(excluding: todaysMove))
        
        // If AI fails and no other alternatives are found, and there's no current move,
        // but the goal does have some moves, offer all of them.
        if alternativeMoves.isEmpty && aiSuggestions.isEmpty && todaysMove == nil && !goal.moves.isEmpty {
            alternativeMoves = goal.moves
        }
    }

    // Called by UI to set a new move (from alternatives or adopted AI suggestion) as the current one
    func updateTodaysMove(with newMove: Move) {
        todaysMove = newMove
        dailyState = .pending // Reset to pending as a new move is selected
        if let goal = currentGoal {
            refreshAlternativeMoves(for: goal, excluding: newMove)
        }
        // self.aiSuggestions = [] // Optional: Clear AI suggestions when a manual move is picked
    }

    // MARK: - AI Integration
    
    // Processes a newly created goal with AI to format it as SMART and generate initial moves.
    func processNewGoalWithAI(_ goal: Goal) async {
        isLoading = true // Indicate that AI processing is happening
        aiError = nil    // Clear previous AI errors specific to this process
        // aiSuggestions are for move generation, not goal formatting, so no need to clear here

        // Prompt for SMART goal formatting
        let smartPromptText = "Reformat the following goal into a SMART (Specific, Measurable, Attainable, Relevant, Time-bound) goal. Provide a concise title (max 15 words) and a detailed description (max 50 words) in JSON format with 'smartTitle' and 'smartDescription' keys. Original Goal Title: \"\(goal.title)\". Original Description: \"\(goal.shortDescriptionOrDetails)\"."

        // Define the expected JSON schema for the SMART response
        let smartSchema: [String: AIProxyJSONValue] = [
            "description": "SMART formatted goal",
            "type": "object",
            "properties": [
                "smartTitle": ["type": "string", "description": "The SMART formatted title"],
                "smartDescription": ["type": "string", "description": "The SMART formatted description"]
            ],
            "required": ["smartTitle", "smartDescription"]
        ]

        let smartRequestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(smartPromptText)])],
            generationConfig: .init(
                maxOutputTokens: 256, // Adjust based on expected output length
                temperature: 0.7,
                responseMimeType: "application/json",
                responseSchema: smartSchema
            ),
             systemInstruction: .init(parts: [.text("You are a helpful assistant that reformats goals into the SMART criteria.")])
        )

        do {
            print("Sending request to Gemini for SMART formatting goal: \(goal.title)")
            let smartResponse = try await geminiService.generateContentRequest(
                body: smartRequestBody,
                model: "gemini-1.5-flash",
                secondsToWait: 30
            )

            // Process the SMART response
            if let firstCandidate = smartResponse.candidates?.first,
               let content = firstCandidate.content,
               let parts = content.parts, !parts.isEmpty {

                var jsonText = ""
                for part in parts {
                    if case .text(let text) = part {
                        jsonText += text
                    }
                }

                print("Gemini SMART response (JSON text): \(jsonText)")

                let cleanedJsonText = cleanupJsonResponse(jsonText) // Reuse existing cleanup
                let jsonData = Data(cleanedJsonText.utf8)

                struct SMARTResponse: Decodable {
                    let smartTitle: String
                    let smartDescription: String
                }

                let decoder = JSONDecoder()
                let smartGoal = try decoder.decode(SMARTResponse.self, from: jsonData)

                // Update the existing goal object with SMART details
                goal.title = smartGoal.smartTitle
                goal.G_description = smartGoal.smartDescription

                print("Successfully formatted goal to SMART: \(goal.title)")

                // Now, generate initial moves based on the SMART formatted goal
                 // Since this is a new goal, it won't have existing moves,
                 // and generateAndProcessMoveSuggestions is designed to handle this
                 // by generating new suggestions and adopting the first one.
                await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)

            } else {
                 print("No valid text part in Gemini SMART response.")
                 self.aiError = "AI did not provide valid SMART formatting suggestions."
            }
            
             // Log API usage for SMART formatting
            if let usage = smartResponse.usageMetadata {
                print("Gemini SMART Formatting API Usage: \(usage.promptTokenCount ?? 0) prompt, \(usage.cachedContentTokenCount ?? 0) cached, \(usage.candidatesTokenCount ?? 0) candidates, \(usage.totalTokenCount ?? 0) total tokens.")
            }

        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBodyString) {
            let messageToPrint = responseBodyString ?? "No response body"
            print("Gemini SMART formatting request failed. Status: \(statusCode), Body: \(messageToPrint)")
            self.aiError = "AI service error during SMART formatting (\(statusCode)). Check console for details."
        } catch {
            print("Error calling Gemini service for SMART formatting: \(error.localizedDescription)")
            self.aiError = "Could not reach AI service for SMART formatting. Details: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // Defines the type of prompt for generating move suggestions
    enum AIPromptType {
        case newMovesForGoal // For when a goal has no moves
        case alternativeMoves(excluding: Move?) // For swapping the current move
    }

    // Generates move suggestions using Gemini and processes the response
    private func generateAndProcessMoveSuggestions(for goal: Goal, promptType: AIPromptType) async {
        isLoading = true
        self.aiError = nil // Clear previous specific AI error for this call
        self.aiSuggestions = [] // Clear previous suggestions

        var promptText = ""
        let goalTitle = goal.title // From Goal model
        let goalDetails = goal.shortDescriptionOrDetails // Using extension on Goal model

        switch promptType {
        case .newMovesForGoal:
            promptText = "My current goal is: \"\(goalTitle)\". Description: \"\(goalDetails)\". Suggest 3-5 concise, actionable steps (moves) to help achieve this goal. Each move should have a short title (max 10 words) and a brief description (max 30 words)."
        case .alternativeMoves(let excludingMove):
            let exclusionText = excludingMove != nil ? " The current move is \"\(excludingMove!.title)\", so please suggest different ones." : ""
            promptText = "For the goal: \"\(goalTitle)\" (Description: \"\(goalDetails)\"), suggest 3 alternative actionable steps (moves).\(exclusionText) Each move should have a short title (max 10 words) and a brief description (max 30 words)."
        }
        promptText += " Provide the suggestions as a JSON array, where each object has 'title' and 'description' keys."

        // Define the expected JSON schema for the AI's response
        let schema: [String: AIProxyJSONValue] = [
            "description": "List of move suggestions",
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The title of the suggested move"],
                    "description": ["type": "string", "description": "A brief description of the suggested move"]
                ],
                "required": ["title", "description"]
            ]
        ]

        // Construct the request body for Gemini
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(promptText)])],
            generationConfig: .init(
                maxOutputTokens: 1024,                // Argument 'maxOutputTokens'
                temperature: 0.7, responseMimeType: "application/json", // must precede 'responseMimeType'
                responseSchema: schema                      // Temperature is usually flexible
            ),
            systemInstruction: .init(parts: [.text("You are a helpful assistant that suggests actionable steps for goals.")])
        )

        do {
            print("Sending request to Gemini for goal: \(goalTitle)")
            // 'geminiService' is the global instance from AIServiceConfig.swift
            let response = try await geminiService.generateContentRequest(
                body: requestBody,
                model: "gemini-1.5-flash", // Or "gemini-2.0-flash", etc.
                secondsToWait: 30          // Timeout for the request
            )

            // Process the response
            if let firstCandidate = response.candidates?.first,
               let content = firstCandidate.content,
               let parts = content.parts, // Assuming 'parts' is Optional [Part]? on Content
               !parts.isEmpty {
                
                // Extract JSON text from the response
                var jsonText = ""
                for part in parts {
                    if case .text(let text) = part {
                        jsonText += text
                    }
                }
                
                print("Gemini response (JSON text): \(jsonText)")
                
                // Try to clean up the JSON if it's not properly formatted
                let cleanedJsonText = cleanupJsonResponse(jsonText)
                let jsonData = Data(cleanedJsonText.utf8)
                
                let decoder = JSONDecoder()
                do {
                    // First try standard JSON array decoding
                    let suggestions = try decoder.decode([GeminiMoveSuggestion].self, from: jsonData)
                    self.aiSuggestions = suggestions
                    print("Successfully decoded \(suggestions.count) suggestions from AI.")
                } catch let decodingError {
                    print("Error decoding JSON from Gemini: \(decodingError.localizedDescription). JSON: \(cleanedJsonText)")
                    
                    // Try parsing as a different JSON structure
                    do {
                        // Some APIs might wrap the array in a container object
                        struct ResponseWrapper: Decodable {
                            let items: [GeminiMoveSuggestion]?
                            let suggestions: [GeminiMoveSuggestion]?
                            let results: [GeminiMoveSuggestion]?
                        }
                        
                        let wrapper = try decoder.decode(ResponseWrapper.self, from: jsonData)
                        let extractedSuggestions = wrapper.items ?? wrapper.suggestions ?? wrapper.results
                        
                        if let suggestions = extractedSuggestions, !suggestions.isEmpty {
                            self.aiSuggestions = suggestions
                            print("Successfully decoded \(suggestions.count) suggestions from wrapped JSON.")
                            return
                        }
                    } catch {
                        print("Also failed to decode as wrapped JSON: \(error.localizedDescription)")
                    }
                    
                    // If all JSON decoding attempts fail, try regex extraction
                    if let extractedSuggestions = extractSuggestionsFromText(jsonText) {
                        self.aiSuggestions = extractedSuggestions
                        print("Extracted \(extractedSuggestions.count) suggestions using fallback method.")
                    } else {
                        self.aiError = "Failed to understand AI suggestions. Details: \(decodingError.localizedDescription)"
                    }
                }
            } else {
                // Improved debug message for when parsing fails
                var debugMessage = "No valid text part in Gemini response."
                if response.candidates?.isEmpty ?? true {
                    debugMessage += " Candidates array was empty or nil."
                } else if response.candidates?.first?.content == nil {
                    debugMessage += " First candidate's content was nil."
                } else if response.candidates?.first?.content?.parts?.isEmpty ?? true { // parts is optional here
                    debugMessage += " First candidate's content parts array was empty or nil."
                } else {
                    debugMessage += " Response structure: \(response.candidates?.first?.content?.parts.debugDescription ?? "No parts description")"
                }
                print(debugMessage)
                self.aiError = "AI did not provide valid suggestions."
            }

            // Log API usage metadata if available
            if let usage = response.usageMetadata {
                print("Gemini API Usage: \(usage.promptTokenCount ?? 0) prompt, \(usage.cachedContentTokenCount ?? 0) cached, \(usage.candidatesTokenCount ?? 0) candidates, \(usage.totalTokenCount ?? 0) total tokens.")
            }

        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBodyString) { // Assuming responseBody is String?
            // CORRECTED: If responseBodyString is String?, use it directly or provide a default.
            let messageToPrint = responseBodyString ?? "No response body"
            print("Gemini request failed. Status: \(statusCode), Body: \(messageToPrint)")
            self.aiError = "AI service error (\(statusCode)). Check console for details."
        } catch {
            print("Error calling Gemini service: \(error.localizedDescription)")
            self.aiError = "Could not reach AI service. Details: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // Helper function to clean up JSON response that might have extra text or formatting issues
    private func cleanupJsonResponse(_ jsonText: String) -> String {
        // Try to extract just the JSON array part if there's extra text
        if let startIndex = jsonText.firstIndex(of: "["),
           let endIndex = jsonText.lastIndex(of: "]") {
            let rangeStart = jsonText.index(startIndex, offsetBy: 0)
            let rangeEnd = jsonText.index(endIndex, offsetBy: 1)
            return String(jsonText[rangeStart..<rangeEnd])
        }
        
        // If no array brackets found, check if it might be a JSON object
        if let startIndex = jsonText.firstIndex(of: "{"),
           let endIndex = jsonText.lastIndex(of: "}") {
            let rangeStart = jsonText.index(startIndex, offsetBy: 0)
            let rangeEnd = jsonText.index(endIndex, offsetBy: 1)
            return String(jsonText[rangeStart..<rangeEnd])
        }
        
        return jsonText
    }
    
    // Improved fallback method to extract suggestions if JSON parsing fails
    private func extractSuggestionsFromText(_ text: String) -> [GeminiMoveSuggestion]? {
        // Simple regex-based extraction as a fallback
        var suggestions: [GeminiMoveSuggestion] = []
        
        // First try the pattern where title comes before description
        let pattern1 = "\"title\"\\s*:\\s*\"([^\"]+)\"[^\"]*\"description\"\\s*:\\s*\"([^\"]+)\""
        // Also try the pattern where description comes before title
        let pattern2 = "\"description\"\\s*:\\s*\"([^\"]+)\"[^\"]*\"title\"\\s*:\\s*\"([^\"]+)\""
        
        do {
            // Try first pattern (title then description)
            let regex1 = try NSRegularExpression(pattern: pattern1, options: [])
            let nsString = text as NSString
            let matches1 = regex1.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches1 {
                if match.numberOfRanges >= 3 {
                    let titleRange = match.range(at: 1)
                    let descriptionRange = match.range(at: 2)
                    
                    if titleRange.location != NSNotFound && descriptionRange.location != NSNotFound {
                        let title = nsString.substring(with: titleRange)
                        let description = nsString.substring(with: descriptionRange)
                        
                        let suggestion = GeminiMoveSuggestion(title: title, description: description)
                        suggestions.append(suggestion)
                    }
                }
            }
            
            // If first pattern didn't find anything, try second pattern (description then title)
            if suggestions.isEmpty {
                let regex2 = try NSRegularExpression(pattern: pattern2, options: [])
                let matches2 = regex2.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches2 {
                    if match.numberOfRanges >= 3 {
                        let descriptionRange = match.range(at: 1)
                        let titleRange = match.range(at: 2)
                        
                        if titleRange.location != NSNotFound && descriptionRange.location != NSNotFound {
                            let title = nsString.substring(with: titleRange)
                            let description = nsString.substring(with: descriptionRange)
                            
                            let suggestion = GeminiMoveSuggestion(title: title, description: description)
                            suggestions.append(suggestion)
                        }
                    }
                }
            }
            
            // If we found suggestions, return them
            if !suggestions.isEmpty {
                return suggestions
            }
            
            // Last resort: try to find any title-like and description-like content
            // This is very lenient and might produce false positives
            let titlePattern = "\"([^\"]{3,50})\"" // Look for quoted strings that could be titles
            let titleRegex = try NSRegularExpression(pattern: titlePattern, options: [])
            let titleMatches = titleRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // If we found at least a few potential titles
            if titleMatches.count >= 2 {
                for i in 0..<min(5, titleMatches.count) {
                    let match = titleMatches[i]
                    if match.numberOfRanges >= 1 {
                        let titleRange = match.range(at: 1)
                        if titleRange.location != NSNotFound {
                            let title = nsString.substring(with: titleRange)
                            // Create a suggestion with just a title if that's all we can extract
                            let suggestion = GeminiMoveSuggestion(
                                title: title,
                                description: "Auto-generated description for \(title)"
                            )
                            suggestions.append(suggestion)
                        }
                    }
                }
            }
            
            return suggestions.isEmpty ? nil : suggestions
            
        } catch {
            print("Regex error: \(error.localizedDescription)")
            return nil
        }
    }

    // Converts a GeminiMoveSuggestion into a persisted Move object and adds it to the model context.
    func adoptAISuggestionAsNewMove(_ suggestion: GeminiMoveSuggestion, forGoal goal: Goal, setAsTodaysMove: Bool = false) {
        // Create a new Move object using the initializer from your DataModels.swift
        let newMove = Move(
            title: suggestion.title,
            M_description: suggestion.description, // Maps 'description' from AI to 'M_description' in Move
            estimatedDuration: 300, // Default from Move model, or could be part of AI suggestion
            category: .planning,    // Default category, or make this part of AI suggestion/user choice
            isDefaultMove: false,   // AI suggestions are typically not default moves initially
            goal: goal              // Associate with the current goal
        )
        
        modelContext.insert(newMove) // Add to SwiftData
        // SwiftData's @Relationship should handle adding it to goal.moves automatically if set up with inverse.
        // If goal.moves is manually managed (less common with @Relationship), you'd append here:
        // goal.moves.append(newMove)

        if setAsTodaysMove || self.todaysMove == nil {
            self.todaysMove = newMove
            self.dailyState = .pending // If a new move is adopted, it becomes pending
        }

        refreshAlternativeMoves(for: goal, excluding: self.todaysMove) // Update alternatives
        aiSuggestions.removeAll { $0.id == suggestion.id } // Remove the adopted suggestion from the list

        do {
            try modelContext.save() // Persist the new Move
            print("New move '\(newMove.title)' created from AI suggestion and saved.")
        } catch {
            print("Error saving new move from AI suggestion: \(error.localizedDescription)")
            modelContext.delete(newMove) // Rollback insertion on save error
            self.aiError = "Failed to save the new move. It has been discarded."
            // Consider re-adding to aiSuggestions or other UX for rollback
        }
    }
}

// MARK: - Extensions
// Helper extension on your Goal model to provide a description for AI prompts.
// Ensure your Goal model (from DataModels.swift) has 'G_description' property.
extension Goal {
    var shortDescriptionOrDetails: String {
        return self.G_description ?? "" // Use G_description and provide a default if nil
    }
}
