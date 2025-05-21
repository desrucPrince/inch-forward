import SwiftUI

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

#Preview {
    PostponedView(
        moveTitle: "Write 500 words",
        remindAt: Date().addingTimeInterval(3600)
    )
} 