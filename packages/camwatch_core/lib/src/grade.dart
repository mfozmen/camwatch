import 'rtsp_paths.dart';
import 'ws_discovery.dart';

/// How exposed a device is, best to worst; also the weight of one finding.
enum Grade { green, amber, red }

/// One thing that makes a device easy to break into, with what to do about it.
class Finding {
  const Finding(this.grade, this.title, this.advice);

  final Grade grade;
  final String title;
  final String advice;

  @override
  bool operator ==(Object other) =>
      other is Finding && other.grade == grade && other.title == title && other.advice == advice;

  @override
  int get hashCode => Object.hash(grade, title, advice);

  @override
  String toString() => 'Finding(${grade.name}, $title)';
}

const _openStream = Finding(
  Grade.red,
  'Anyone on the network can watch the stream',
  'Set a password on the camera, or turn on RTSP authentication in its settings.',
);

const _telnet = Finding(
  Grade.red,
  'Telnet is open',
  'Telnet sends passwords in plain text and is how camera botnets get in. '
      'Turn it off, or update the firmware if there is no switch.',
);

const _xmeye = Finding(
  Grade.red,
  'The XMeye DVR port is open',
  'Port 34567 has built-in accounts that botnets log into. Put the device on its '
      'own network segment, or replace it: firmware rarely closes this.',
);

const _ssh = Finding(
  Grade.amber,
  'SSH is open',
  'Many cameras ship SSH with a root password you cannot change. Turn it off, '
      'or make sure the password is yours.',
);

const _dahua = Finding(
  Grade.amber,
  'The Dahua protocol port is open',
  'Port 37777 is a private control channel that old firmware leaves without a '
      'login. Keep the firmware current; most Dahua devices cannot turn this port off, '
      'so keep the camera off any network guests use.',
);

const _plainWeb = Finding(
  Grade.amber,
  'The web page has no HTTPS',
  'Logins to its web page cross your network unencrypted. Turn on HTTPS if the '
      'camera offers it.',
);

/// The finding an RTSP device carries until its stream check has run; the
/// app drops it while that check is in flight.
const uncheckedStream = Finding(
  Grade.amber,
  'The stream has not been checked yet',
  'Open the camera once: camwatch then sees whether it asks for a password.',
);

const _sdk = Finding(
  Grade.amber,
  'The vendor SDK port is open',
  'Port 8000 is a private control channel with a history of holes. Turn it off '
      'unless a recorder needs it, and keep the firmware current.',
);

const _ftp = Finding(
  Grade.amber,
  'FTP is open',
  'FTP sends logins and recordings in plain text. Turn it off unless you use it.',
);

/// What makes [device] easy to break into, worst first, given its open ports
/// and what the stream check found on it; [streams] is empty until that check
/// has run, and a stream never checked is not green.
List<Finding> findings(Device device, Map<String, PathStatus> streams) {
  final ports = device.openPorts;
  final hasWeb = ports.contains(80) || ports.contains(8080);
  return [
    if (streams.containsValue(PathStatus.open)) _openStream,
    if (ports.contains(23)) _telnet,
    if (ports.contains(34567)) _xmeye,
    if (hasWeb && !ports.contains(443)) _plainWeb,
    if (ports.contains(22)) _ssh,
    if (ports.contains(21)) _ftp,
    if (ports.contains(8000)) _sdk,
    if (ports.contains(37777)) _dahua,
    if (device.rtspPort != null && streams.isEmpty) uncheckedStream,
  ];
}

/// The worst of [found], green when there is nothing to report.
Grade gradeOf(Iterable<Finding> found) =>
    found.fold(Grade.green, (worst, f) => f.grade.index > worst.index ? f.grade : worst);
