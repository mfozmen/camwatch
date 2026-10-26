import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

void main() {
  Device device(List<int> ports) => Device('192.168.1.10', openPorts: ports);

  group('findings', () {
    test('a stream anyone can watch is red', () {
      final found = findings(device([554]), {'/': PathStatus.needsAuth, '/live': PathStatus.open});
      expect(found, [
        const Finding(
          Grade.red,
          'Anyone on the network can watch the stream',
          'Set a password on the camera, or turn on RTSP authentication in its settings.',
        ),
      ]);
    });

    test('a stream behind a password, or none found, is no finding', () {
      expect(findings(device([554]), {'/': PathStatus.needsAuth}), isEmpty);
      expect(
        findings(device([554]), {'/': PathStatus.missing, '/live': PathStatus.error}),
        isEmpty,
      );
    });

    test('an RTSP port whose stream was never checked is amber, not green', () {
      expect(findings(device([554]), {}).single, uncheckedStream);
      expect(uncheckedStream.title, 'The stream has not been checked yet');
      expect(findings(device([80, 443]), {}), isEmpty);
    });

    test('telnet is red', () {
      expect(
        findings(device([23]), {}).single,
        const Finding(
          Grade.red,
          'Telnet is open',
          'Telnet sends passwords in plain text and is how camera botnets get in. '
              'Turn it off, or update the firmware if there is no switch.',
        ),
      );
    });

    test('a web page without HTTPS is amber, on 80 or 8080', () {
      const web = Finding(
        Grade.amber,
        'The web page has no HTTPS',
        'Logins to its web page cross your network unencrypted. Turn on HTTPS if the '
            'camera offers it.',
      );
      expect(findings(device([80]), {}), [web]);
      expect(findings(device([8080]), {}), [web]);
      expect(findings(device([80, 443]), {}), isEmpty);
    });

    test('FTP is amber', () {
      expect(
        findings(device([21]), {}).single,
        const Finding(
          Grade.amber,
          'FTP is open',
          'FTP sends logins and recordings in plain text. Turn it off unless you use it.',
        ),
      );
    });

    test('the vendor SDK port is amber', () {
      expect(
        findings(device([8000]), {}).single,
        const Finding(
          Grade.amber,
          'The vendor SDK port is open',
          'Port 8000 is a private control channel with a history of holes. Turn it off '
              'unless a recorder needs it, and keep the firmware current.',
        ),
      );
    });

    test('findings come worst first', () {
      final grades = findings(device([21, 23, 80, 554, 8000]), {
        '/': PathStatus.open,
      }).map((f) => f.grade);
      expect(grades, [Grade.red, Grade.red, Grade.amber, Grade.amber, Grade.amber]);
    });
  });

  group('gradeOf', () {
    test('is the worst finding, green without any', () {
      expect(gradeOf(const []), Grade.green);
      expect(gradeOf(findings(device([80]), {})), Grade.amber);
      expect(gradeOf(findings(device([80, 23]), {})), Grade.red);
    });
  });

  test('Finding compares by value and prints its title', () {
    const a = Finding(Grade.amber, 'FTP is open', 'advice');
    expect(a, const Finding(Grade.amber, 'FTP is open', 'advice'));
    expect(a.hashCode, const Finding(Grade.amber, 'FTP is open', 'advice').hashCode);
    expect(a, isNot(const Finding(Grade.red, 'FTP is open', 'advice')));
    expect(a.toString(), 'Finding(amber, FTP is open)');
  });
}
