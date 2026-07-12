import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:core/src/security/url_scanner.dart';

/// Entry-point for the browser extension helper bundle.
///
/// Registers two JavaScript-callable functions on `globalThis`:
///
/// * `extractDomain(url)` — delegates to [UrlScanner.extractDomain] and
///   returns the eTLD+1 of [url] as a JavaScript string.
/// * `matchOrigins(pageUrl, itemUrl)` — returns `true` when [pageUrl] and
///   [itemUrl] share the same effective domain, enabling autofill matching
///   without leaking full URL paths to the browser extension context.
void main() {
  globalContext.setProperty(
    'extractDomain'.toJS,
    ((JSString url) => UrlScanner.extractDomain(url.toDart).toJS).toJS,
  );

  globalContext.setProperty(
    'matchOrigins'.toJS,
    ((JSString pageUrl, JSString itemUrl) {
      final pageDomain = UrlScanner.extractDomain(pageUrl.toDart);
      final itemDomain = UrlScanner.extractDomain(itemUrl.toDart);
      return (pageDomain == itemDomain).toJS;
    }).toJS,
  );
}
