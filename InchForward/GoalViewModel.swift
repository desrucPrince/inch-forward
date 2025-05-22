
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
        } else if let completedMove = progress.moveCompleted {
            dailyState = .completed
            todaysMove = completedMove
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
        dailyState = .completed
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
        let promptText = """
    Reformat the following goal into a SMART (Specific, Measurable, Attainable, Relevant, Time-bound) goal. 
    Provide a concise title (max 15 words) and a detailed description (max 50 words) in JSON format 
    with 'smartTitle' and 'smartDescription' keys. 
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
            systemInstruction: .init(parts: [.text("You are a helpful assistant that reformats goals into the SMART criteria.")])
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
        
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: [.text(promptText)])],
            generationConfig: .init(
                maxOutputTokens: 1024,
                temperature: 0.7,
                responseMimeType: "application/json",
                responseSchema: schema
            ),
            systemInstruction: .init(parts: [.text("You are a helpful assistant that suggests actionable steps for goals.")])
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
        
        var promptText = ""
        
        switch type {
        case .newMovesForGoal:
            promptText = """
        My current goal is: "\(goalTitle)". Description: "\(goalDetails)". 
        Suggest 3-5 concise, actionable steps (moves) to help achieve this goal. 
        Each move should have a short title (max 10 words) and a brief description (max 30 words).
        """
        case .alternativeMoves(let excludingMove):
            let exclusionText = excludingMove != nil ? " The current move is \"\(excludingMove!.title)\", so please suggest different ones." : ""
            promptText = """
        For the goal: "\(goalTitle)" (Description: "\(goalDetails)"), suggest 3 alternative actionable steps (moves).\(exclusionText) 
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
}

// MARK: - Extensions

extension Goal {
    var shortDescriptionOrDetails: String {
        return G_description ?? ""
    }
}
