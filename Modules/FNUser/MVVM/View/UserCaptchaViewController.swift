//
//  UserCaptchaViewController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import WebKit
import SnapKit
#if canImport(FNNetwork)
    import FNNetwork
#endif

/// Hosts a one-use Tencent security challenge without exposing account tokens to JavaScript.
@MainActor
final class UserCaptchaViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {

    /// The tenant-provided Tencent application identifier.
    private let appID: String

    /// The operation being authorized, matching the platform web client.
    private let businessState: String

    /// The nonpersistent browser used solely for the security challenge.
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            self,
            name: "facenowCaptcha"
        )
        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        view.navigationDelegate = self
        view.underPageBackgroundColor = .clear
        // Disable WebKit's default page fill so transparent HTML reveals the native parent window.
        view.setValue(false, forKey: "drawsBackground")
        return view
    }()

    /// Resumes exactly once after success, cancellation, or a load failure.
    private var continuation: CheckedContinuation<CaptchaProof, Error>?

    /// The existing login window; verification never creates an additional native window.
    private weak var hostWindow: NSWindow?

    /// Restores the original editor after the transparent challenge layer closes.
    private weak var previousFirstResponder: NSResponder?

    /// Keeps Escape cancellation available even when the third-party iframe has keyboard focus.
    private var escapeMonitor: Any?

    /// Bounds a challenge that never loads or returns a result.
    private var deadline: Task<Void, Never>?

    /// Creates one challenge for one request; tickets are never cached or reused.
    init(
        appID: String,
        businessState: String
    ) {
        self.appID = appID
        self.businessState = businessState
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    /// Storyboard decoding is unsupported for this programmatic controller.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Mounts the challenge directly over the login page and propagates task cancellation.
    func verify(
        presenting parent: NSViewController
    ) async throws -> CaptchaProof {
        try Task.checkCancellation()
        guard let parentWindow = parent.view.window else { throw CancellationError() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                hostWindow = parentWindow
                previousFirstResponder = parentWindow.firstResponder
                parent.addChild(self)
                parent.view.addSubview(view)
                view.snp.makeConstraints { make in make.edges.equalToSuperview() }
                parentWindow.makeFirstResponder(webView)
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53, let self, event.window === self.hostWindow else { return event }
                    self.finish(.failure(CancellationError()))
                    return nil
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    self?.finish(
                        .failure(
                            NetworkError.server(
                                code: 408,
                                message: UserStrings.securityTimedOut
                            )
                        )
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    /// Loads only the official Tencent SDK and forwards its result through a narrow bridge.
    override func loadView() {
        let canvas = Canvas()
        view = canvas
        canvas.addSubview(webView)
        webView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        let options: [String: String] = [
            "appID": appID, "bizState": businessState,
            "language": Localization.languageCode == "zh-Hans" ? "zh-cn" : "en",
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: options,
                options: [.fragmentsAllowed]
            ),
            let json = String(
                data: data,
                encoding: .utf8
            )
        else { return }
        // Encoding the configuration keeps server-controlled text out of executable source.
        let encoded = Data(json.utf8).base64EncodedString()
        let html = """
            <!doctype html><html lang="\(Localization.languageCode)"><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>\(Typography.webFontCSS)
            html,body{margin:0;width:100%;height:100%;background:transparent}
            body{overflow:hidden}</style></head>
            <body><script>
            const post = value => window.webkit.messageHandlers.facenowCaptcha.postMessage(value);
            const options = JSON.parse(atob('\(encoded)'));
            const script = document.createElement('script');
            script.src = 'https://turing.captcha.qcloud.com/TJCaptcha.js';
            script.onerror = () => post({ret: -1});
            script.onload = () => {
              try {
                window.challenge = new TencentCaptcha(options.appID, post, {
                  type:'popup',userLanguage:options.language,bizState:options.bizState
                });
                window.challenge.show();
              } catch (_) { post({ret: -1}); }
            };
            document.head.appendChild(script);
            </script></body></html>
            """
        webView.loadHTMLString(
            html,
            baseURL: URL(string: "https://cloud.xmax.22duck.cn")
        )
    }

    /// Cancels a challenge when its host page disappears without leaving the caller suspended.
    override func viewWillDisappear() {
        super.viewWillDisappear()
        finish(.failure(CancellationError()))
    }

    /// Accepts results only from this page's main frame and validates both opaque proof fields.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
            let value = message.body as? [String: Any], let result = value["ret"] as? Int
        else { return }
        if result == 2 {
            finish(.failure(CancellationError()))
            return
        }
        guard result == 0, let ticket = value["ticket"] as? String, !ticket.isEmpty,
            let random = value["randstr"] as? String, !random.isEmpty
        else {
            finish(
                .failure(
                    NetworkError.server(
                        code: 400,
                        message: UserStrings.securityFailed
                    )
                )
            )
            return
        }
        finish(
            .success(
                CaptchaProof(
                    ticket: ticket,
                    randomString: random
                )
            )
        )
    }

    /// Ends a failed page load instead of leaving the account form locked.
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) { finish(.failure(error)) }

    /// Ends a navigation failure after the page has started loading.
    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) { finish(.failure(error)) }

    /// Removes the script bridge and page overlay, then completes its pending caller once.
    private func finish(
        _ result: Result<CaptchaProof, Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "facenowCaptcha")
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        view.removeFromSuperview()
        removeFromParent()
        hostWindow?.makeFirstResponder(previousFirstResponder)
        hostWindow = nil
        previousFirstResponder = nil
        continuation.resume(with: result)
    }
}
