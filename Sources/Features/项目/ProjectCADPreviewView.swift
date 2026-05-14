import SwiftUI

struct ProjectCADPreviewView: View {
    let request: ProjectCADPreviewRequest

    var body: some View {
        CADPreviewContainer(request: request)
    }
}
