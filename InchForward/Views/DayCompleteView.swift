import SwiftUI

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

#Preview {
    DayCompleteView(message: "Great job completing 'Write 500 words'!")
} 