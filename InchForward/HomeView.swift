//
//  HomeView.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var viewModel: GoalViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showSwapMoveSheet = false
    @State private var showCreateGoalSheet = false
    @State private var showEditGoal = false

    init(modelContext: ModelContext) {
        _viewModel = State(wrappedValue: GoalViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("Loading your 1%...")
                        .padding()
                } else {
                    switch viewModel.dailyState {
                    case .loading:
                        ProgressView()
                    case .noGoal:
                        NoGoalView(showCreateGoalSheet: $showCreateGoalSheet)
                    case .completed:
                        let completedCount = viewModel.getCompletedMovesCountForToday()
                        let messageText = completedCount > 1 
                            ? "Incredible! You've completed \(completedCount) moves today including '\(viewModel.todaysMove?.title ?? "your latest move")'!"
                            : "Great job completing '\(viewModel.todaysMove?.title ?? "your move")'!"
                        
                        DayCompleteView(
                            message: messageText,
                            onContinue: {
                                Task {
                                    await viewModel.lookForMoreMoves()
                                }
                            }
                        )
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
                                    showEditGoal = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Text("Something went wrong. Try restarting the app.")
                        }
                    }
                }
            }
            .navigationTitle("Inch Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadTodaysSituation()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.currentGoal != nil {
                        Button {
                            showEditGoal = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showEditGoal) {
                EditGoalView(viewModel: viewModel)
            }
            .onAppear {
                Task {
                    await viewModel.loadTodaysSituation()
                }
            }
            .sheet(isPresented: $showSwapMoveSheet) {
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
                        goal: currentGoal,
                        viewModel: viewModel
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    Text("No current goal to swap moves for.")
                }
            }
            .sheet(isPresented: $showCreateGoalSheet) {
                CreateGoalView()
                    .environment(\.modelContext, modelContext)
                    .environment(viewModel)
            }
            .onChange(of: showCreateGoalSheet) { oldValue, newValue in
                if oldValue == true && newValue == false {
                    // Sheet was dismissed, reload data
                    Task {
                        await viewModel.loadTodaysSituation()
                    }
                }
            }
            .onChange(of: showEditGoal) { oldValue, newValue in
                if oldValue == true && newValue == false {
                    // User returned from EditGoalView, reload data
                    Task {
                        await viewModel.loadTodaysSituation()
                    }
                }
            }
        }
    }
}


// --- Preview ---
// To make the preview work, you'll need to set up an in-memory ModelContainer
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Move.self, DailyProgress.self, configurations: config)

    let sampleGoal = Goal(title: "Write a Novel", G_description: "Finish the first draft of my fantasy novel.", createdAt: Date())
    container.mainContext.insert(sampleGoal)

    let move1 = Move(title: "Outline Chapter 1", M_description: "Detailed bullet points for the first chapter.", estimatedDuration: 1800, category: .planning, isDefaultMove: true, goal: sampleGoal)
    let move2 = Move(title: "Write 500 words", M_description: "Focus on getting words on the page.", estimatedDuration: 3600, category: .writing, goal: sampleGoal)
    let move3 = Move(title: "Research world history", M_description: "Look up ancient civilizations for inspiration.", estimatedDuration: 2700, category: .learning, goal: sampleGoal)
    
    container.mainContext.insert(move1)
    container.mainContext.insert(move2)
    container.mainContext.insert(move3)

    return HomeView(modelContext: container.mainContext)
        .modelContainer(container)
}
