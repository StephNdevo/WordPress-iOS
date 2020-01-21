/// Presents the appropriate reblog scene, depending on the number of available sites
class ReaderReblogPresenter {
    private let postService: PostService

    private struct NoSitesConfiguration {
        static let noSitesTitle = NSLocalizedString("No available sites",
                                                    comment: "A short message that informs the user no sites could be found.")
        static let noSitesSubtitle = NSLocalizedString("Once you create a site, you can reblog content that you like to your own site.",
                                                       comment: "A subtitle with more detailed info for the user when no sites could be found.")
        static let manageSitesLabel = NSLocalizedString("Manage Sites",
                                                        comment: "Button title. Tapping lets the user manage the sites they follow.")
        static let backButtonTitle = NSLocalizedString("Back",
                                                       comment: "Back button title.")
    }

    init(postService: PostService? = nil) {

        // fallback for self.postService
        func makePostService() -> PostService {
            let context = ContextManager.sharedInstance().mainContext
            return PostService(managedObjectContext: context)
        }
        self.postService = postService ?? makePostService()
    }

    /// Presents the reblog screen(s)
    func presentReblog(blogService: BlogService,
                       readerPost: ReaderPost,
                       origin: UIViewController) {

        let blogCount = blogService.blogCountForAllAccounts()

        switch blogCount {
        case 0:
            presentNoSitesScene(origin: origin)
        case 1:
            guard let blog = blogService.blogsForAllAccounts().first else {
                return
            }
            presentEditor(with: readerPost, blog: blog, origin: origin)
        default:
            guard let blog = blogService.lastUsedOrFirstBlog() else {
                return
            }
            presentBlogPicker(from: origin,
                              blog: blog,
                              blogService: blogService,
                              readerPost: readerPost)
        }
    }
}


// MARK: - Blog Picker
private extension ReaderReblogPresenter {
    /// presents the blog picker before the editor, for users with multiple sites
    func presentBlogPicker(from origin: UIViewController,
                           blog: Blog,
                           blogService: BlogService,
                           readerPost: ReaderPost) {

        let selectorViewController = BlogSelectorViewController(selectedBlogObjectID: nil,
                                                                successHandler: nil,
                                                                dismissHandler: nil)

        selectorViewController.displaysNavigationBarWhenSearching = WPDeviceIdentification.isiPad()
        selectorViewController.dismissOnCancellation = true

        let navigationController = getNavigationController(selectorViewController)

        let successHandler: BlogSelectorSuccessHandler = { selectedObjectID in
            guard let newBlog = blogService.managedObjectContext.object(with: selectedObjectID) as? Blog else {
                return
            }
            navigationController.dismiss(animated: true) {
                self.presentEditor(with: readerPost, blog: newBlog, origin: origin)
            }
        }
        selectorViewController.successHandler = successHandler
        origin.present(navigationController, animated: true)
    }

    /// returns an AdaptiveNavigationController with preconfigured modal presentation style
    func getNavigationController(_ controller: UIViewController) -> AdaptiveNavigationController {
        let navigationController = AdaptiveNavigationController(rootViewController: controller)
        if #available(iOS 13.0, *) {
            navigationController.modalPresentationStyle = .automatic
        } else {
            // suits both iPad and iPhone
            navigationController.modalPresentationStyle = .pageSheet
        }
        return navigationController
    }
}


// MARK: - Post Editor
private extension ReaderReblogPresenter {
    /// presents the post editor when users have at least one blog site.
    func presentEditor(with readerPost: ReaderPost,
                               blog: Blog,
                               origin: UIViewController) {

        let post = postService.createDraftPost(for: blog)
        post.prepareForReblog(with: readerPost) {
            
            let editor = EditPostViewController(post: post, loadAutosaveRevision: false)
            editor.modalPresentationStyle = .fullScreen
            editor.postIsReblogged = true
            
            if let featuredImage = post.featuredImage {
                editor.insertedMedia = [featuredImage]
            }
            
            origin.present(editor, animated: false)
        }

    }
}


// MARK: - No Sites
private extension ReaderReblogPresenter {
    /// presents the no sites screen, with related actions
    func presentNoSitesScene(origin: UIViewController) {
        let controller = NoResultsViewController.controllerWith(title: NoSitesConfiguration.noSitesTitle,
                                                                buttonTitle: NoSitesConfiguration.manageSitesLabel,
                                                                subtitle: NoSitesConfiguration.noSitesSubtitle)
        controller.showDismissButton(title: NoSitesConfiguration.backButtonTitle)

        controller.actionButtonHandler = { [weak origin] in
            guard let tabBarController = origin?.tabBarController as? WPTabBarController else {
                return
            }
            controller.dismiss(animated: true) {
                tabBarController.showMySitesTab()
            }
        }

        controller.dismissButtonHandler = {
            controller.dismiss(animated: true)
        }

        let navigationController = getNavigationController(controller)
        origin.present(navigationController, animated: true)
    }
}

// MARK: - Post updates
private extension Post {
    /// Formats the new Post content for reblogging, using an existing ReaderPost
    func prepareForReblog(with readerPost: ReaderPost, completion: @escaping () -> ()) {
        guard let context = self.managedObjectContext else {
            return
        }
        let mediaService = MediaService(managedObjectContext: context)
        
        // update the post
        update(with: readerPost)
        // initialize the content
        var content = String()
        // add the quoted summary to the content, if it exists
        if let summary = readerPost.summary {
            var citation: String?
            // add the optional citation
            if let permaLink = readerPost.permaLink, let title = readerPost.titleForDisplay() {
                citation = ReaderReblogFormatter.hyperLink(url: permaLink, text: title)
            }
            content = self.blog.isGutenbergEnabled ? ReaderReblogFormatter.gutenbergQuote(text: summary, citation: citation) :
                ReaderReblogFormatter.aztecQuote(text: summary, citation: citation)

            content = self.blog.isGutenbergEnabled ? "<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->" + content : "<p></p>" + content
        }
        // insert the image on top of the content
        if let image = readerPost.featuredImage, image.isValidURL(), let url = URL(string: image) {

            ImageDownloader.shared.downloadImage(at: url) { image, error in
                guard let image = image else {
                    return
                }
                mediaService.createMedia(with: image, blog: self.blog, post: self, progress: nil, thumbnailCallback: nil) { media, error in
                    guard let media = media else {
                        return
                    }
                    self.featuredImage = media

                    completion()
                }
            }
        }
        self.content = content
    }

    func update(with readerPost: ReaderPost) {
        self.postTitle = readerPost.titleForDisplay()
        self.permaLink = readerPost.permaLink
    }
}
