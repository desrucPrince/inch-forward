import SwiftUI

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
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    NoGoalView(showCreateGoalSheet: .constant(false))
} 