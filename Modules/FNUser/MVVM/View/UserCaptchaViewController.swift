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
        return view
    }()

    /// Resumes exactly once after success, cancellation, or a load failure.
    private var continuation: CheckedContinuation<CaptchaProof, Error>?

    /// The parent presenting this sheet.
    private weak var presenter: NSViewController?

    /// Bounds a challenge that never loads or returns a result.
    private var deadline: Task<Void, Never>?

    /// Provides an explicit native cancellation action independent of web content.
    private lazy var cancelButton: NSButton = {
        let button = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel)
        )
        button.bezelStyle = .rounded
        button.font = Typography.font(size: 13)
        button.keyEquivalent = "\u{1b}"
        return button
    }()

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
        preferredContentSize = NSSize(
            width: 420,
            height: 440
        )
    }

    /// Storyboard decoding is unsupported for this programmatic controller.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Presents the challenge and propagates cancellation to the native sheet.
    func verify(
        presenting parent: NSViewController
    ) async throws -> CaptchaProof {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                presenter = parent
                parent.presentAsSheet(self)
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    self?.finish(
                        .failure(
                            NetworkError.server(
                                code: 408,
                                message: "Security verification timed out. Please try again."
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
        let canvas = Canvas(color: .white)
        canvas.frame.size = preferredContentSize
        view = canvas
        let title = makeLabel(
            "Complete the security check",
            size: 16,
            weight: .semibold
        )
        [title, webView, cancelButton].forEach(canvas.addSubview)
        title.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalToSuperview().offset(20)
            make.height.equalTo(26)
        }
        webView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(58)
            make.bottom.equalToSuperview().inset(62)
        }
        cancelButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(18)
            make.width.equalTo(80)
            make.height.equalTo(30)
        }
        let options: [String: String] = ["appID": appID, "bizState": businessState]
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
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>\(Typography.webFontCSS)
            body{margin:0;background:white;font-size:14px;text-align:center;color:#69717d}p{margin-top:100px}</style></head>
            <body><p>Loading security verification…</p><script>
            const post = value => window.webkit.messageHandlers.facenowCaptcha.postMessage(value);
            const options = JSON.parse(atob('\(encoded)'));
            const script = document.createElement('script');
            script.src = 'https://turing.captcha.qcloud.com/TJCaptcha.js';
            script.onerror = () => post({ret: -1});
            script.onload = () => {
              try {
                window.challenge = new TencentCaptcha(options.appID, post, {userLanguage:'zh-cn',bizState:options.bizState});
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

    /// Completes a sheet closed by its host without leaving the caller suspended.
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
                        message: "Security verification failed. Please try again."
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

    /// Cancels the challenge without sending a verification-code request.
    @objc private func cancel() { finish(.failure(CancellationError())) }

    /// Removes the script bridge, closes the sheet, and completes its pending caller once.
    private func finish(
        _ result: Result<CaptchaProof, Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "facenowCaptcha")
        presenter?.dismiss(self)
        continuation.resume(with: result)
    }
}
