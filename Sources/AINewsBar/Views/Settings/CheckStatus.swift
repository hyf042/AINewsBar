import SwiftUI

/// 通用检测状态：RSS 源连通性 / API Key 可用性等共用
enum CheckStatus {
    case idle
    case checking
    case success(Int)
    case failure(String)
}

struct CheckStatusIcon: View {
    let status: CheckStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .success(let count):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
                .help("可用，共 \(count) 篇文章")
        case .failure(let msg):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 13))
                .help(msg)
        }
    }
}
