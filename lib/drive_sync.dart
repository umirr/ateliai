import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';

class DriveSync {
  DriveSync(this.store, {this.clientFactory, this.accessToken});
  final WorkspaceStore store;
  final http.Client Function()? clientFactory;
  final Future<String> Function()? accessToken;
  static const storage = FlutterSecureStorage();
  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  bool busy = false;
  static bool androidReady = false;
  Future<String> token({bool interactive = false}) async {
    final config = store.preferences;
    if (Platform.isAndroid) {
      if (!androidReady) {
        await GoogleSignIn.instance.initialize(
          serverClientId: config['googleAndroidClient'] as String?,
        );
        androidReady = true;
      }
      final account = interactive
          ? await GoogleSignIn.instance.authenticate(scopeHint: [scope])
          : await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) throw const FormatException('Google 계정 연결이 필요합니다.');
      final auth =
          await account.authorizationClient.authorizationForScopes([scope]) ??
          (interactive
              ? await account.authorizationClient.authorizeScopes([scope])
              : null);
      if (auth == null) {
        throw const FormatException('Google Drive 접근 허용이 필요합니다.');
      }
      return auth.accessToken;
    }
    final clientId = config['googleDesktopClient'] as String? ?? '';
    if (clientId.isEmpty) {
      throw const FormatException('Google Cloud 데스크톱 OAuth 클라이언트 ID를 입력하세요.');
    }
    final refresh = await storage.read(key: 'storyloom.drive.refresh');
    final secret = await storage.read(key: 'storyloom.drive.secret');
    if (!interactive && refresh != null) {
      final res = await http
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            body: {
              'client_id': clientId,
              if (secret != null && secret.isNotEmpty) 'client_secret': secret,
              'refresh_token': refresh,
              'grant_type': 'refresh_token',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as Map)['access_token'] as String;
      }
      throw const FormatException('Google 연결이 만료되었습니다. 다시 연결하세요.');
    }
    if (!interactive) throw const FormatException('Google Drive를 먼저 연결하세요.');
    final rng = Random.secure();
    String random() => base64UrlEncode(
      List.generate(32, (_) => rng.nextInt(256)),
    ).replaceAll('=', '');
    final state = random(), verifier = random();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/callback';
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const FormatException('로그인 브라우저를 열 수 없습니다.');
      }
      final request = await server.first.timeout(const Duration(minutes: 3));
      final query = request.uri.queryParameters;
      final valid =
          request.uri.path == '/callback' &&
          query['state'] == state &&
          query['code'] != null;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        valid
            ? 'Connected. You can close this window.'
            : 'Authorization failed.',
      );
      await request.response.close();
      if (!valid) throw const FormatException('Google 로그인 확인에 실패했습니다.');
      final res = await http
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            body: {
              'client_id': clientId,
              if (secret != null && secret.isNotEmpty) 'client_secret': secret,
              'code': query['code']!,
              'code_verifier': verifier,
              'redirect_uri': redirect,
              'grant_type': 'authorization_code',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw FormatException('Google 토큰 발급 실패 (${res.statusCode})');
      }
      final data = jsonDecode(res.body) as Map;
      if (data['refresh_token'] != null) {
        await storage.write(
          key: 'storyloom.drive.refresh',
          value: data['refresh_token'] as String,
        );
      }
      return data['access_token'] as String;
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> connect() async {
    await token(interactive: true);
    await store.setPreferences({'driveEnabled': true});
  }

  Future<void> disconnect() async {
    await storage.delete(key: 'storyloom.drive.refresh');
    await store.setPreferences({'driveEnabled': false});
  }

  Future<String> sync() async {
    if (busy) return '동기화 중';
    busy = true;
    final client = clientFactory?.call() ?? http.Client();
    try {
      final access = await (accessToken?.call() ?? token());
      final headers = {'Authorization': 'Bearer $access'};
      final remote = <String, String>{};
      String? cursor;
      do {
        final res = await client
            .get(
              Uri.https('www.googleapis.com', '/drive/v3/files', {
                'spaces': 'appDataFolder',
                'fields': 'nextPageToken,files(id,name)',
                'pageSize': '1000',
                'q': 'trashed = false',
                'pageToken': ?cursor,
              }),
              headers: headers,
            )
            .timeout(const Duration(seconds: 40));
        if (res.statusCode != 200) {
          throw FormatException('Drive 목록 실패 (${res.statusCode})');
        }
        final data = jsonDecode(res.body) as Map;
        for (final f in data['files'] as List) {
          remote[f['name'] as String] = f['id'] as String;
        }
        cursor = data['nextPageToken'] as String?;
      } while (cursor != null);
      var downloaded = 0, uploaded = 0;
      final files = <String, File>{};
      for (final folder in ['revisions', 'media']) {
        await for (final f in Directory('${store.root.path}/$folder').list()) {
          if (f is! File || f.path.endsWith('.tmp')) continue;
          final name = f.uri.pathSegments.last;
          if (folder == 'revisions') {
            final r = jsonDecode(await f.readAsString()) as Map;
            if (['preferences', 'migration'].contains(r['type'])) continue;
          }
          files['$folder--$name'] = f;
        }
      }
      for (final e in remote.entries) {
        if (files.containsKey(e.key)) continue;
        final match = RegExp(
          r'^(revisions|media)--([a-zA-Z0-9._-]+)$',
        ).firstMatch(e.key);
        if (match == null || match[2] == '.' || match[2] == '..') continue;
        final target = File('${store.root.path}/${match[1]}/${match[2]}');
        final res = await client
            .get(
              Uri.https('www.googleapis.com', '/drive/v3/files/${e.value}', {
                'alt': 'media',
              }),
              headers: headers,
            )
            .timeout(const Duration(minutes: 2));
        if (res.statusCode != 200) {
          throw FormatException('Drive 다운로드 실패 (${res.statusCode})');
        }
        if (res.bodyBytes.length > 64 * 1024 * 1024) {
          throw const FormatException('64MB 이상 파일은 동기화할 수 없습니다.');
        }
        if (match[1] == 'revisions') {
          final r = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
          if (r['schema'] != 1 ||
              r['id'] is! String ||
              r['generation'] is! int ||
              r['revision'] is! String) {
            throw const FormatException('잘못된 동기화 데이터');
          }
          if (['preferences', 'migration'].contains(r['type'])) continue;
        }
        await File(
          '${target.path}.tmp',
        ).writeAsBytes(res.bodyBytes, flush: true);
        await File('${target.path}.tmp').rename(target.path);
        downloaded++;
      }
      for (final e in files.entries) {
        if (remote.containsKey(e.key)) continue;
        if (await e.value.length() > 64 * 1024 * 1024) {
          throw const FormatException('64MB 이상 파일은 동기화할 수 없습니다.');
        }
        final boundary = 'storyloom${WorkspaceStore.uuid.v4()}';
        final bytes = <int>[
          ...utf8.encode(
            '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode({
              'name': e.key,
              'parents': ['appDataFolder'],
            })}\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n',
          ),
          ...await e.value.readAsBytes(),
          ...utf8.encode('\r\n--$boundary--'),
        ];
        final res = await client
            .post(
              Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
                'uploadType': 'multipart',
              }),
              headers: {
                ...headers,
                'Content-Type': 'multipart/related; boundary=$boundary',
              },
              body: bytes,
            )
            .timeout(const Duration(minutes: 2));
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw FormatException('Drive 업로드 실패 (${res.statusCode})');
        }
        uploaded++;
      }
      if (downloaded > 0) await store.load();
      return '업로드 $uploaded · 다운로드 $downloaded';
    } finally {
      client.close();
      busy = false;
    }
  }
}

class DriveSettings extends StatefulWidget {
  const DriveSettings({super.key, required this.sync});
  final DriveSync sync;
  @override
  State<DriveSettings> createState() => _DriveSettingsState();
}

class _DriveSettingsState extends State<DriveSettings> {
  late final desktop = TextEditingController(
    text: widget.sync.store.preferences['googleDesktopClient'] as String? ?? '',
  );
  late final android = TextEditingController(
    text: widget.sync.store.preferences['googleAndroidClient'] as String? ?? '',
  );
  final secret = TextEditingController();
  bool busy = false;
  String status = '';
  @override
  void dispose() {
    desktop.dispose();
    android.dispose();
    secret.dispose();
    super.dispose();
  }

  Future<void> run(Future<String> Function() work) async {
    setState(() => busy = true);
    try {
      final result = await work();
      if (mounted) setState(() => status = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => status = e is FormatException
              ? e.message
              : '연결 실패. 계정과 네트워크를 확인하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Google Drive 동기화',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '같은 Google 계정으로 기기들을 연결합니다. 최초 설정은 Google Cloud의 Drive API와 OAuth 클라이언트 구성이 필요합니다. 동기화는 앱 실행 중 작동합니다.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: desktop,
        decoration: const InputDecoration(labelText: '데스크톱 OAuth 클라이언트 ID'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: secret,
        obscureText: true,
        decoration: const InputDecoration(labelText: '데스크톱 OAuth 클라이언트 시크릿'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: android,
        decoration: const InputDecoration(
          labelText: 'Android용 서버 클라이언트 ID (웹 클라이언트)',
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.sync.store.setPreferences({
                      'googleDesktopClient': desktop.text.trim(),
                      'googleAndroidClient': android.text.trim(),
                    });
                    if (secret.text.isNotEmpty) {
                      await DriveSync.storage.write(
                        key: 'storyloom.drive.secret',
                        value: secret.text.trim(),
                      );
                    }
                    await widget.sync.connect();
                    return '연결 완료';
                  }),
            child: const Text('Google 연결'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(widget.sync.sync),
            child: const Text('지금 동기화'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.sync.disconnect();
                    return '연결 해제';
                  }),
            child: const Text('연결 해제'),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      Text(status),
    ],
  );
}
