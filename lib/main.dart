import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'store.dart';
import 'workspace.dart';
import 'appearance.dart';
import 'package:flutter_quill/flutter_quill.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(Startup(args: args));
}

class Startup extends StatefulWidget {
  const Startup({super.key, required this.args});
  final List<String> args;
  @override
  State<Startup> createState() => _StartupState();
}

class _StartupState extends State<Startup> {
  WorkspaceStore? store;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    try {
      final support = await getApplicationSupportDirectory();
      final override = widget.args
          .where((a) => a.startsWith('--data-dir='))
          .firstOrNull;
      final db = WorkspaceStore(
        Directory(
          override == null
              ? '${support.path}/storyloom'
              : override.substring('--data-dir='.length),
        ),
      );
      await db.load(fast: true);
      await db.attachLegacyImages();
      await db.migrateFolders();
      if (mounted) setState(() => store = db);
    } catch (_) {
      if (mounted) {
        setState(() => error = '작업 공간을 열지 못했습니다. 저장 공간과 폴더 접근 권한을 확인하세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => store != null
      ? StoryloomApp(store: store!)
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ateliai',
                    style: TextStyle(fontFamily: 'Pretendard', fontSize: 32),
                  ),
                  const SizedBox(height: 24),
                  if (error == null)
                    const CircularProgressIndicator()
                  else
                    Text(error!),
                ],
              ),
            ),
          ),
        );
}

class StoryloomApp extends StatelessWidget {
  const StoryloomApp({super.key, required this.store});
  final WorkspaceStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store.settings,
    builder: (context, _) => buildApp(context),
  );
  Widget buildApp(BuildContext context) {
    StudioColors.configure(store.preferences);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: StudioColors.line),
    );
    return MaterialApp(
      title: 'Ateliai',
      builder: (context, child) => Listener(
        onPointerDown: (_) {
          if (Platform.isWindows) {
            const MethodChannel(
              'storyloom/ime',
            ).invokeMethod<void>('capture').catchError((_) {});
          }
        },
        child: child!,
      ),
      debugShowCheckedModeBanner: false,
      locale: Locale('ko'),
      supportedLocales: [Locale('ko'), Locale('en')],
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        hoverColor: StudioColors.hover,
        popupMenuTheme: PopupMenuThemeData(
          color: StudioColors.raised,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: StudioColors.line),
          ),
        ),
        tooltipTheme: TooltipThemeData(
          waitDuration: Duration(milliseconds: 500),
        ),
        brightness: StudioColors.palette.light
            ? Brightness.light
            : Brightness.dark,
        fontFamily: 'Pretendard',
        textTheme: Typography.englishLike2021.apply(
          fontFamily: 'Pretendard',
          fontSizeDelta: 4,
          bodyColor: StudioColors.text,
          displayColor: StudioColors.text,
        ),
        scaffoldBackgroundColor: StudioColors.base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: StudioColors.accent,
          brightness: StudioColors.palette.light
              ? Brightness.light
              : Brightness.dark,
          primary: StudioColors.accent,
          onPrimary: StudioColors.palette.light
              ? Colors.white
              : Color(0xff20251b),
          surface: StudioColors.panel,
          onSurface: StudioColors.text,
          outline: StudioColors.line,
        ),
        dividerColor: StudioColors.line,
        dividerTheme: DividerThemeData(color: StudioColors.line, thickness: 1),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: StudioColors.base,
          contentPadding: EdgeInsets.all(14),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: StudioColors.accent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: Size(96, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(96, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: Size(96, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: Size(40, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: StudioColors.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        cardTheme: CardThemeData(
          color: StudioColors.raised,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: ColoredBox(
        color: StudioColors.base,
        child: Stack(
          children: [
            Positioned.fill(child: WallpaperLayer(store: store)),
            Positioned.fill(child: Workspace(store: store)),
          ],
        ),
      ),
    );
  }
}
