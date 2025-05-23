import SwiftUI
import SwiftData
import UserNotifications
import AIProxy
import Observation

// MARK: - Data Transfer Objects

struct GeminiMoveSuggestion: Decodable, Identifiable {
    let id = UUID()
    let title: String
    let description: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
    }
    
    init(title: String, description: String) {
        self.title = title
        self.description = description
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, description
    }
}

// MARK: - View Model

@Observable
@MainActor
final class GoalViewModel {
    // MARK: - State Properties for UI Updates
    var currentGoal: Goal?
    var todaysMove: Move?
    var dailyState: DailyMoveState = .loading
    var alternativeMoves: [Move] = []
    var isLoading: Bool = true
    var aiSuggestions: [GeminiMoveSuggestion] = []
    var aiError: String?
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext
    
    // MARK: - Enums
    
    enum DailyMoveState {
        case loading
        case noGoal
        case pending
        case completed
        case skipped
        case later(Date)
    }
    
    enum AIPromptType {
        case newMovesForGoal
        case alternativeMoves(excluding: Move?)
    }
    
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Core Logic
    
    func loadTodaysSituation() async {
        await setLoadingState(true)
        clearAIState()
        
        do {
            try await fetchCurrentGoal()
            
            guard let goal = currentGoal else {
                dailyState = .noGoal
                await setLoadingState(false)
                return
            }
            
            await processTodaysProgress(for: goal)
            
        } catch {
            print("Error loading today's situation: \(error.localizedDescription)")
            dailyState = .noGoal
        }
        
        await setLoadingState(false)
    }
    
    private func fetchCurrentGoal() async throws {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\Goal.createdAt, order: .forward)]
        )
        
        let goals = try modelContext.fetch(descriptor)
        currentGoal = goals.first
    }
    
    private func processTodaysProgress(for goal: Goal) async {
        let todaysProgress = getTodaysProgress(for: goal)
        
        if let progress = todaysProgress {
            await handleExistingProgress(progress)
        } else {
            await handleNewDay(for: goal)
        }
    }
    
    private func getTodaysProgress(for goal: Goal) -> DailyProgress? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        return goal.dailyProgresses.first { progress in
            calendar.isDate(progress.date, inSameDayAs: todayStart)
        }
    }
    
    private func handleExistingProgress(_ progress: DailyProgress) async {
        if progress.wasSkipped {
            dailyState = .skipped
            todaysMove = progress.moveCompleted
        } else if progress.moveCompleted != nil {
            // User has completed at least one move today, but let's see if they can do more
            await checkForAdditionalMoves()
        } else {
            dailyState = .pending
            await determineDefaultOrSuggestMove()
        }
    }
    
    private func handleNewDay(for goal: Goal) async {
        dailyState = .pending
        await determineDefaultOrSuggestMove()
    }
    
    private func determineDefaultOrSuggestMove() async {
        guard let goal = currentGoal else { return }
        
        todaysMove = goal.todaysRecommendedMove
        refreshAlternativeMoves(excluding: todaysMove)
        
        // Generate moves if none exist
        if todaysMove == nil && goal.moves.isEmpty {
            await generateInitialMoves(for: goal)
        }
    }
    
    private func generateInitialMoves(for goal: Goal) async {
        print("No moves found for goal '\(goal.title)'. Attempting to generate initial suggestions...")
        
        await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)
        
        // Automatically adopt first suggestion
        if let firstSuggestion = aiSuggestions.first {
            print("Automatically adopting first suggestion: \(firstSuggestion.title)")
            adoptAISuggestionAsNewMove(firstSuggestion, forGoal: goal, setAsTodaysMove: true)
        }
        
        // Ensure todaysMove is set
        if todaysMove == nil,
           let adoptedMove = goal.moves.first(where: { $0.title == aiSuggestions.first?.title }) {
            todaysMove = adoptedMove
            dailyState = .pending
        }
        
        refreshAlternativeMoves(excluding: todaysMove)
    }
    
    // MARK: - User Actions
    
    func markMoveAsDone() {
        guard let goal = currentGoal, let move = todaysMove else {
            print("Error: Cannot mark move as done. No current goal or move.")
            return
        }
        
        recordDailyProgress(goal: goal, move: move, wasSkipped: false)
        
        // Instead of setting state to completed immediately, prepare next move
        Task {
            await prepareNextMove()
        }
    }
    
    // Function to manually look for more moves when user wants to continue
    func lookForMoreMoves() async {
        await setLoadingState(true)
        await checkForAdditionalMoves()
        await setLoadingState(false)
    }
    
    // New function to prepare the next move after completion
    private func prepareNextMove() async {
        guard let goal = currentGoal else { return }
        
        // Find a different move to do next
        let completedMoveIds = getCompletedMoveIdsForToday()
        let availableMoves = goal.moves.filter { move in
            !completedMoveIds.contains(move.id)
        }
        
        if let nextMove = availableMoves.first {
            // Use an existing unfinished move
            todaysMove = nextMove
            dailyState = .pending
            refreshAlternativeMoves(excluding: nextMove)
        } else {
            // Generate new moves if all existing ones are completed
            await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)
            
            if let firstSuggestion = aiSuggestions.first {
                adoptAISuggestionAsNewMove(firstSuggestion, forGoal: goal, setAsTodaysMove: true)
            } else {
                // If AI generation fails, show completion state
                dailyState = .completed
            }
        }
    }
    
    // Helper function to get completed move IDs for today
    private func getCompletedMoveIdsForToday() -> Set<UUID> {
        guard let goal = currentGoal else { return Set() }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        let todaysProgresses = goal.dailyProgresses.filter { progress in
            calendar.isDate(progress.date, inSameDayAs: todayStart) && 
            !progress.wasSkipped && 
            progress.moveCompleted != nil
        }
        
        return Set(todaysProgresses.compactMap { $0.moveCompleted?.id })
    }
    
    // Public function to get count of completed moves today
    func getCompletedMovesCountForToday() -> Int {
        return getCompletedMoveIdsForToday().count
    }
    
    // Public function to get recent completed moves for display purposes
    func getRecentCompletedMoves(limit: Int = 3) -> [Move] {
        return Array(getLastThreeCompletedMoves().prefix(limit))
    }
    
    // Public function to get formatted completed moves summary for display
    func getCompletedMovesDisplayText(limit: Int = 3) -> String {
        let completedMoves = getRecentCompletedMoves(limit: limit)
        
        if completedMoves.isEmpty {
            return "No recent completed moves"
        }
        
        return completedMoves.enumerated().map { index, move in
            "\(index + 1). \(move.title)"
        }.joined(separator: "\n")
    }
    
    func markAsSkipped() {
        guard let goal = currentGoal else {
            print("Error: Cannot mark as skipped. No current goal.")
            return
        }
        
        recordDailyProgress(goal: goal, move: todaysMove, wasSkipped: true)
        dailyState = .skipped
    }
    
    func postponeMove(for interval: TimeInterval = 3600) {
        guard todaysMove != nil else {
            print("Cannot postpone, no current 'todaysMove' is set.")
            return
        }
        
        let postponeDate = Date().addingTimeInterval(interval)
        dailyState = .later(postponeDate)
        print("Move postponed. Reminder set for \(postponeDate).")
    }
    
    func prepareForSwap() async {
        guard let goal = currentGoal else {
            alternativeMoves = []
            aiSuggestions = []
            return
        }
        
        clearAIState()
        refreshAlternativeMoves(excluding: todaysMove)
        
        print("Preparing for swap. Attempting to generate alternative move suggestions for goal '\(goal.title)'...")
        await generateAndProcessMoveSuggestions(for: goal, promptType: .alternativeMoves(excluding: todaysMove))
        
        // Fallback to all moves if no alternatives found
        if alternativeMoves.isEmpty && aiSuggestions.isEmpty && todaysMove == nil && !goal.moves.isEmpty {
            alternativeMoves = goal.moves
        }
    }
    
    func updateTodaysMove(with newMove: Move) {
        todaysMove = newMove
        dailyState = .pending
        refreshAlternativeMoves(excluding: newMove)
    }
    
    // MARK: - AI Integration
    
    func processNewGoalWithAI(_ goal: Goal) async {
        await setLoadingState(true)
        aiError = nil
        
        await formatGoalAsSMART(goal)
        await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)
        
        await setLoadingState(false)
    }
    
    private func formatGoalAsSMART(_ goal: Goal) async {
        let currentDateContext = getCurrentDateContext()
        print("Including current date context in SMART formatting: \(Date())")
        let promptText = """
    Reformat the following goal into a SMART (Specific, Measurable, Attainable, Relevant, Time-bound) goal. 
    Provide a concise title (max 15 words) and a detailed description (max 50 words) in JSON format 
    with 'smartTitle' and 'smartDescription' keys.\(currentDateContext)
    Original Goal Title: "\(goal.title)". 
    Original Description: "\(goal.shortDescriptionOrDetails)".
    """
        
        let schema: [String: AIProxyJSONValue] = [
            "description": "SMART formatted goal",
            "type": "object",
            "properties": [
                "smartTitle": ["type": "string", "description": "The SMART formatted title"],
                "smartDescription": ["type": "string", "description": "The SMART formatted description"]
            ],
            "required": ["smartTitle", "smartDescription"]
        ]
        
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(promptText)])],
            generationConfig: .init(
                maxOutputTokens: 256,
                temperature: 0.7,
                responseMimeType: "application/json",
                responseSchema: schema
            ),
            systemInstruction: .init(parts: [.text("You are a helpful assistant that reformats goals into the SMART criteria. Always ensure time-bound elements use realistic future dates and deadlines based on the current date provided. Avoid suggesting past dates or unrealistic timelines.")])
        )
        
        do {
            print("Sending request to Gemini for SMART formatting goal: \(goal.title)")
            let response = try await geminiService.generateContentRequest(
                body: requestBody,
                model: "gemini-1.5-flash",
                secondsToWait: 30
            )
            
            await processSMARTResponse(response, for: goal)
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBodyString) {
            let message = responseBodyString
            print("Gemini SMART formatting request failed. Status: \(statusCode), Body: \(message)")
            aiError = "AI service error during SMART formatting (\(statusCode)). Check console for details."
        } catch {
            print("Error calling Gemini service for SMART formatting: \(error.localizedDescription)")
            aiError = "Could not reach AI service for SMART formatting. Details: \(error.localizedDescription)"
        }
    }
    
    private func processSMARTResponse(_ response: GeminiGenerateContentResponseBody, for goal: Goal) async {
        print("Processing SMART response for goal: \(goal.title)")
        
        guard let firstCandidate = response.candidates?.first,
              let content = firstCandidate.content,
              let parts = content.parts,
              let firstPart = parts.first else {
            print("No candidates or parts found in Gemini SMART response.")
            aiError = "AI did not provide valid SMART formatting suggestions."
            return
        }
        
        // Extract text from the part enum
        let jsonText: String
        switch firstPart {
        case .text(let text):
            jsonText = text
        case .functionCall(_, _):
            print("Unexpected function call in SMART response")
            aiError = "AI response format not supported."
            return
        case .inlineData(_, _):
            print("Unexpected inline data in SMART response")
            aiError = "AI response format not supported."
            return
        }
        
        print("Gemini SMART response (JSON text): \(jsonText)")
        
        do {
            let cleanedJsonText = cleanupJsonResponse(jsonText)
            let jsonData = Data(cleanedJsonText.utf8)
            
            struct SMARTResponse: Decodable {
                let smartTitle: String
                let smartDescription: String
            }
            
            let smartGoal = try JSONDecoder().decode(SMARTResponse.self, from: jsonData)
            
            goal.title = smartGoal.smartTitle
            goal.G_description = smartGoal.smartDescription
            
            // Save the changes
            do {
                try modelContext.save()
                print("Successfully formatted goal to SMART: \(goal.title)")
            } catch {
                print("Error saving SMART formatted goal: \(error.localizedDescription)")
            }
            
        } catch {
            print("Error decoding SMART response: \(error.localizedDescription)")
            print("Raw JSON: \(jsonText)")
            aiError = "Failed to process SMART formatting response."
        }
        
        // Log API usage
        if let usage = response.usageMetadata {
            print("Gemini SMART Formatting API Usage: \(usage.promptTokenCount ?? 0) prompt, \(usage.candidatesTokenCount ?? 0) candidates, \(usage.totalTokenCount ?? 0) total tokens.")
        }
    }
    
    private func generateAndProcessMoveSuggestions(for goal: Goal, promptType: AIPromptType) async {
        await setLoadingState(true)
        clearAIState()
        
        let promptText = createPromptText(for: goal, type: promptType)
        let schema = createMovesSuggestionsSchema()
        
        // Debug: Log completed moves context
        let completedMoves = getLastThreeCompletedMoves()
        if !completedMoves.isEmpty {
            print("Including \(completedMoves.count) completed moves in AI context: \(completedMoves.map { $0.title })")
        } else {
            print("No completed moves to include in AI context")
        }
        print("Including current date context in move suggestions: \(Date())")
        
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(promptText)])],
            generationConfig: .init(
                maxOutputTokens: 1024,
                temperature: 0.7,
                responseMimeType: "application/json",
                responseSchema: schema
            ),
            systemInstruction: .init(parts: [.text("You are a helpful assistant that suggests actionable steps for goals. Focus on creating progressive momentum by building upon completed actions and avoiding duplicates. Suggest moves that naturally advance toward the goal while being distinct from previous work.")])
        )
        
        do {
            print("Sending request to Gemini for goal: \(goal.title)")
            let response = try await geminiService.generateContentRequest(
                body: requestBody,
                model: "gemini-1.5-flash",
                secondsToWait: 30
            )
            
            await processMoveSuggestionsResponse(response)
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBodyString) {
            let message = responseBodyString
            print("Gemini request failed. Status: \(statusCode), Body: \(message)")
            aiError = "AI service error (\(statusCode)). Check console for details."
        } catch {
            print("Error calling Gemini service: \(error.localizedDescription)")
            aiError = "Could not reach AI service. Details: \(error.localizedDescription)"
        }
        
        await setLoadingState(false)
    }
    
    private func createPromptText(for goal: Goal, type: AIPromptType) -> String {
        let goalTitle = goal.title
        let goalDetails = goal.shortDescriptionOrDetails
        let completedMovesContext = formatCompletedMovesForPrompt()
        let currentDateContext = getCurrentDateContext()
        
        var promptText = ""
        
        switch type {
        case .newMovesForGoal:
            promptText = """
        My current goal is: "\(goalTitle)". Description: "\(goalDetails)".\(completedMovesContext)\(currentDateContext)
        Suggest 3-5 concise, actionable steps (moves) to help achieve this goal. 
        Each move should have a short title (max 10 words) and a brief description (max 30 words).
        """
        case .alternativeMoves(let excludingMove):
            let exclusionText = excludingMove != nil ? " The current move is \"\(excludingMove!.title)\", so please suggest different ones." : ""
            promptText = """
        For the goal: "\(goalTitle)" (Description: "\(goalDetails)"), suggest 3 alternative actionable steps (moves).\(exclusionText)\(completedMovesContext)\(currentDateContext) 
        Each move should have a short title (max 10 words) and a brief description (max 30 words).
        """
        }
        
        promptText += " Provide the suggestions as a JSON array, where each object has 'title' and 'description' keys."
        return promptText
    }
    
    private func createMovesSuggestionsSchema() -> [String: AIProxyJSONValue] {
        return [
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
    }
    
    private func processMoveSuggestionsResponse(_ response: GeminiGenerateContentResponseBody) async {
        print("Processing move suggestions response")
        
        guard let firstCandidate = response.candidates?.first,
              let content = firstCandidate.content,
              let parts = content.parts,
              let firstPart = parts.first else {
            print("No candidates or parts found in Gemini response.")
            aiError = "AI did not provide valid suggestions."
            return
        }
        
        // Extract text from the part enum
        let jsonText: String
        switch firstPart {
        case .text(let text):
            jsonText = text
        case .functionCall(_, _):
            print("Unexpected function call in move suggestions response")
            aiError = "AI response format not supported."
            return
        case .inlineData(_, _):
            print("Unexpected inline data in move suggestions response")
            aiError = "AI response format not supported."
            return
        }
        
        print("Gemini response (JSON text): \(jsonText)")
        
        do {
            let cleanedJsonText = cleanupJsonResponse(jsonText)
            let jsonData = Data(cleanedJsonText.utf8)
            let suggestions = try JSONDecoder().decode([GeminiMoveSuggestion].self, from: jsonData)
            
            aiSuggestions = suggestions
            print("Successfully decoded \(suggestions.count) suggestions from AI.")
            
        } catch {
            print("Error decoding JSON from Gemini: \(error.localizedDescription). JSON: \(jsonText)")
            
            // Fallback to text extraction
            if let extractedSuggestions = extractSuggestionsFromText(jsonText) {
                aiSuggestions = extractedSuggestions
                print("Extracted \(extractedSuggestions.count) suggestions using fallback method.")
            } else {
                aiError = "Failed to understand AI suggestions. Details: \(error.localizedDescription)"
            }
        }
        
        // Log API usage
        if let usage = response.usageMetadata {
            print("Gemini API Usage: \(usage.promptTokenCount ?? 0) prompt, \(usage.candidatesTokenCount ?? 0) candidates, \(usage.totalTokenCount ?? 0) total tokens.")
        }
    }
    
    func adoptAISuggestionAsNewMove(
        _ suggestion: GeminiMoveSuggestion,
        forGoal goal: Goal,
        setAsTodaysMove: Bool = false
    ) {
        let newMove = Move(
            title: suggestion.title,
            M_description: suggestion.description,
            estimatedDuration: 300,
            category: .planning,
            isDefaultMove: false,
            goal: goal
        )
        
        modelContext.insert(newMove)
        
        if setAsTodaysMove || todaysMove == nil {
            todaysMove = newMove
            dailyState = .pending
        }
        
        refreshAlternativeMoves(excluding: todaysMove)
        aiSuggestions.removeAll { $0.id == suggestion.id }
        
        do {
            try modelContext.save()
            print("New move '\(newMove.title)' created from AI suggestion and saved.")
        } catch {
            print("Error saving new move from AI suggestion: \(error.localizedDescription)")
            modelContext.delete(newMove)
            aiError = "Failed to save the new move. It has been discarded."
        }
    }
    
    // MARK: - Helper Methods
    
    private func setLoadingState(_ isLoading: Bool) async {
        self.isLoading = isLoading
    }
    
    private func clearAIState() {
        aiError = nil
        aiSuggestions = []
    }
    
    private func refreshAlternativeMoves(excluding excludedMove: Move?) {
        guard let goal = currentGoal else {
            alternativeMoves = []
            return
        }
        
        alternativeMoves = goal.moves.filter { $0.id != excludedMove?.id }
    }
    
    private func recordDailyProgress(goal: Goal, move: Move?, wasSkipped: Bool) {
        let progress = DailyProgress(
            date: Date(),
            wasSkipped: wasSkipped,
            goal: goal,
            moveCompleted: move
        )
        modelContext.insert(progress)
        
        do {
            try modelContext.save()
            print("Daily progress recorded successfully")
        } catch {
            print("Error saving daily progress: \(error.localizedDescription)")
        }
    }
    
    private func cleanupJsonResponse(_ jsonText: String) -> String {
        // Extract JSON array
        if let startIndex = jsonText.firstIndex(of: "["),
           let endIndex = jsonText.lastIndex(of: "]") {
            let rangeStart = jsonText.index(startIndex, offsetBy: 0)
            let rangeEnd = jsonText.index(endIndex, offsetBy: 1)
            return String(jsonText[rangeStart..<rangeEnd])
        }
        
        // Extract JSON object
        if let startIndex = jsonText.firstIndex(of: "{"),
           let endIndex = jsonText.lastIndex(of: "}") {
            let rangeStart = jsonText.index(startIndex, offsetBy: 0)
            let rangeEnd = jsonText.index(endIndex, offsetBy: 1)
            return String(jsonText[rangeStart..<rangeEnd])
        }
        
        return jsonText
    }
    
    private func extractSuggestionsFromText(_ text: String) -> [GeminiMoveSuggestion]? {
        var suggestions: [GeminiMoveSuggestion] = []
        
        let pattern1 = "\"title\"\\s*:\\s*\"([^\"]+)\"[^\"]*\"description\"\\s*:\\s*\"([^\"]+)\""
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
                        suggestions.append(GeminiMoveSuggestion(title: title, description: description))
                    }
                }
            }
            
            // Try second pattern if first failed
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
                            suggestions.append(GeminiMoveSuggestion(title: title, description: description))
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
    
    // New function to check if user can do additional moves after completing some
    private func checkForAdditionalMoves() async {
        guard let goal = currentGoal else { 
            dailyState = .completed
            return 
        }
        
        let completedMoveIds = getCompletedMoveIdsForToday()
        let availableMoves = goal.moves.filter { move in
            !completedMoveIds.contains(move.id)
        }
        
        if let nextMove = availableMoves.first {
            // There are more moves available
            todaysMove = nextMove
            dailyState = .pending
            refreshAlternativeMoves(excluding: nextMove)
        } else if !goal.moves.isEmpty {
            // All existing moves completed, try to generate new ones
            await generateAndProcessMoveSuggestions(for: goal, promptType: .newMovesForGoal)
            
            if let firstSuggestion = aiSuggestions.first {
                adoptAISuggestionAsNewMove(firstSuggestion, forGoal: goal, setAsTodaysMove: true)
            } else {
                // Show completion state only if we can't generate new moves
                dailyState = .completed
                // Set todaysMove to the last completed move for display purposes
                let lastCompleted = getLastCompletedMoveForToday()
                todaysMove = lastCompleted
            }
        } else {
            // No moves exist and generation failed/not attempted
            dailyState = .completed
            let lastCompleted = getLastCompletedMoveForToday()
            todaysMove = lastCompleted
        }
    }
    
    // Helper function to get the last completed move for today (for display in completion view)
    private func getLastCompletedMoveForToday() -> Move? {
        guard let goal = currentGoal else { return nil }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        let todaysProgresses = goal.dailyProgresses
            .filter { progress in
                calendar.isDate(progress.date, inSameDayAs: todayStart) && 
                !progress.wasSkipped && 
                progress.moveCompleted != nil
            }
            .sorted { $0.date > $1.date } // Most recent first
        
        return todaysProgresses.first?.moveCompleted
    }
    
    // MARK: - Completed Moves Tracking for AI Context
    
    // Get the last three completed moves across all days for AI context
    private func getLastThreeCompletedMoves() -> [Move] {
        guard let goal = currentGoal else { return [] }
        
        let completedProgresses = goal.dailyProgresses
            .filter { progress in
                !progress.wasSkipped && progress.moveCompleted != nil
            }
            .sorted { $0.date > $1.date } // Most recent first
        
        let lastThreeMoves = Array(completedProgresses.prefix(3))
            .compactMap { $0.moveCompleted }
        
        return lastThreeMoves
    }
    
    // Format completed moves for AI prompt context
    private func formatCompletedMovesForPrompt() -> String {
        let completedMoves = getLastThreeCompletedMoves()
        let existingMoves = getCurrentExistingMoves()
        
        var contextText = ""
        
        if !completedMoves.isEmpty {
            let movesText = completedMoves.enumerated().map { index, move in
                let moveTitle = move.title
                let moveDescription = move.M_description ?? "No description"
                return "\(index + 1). \"\(moveTitle)\" - \(moveDescription)"
            }.joined(separator: "\n")
            
            contextText += """
            
            Recent completed moves (most recent first):
            \(movesText)
            """
        }
        
        if !existingMoves.isEmpty {
            let existingMovesText = existingMoves.enumerated().map { index, move in
                let moveTitle = move.title
                return "\(index + 1). \"\(moveTitle)\""
            }.joined(separator: "\n")
            
            contextText += """
            
            Existing moves already available:
            \(existingMovesText)
            """
        }
        
        if !contextText.isEmpty {
            contextText += """
            
            Please suggest moves that build upon completed actions, create momentum toward the goal, and avoid duplicating existing moves.
            """
        }
        
        return contextText
    }
    
    // Get current existing moves for the goal
    private func getCurrentExistingMoves() -> [Move] {
        guard let goal = currentGoal else { return [] }
        return goal.moves
    }
    
    // MARK: - Date Context for AI
    
    // Get current date context for AI prompts
    private func getCurrentDateContext() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        let currentDateString = formatter.string(from: Date())
        
        return """
        
        Current date: \(currentDateString)
        Please ensure all dates, timelines, and deadlines are realistic and in the future relative to this current date.
        """
    }
    
    // MARK: - Move Detail Level Adjustment
    
    // Generate adjusted move based on detail level
    func adjustMoveDetailLevel(_ move: Move, to level: MoveDetailLevel) async {
        await setLoadingState(true)
        clearAIState()
        
        guard let goal = currentGoal else {
            await setLoadingState(false)
            return
        }
        
        let adjustedMovePrompt = createMoveAdjustmentPrompt(move: move, level: level, goal: goal)
        let schema = createMoveAdjustmentSchema()
        
        print("Adjusting move detail level to: \(level.title)")
        
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(adjustedMovePrompt)])],
            generationConfig: .init(
                maxOutputTokens: 512,
                temperature: 0.7,
                responseMimeType: "application/json",
                responseSchema: schema
            ),
            systemInstruction: .init(parts: [.text("You are a helpful assistant that adjusts task detail levels. Provide appropriate detail based on the requested level while maintaining the core objective.")])
        )
        
        do {
            let response = try await geminiService.generateContentRequest(
                body: requestBody,
                model: "gemini-1.5-flash",
                secondsToWait: 30
            )
            
            await processAdjustedMoveResponse(response, for: move, level: level)
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBodyString) {
            print("Move adjustment request failed. Status: \(statusCode), Body: \(responseBodyString)")
            aiError = "Failed to adjust move detail level (\(statusCode))"
        } catch {
            print("Error adjusting move detail level: \(error.localizedDescription)")
            aiError = "Could not adjust move detail level. Details: \(error.localizedDescription)"
        }
        
        await setLoadingState(false)
    }
    
    private func createMoveAdjustmentPrompt(move: Move, level: MoveDetailLevel, goal: Goal) -> String {
        let currentDateContext = getCurrentDateContext()
        let originalTitle = move.title
        let originalDescription = move.M_description ?? ""
        let originalDuration = move.estimatedDuration
        
        let levelInstructions: String
        switch level {
        case .vague:
            levelInstructions = "Make this move very high-level and less overwhelming. Remove specific details and keep it simple and broad. Reduce time estimate."
        case .concise:
            levelInstructions = "Make this move brief and focused. Keep essential details but remove complexity. Slightly reduce time estimate."
        case .detailed:
            levelInstructions = "Keep the current level of detail as is, but ensure it's realistic and well-structured."
        case .granular:
            levelInstructions = "Break this move into more specific, actionable steps. Add helpful details and increase time estimate to be more realistic."
        case .stepByStep:
            levelInstructions = "Break this move into very small, micro-steps that can be easily completed in sequence. Each step should feel achievable. Significantly increase time estimate to be realistic."
        }
        
        return """
        For the goal: "\(goal.title)", adjust the following move to the "\(level.title)" detail level.
        
        Original Move:
        Title: "\(originalTitle)"
        Description: "\(originalDescription)"
        Estimated Duration: \(originalDuration) seconds
        
        Instructions: \(levelInstructions)
        \(currentDateContext)
        
        Provide an adjusted version with:
        - Appropriate title length (shorter for vague, longer for granular)
        - Description that matches the detail level
        - Realistic time estimate in seconds for the adjusted complexity
        
        Return as JSON with 'title', 'description', and 'estimatedDuration' fields.
        """
    }
    
    private func createMoveAdjustmentSchema() -> [String: AIProxyJSONValue] {
        return [
            "description": "Adjusted move with appropriate detail level",
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Adjusted move title"],
                "description": ["type": "string", "description": "Adjusted move description"],
                "estimatedDuration": ["type": "integer", "description": "Estimated duration in seconds"]
            ],
            "required": ["title", "description", "estimatedDuration"]
        ]
    }
    
    private func processAdjustedMoveResponse(_ response: GeminiGenerateContentResponseBody, for move: Move, level: MoveDetailLevel) async {
        print("Processing adjusted move response for level: \(level.title)")
        
        guard let firstCandidate = response.candidates?.first,
              let content = firstCandidate.content,
              let parts = content.parts,
              let firstPart = parts.first else {
            print("No candidates or parts found in move adjustment response.")
            aiError = "AI did not provide valid move adjustment."
            return
        }
        
        let jsonText: String
        switch firstPart {
        case .text(let text):
            jsonText = text
        case .functionCall(_, _):
            print("Unexpected function call in move adjustment response")
            aiError = "AI response format not supported."
            return
        case .inlineData(_, _):
            print("Unexpected inline data in move adjustment response")
            aiError = "AI response format not supported."
            return
        }
        
        print("Move adjustment response (JSON text): \(jsonText)")
        
        do {
            let cleanedJsonText = cleanupJsonResponse(jsonText)
            let jsonData = Data(cleanedJsonText.utf8)
            
            struct AdjustedMoveResponse: Decodable {
                let title: String
                let description: String
                let estimatedDuration: Int
            }
            
            let adjustedMove = try JSONDecoder().decode(AdjustedMoveResponse.self, from: jsonData)
            
            // Update the move with adjusted details
            move.title = adjustedMove.title
            move.M_description = adjustedMove.description
            move.estimatedDuration = TimeInterval(adjustedMove.estimatedDuration)
            
            // Save the changes
            do {
                try modelContext.save()
                print("Successfully adjusted move to \(level.title) level: \(move.title)")
            } catch {
                print("Error saving adjusted move: \(error.localizedDescription)")
                aiError = "Failed to save adjusted move."
            }
            
        } catch {
            print("Error decoding move adjustment response: \(error.localizedDescription)")
            print("Raw JSON: \(jsonText)")
            aiError = "Failed to process move adjustment response."
        }
        
        // Log API usage
        if let usage = response.usageMetadata {
            print("Move Adjustment API Usage: \(usage.promptTokenCount ?? 0) prompt, \(usage.candidatesTokenCount ?? 0) candidates, \(usage.totalTokenCount ?? 0) total tokens.")
        }
    }
}

// MARK: - Extensions

extension Goal {
    var shortDescriptionOrDetails: String {
        return G_description ?? ""
    }
}
