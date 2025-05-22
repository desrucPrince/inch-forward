import SwiftUI
import SwiftData

struct SwapMoveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var selectedMoveBinding: Move?
    var allPossibleMovesForGoal: [Move]
    var goal: Goal
    @ObservedObject var viewModel: GoalViewModel

    @State private var internalAlternativeMoves: [Move] = []
    @State private var isLoadingAlternatives = false

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Finding other moves...")
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Existing moves section
                            if !internalAlternativeMoves.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("EXISTING MOVES")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                    
                                    ForEach(internalAlternativeMoves) { move in
                                        MoveOptionCard(
                                            move: move,
                                            estimatedTime: move.displayDuration,
                                            action: {
                                                selectedMoveBinding = move
                                                dismiss()
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // AI Suggestions section
                            if !viewModel.aiSuggestions.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("AI SUGGESTIONS")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewModel.aiSuggestions) { suggestion in
                                        AISuggestionCard(
                                            suggestion: suggestion,
                                            action: {
                                                // Adopt the suggestion as a new move
                                                viewModel.adoptAISuggestionAsNewMove(suggestion, forGoal: goal, setAsTodaysMove: true)
                                                dismiss()
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Error message if AI failed
                            if let error = viewModel.aiError {
                                VStack {
                                    Text("Could not generate suggestions")
                                        .font(.headline)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("Try Again") {
                                        Task {
                                            await viewModel.prepareForSwap()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            }
                            
                            // No moves available message
                            if internalAlternativeMoves.isEmpty && viewModel.aiSuggestions.isEmpty && viewModel.aiError == nil && !viewModel.isLoading {
                                ContentUnavailableView {
                                    Label("No Other Moves", systemImage: "tray.fill")
                                } description: {
                                    Text("There are no other moves defined for '\(goal.title)'. You can add more moves when editing the goal.")
                                }
                                .padding()
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Swap Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await viewModel.prepareForSwap()
                        }
                    }
                }
            }
            .onAppear {
                self.internalAlternativeMoves = allPossibleMovesForGoal
            }
        }
    }
}

// Card for displaying AI suggestions
struct AISuggestionCard: View {
    let suggestion: GeminiMoveSuggestion
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                }
                
                Text(suggestion.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                HStack {
                    Spacer()
                    Text("Tap to adopt this suggestion")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
