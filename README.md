# MacPin
<center>
MacPin creates OSX & [iOS](#iOS) apps for websites & webapps, configured with JavaScript.  
![screenie](/dock_screenshot.png?raw=true)  
</center>

The Browser UI is very minimal, just a toolbar (with site tabs) that disappears in Full-Screen mode.  

(I have thoughts to allow browser UI to be replaceable by supplying React or Vue/Weex  
JS scripts... [XUL](https://github.com/facebook/react/issues/4138) worked great for Mozilla, amirite?)   

MacPin apps are shown in the Dock (or Springboard on iOS), tabbing App Switcher, & Launchpad.  
New apps need only a single highest-res 1:1 PNG badge to be supplied for all of these representations.  

Custom URL schemes can also be registered to launch a MacPin App from any other app on your Mac.  

There are a few development branches with their own requirements:
* swift2.3: Requires OSX 10.11 "El Capitan" with Safari Technical Preview and Xcode 8.2.3 installed.  
  * This branch is no longer maintained.
* swift3.1: Requires OSX 10.12 "Sierra" with Safari Technical Preview and Xcode 9 installed.  
  * This is the current development target.

## Included Apps in the [Release](https://github.com/kfix/MacPin/releases)

#### [Hangouts.app](http://plus.google.com/hangouts): SMS/IM/Video chat client for the desktop

Google Voice and Project Fi users can [make & take phone calls and SMS/MMS messages](http://fi.google.com/about/faq/#talk-and-text-4).  

New incoming messages are shown in the system's Notification Center,  
which you can click on to reply back in the app.

Some optional goodies you can install:  
* [`Call Phone with Hangouts`](extras/Call Phone with Hangouts.workflow): (_OSX_) Call text-selected phone numbers from the context menu (right-click)
* [`AddressBookHangoutsPlugin`](extras/AddressBookHangoutsPlugin): (_OSX_) click-to-call phone number fields in Contacts and Spotlight

Several browser extensions can also make phone numbers found in webpages clickable.

When receiving a call, Hangouts.app will automatically steal focus so you can quickly answer or reject the call using the keyboard:  

* press Enter or Spacebar to accept the call
* press Escape or Backspace to decline it

Hooked URLs:
* [`sms:`](sms:5558675309)
* [`tel:`](tel:18001234567)
* [`hangouts:`](hangouts:coolguy@example.com)

#### [Messenger.app](https://www.messenger.com/hangouts): RIP *WhatsApp in your Facebook while you Facebook*

#### [WhatsApp.app](https://web.whatsapp.com): WhatsApp, this app is. [HAP](https://www.youtube.com/watch?v=5tJt9hs7-vo)!

#### [Slack.app](https://signin.slack.com): A hackable runtime for Slack (your co-workers will be thrilled)

#### [Salesforce.app](https://signin.salesforce.com): _[ALWAYS BE CLOSING](https://www.youtube.com/watch?v=r6Lf8GtMe4M)_ without tying up your main browser

#### [Trello.app](http://trello.com): Mind-mapper and project planner
Hooked URLs:
* [`trello:`](trello:search for something)

#### [Vine.app](http://vine.co): Mobile-layout edition for the desktop

* shows a single-column stream
* does not preload any videos
* makes the controls mouse-friendly

#### [YouTube_TV.app](http://youtube.com/tv): TV edition for the desktop.

#### [Facebook.app](https://m.facebook.com/home.php): It knows who your friends are.

* mobile edition
* ~~Facebook-in-your-facebook sidebars~~


Hooked URLs:
* [`facebook:`](facebook:search for something)

#### [CloudPebble.app](https://cloudpebble.net/ide): Use the Interweb to program your Dick Tracy watch.
[ERMAHGERD](http://knowyourmeme.com/memes/ermahgerd) ClerdPehble mah favrit smurtwerch & IDE evar!

#### [DevDocs.app](http://devdocs.io): Code documentaion browser for most front-end frameworks
Hooked URLs:
* [`devdocs:`](devdocs:someFuncName)

## Creating an App
Some call these Apps [Site-specific Browsers](https://en.wikipedia.org/wiki/Site-specific_browser) or Hybrid apps.  
They are configured with an imperative JavaScript which you need to copy-paste and customize.  

Userscripts can be added to facilitate posting to the Notification Center & recalling webapp locations/state from those posts.

Eventually, I plan to make a UI wizard to generate MacPin apps from MacPin. But for now:  

```
cd ~/src/MacPin
mkdir sites/MySite
cp sites/MacPin/app.js sites/MySite
$EDITOR sites/MySite/app.js

# find a large & square .png for the app, like an App Store image.
cp ~/Pictures/MySite.png sites/MySite/icon.png

make sites/MySite/
open builds/macosx-x86*/apps/MySite.app
# test, tweak, lather, repeat

make install
open -a MySite.app
```

### sample app.js
```
/*eslint-env applescript*/
/*eslint eqeqeq:0, quotes:0, space-infix-ops:0, curly:0*/
"use strict";

var delegate = {}; // our delegate to receive events from the webview app

delegate.AppFinishedLaunching = function() {
	$.browser.tabSelected = new $.WebView({
		url: "http://vine.co",
		preinject: ['unpreloader'], // this prevents buffering every video in a feed. If you have a fast Mac and Internet, comment out this line
		postinject: ['styler'],
		agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 8_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Mobile/12B411" // mobile version doesnt autoplay on mouseover
	});
};

delegate; //return this to macpin
```

## Hacking MacPin
Its written in Swift using WKWebView and NSTabViewController with a fully programmatic NIB-less UI layout.  
You need [Xcode 9](https://developer.apple.com/xcode/) installed on OSX to get the Swift compiler and Cocoa headers.  
Otherwise `$EDITOR` and `make` are your fork and knife.

```
vim execs/MacPin.swift
vim modules/MacPin/*.swift
make test.app
# CTRL-D when finished debugging ...
make only=sim test.ios
```

Web Inspector can be accessed for any tab by right clicking in the page and selecting "Inspect Element" from the context menu.  
Debug builds (`make test|test.app|repl`) can be remotely inspected from Safari->Develop-><ComputerName>

The JavaScript API for app construction is undocumented and [non-final](https://github.com/kfix/MacPin/issues/11).  
If you want to play with it, run any MacPin app with the `-i` argument in Terminal to get a JS console (or `make repl`).  
Safari can also remotely inspect the `JSContext` of debug builds.

Browser functionality currently unimplementable in WKWebKit:
* Status Bar
  * Drag any link some distance to see a URL preview. Force Touch previewing should also work.
  * a JS emulation should be possible to preview any hovered links

Some things I just haven't had need to write, but wouldn't mind having:

* Global history
* Undo/redo for Tab closings

#### use MacPin to make hybrid apps from existing projects
```
cd ~/src/SomeWebApp
test -d browser/SomeWebApp.com &&
  make -C ~/src/MacPin macpin_sites=$PWD/browser appdir=$PWD/hybrid xcassetdir=$PWD/hybrid $PWD/hybrid/SomeWebApp.com.app
open hybrid/SomeWebApp.com.app
```

#### Safari Technology Preview
The future of MacPin is now!
[Install](https://developer.apple.com/safari/download/) Safari Technology Preview first.
use `make stp` & `make stp.app` to link and run MacPin against STP's WebKit.
This makes up-and-coming WKWebView changes (find UI, printing) actually work!

#### iOS

Basic support has landed for generating iOS apps.  
Its kinda pointless for most of `sites/*` since native apps exist for all of them.  
But maybe you want to quickly package a React.js application for offline mobile use...  

## Other WebKit browsers:

* [Firefox for iOS](https://github.com/mozilla/firefox-ios/): another Swift-based browser for iOS.
* [go-webkit2](https://github.com/sourcegraph/go-webkit2)
* [Puny Browser](https://github.com/ahungry/puny-browser)
