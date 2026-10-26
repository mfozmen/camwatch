import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

void main() {
  group('rtspUrl', () {
    test('has no user info without credentials', () {
      expect(rtspUrl('192.168.1.10', 554, '/live'), 'rtsp://192.168.1.10:554/live');
    });

    test('puts the credentials in the URL, escaping what the URL grammar owns', () {
      final url = rtspUrl(
        '192.168.1.10',
        554,
        '/live',
        const Credentials('ad:min', r'p@ss/w%rd#?'),
      );
      expect(url, 'rtsp://ad%3Amin:p%40ss%2Fw%25rd%23%3F@192.168.1.10:554/live');
      expect(Uri.parse(url).userInfo, 'ad%3Amin:p%40ss%2Fw%25rd%23%3F');
    });
  });

  group('Credentials', () {
    test('never prints the password', () {
      expect('${const Credentials('admin', 'secret')}', isNot(contains('secret')));
      expect('${const Credentials('admin', 'secret')}', contains('admin'));
    });

    test('compares by value', () {
      expect(const Credentials('a', 'b'), const Credentials('a', 'b'));
      expect(const Credentials('a', 'b').hashCode, const Credentials('a', 'b').hashCode);
      expect(const Credentials('a', 'b'), isNot(const Credentials('a', 'c')));
    });
  });

  test('firstPath finds the first path with a status', () {
    const result = {
      '/': PathStatus.needsAuth,
      '/live': PathStatus.open,
      '/h264': PathStatus.needsAuth,
    };
    expect(firstPath(result, PathStatus.open), '/live');
    expect(firstPath(result, PathStatus.needsAuth), '/');
    expect(firstPath(result, PathStatus.missing), isNull);
  });
}
