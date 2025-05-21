//
//  HomeView.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    // Use @StateObject for ViewModels owned by the View
    @StateObject private var viewModel: GoalViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showSwapMoveSheet = false
    @State private var showCreateGoalSheet = false // For when no goal exists

    // Initializer to inject modelContext into the ViewModel
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: GoalViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("Loading your 1%...")
                        .padding()
                } else {
                    switch viewModel.dailyState {
                    case .loading: // Should be brief, covered by viewModel.isLoading
                        ProgressView()
                    case .noGoal:
                        NoGoalView(showCreateGoalSheet: $showCreateGoalSheet)
                    case .completed:
                        DayCompleteView(message: "Great job completing '\(viewModel.todaysMove?.title ?? "your move")'!")
                    case .skipped:
                        DayCompleteView(message: "Move skipped for today. Fresh start tomorrow!")
                    case .later(let date):
                        PostponedView(moveTitle: viewModel.todaysMove?.title ?? "Your move", remindAt: date)
                    case .pending:
                        if let goal = viewModel.currentGoal, let move = viewModel.todaysMove {
                            GoalAndMoveView(goal: goal, move: move, viewModel: viewModel, showSwapMoveSheet: $showSwapMoveSheet)
                        } else if viewModel.currentGoal != nil && viewModel.todaysMove == nil {
                             ContentUnavailableView {
                                Label("No Moves for \(viewModel.currentGoal?.title ?? "Goal")", systemImage: "figure.walk.motion")
                            } description: {
                                Text("This goal doesn't have any moves defined yet. Add some moves to get started.")
                                Button("Add Moves to Goal") {
                                    // Navigate to a view to add/edit moves for viewModel.currentGoal
                                    // This would typically be part of a GoalDetailView or similar
                                    print("Navigate to add moves for goal: \(viewModel.currentGoal?.title ?? "")")
                                }
                            }
                        } else {
                            // This case should ideally be .noGoal, but as a fallback:
                            Text("Something went wrong. Try restarting the app.")
                        }
                    }
                }
            }
            .navigationTitle("Inch Forward")
            .toolbar {
                // Example: Button to refresh or access settings
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadTodaysSituation()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    // Could be settings or a way to view all goals
                    // For now, an edit button for the current goal if it exists
                    if viewModel.currentGoal != nil {
                        NavigationLink {
                            // Placeholder for GoalEditView or GoalListView
                            Text("Edit Goal / View All Goals (Not Implemented)")
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadTodaysSituation()
                }
            }
            .sheet(isPresented: $showSwapMoveSheet) {
                // Ensure alternatives are ready before showing sheet
                // The VM's prepareForSwap should be called before setting this to true
                if let currentGoal = viewModel.currentGoal {
                     SwapMoveView(
                        selectedMoveBinding: Binding(
                            get: { viewModel.todaysMove },
                            set: { newMove in
                                if let newMove = newMove {
                                    viewModel.updateTodaysMove(with: newMove)
                                }
                            }
                        ),
                        allPossibleMovesForGoal: viewModel.alternativeMoves.isEmpty && viewModel.todaysMove != nil ? currentGoal.moves.filter { $0.id != viewModel.todaysMove?.id } : viewModel.alternativeMoves,
                        goal: currentGoal // Pass goal for context if needed in SwapMoveView
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    Text("No current goal to swap moves for.") // Fallback
                }
            }
            .sheet(isPresented: $showCreateGoalSheet) {
                // Pass modelContext for creating a new goal
                CreateGoalView() // Assuming this view uses the modelContext from environment
                    .environment(\.modelContext, modelContext)
            }
        }
    }
}

// MARK: - Helper Subviews for HomeView

struct NoGoalView: View {
    @Binding var showCreateGoalSheet: Bool
    var body: some View {
        ContentUnavailableView {
            Label("No Active Goal", systemImage: "figure.walk.circle")
        } description: {
            Text("Let's set up your first goal to start inching forward!")
        } actions: {
            Button("Create Your First Goal") {
                showCreateGoalSheet = true
            }
            .buttonStyle(.borderedProminent) // To maintain similar button styling
        }
        .padding() // Added padding to match the previous VStack's padding
    }
}

struct GoalAndMoveView: View {
    @Bindable var goal: Goal // Changed from @ObservedObject to @Bindable
    @Bindable var move: Move // Changed from @ObservedObject to @Bindable
    @ObservedObject var viewModel: GoalViewModel // For actions
    @Binding var showSwapMoveSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Goal Information
            VStack(alignment: .leading) {
                Text("YOUR GOAL:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(goal.title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let desc = goal.G_description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)

            Divider()

            // Today's Move Card
            VStack(alignment: .leading) {
                Text("TODAY'S 1% MOVE:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(move.title)
                    .font(.title)
                    .fontWeight(.semibold)
                if let moveDesc = move.M_description, !moveDesc.isEmpty {
                    Text(moveDesc)
                        .font(.body)
                        .foregroundColor(.gray)
                }
                HStack {
                    Image(systemName: "timer")
                    Text(move.displayDuration) // Using your helper
                }
                .font(.subheadline)
                .foregroundColor(.orange)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(radius: 3, x: 0, y: 2)
            .padding(.horizontal)


            // Action Buttons
            HStack(spacing: 15) {
                actionButton(title: "Done", systemImage: "checkmark.circle.fill", color: .green) {
                    viewModel.markMoveAsDone()
                }
                actionButton(title: "Swap", systemImage: "arrow.left.arrow.right.circle.fill", color: .blue) {
                    Task { await viewModel.prepareForSwap() } // Prepare alternatives
                    showSwapMoveSheet = true
                }
                Menu {
                    Button("Later Today (1hr)") { viewModel.postponeMove(for: 3600) }
                    Button("Later Today (3hr)") { viewModel.postponeMove(for: 3600 * 3) }
                    Button("Skip for Today", role: .destructive) { viewModel.markAsSkipped() }
                } label: {
                     Label("Later / Skip", systemImage: "ellipsis.circle.fill")
                        .padding(.vertical, 10)
                        .padding(.horizontal, 5) // Make it a bit wider
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .font(.headline)
                        .cornerRadius(10)
                }

            }
            .padding(.horizontal)
            Spacer() // Push content to top
        }
    }
    
    @ViewBuilder
    private func actionButton(title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .padding(.vertical, 10)
            .frame(minWidth: 0, maxWidth: .infinity) // Make buttons expand
            .background(color)
            .foregroundColor(.white)
            .font(.headline)
            .cornerRadius(10)
        }
    }
}

struct DayCompleteView: View {
    let message: String
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)
            Text("All Set for Today!")
                .font(.title)
                .fontWeight(.bold)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct PostponedView: View {
    let moveTitle: String
    let remindAt: Date
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "timer.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.orange)
            Text("Move Postponed")
                .font(.title)
                .fontWeight(.bold)
            Text("'\(moveTitle)' is scheduled for later.")
            Text("Reminder set for: \(remindAt, style: .time)")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// --- Placeholder for SwapMoveView (from previous discussions) ---
// (You'd integrate your actual SwapMoveView here)
struct SwapMoveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var selectedMoveBinding: Move? // This will update viewModel.todaysMove
    var allPossibleMovesForGoal: [Move]
    var goal: Goal // For context, e.g., generating new moves via LLM

    @State private var internalAlternativeMoves: [Move] = []
    @State private var isLoadingAlternatives = false
    
    // private let suggestionEngine = SuggestionEngine() // If LLM is triggered here

    var body: some View {
        NavigationView { // For a title and potential toolbar items in the sheet
            VStack {
                if isLoadingAlternatives {
                    ProgressView("Finding other moves...")
                        .padding()
                } else if internalAlternativeMoves.isEmpty {
                     ContentUnavailableView {
                        Label("No Other Moves", systemImage: "tray.fill")
                    } description: {
                        Text("There are no other moves defined for '\(goal.title)'. You can add more moves when editing the goal.")
                        // Optional: Button to trigger LLM generation
                        /*
                        Button("Suggest Moves with AI") {
                            Task {
                                isLoadingAlternatives = true
                                // internalAlternativeMoves = try await suggestionEngine.generateAlternativeMoves(for: goal, ...)
                                isLoadingAlternatives = false
                            }
                        }
                        */
                    }
                    .padding()
                } else {
                    List {
                        ForEach(internalAlternativeMoves) { move in
                            MoveOptionCard(
                                move: move,
                                estimatedTime: move.displayDuration,
                                action: {
                                    selectedMoveBinding = move
                                    dismiss()
                                }
                            )
                            .listRowSeparator(Visibility.automatic)
                            .padding(Edge.Set.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
                Spacer()
            }
            .navigationTitle("Swap Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                self.internalAlternativeMoves = allPossibleMovesForGoal
            }
        }
    }
}

// --- Placeholder for MoveOptionCard (from previous discussions) ---
struct MoveOptionCard: View {
    @Bindable var move: Move
    let estimatedTime: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(move.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let desc = move.M_description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Text("Category: \(move.category.rawValue.capitalized)")
                        .font(.caption2)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(estimatedTime)
                    }
                    .font(.caption2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground)) // Adapts to light/dark mode
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain) // Use plain to make the whole card tappable
    }
}

// --- Placeholder for CreateGoalView ---
struct CreateGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    // Add other fields like estimatedTimeToComplete, initial moves, etc.

    var body: some View {
        NavigationView {
            Form {
                TextField("Goal Title", text: $title)
                TextField("Description (Optional)", text: $description, axis: .vertical)
                // Add more fields

                Button("Create Goal") {
                    guard !title.isEmpty else { return } // Basic validation
                    let newGoal = Goal(title: title, G_description: description.isEmpty ? nil : description)
                    modelContext.insert(newGoal)
                    // try? modelContext.save() // If needed explicitly
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// --- Preview ---
// To make the preview work, you'll need to set up an in-memory ModelContainer
#Preview {
    // Create an in-memory container
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Move.self, DailyProgress.self, configurations: config)

    // Example Data for Preview
    let sampleGoal = Goal(title: "Write a Novel", G_description: "Finish the first draft of my fantasy novel.", createdAt: Date())
    container.mainContext.insert(sampleGoal)

    let move1 = Move(title: "Outline Chapter 1", M_description: "Detailed bullet points for the first chapter.", estimatedDuration: 1800, category: .planning, isDefaultMove: true, goal: sampleGoal)
    let move2 = Move(title: "Write 500 words", M_description: "Focus on getting words on the page.", estimatedDuration: 3600, category: .writing, goal: sampleGoal)
    let move3 = Move(title: "Research world history", M_description: "Look up ancient civilizations for inspiration.", estimatedDuration: 2700, category: .learning, goal: sampleGoal)
    // sampleGoal.moves = [move1, move2, move3] // Not needed due to inverse relationship being set
    container.mainContext.insert(move1)
    container.mainContext.insert(move2)
    container.mainContext.insert(move3)
    
    // To test "completed" state in preview:
    // let progress = DailyProgress(date: Date(), wasSkipped: false, goal: sampleGoal, moveCompleted: move1)
    // container.mainContext.insert(progress)


    return HomeView(modelContext: container.mainContext)
        .modelContainer(container) // Provide the container to the preview
}
