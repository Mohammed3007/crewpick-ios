import Social
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: SLComposeServiceViewController {
    private let store = SharedImportStore()
    private var sharedURL: URL?
    private var selectedGroup: SharedGroupSummary?
    private var availableGroups: [SharedGroupSummary] { store?.groups() ?? [] }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        loadSharedURL()
    }

    override func isContentValid() -> Bool {
        sharedURL != nil && selectedGroup != nil
    }

    override func didSelectPost() {
        guard let sharedURL, let selectedGroup, let store else {
            extensionContext?.cancelRequest(withError: ShareError.missingSelection)
            return
        }
        do {
            try store.append(PendingImport(sourceURL: sharedURL, destinationGroupID: selectedGroup.id, state: .awaitingConfirmation))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = "Group"
        item.value = selectedGroup.map { "\($0.emoji) \($0.name)" } ?? "Choose"
        item.tapHandler = { [weak self] in self?.showGroupPicker() }
        return [item]
    }

    private func showGroupPicker() {
        let alert = UIAlertController(title: "Save to a group", message: nil, preferredStyle: .actionSheet)
        for group in availableGroups {
            alert.addAction(UIAlertAction(title: "\(group.emoji) \(group.name)", style: .default) { [weak self] _ in
                self?.selectedGroup = group
                self?.reloadConfigurationItems()
                self?.validateContent()
            })
        }
        if availableGroups.isEmpty {
            alert.message = "Open CrewPick and join or create a group first."
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func loadSharedURL() {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers: [NSItemProvider] = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            validateContent()
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            let url = item as? URL ?? (item as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                self?.sharedURL = url
                self?.placeholder = url?.host ?? "Shared link"
                self?.validateContent()
            }
        }
    }
}

private enum ShareError: LocalizedError {
    case missingSelection
    var errorDescription: String? { "Choose a destination group before posting." }
}
