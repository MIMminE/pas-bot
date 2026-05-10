import SwiftUI

struct OutputView: View {
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실행 결과")
                .font(.headline)

            ScrollView {
                Text(output.isEmpty ? "출력 없음" : output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }
}


