// MacPin WKWebView subclass
///
/// Add some porcelain to WKWebViews


import WebKit
import WebKitPrivates
import JavaScriptCore
import UTIKit

/*
var globalIconClient = WKIconDatabaseClientV1(
	base: WKIconDatabaseClientBase(version: 1, clientInfo: nil),
	didChangeIconForPageURL: { (iconDatabase, pageURL, clientInfo) -> Void in
		warn("changed thunk!")
		return
	},
	didRemoveAllIcons: { (iconDatabase, clientInfo) -> Void in
		warn("thunk!")
		return
	},
	iconDataReadyForPageURL: { (iconDatabase, pageURL, clientInfo) -> Void in
		warn("ready thunk!")
		return
	}
)
*/

@objc protocol WebViewScriptExports: JSExport { // $.WebView & $.browser.tabs[WebView]
	init?(object: [String:AnyObject]) //> new WebView({url: 'http://example.com'});
	// can only JSExport one init*() func!
	// https://github.com/WebKit/webkit/blob/master/Source/JavaScriptCore/API/tests/testapi.mm
	// https://github.com/WebKit/webkit/blob/master/Source/JavaScriptCore/API/JSWrapperMap.mm#L412

	var title: String? { get }
	@objc(url)var urlstr: String { get set }
	var transparent: Bool { get set }
	var userAgent: String { get set }
	var allowsMagnification: Bool { get set }
	var allowsRecording: Bool { get set }
	//var canGoBack: Bool { get }
	//var canGoForward: Bool { get }
	//var hasOnlySecureContent: Bool { get }
	// var userLabel // allow to be initiated with a trackable tag
	var injected: [String] { get }
	var styles: [String] { get }
	static var MatchedAddressOptions: [String:String] { get set }
	@objc(evalJS::) func evalJS(_ js: String, callback: JSValue?)
	@objc(asyncEvalJS:::) func asyncEvalJS(_ js: String, delay: Int, callback: JSValue?)
	func loadURL(_ urlstr: String) -> Bool
	func loadIcon(_ icon: String) -> Bool
	func popStyle(_ idx: Int)
	func style(_ css: String) -> Bool
	func mainStyle(_ css: String) -> Bool
	func preinject(_ script: String) -> Bool
	func postinject(_ script: String) -> Bool
	func addHandler(_ handler: String) // FIXME kill
	func subscribeTo(_ handler: String)
	func console()
	func scrapeIcon()
	var thumbnail: _WKThumbnailView? { get }
	//func goBack()
	//func goForward()
	//func reload()
	//func reloadFromOrigin()
	//func stopLoading() -> WKNavigation?
	//var snapshotURL: String { get } // gets a data:// of the WKThumbnailView
}

@objc class MPWebView: WKWebView, WebViewScriptExports {
	static var MatchedAddressOptions: [String:String] = [:] // cvar singleton

	static func WebProcessConfiguration() -> _WKProcessPoolConfiguration {
		let config = _WKProcessPoolConfiguration()
		//config.injectedBundleURL = NSbundle.mainBundle().URLForAuxillaryExecutable("contentfilter.wkbundle")
		// https://github.com/WebKit/webkit/blob/master/Source/WebKit2/WebProcess/InjectedBundle/API/c/WKBundle.cpp

		// https://github.com/WebKit/webkit/commit/9d4359a1f767846db078e6ba669715d5ec4a7ba9
		// config.trackNetworkActivity = true

		return config
	}
	static var sharedWebProcessPool = WKProcessPool()._init(with: MPWebView.WebProcessConfiguration()) // cvar singleton

	var injected: [String] = [] //list of script-names already loaded
	var styles: [String] = [] //list of css-names already loaded
	// cachedUserScripts: [UserScript] // are pushed/popped from the contentController by navigation delegates depending on URL being visited

	//let jsdelegate = AppScriptRuntime.shared.jsdelegate
	// race condition? seems to hit a phantom JSContext/JSValue that doesn't represent the delegate!?
	var jsdelegate: JSValue { get { return AppScriptRuntime.shared.jsdelegate } }

	var urlstr: String { // accessor for JSC, which doesn't support `new URL()`
		get { return url?.absoluteString ?? "" }
		set { loadURL(newValue) }
	}

	var userAgent: String {
		get { return _customUserAgent ?? _userAgent ?? "" }
		// https://github.com/WebKit/webkit/blob/master/Source/WebCore/page/mac/UserAgentMac.mm#L48
		set(agent) { if !agent.isEmpty { _customUserAgent = agent } }
	}

	//let page = self.browsingContextController()._pageRef // https://github.com/WebKit/webkit/blob/e41847fbe7dd0bf191a8dafc2c3a5d965e96d277/Source/WebKit2/UIProcess/Cocoa/WebViewImpl.h#L368
	//let browsingContext = WKWebProcessPlugInBrowserContextController.lookUpBrowsingContextFromHandle(_handle)
	//let page = browsingContext._pageRef
	//let browsingContextController = WKBrowsingContextController._browsingContextControllerForPageRef(_pageForTesting())
		// register a custom protocol to handle X-Host: https://github.com/WebKit/webkit/blob/fa0c14782ed939dabdb52f7cffcb1fd0254d4ef0/Tools/TestWebKitAPI/cocoa/TestProtocol.mm
		// https://github.com/WebKit/webkit/blob/49cc03e4bf77a42908478cfbda938088cf1a8567/Source/WebKit2/NetworkProcess/CustomProtocols/CustomProtocolManager.h
		//   registerProtocolClass(NSURLSessionConfiguration) <- that could let you configure ad-hoc CFProxySupport dictionaries: http://stackoverflow.com/a/28101583/3878712
		// NSURLSessionConfiguration ? https://www.objc.io/issues/5-ios7/from-nsurlconnection-to-nsurlsession/

	var context: WKContextRef? = nil

	// iconDB is going bye-bye: https://github.com/WebKit/webkit/commit/9a48388fe4e65e01969c475a1df0ed9b23c8bb43
	var iconDB: WKIconDatabaseRef? = nil
	/*
	var iconClient: WKIconDatabaseClientV1? = WKIconDatabaseClientV1() {
		didSet {
			if let iconDB = iconDB, let context = context {
				WKIconDatabaseClose(iconDB)
				guard var iconClient = iconClient else { return }
				//https://github.com/WebKit/webkit/blob/91700b336a0d0abf1be06c627e3f41281b2728a3/Source/WebCore/loader/icon/IconDatabase.cpp#L114 must close IconDB, setClient, and reopen
			    WKIconDatabaseSetIconDatabaseClient(iconDB, &iconClient.base)
				WKIconDatabaseCheckIntegrityBeforeOpening(iconDB)
				WKIconDatabaseEnableDatabaseCleanup(iconDB)
				"icondb.sqlite".withCString { sqdb in
					WKContextSetIconDatabasePath(context, WKStringCreateWithUTF8CString(sqdb)) // is relative to CWD // should report success https://bugs.webkit.org/show_bug.cgi?id=117632
				}
		   }
		}
	}
	*/

#if STP
	// a long lived thumbnail viewer should construct and store thumbviews itself, this is for convenient dumping
	var thumbnail: _WKThumbnailView? {
		get {
			let snap = self._thumbnailView ?? _WKThumbnailView(frame: self.frame, from: self)
			snap?.requestSnapshot()
			return snap
		}
	}
#endif

#if os(OSX)

#if !STP // no inner WKView in STP, iOS10, & Sierra: https://bugs.webkit.org/show_bug.cgi?id=150174#c0
	// https://github.com/WebKit/webkit/blob/8c504b60d07b2a5c5f7c32b51730d3f6f6daa540/Source/WebKit2/UIProcess/mac/WebInspectorProxyMac.mm#L679
	override var _inspectorAttachmentView: NSView? {
		// when inspector is open, subviews.first is actually the inspector (WKWebInspectorWKWebView), not the WKView
		// tabitem.view.subviews = [ WKWebInspectorView, WKView, ... ]
		get {
			if let topFrame = subviews.first as? WKView {
				return topFrame._inspectorAttachmentView
			}
			return nil
		}
		set {
			if let topFrame = subviews.first as? WKView {
				topFrame._inspectorAttachmentView = newValue
			}
		}
	}
#endif

	var transparent: Bool {
		get {
#if STP
			return !_drawsBackground
#else
			return _drawsTransparentBackground
#endif
		}
		set(transparent) {
#if STP
			_drawsBackground = !transparent
#else
			_drawsTransparentBackground = transparent
#endif
			//^ background-color:transparent sites immediately bleedthru to a black CALayer, which won't go clear until the content is reflowed or reloaded
 			// so frobble frame size to make content reflow & re-colorize
			setFrameSize(NSSize(width: frame.size.width, height: frame.size.height - 1)) //needed to fully redraw w/ dom-reflow or reload!
			AppScriptRuntime.shared.jsdelegate.tryFunc("tabTransparencyToggled", transparent as AnyObject, self)
			evalJS("window.dispatchEvent(new window.CustomEvent('MacPinWebViewChanged',{'detail':{'transparent': \(transparent)}}));" +
				"document.head.appendChild(document.createElement('style')).remove();") //force redraw in case event didn't
				//"window.scrollTo();")
			setFrameSize(NSSize(width: frame.size.width, height: frame.size.height + 1))
			needsDisplay = true
		}
	}
#elseif os(iOS)
	var transparent = false // no overlaying MacPin apps upon other apps in iOS, so make it a no-op
	var allowsMagnification = true // not exposed on iOS WebKit, make it no-op
#endif
	var allowsRecording: Bool {
		get { return _mediaCaptureEnabled }
		set (recordable) { _mediaCaptureEnabled = recordable }
	}

	let favicon: FavIcon = FavIcon()

	convenience init(config: WKWebViewConfiguration? = nil, agent: String? = nil, isolated: Bool? = false, privacy: Bool? = false) {
		// init webview with custom config, needed for JS:window.open() which links new child Windows to parent Window
		let configuration = config ?? WKWebViewConfiguration()
		if config == nil {
#if STP
			configuration._allowUniversalAccessFromFileURLs = true
#if os(OSX)
			configuration._showsURLsInToolTips = true
			configuration._serviceControlsEnabled = true
			configuration._imageControlsEnabled = true
			//configuration._requiresUserActionForEditingControlsManager = true
#endif
#endif
			if #available(OSX 10.13, iOS 11, *) {
				// https://forums.developer.apple.com/thread/87474#267547
				configuration.setURLSchemeHandler(MPRetriever(), forURLScheme: "x-macpin")
				// has to be set before self.init
			}
		}
		let prefs = WKPreferences() // http://trac.webkit.org/browser/trunk/Source/WebKit2/UIProcess/API/Cocoa/WKPreferences.mm
#if os(OSX)
		//geolocationProvider = <GeolocationProviderMock>(context)
		prefs.plugInsEnabled = true // NPAPI for Flash, Java, Hangouts
		prefs._developerExtrasEnabled = true // Enable "Inspect Element" in context menu
		prefs._fullScreenEnabled = true

		// https://webkit.org/blog/7763/a-closer-look-into-webrtc/
		if #available(OSX 10.13, iOS 11, *) {
			prefs._mediaCaptureRequiresSecureConnection = false
			prefs._mediaDevicesEnabled = true
			prefs._mockCaptureDevicesEnabled = false
		}
#endif
		if let privacy = privacy, privacy {
			//prevent HTML5 application cache and asset/page caching by WebKit, MacPin never saves any history itself
			prefs._storageBlockingPolicy = .blockAll
		}
		prefs._allowFileAccessFromFileURLs = true // file://s can xHr other file://s
		//prefs._allowUniversalAccessFromFileURLs = true
		//prefs._isStandalone = true // `window.navigator.standalone == true` mimicing MobileSafari's springboard-link shell mode
		//prefs.minimumFontSize = 14 //for blindies
		prefs.javaScriptCanOpenWindowsAutomatically = true;
#if WK2LOG
		prefs._diagnosticLoggingEnabled = true
		prefs._logsPageMessagesToSystemConsoleEnabled = true // dumps to ASL
		//prefs._javaScriptRuntimeFlags = 0 // ??
#endif
		//prefs._loadsImagesAutomatically = true // STP v20: https://github.com/WebKit/webkit/commit/326fc529da43b4a028a3a1644edb2198d23ecb68
		configuration.preferences = prefs
		configuration.suppressesIncrementalRendering = false
		//if let privacy = privacy { if privacy { configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore() } }
		if let isolated = isolated {
			if isolated {
				configuration.processPool = WKProcessPool() // not "private" but usually gets new session variables from server-side webapps
			} else {
				configuration.processPool = config?.processPool ?? (MPWebView.self.sharedWebProcessPool)!
			}
		}

		self.init(frame: CGRect.zero, configuration: configuration)
#if SAFARIDBG
		_allowsRemoteInspection = true // start webinspectord child
		// enables Safari.app->Develop-><computer name> remote debugging of JSCore and all webviews' JS threads
		// http://stackoverflow.com/questions/11361822/debug-ios-67-mobile-safari-using-the-chrome-devtools
#endif
		//_editable = true // https://github.com/WebKit/webkit/tree/master/Tools/WebEditingTester
		// 	add a toggle: https://github.com/WebKit/webkit/commit/d3a81d4cdbdf947d484987578b21fc0d1f42be5e

		allowsBackForwardNavigationGestures = true
		allowsLinkPreview = true // enable Force Touch peeking (when not captured by JS/DOM)
#if os(OSX)
		allowsMagnification = true
		//_mediaCaptureEnabled = false
#if STP
		_applicationNameForUserAgent = "Version/10.1 Safari/603.1.30"
#else
		_applicationNameForUserAgent = "Version/9.0 Safari/600.5.17"
#endif
#elseif os(iOS)
		_applicationNameForUserAgent = "Version/8.0 Mobile/12F70 Safari/600.1.4"
#endif
		if let agent = agent { if !agent.isEmpty { _customUserAgent = agent } }

		let context = WKPageGetContext(_pageRefForTransitionToWKWebView)
		self.context = context
		"http".withCString { http in
			WKContextRegisterURLSchemeAsBypassingContentSecurityPolicy(context, WKStringCreateWithUTF8CString(http)) // FIXME: makeInsecure() toggle!
		}
		"https".withCString { https in
			WKContextRegisterURLSchemeAsBypassingContentSecurityPolicy(context, WKStringCreateWithUTF8CString(https))
		}
		//self.iconDB = WKContextGetIconDatabase(context)
	}

	/*
	 func reloadPlugins() {
		WKContextRefreshPlugIns(self.context) // STP v20: https://github.com/WebKit/webkit/commit/334a90ae91c0358385c2a971ac8ee7a5b1577fa6
	}
	*/

	convenience required init?(object: [String:AnyObject]) {
		// check for isolated pre-init
		if let isolated = object["isolated"] as? Bool {
			self.init(config: nil, isolated: isolated)
		} else if let privacy = object["private"] as? Bool {
			// a private tab would imply isolation, not sweating lack of isolated+private corner case
			self.init(config: nil, privacy: privacy)
		} else {
			self.init(config: nil)
		}
		var url = NSURL(string: "about:blank")
		for (key, value) in object {
			switch value {
				case let urlstr as String where key == "url": url = NSURL(string: urlstr)
				case let agent as String where key == "agent": _customUserAgent = agent
				case let icon as String where key == "icon": loadIcon(icon)
				case let magnification as Bool where key == "allowsMagnification": allowsMagnification = magnification
				case let recordable as Bool where key == "allowsRecording": _mediaCaptureEnabled = recordable
				case let transparent as Bool where key == "transparent":
#if os(OSX)
#if STP
					_drawsBackground = !transparent
#else
					_drawsTransparentBackground = transparent
#endif
#endif
				case let value as [String] where key == "preinject": for script in value { preinject(script) }
				case let value as [String] where key == "postinject": for script in value { postinject(script) }
				case let value as [String] where key == "style": for css in value { style(css) }
				case let value as [String] where key == "handlers": for handler in value { addHandler(handler) } //FIXME kill
				case let value as [String] where key == "subscribeTo": for handler in value { subscribeTo(handler) }
				default: warn("unhandled param: `\(key): \(value)`")
			}
		}

		if let url = url { gotoURL(url) } else { return nil }
	}

	convenience required init(url: NSURL, agent: String? = nil, isolated: Bool? = false, privacy: Bool? = false) {
		self.init(config: nil, agent: agent, isolated: isolated, privacy: privacy)
		gotoURL(url)
	}

	override var description: String { return "<\(type(of: self))> `\(title ?? String())` [\(urlstr)]" }
	//func toString() -> String { return description } // $.browser.tabs[0].__proto__.toString = function(){ return this.title; }

	deinit {
		iconDB = nil
		context = nil
		warn(description)
	}

	func flushProcessPool() {
		// reinit the NetworkProcess to change HTTP(s) proxies or write cookies to disk
		UserDefaults.standard.synchronize()
		if configuration.processPool == MPWebView.self.sharedWebProcessPool {
			// replace the global pool if that's what we were using
			MPWebView.self.sharedWebProcessPool = WKProcessPool()._init(with: MPWebView.WebProcessConfiguration())
			configuration.processPool = MPWebView.self.sharedWebProcessPool!
		} else { // regenerate a personal pool
			configuration.processPool = WKProcessPool()
		}
	}

	@objc(evalJS::) func evalJS(_ js: String, callback: JSValue? = nil) {
		if let callback = callback, callback.isObject { //is a function or a {}
			warn("callback: \(callback)")
			evaluateJavaScript(js, completionHandler:{ (result: Any?, exception: Error?) -> Void in
				// (result: WebKit::WebSerializedScriptValue*, exception: WebKit::CallbackBase::Error)
				//withCallback.callWithArguments([result, exception]) // crashes, need to translate exception into something javascripty
				warn("callback() ~> \(result),\(exception)")
				// FIXME: check if exception is WKErrorCode.JavaScriptExceptionOccurred,.JavaScriptResultTypeIsUnsupported
				if let result = result {
					callback.call(withArguments: [result, true]) // unowning withCallback causes a crash and weaking it muffs the call
				} else {
					// passing nil crashes
					callback.call(withArguments: [JSValue(nullIn: callback.context), true])
				}
				return
			})
			return
		}
		evaluateJavaScript(js, completionHandler: nil)
	}

	// cuz JSC doesn't come with setTimeout()
	@objc(asyncEvalJS:::) func asyncEvalJS(_ js: String, delay: Int, callback: JSValue?) {
		let delayTime = DispatchTime.now() + DispatchTimeInterval.seconds(delay)
		DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: delayTime) {
			if let callback = callback, callback.isObject { //is a function or a {}
				warn("callback: \(callback)")
				self.evaluateJavaScript(js, completionHandler:{ (result: Any?, exception: Error?) -> Void in
					// (result: WebKit::WebSerializedScriptValue*, exception: WebKit::CallbackBase::Error)
					//withCallback.callWithArguments([result, exception]) // crashes, need to translate exception into something javascripty
					warn("callback() ~> \(result),\(exception)")
					if let result = result {
						callback.call(withArguments: [result, true]) // unowning withCallback causes a crash and weaking it muffs the call
					} else {
						// passing nil crashes
						callback.call(withArguments: [JSValue(nullIn: callback.context), true])
					}
				})
			} else {
				self.evaluateJavaScript(js, completionHandler: nil)
			}
		}
	}

	@discardableResult
	func gotoURL(_ url: NSURL) {
		let act = ProcessInfo.processInfo.beginActivity(options: [ProcessInfo.ActivityOptions.userInitiated, ProcessInfo.ActivityOptions.idleSystemSleepDisabled], reason: "browsing begun")
		guard #available(OSX 10.11, iOS 9.1, *) else { load(URLRequest(url: url as URL)); return }
		guard url.scheme == "file" else { load(URLRequest(url: url as URL)); return }
		if let readURL = url.deletingLastPathComponent {
		//if let readURL = url.baseURL {
		//if let readURL = url.URLByDeletingPathExtension {
			warn("Bypassing CORS: \(readURL)")
			loadFileURL(url as URL, allowingReadAccessTo: readURL)
		}
		ProcessInfo.processInfo.endActivity(act)
	}

	@discardableResult
	func loadURL(_ urlstr: String) -> Bool {
		if let url = NSURL(string: urlstr) {
			gotoURL(url as NSURL)
			return true
		}
		return false // tell JS we were given a malformed URL
	}

	@discardableResult
	func scrapeIcon() { // extract icon location from current webpage and initiate retrieval

		// this C SPI was scrapped in https://github.com/WebKit/webkit/commit/9a48388fe4e65e01969c475a1df0ed9b23c8bb43#diff-e43281f560648e1bddf2935b1d1b8b8b
		if let iconDB = iconDB, iconDB != nil { // scrape icon from WebCore's IconDatabase
			if let wkurl = WKIconDatabaseCopyIconURLForPageURL(iconDB, WKURLCreateWithCFURL(url as CFURL!)) {
				WKIconDatabaseRetainIconForURL(iconDB, wkurl)
				favicon.url = WKURLCopyCFURL(kCFAllocatorDefault, wkurl) as NSURL

/*
				let cgicon = WKIconDatabaseTryGetCGImageForURL(iconDB, wkurl, WKSize()).takeUnretainedValue()
#if os(OSX)
				favicon.icon = NSImage(CGImage: cgicon, size: NSZeroSize)
				favicon.icon16 = NSImage(CGImage: cgicon, size: NSZeroSize)
#elseif os(iOS)
				favicon.icon = UIImage(CGImage: cgicon, size: UIZeroSize)
#endif
*/
				/*
				if let cgicon = WKIconDatabaseTryGetCGImageForURL(iconDB, wkurl, WKSize(32, 32)) as? Image where cgicon != nil {
					favicon.icon = Image(CGImage: cgicon)
				} else if let cgicon16 = WKIconDatabaseTryGetCGImageForURL(iconDB, wkurl, WKSize(16, 16)) as? Image where cgicon16 != nil {
					favicon.icon16 = Image(CGImage: cgicon16)
				}
				if let wkdata = WKIconDatabaseCopyIconDataForPageURL(iconDB, wkurl) as? WKDataRef where wkdata != nil {
					let bytes = WKDataGetBytes(wkdata)
					favicon.data = NSData(bytes, bytes.length)
				}
				*/
			}
		} else { // scrape icon from JS DOM
			evaluateJavaScript("if (icon = document.head.querySelector('link[rel$=icon]')) { icon.href };", completionHandler:{ [unowned self] (result: Any?, exception: Error?) -> Void in
				if let href = result as? String { // got link for icon or apple-touch-icon from DOM
					// FIXME: very rarely this crashes if a page closes/reloads itself during the update closure
					self.loadIcon(href)
				} else if let url = self.url, let iconurlp = NSURLComponents(url: url, resolvingAgainstBaseURL: false), !((iconurlp.host ?? "").isEmpty) {
					iconurlp.path = "/favicon.ico" // request a root-of-domain favicon
					self.loadIcon(iconurlp.string!)
				}
			})
		}
	}

	func loadIcon(_ icon: String) -> Bool {
		if let url = NSURL(string: icon), !icon.isEmpty {
			favicon.url = url
			return true
		}
		return false
	}

/*
	func addUserScript(name: String) -> UserScript? {
		let script = UserScript.load(basename: name, inject: .AtDocumentStart, onlyForTop: false)
		let webctl = configuration.userContentController
		guard webctl.userScripts.filter({$0 == script}).count < 1 else { warn("\(script) already loaded!"); return nil }
		//if (find(webctl.userScripts, script) ?? -1) < 0 { // don't re-add identical userscripts
		webctl.addUserScript(script)
		return script
	}
*/

	func popStyle(_ idx: Int) {
		guard idx >= 0 && idx <= configuration.userContentController._userStyleSheets.count else { return }
		let style = configuration.userContentController._userStyleSheets[idx]
		configuration.userContentController._remove(style)
		styles.remove(at: idx)
	}

	func style(_ css: String) -> Bool {
		if !styles.contains(css) && loadUserStyleSheetFromBundle(css, webctl: configuration.userContentController, onlyForTop: false) { styles.append(css); return true }
		return false
	}
	func mainStyle(_ css: String) -> Bool {
		if !styles.contains(css) && loadUserStyleSheetFromBundle(css, webctl: configuration.userContentController, onlyForTop: true) { styles.append(css); return true }
		return false
	}
	func preinject(_ script: String) -> Bool {
		if !injected.contains(script) && loadUserScriptFromBundle(script, webctl: configuration.userContentController, inject: .atDocumentStart, onlyForTop: false) { injected.append(script); return true }
		return false
	}
	func postinject(_ script: String) -> Bool {
		if !injected.contains(script) && loadUserScriptFromBundle(script, webctl: configuration.userContentController, inject: .atDocumentEnd, onlyForTop: false) { injected.append(script); return true }
		return false
		// forcefully install a userscript fror post-page-loads
		//guard unless !injected.contains(script) else {return false}
		//guard let script = loadUserScript(script, inject: .AtDocumentEnd, onlyForTop: false) else { return false }
		//addUserScript(script)
		//injected.append(script)
		//return true
	}

	func addHandler(_ handler: String) { configuration.userContentController.add(AppScriptRuntime.shared, name: handler) } //FIXME kill
	func subscribeTo(_ handler: String) {
		configuration.userContentController.removeScriptMessageHandler(forName: handler)
		configuration.userContentController.add(AppScriptRuntime.shared, name: handler)
	}

	func REPL() {
		termiosREPL({ (line: String) -> Void in
			self.evaluateJavaScript(line, completionHandler:{ (result: Any?, exception: Error?) -> Void in
				// FIXME: the JS execs async so these print()s don't consistently precede the REPL thread's prompt line
				if let result = result { Swift.print(result) }
				guard let exception = exception else { return }
				switch (exception._domain, exception._code) { // codes: https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/API/Cocoa/WKError.h
					// case(WKErrorDomain, Int(WKErrorCode.JavaScriptExceptionOccurred.rawValue)): fallthrough
					// case(WKErrorDomain, Int(WKErrorCode.JavaScriptResultTypeIsUnsupported.rawValue)): fallthrough
						// info keys: https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/API/Cocoa/WKErrorPrivate.h
						// _WKJavaScriptExceptionMessageErrorKey
						// _WKJavaScriptExceptionLineNumberErrorKey
						// _WKJavaScriptExceptionColumnNumberErrorKey
						// _WKJavaScriptExceptionSourceURLErrorKey
					default: Swift.print("Error: \(exception)")
				}
			})
		},
		ps1: #file,
		ps2: #function,
		abort: { () -> Void in
			// EOF'd by Ctrl-D
			// self.close() // FIXME: self is still retained (by the browser?)
		})
	}

#if os(OSX)
	// dragDestinationActionMaskForDraggingInfo -> WKDragDestinationActionAny https://github.com/WebKit/webkit/commit/5e1e5eab17cfded9ea9eaa9b46075b78d68575e4

	// FIXME: unified save*()s like Safari does with a drop-down for "Page Source" & Web Archive, or auto-mime for single non-HTML asset
	func saveWebArchive() {
		_getWebArchiveData() { [unowned self] (data: Data?, err: Error?) -> Void in
			//pop open a save Panel to dump data into file
			let saveDialog = NSSavePanel();
			saveDialog.canCreateDirectories = true
			saveDialog.allowedFileTypes = [kUTTypeWebArchive as String]
			if let window = self.window {
				saveDialog.beginSheetModal(for: window) { (result: Int) -> Void in
					if let url = saveDialog.url, result == NSModalResponseOK {
						FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
						}
				}
			}
		}
	}

	func savePage() {
		_getMainResourceData() { [unowned self] (data: Data?, err: Error?) -> Void in
			//pop open a save Panel to dump data into file
			let saveDialog = NSSavePanel();
			saveDialog.canCreateDirectories = true
			if let mime = self._MIMEType, let uti = UTI(mimeType: mime) {
				saveDialog.allowedFileTypes = [uti.utiString]
			}
			if let window = self.window {
				saveDialog.beginSheetModal(for: window) { (result: Int) -> Void in
					if let url = saveDialog.url, result == NSModalResponseOK {
						FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
						}
				}
			}
		}
	}

	override func validateUserInterfaceItem(_ anItem: NSValidatedUserInterfaceItem) -> Bool {
		switch (anItem.action!.description) {
			//case "askToOpenCurrentURL": return true
			case "copyAsPDF": fallthrough
			case "console": fallthrough
			case "saveWebArchive": fallthrough
			case "close": fallthrough
			case "savePage": return true
			case "printWebView:": return true
			default:
				warn("not capturing selector but passing to super: \(anItem.action)")
				return super.validateUserInterfaceItem(anItem)
		}

	}

	/* overide func _registerForDraggedTypes() {
		// https://github.com/WebKit/webkit/blob/f72e25e3ba9d3d25d1c3a4276e8dffffa4fec4ae/Source/WebKit2/UIProcess/API/mac/WKView.mm#L3653
		self.registerForDraggedTypes([ // https://github.com/WebKit/webkit/blob/master/Source/WebKit2/Shared/mac/PasteboardTypes.mm [types]
			// < forEditing
			WebArchivePboardType, NSHTMLPboardType, NSFilenamesPboardType, NSTIFFPboardType, NSPDFPboardType,
		    NSURLPboardType, NSRTFDPboardType, NSRTFPboardType, NSStringPboardType, NSColorPboardType, kUTTypePNG,
			// < forURL
			WebURLsWithTitlesPboardType, //webkit proprietary
			NSURLPboardType, // single url from older apps and Chromium -> text/uri-list
			WebURLPboardType (kUTTypeURL), //webkit proprietary: public.url
			WebURLNamePboardType (kUTTypeURLName), //webkit proprietary: public.url-name
			NSStringPboardType, // public.utf8-plain-text -> WKJS: text/plain
			NSFilenamesPboardType, // Finder -> text/uri-list & Files
		])
	} */

	// TODO: give some feedback when a url is being dragged in to indicate what will happen
	//  (-[WKWebView draggingEntered:]):
	//  (-[WKWebView draggingUpdated:]):
	//  (-[WKWebView draggingExited:]):
	//  (-[WKWebView prepareForDragOperation:]):

	// try to accept DnD'd links from other browsers more gracefully than default WebKit behavior
	// this mess ain't funny: https://hsivonen.fi/kesakoodi/clipboard/
	// https://webkit.org/blog/8170/clipboard-api-improvements/
	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		if sender.draggingSource() == nil { //dragged from external application
			let pboard = sender.draggingPasteboard()

			if let file = pboard.string(forType: kUTTypeFileURL as String) { //drops from Finder
				warn("DnD: file from Finder: \(file)")
			} else {
				pboard.dump()
				pboard.normalizeURLDrag() // *cough* Trello! *cough*
				pboard.dump()
			}

			if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) {
				if AppScriptRuntime.shared.jsdelegate.tryFunc("handleDragAndDroppedURLs", NSArray(array: urls.map({($0 as! NSURL).description}))) {
			 		return true  // app.js indicated it handled drag itself
				}
			}
		} // -from external app

		return super.performDragOperation(sender)
		// if current page doesn't have HTML5 DnD event observers, webview will just navigate to URL dropped in
	}

/*
	// allow controlling drags out of a MacPin window
	override func beginDraggingSessionWithItems(items: [AnyObject], event: NSEvent, source: NSDraggingSource) -> NSDraggingSession {
		// API didn't land in 10.11.4 or STP v7... https://bugs.webkit.org/show_bug.cgi?id=143618
		warn()
		return super.beginDraggingSessionWithItems(items, event: event, source: source)
		//  (-[WKWebView _setDragImage:at:linkDrag:]):
		// https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragsource.html#//apple_ref/doc/uid/20000976-CJBFBADF
		// https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/NSView_Class/index.html#//apple_ref/occ/instm/NSView/beginDraggingSessionWithItems:event:source:
	}
*/

	//func dumpImage() -> NSImage { return NSImage(data: view.dataWithPDFInsideRect(view.bounds)) }
	//var snapshotURL: String { get { NSImage(data: thumbnail.dataWithPDFInsideRect(thumbnail.bounds)) } } //data::
	// http://gauravstomar.blogspot.com/2012/08/convert-uiimage-to-base64-and-vice-versa.html
	// http://www.cocoabuilder.com/archive/cocoa/318060-base64-encoding-of-nsimage.html#318071
	// http://stackoverflow.com/questions/392464/how-do-i-do-base64-encoding-on-iphone-sdk

	func copyAsPDF() {
		let pb = NSPasteboard.general()
		pb.clearContents()
		writePDF(inside: bounds, to: pb)
	}

	func printWebView(_ sender: AnyObject?) {
#if STP
		// _printOperation not avail in 10.11.4's WebKit
		let printer = _printOperation(with: NSPrintInfo.shared())
		printer?.showsPrintPanel = true
		printer?.run()
#endif
	}

	func console() {
		let inspector = WKPageGetInspector(_pageRefForTransitionToWKWebView)
		DispatchQueue.main.async() {
			WKInspectorShowConsole(inspector) // ShowConsole, Hide, Close, IsAttatched, Attach, Detach
		}
	}

#endif
}
