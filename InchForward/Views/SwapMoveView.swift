import SwiftUI
import SwiftData

struct SwapMoveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var selectedMoveBinding: Move?
    var allPossibleMovesForGoal: [Move]
    var goal: Goal

    @State private var internalAlternativeMoves: [Move] = []
    @State private var isLoadingAlternatives = false

    var body: some View {
        NavigationView {
            VStack {
                if isLoadingAlternatives {
                    ProgressView("Finding other moves...")
                        .padding()
                } else if internalAlternativeMoves.isEmpty {
                    ContentUnavailableView {
                        Label("No Other Moves", systemImage: "tray.fill")
                    } description: {
                        Text("There are no other moves defined for '\(goal.title)'. You can add more moves when editing the goal.")
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

