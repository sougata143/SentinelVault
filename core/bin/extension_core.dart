import 'dart:js' as js;
import 'package:core/src/security/url_scanner.dart';

void main() {
  js.context['extractDomain'] = (String url) {
    return UrlScanner.extractDomain(url);
  };
  js.context['matchOrigins'] = (String pageUrl, String itemUrl) {
    final pageDomain = UrlScanner.extractDomain(pageUrl);
    final itemDomain = UrlScanner.extractDomain(itemUrl);
    return pageDomain == itemDomain;
  };
}
