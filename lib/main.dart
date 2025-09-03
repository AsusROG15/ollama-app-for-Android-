import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ollama_app_for_Android_/features/settings/settings_screen.dart';
import 'package:ollama_app_for_Android_/features/welcome/welcome_screen.dart';
import 'worker_setter.dart';

import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visibility_detector/visibility_detector.dart';
// import 'package:http/http.dart' as http;
import 'package:ollama_dart/ollama_dart.dart' as llama;
import 'package:dartx/dartx.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

// client configuration

// use host or not, if false dialog is shown
const useHost = false;
// host of ollama, must be accessible from the client, without trailing slash, will always be accepted as valid
const fixedHost = "http://example.com:11434";
// use model or not, if false selector is shown
const useModel = false;
// model name as string, must be valid ollama model!
const fixedModel = "gemma";
// recommended models, shown with as star in model selector
const recommendedModels = ["gemma", "llama3"];
// allow opening of settings
const allowSettings = true;
// allow multiple chats
const allowMultipleChats = true;

// client configuration end

SharedPreferences? prefs;
ThemeData? theme;
ThemeData? themeDark;

String? model;
String? host;

bool multimodal = false;

List<types.Message> messages = [];
String? chatUuid;
bool chatAllowed = true;

final user = types.User(id: const Uuid().v4());
final assistant = types.User(id: const Uuid().v4());

bool settingsOpen = false;

void main() {
  runApp(const App());

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    doWhenWindowReady(() {
      appWindow.minSize = const Size(600, 450);
      appWindow.size = const Size(1200, 650);
      appWindow.alignment = Alignment.center;
      appWindow.show();
    });
  }
}

class App extends StatefulWidget {
  const App({
    super.key,
  });

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();

    void load() async {
      try {
      await FlutterDisplayMode.setHighRefreshRate();
      } catch (_) {}
      SharedPreferences.setPrefix("ollama.");
      SharedPreferences tmp = await SharedPreferences.getInstance();
      setState(() {
        prefs = tmp;
      });
    }

    load();

    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        if (!(prefs?.getBool("useDeviceTheme") ?? false)) {
          theme = ThemeData.from(
              colorScheme: const ColorScheme(
                  brightness: Brightness.light,
                  primary: Colors.black,
                  onPrimary: Colors.white,
                  secondary: Colors.white,
                  onSecondary: Colors.black,
                  error: Colors.red,
                  onError: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black));
          themeDark = ThemeData.from(
              colorScheme: const ColorScheme(
                  brightness: Brightness.dark,
                  primary: Colors.white,
                  onPrimary: Colors.black,
                  secondary: Colors.black,
                  onSecondary: Colors.white,
                  error: Colors.red,
                  onError: Colors.black,
                  surface: Colors.black,
                  onSurface: Colors.white));
          setState(() {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: (deviceLocales, supportedLocales) {
          if (deviceLocales != null) {
            for (final locale in deviceLocales) {
              var newLocale = Locale(locale.languageCode);
              if (supportedLocales.contains(newLocale)) {
                return locale;
              }
            }
          }
          return const Locale("en");
        },
        title: "Ollama",
        theme: theme,
        darkTheme: themeDark,
        themeMode: ((prefs?.getString("brightness") ?? "system") == "system")
            ? ThemeMode.system
            : ((prefs!.getString("brightness") == "dark")
                ? ThemeMode.dark
                : ThemeMode.light),
        home: const MainApp());
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool logoVisible = true;
  bool menuVisible = false;

  int tipId = Random().nextInt(5);
  bool sendable = false;

  List<Widget> sidebar(BuildContext context, Function setState) {
    return List.from([
      ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
              MediaQuery.of(context).size.width >= 1000)
          ? const SizedBox.shrink()
          : (Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: InkWell(
                  customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(50))),
                  onTap: () {},
                  child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 16),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 16, right: 12),
                            child: ImageIcon(AssetImage("assets/logo512.png"))),
                        Expanded(
                          child: Text(AppLocalizations.of(context)!.appTitle,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 16),
                      ]))))),
      ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
              MediaQuery.of(context).size.width >= 1000)
          ? const SizedBox.shrink()
          : (!allowMultipleChats && !allowSettings)
              ? const SizedBox.shrink()
              : const Divider(),
      (allowMultipleChats)
          ? (Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: InkWell(
                  customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(50))),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (!(Platform.isWindows ||
                            Platform.isLinux ||
                            Platform.isMacOS) &&
                        MediaQuery.of(context).size.width <= 1000) {
                      Navigator.of(context).pop();
                    }
                    if (!chatAllowed) return;
                    chatUuid = null;
                    messages = [];
                    setState(() {});
                  },
                  child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 16),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 16, right: 12),
                            child: Icon(Icons.add_rounded)),
                        Expanded(
                          child: Text(
                              AppLocalizations.of(context)!.optionNewChat,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 16),
                      ])))))
          : const SizedBox.shrink(),
      (allowSettings)
          ? (Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: InkWell(
                  customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(50))),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (!(Platform.isWindows ||
                            Platform.isLinux ||
                            Platform.isMacOS) &&
                        MediaQuery.of(context).size.width <= 1000) {
                      Navigator.of(context).pop();
                    }
                    setState(() {
                      settingsOpen = true;
                    });
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ScreenSettings()));
                  },
                  child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 16),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 16, right: 12),
                            child: Icon(Icons.dns_rounded)),
                        Expanded(
                          child: Text(
                              AppLocalizations.of(context)!.optionSettings,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 16),
                      ])))))
          : const SizedBox.shrink(),
      Divider(
          color:
              ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
                      MediaQuery.of(context).size.width >= 1000)
                  ? (Theme.of(context).brightness == Brightness.light)
                      ? Colors.grey[400]
                      : Colors.grey[900]
                  : null),
      ((prefs?.getStringList("chats") ?? []).isNotEmpty)
          ? const SizedBox.shrink()
          : (Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: InkWell(
                  customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(50))),
                  onTap: () {
                    HapticFeedback.selectionClick();
                  },
                  child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 16),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 16, right: 12),
                            child: Icon(Icons.question_mark_rounded,
                                color: Colors.grey)),
                        Expanded(
                          child: Text(
                              AppLocalizations.of(context)!.optionNoChatFound,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey)),
                        ),
                        const SizedBox(width: 16),
                      ]))))),
      Builder(builder: (context) {
        String tip = (tipId == 0)
            ? AppLocalizations.of(context)!.tip0
            : (tipId == 1)
                ? AppLocalizations.of(context)!.tip1
                : (tipId == 2)
                    ? AppLocalizations.of(context)!.tip2
                    : (tipId == 3)
                        ? AppLocalizations.of(context)!.tip3
                        : AppLocalizations.of(context)!.tip4;
        return (!(prefs?.getBool("tips") ?? true) ||
                (prefs?.getStringList("chats") ?? []).isNotEmpty ||
                !allowSettings)
            ? const SizedBox.shrink()
            : (Padding(
                padding: const EdgeInsets.only(left: 12, right: 12),
                child: InkWell(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  enableFeedback: false,
                  hoverColor: Colors.transparent,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      tipId = Random().nextInt(5);
                    });
                  },
                  child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 16),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 16, right: 12),
                            child: Icon(Icons.tips_and_updates_rounded,
                                color: Colors.grey)),
                        Expanded(
                          child: Text(
                              AppLocalizations.of(context)!.tipPrefix + tip,
                              softWrap: true,
                              maxLines: 3,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey)),
                        ),
                        const SizedBox(width: 16),
                      ])), 
                )));
      }),
    ])
      ..addAll((prefs?.getStringList("chats") ?? []).map((item) {
        return Dismissible(
            key: Key(jsonDecode(item)["uuid"]),
            direction: (chatAllowed)
                ? DismissDirection.startToEnd
                : DismissDirection.none,
            confirmDismiss: (direction) async {
              bool returnValue = false;
              if (!chatAllowed) return false;

              if (prefs!.getBool("askBeforeDeletion") ?? false) {
                await showDialog(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(builder: (context, setLocalState) {
                        return AlertDialog(
                            title: Text(AppLocalizations.of(context)!
                                .deleteDialogTitle),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(AppLocalizations.of(context)!
                                      .deleteDialogDescription),
                                ]),
                            actions: [
                              TextButton(
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.of(context).pop();
                                    returnValue = false;
                                  },
                                  child: Text(AppLocalizations.of(context)!
                                      .deleteDialogCancel)),
                              TextButton(
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.of(context).pop();
                                    returnValue = true;
                                  },
                                  child: Text(AppLocalizations.of(context)!
                                      .deleteDialogDelete))
                            ]);
                      });
                    });
              } else {
                returnValue = true;
              }
              return returnValue;
            },
            onDismissed: (direction) {
              HapticFeedback.selectionClick();
              for (var i = 0;
                  i < (prefs!.getStringList("chats") ?? []).length;
                  i++) {
                if (jsonDecode(
                        (prefs!.getStringList("chats") ?? [])[i])["uuid"] ==
                    jsonDecode(item)["uuid"]) {
                  List<String> tmp = prefs!.getStringList("chats")!;
                  tmp.removeAt(i);
                  prefs!.setStringList("chats", tmp);
                  break;
                }
              }
              if (chatUuid == jsonDecode(item)["uuid"]) {
                messages = [];
                chatUuid = null;
                if (!(Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS) &&
                    MediaQuery.of(context).size.width <= 1000) {
                  Navigator.of(context).pop();
                }
              }
              setState(() {});
            },
            child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 12),
                child: InkWell(
                    customBorder: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(50))),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (!(Platform.isWindows ||
                              Platform.isLinux ||
                              Platform.isMacOS) &&
                          MediaQuery.of(context).size.width <= 1000) {
                        Navigator.of(context).pop();
                      }
                      if (!chatAllowed) return;
                      loadChat(jsonDecode(item)["uuid"], setState);
                      chatUuid = jsonDecode(item)["uuid"];
                    },
                    onLongPress: () async {
                      HapticFeedback.selectionClick();
                      if (!chatAllowed) return;
                      if (!allowSettings) return;
                      String oldTitle = jsonDecode(item)["title"];
                      var newTitle = await prompt(context,
                          title:
                              AppLocalizations.of(context)!.dialogEnterNewTitle,
                          value: oldTitle,
                          uuid: jsonDecode(item)["uuid"]);
                      var tmp = (prefs!.getStringList("chats") ?? []);
                      for (var i = 0; i < tmp.length; i++) {
                        if (jsonDecode((prefs!.getStringList("chats") ??
                                [])[i])["uuid"] ==
                            jsonDecode(item)["uuid"]) {
                          var tmp2 = jsonDecode(tmp[i]);
                          tmp2["title"] = newTitle;
                          tmp[i] = jsonEncode(tmp2);
                          break;
                        }
                      }
                      prefs!.setStringList("chats", tmp);
                      setState(() {});
                    },
                    child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 16),
                        child: Row(children: [
                          Padding(
                              padding:
                                  const EdgeInsets.only(left: 16, right: 16),
                              child: Icon((chatUuid == jsonDecode(item)["uuid"]) 
                                  ? Icons.location_on_rounded
                                  : Icons.restore_rounded)),
                          Expanded(
                            child: Text(jsonDecode(item)["title"],
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(width: 16),
                        ])))));
      }).toList());
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        if (prefs == null) {
          await Future.doWhile(
              () => Future.delayed(const Duration(milliseconds: 1)).then((_) {
                    return prefs == null;
                  }));
        }

        void setBrightness() {
          WidgetsBinding
              .instance.platformDispatcher.onPlatformBrightnessChanged = () {
            // invert colors used, because brightness not updated yet
            SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                systemNavigationBarColor:
                    (prefs!.getString("brightness") ?? "system") == "system"
                        ? ((MediaQuery.of(context).platformBrightness ==
                                Brightness.light)
                            ? (themeDark ?? ThemeData.dark())
                                .colorScheme
                                .surface
                            : (theme ?? ThemeData()).colorScheme.surface)
                        : (prefs!.getString("brightness") == "dark"
                            ? (themeDark ?? ThemeData()).colorScheme.surface
                            : (theme ?? ThemeData.dark()).colorScheme.surface),
                systemNavigationBarIconBrightness:
                    (((prefs!.getString("brightness") ?? "system") ==
                                    "system" &&
                                MediaQuery.of(context).platformBrightness ==
                                    Brightness.dark) ||
                            prefs!.getString("brightness") == "light")
                        ? Brightness.dark
                        : Brightness.light));
          };

          // brightness changed function not run at first startup
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
              systemNavigationBarColor:
                  (prefs!.getString("brightness") ?? "system") == "system"
                      ? ((MediaQuery.of(context).platformBrightness ==
                              Brightness.light)
                          ? (theme ?? ThemeData.dark()).colorScheme.surface
                          : (themeDark ?? ThemeData()).colorScheme.surface)
                      : (prefs!.getString("brightness") == "dark"
                          ? (themeDark ?? ThemeData()).colorScheme.surface
                          : (theme ?? ThemeData.dark()).colorScheme.surface),
              systemNavigationBarIconBrightness:
                  (((prefs!.getString("brightness") ?? "system") == "system" &&
                              MediaQuery.of(context).platformBrightness ==
                                  Brightness.light) ||
                          prefs!.getString("brightness") == "light")
                      ? Brightness.dark
                      : Brightness.light));
        }

        setBrightness();

        // prefs!.remove("welcomeFinished");
        if (!(prefs!.getBool("welcomeFinished") ?? false) && allowSettings) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const ScreenWelcome()));
          return;
        }

        if (!(allowSettings || useHost)) {
          showDialog(
              // ignore: use_build_context_synchronously
              context: context,
              builder: (context) {
                return const PopScope(
                    canPop: false,
                    child: Dialog.fullscreen(
                        backgroundColor: Colors.black,
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                "*Build Error:*

useHost: $useHost
allowSettings: $allowSettings

You created this build? One of them must be set to true or the app is not functional!\n\nYou received this build by someone else? Please contact them and report the issue.",
                                style: TextStyle(color: Colors.red))))));
              });
        }

        if (!allowMultipleChats &&
            (prefs!.getStringList("chats") ?? []).isNotEmpty) {
          chatUuid =
              jsonDecode((prefs!.getStringList("chats") ?? [])[0])["uuid"];
          loadChat(chatUuid!, setState);
        }

        setState(() {
          model = useModel ? fixedModel : prefs!.getString("model");
          chatAllowed = !(model == null);
          multimodal = prefs?.getBool("multimodal") ?? false;
          host = useHost ? fixedHost : prefs?.getString("host");
        });

        if (host == null) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              // ignore: use_build_context_synchronously
              content: Text(AppLocalizations.of(context)!.noHostSelected),
              showCloseIcon: true));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget selector = InkWell(
        onTap: () {
          if (host == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(AppLocalizations.of(context)!.noHostSelected),
                showCloseIcon: true));
            return;
          }
          setModel(context, setState);
        },
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        enableFeedback: false,
        hoverColor: Colors.transparent,
        child: SizedBox(
            height: 200,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                      child: Text(
                          (model ??
                                  AppLocalizations.of(context)!.noSelectedModel)
                              .split(":")[0],
                          overflow: TextOverflow.fade,
                          style: const TextStyle(
                              fontFamily: "monospace", fontSize: 16))),
                  useModel
                      ? const SizedBox.shrink()
                      : const Icon(Icons.expand_more_rounded)
                ])));

    return WindowBorder(
      color: Theme.of(context).colorScheme.surface,
      child: Scaffold(
          appBar: AppBar(
              title: Row(
                children: [
                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                      ? SizedBox(width: 85, height: 200, child: MoveWindow())
                      : const SizedBox.shrink(),
                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                      ? Expanded(
                          child: SizedBox(height: 200, child: MoveWindow()))
                      : const SizedBox.shrink(),
                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                      ? selector
                      : Expanded(child: selector),
                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                      ? Expanded(
                          child: SizedBox(height: 200, child: MoveWindow()))
                      : const SizedBox.shrink(),
                ],
              ),
              actions: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)
                  ? [
                      SizedBox(
                          height: 200,
                          child: WindowTitleBarBox(
                              child: Row(
                            children: [
                              // Expanded(child: MoveWindow()),
                              SizedBox(
                                  height: 200,
                                  child: MinimizeWindowButton(
                                      animate: true,
                                      colors: WindowButtonColors(
                                          iconNormal: Theme.of(context)
                                              .colorScheme
                                              .primary))),
                              SizedBox(
                                  height: 72,
                                  child: MaximizeWindowButton(
                                      animate: true,
                                      colors: WindowButtonColors(
                                          iconNormal: Theme.of(context)
                                              .colorScheme
                                              .primary))),
                              SizedBox(
                                  height: 72,
                                  child: CloseWindowButton(
                                      animate: true,
                                      colors: WindowButtonColors(
                                          iconNormal: Theme.of(context)
                                              .colorScheme
                                              .primary))),
                            ],
                          )))
                    ]
                  : [
                      const SizedBox(width: 4),
                      IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            if (!chatAllowed) return;

                            if (prefs!.getBool("askBeforeDeletion") ??
                                // ignore: dead_code
                                false && messages.isNotEmpty) {
                              showDialog(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                        builder: (context, setLocalState) {
                                      return AlertDialog(
                                          title: Text(
                                              AppLocalizations.of(context)!
                                                  .deleteDialogTitle),
                                          content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(AppLocalizations.of(context)!
                                                    .deleteDialogDescription),
                                              ]),
                                          actions: [
                                            TextButton(
                                                onPressed: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  Navigator.of(context).pop();
                                                },
                                                child: Text(AppLocalizations.of(context)!
                                                    .deleteDialogCancel)),
                                            TextButton(
                                                onPressed: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  Navigator.of(context).pop();

                                                  for (var i = 0;
                                                      i <
                                                          (prefs!.getStringList(
                                                                      "chats") ??
                                                                  [])
                                                              .length;
                                                      i++) {
                                                    if (jsonDecode((prefs!.
                                                                getStringList(
                                                                    "chats") ??
                                                            [])[i])["uuid"] ==
                                                        chatUuid) {
                                                      List<String> tmp = prefs!.getStringList("chats")!;
                                                      tmp.removeAt(i);
                                                      prefs!.setStringList("chats", tmp);
                                                      break;
                                                    }
                                                  }
                                                  messages = [];
                                                  chatUuid = null;
                                                  setState(() {});
                                                },
                                                child: Text(AppLocalizations.of(context)!
                                                    .deleteDialogDelete))
                                          ]);
                                    });
                                  });
                            } else {
                              for (var i = 0;
                                  i <
                                      (prefs!.getStringList("chats") ?? [])
                                          .length;
                                  i++) {
                                if (jsonDecode((prefs!.getStringList("chats") ??
                                        [])[i])["uuid"] ==
                                    chatUuid) {
                                  List<String> tmp =
                                      prefs!.getStringList("chats")!;
                                  tmp.removeAt(i);
                                  prefs!.setStringList("chats", tmp);
                                  break;
                                }
                              }
                              messages = [];
                              chatUuid = null;
                            }
                            setState(() {});
                          },
                          icon: const Icon(Icons.restart_alt_rounded))
                    ],
              bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: (!chatAllowed && model != null)
                      ? const LinearProgressIndicator()
                      : ((Platform.isWindows ||
                                  Platform.isLinux ||
                                  Platform.isMacOS) &&
                              MediaQuery.of(context).size.width >= 1000)
                          ? AnimatedOpacity(
                              opacity: menuVisible ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 500),
                              child: Divider(
                                  height: 2,
                                  color:
                                      (Theme.of(context).brightness ==
                                              Brightness.light)
                                          ? Colors.grey[400]
                                          : Colors.grey[900]))
                          : const SizedBox.shrink()),
              leading: ((Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS) &&
                      MediaQuery.of(context).size.width >= 1000)
                  ? const SizedBox()
                  : null),
          body: Row(
            children: [
              ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
                      MediaQuery.of(context).size.width >= 1000)
                  ? SizedBox(
                      width: 304,
                      height: double.infinity,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: VisibilityDetector(
                              key: const Key("menuVisible"),
                              onVisibilityChanged: (VisibilityInfo info) {
                                if (settingsOpen) return;
                                menuVisible = info.visibleFraction > 0;
                                try {
                                  setState(() {});
                                } catch (_) {}
                              },
                              child: AnimatedOpacity(
                                  opacity: menuVisible ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 500),
                                  child: ListView(
                                      children: sidebar(context, setState))))))
                  : const SizedBox.shrink(),
              ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
                      MediaQuery.of(context).size.width >= 1000)
                  ? AnimatedOpacity(
                      opacity: menuVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: VerticalDivider(
                          width: 2,
                          color:
                              (Theme.of(context).brightness == Brightness.light)
                                  ? Colors.grey[400]
                                  : Colors.grey[900]))
                  : const SizedBox.shrink(),
              Expanded(
                  child: Chat(
                      messages: messages,
                      textMessageBuilder: (p0,
                          {required messageWidth, required showName}) {
                        var white = const TextStyle(color: Colors.white);
                        return Padding(
                            padding: const EdgeInsets.only(
                                left: 20, right: 23, top: 17, bottom: 17),
                            child: MarkdownBody(
                                data: p0.text,
                                onTapLink: (text, href, title) async {
                                  HapticFeedback.selectionClick();
                                  try {
                                    var url = Uri.parse(href!);
                                    if (await canLaunchUrl(url)) {
                                      launchUrl(
                                          mode: LaunchMode.inAppBrowserView,
                                          url);
                                    } else {
                                      throw Exception();
                                    }
                                  } catch (_) {
                                    // ignore: use_build_context_synchronously
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                // ignore: use_build_context_synchronously
                                                AppLocalizations.of(context)!
                                                    .settingsHostInvalid(
                                                        "url"))
                                            showCloseIcon: true));
                                  }
                                },
                                extensionSet: md.ExtensionSet(
                                  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                                  <md.InlineSyntax>[
                                    md.EmojiSyntax(),
                                    ...md.ExtensionSet.gitHubFlavored
                                        .inlineSyntaxes
                                  ],
                                ),
                                imageBuilder: (uri, title, alt) {
                                  if (uri.isAbsolute) {
                                    return Image.network(uri.toString(),
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                      return InkWell(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        AppLocalizations.of(
                                                                context)!
                                                            .notAValidImage),
                                                    showCloseIcon: true));
                                          },
                                          child: Container(
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  color: Theme.of(context)
                                                              .brightness ==
                                                          Brightness.light
                                                      ? Colors.white
                                                      : Colors.black),
                                              padding: const EdgeInsets.only(
                                                  left: 100,
                                                  right: 100,
                                                  top: 32),
                                              child: const Image(
                                                  image: AssetImage(
                                                      "assets/logo512error.png"))));
                                    });
                                  } else {
                                    return InkWell(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      AppLocalizations.of(
                                                              context)!
                                                          .notAValidImage),
                                                  showCloseIcon: true));
                                        },
                                        child: Container(
                                            decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: Theme.of(context)
                                                            .brightness ==
                                                        Brightness.light
                                                    ? Colors.white
                                                    : Colors.black),
                                            padding: const EdgeInsets.only(
                                                left: 100, right: 100, top: 32),
                                            child: const Image(
                                                image: AssetImage(
                                                    "assets/logo512error.png"))));
                                  }
                                },
                                styleSheet: (p0.author == user)
                                    ? MarkdownStyleSheet(
                                        p: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500),
                                        blockquoteDecoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        code: const TextStyle(
                                            color: Colors.black,
                                            backgroundColor: Colors.white),
                                        codeblockDecoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        h1: white,
                                        h2: white,
                                        h3: white,
                                        h4: white,
                                        h5: white,
                                        h6: white,
                                        listBullet: white,
                                        horizontalRuleDecoration: BoxDecoration(
                                            border: Border(
                                                top: BorderSide(
                                                    color: Colors.grey[800]!,
                                                    width: 1))),
                                        tableBorder: TableBorder.all(
                                            color: Colors.white),
                                        tableBody: white)
                                    : (Theme.of(context).brightness ==
                                            Brightness.light)
                                        ? MarkdownStyleSheet(
                                            p: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500),
                                            blockquoteDecoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            code: const TextStyle(
                                                color: Colors.white,
                                                backgroundColor: Colors.black),
                                            codeblockDecoration: BoxDecoration(
                                                color: Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            horizontalRuleDecoration: BoxDecoration(
                                                border: Border(
                                                    top: BorderSide(
                                                        color:
                                                            Colors.grey[200]!,
                                                        width: 1))))
                                        : MarkdownStyleSheet(
                                            p: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500),
                                            blockquoteDecoration: BoxDecoration(
                                              color: Colors.grey[800]!,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            code: const TextStyle(
                                                color: Colors.black,
                                                backgroundColor: Colors.white),
                                            codeblockDecoration:
                                                BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                            horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1))))));
                      },
                      imageMessageBuilder: (p0, {required messageWidth}) {
                        return SizedBox(
                            width: ((Platform.isWindows ||
                                        Platform.isLinux ||
                                        Platform.isMacOS) &&
                                    MediaQuery.of(context).size.width >= 1000)
                                ? 360.0
                                : 160.0,
                            child:
                                MarkdownBody(data: "![${p0.name}](${p0.uri})"));
                      },
                      disableImageGallery: true,
                      // keyboardDismissBehavior:
                      //     ScrollViewKeyboardDismissBehavior.onDrag,
                      emptyState: Center(
                          child: VisibilityDetector(
                              key: const Key("logoVisible"),
                              onVisibilityChanged: (VisibilityInfo info) {
                                if (settingsOpen) return;
                                logoVisible = info.visibleFraction > 0;
                                try {
                                  setState(() {});
                                } catch (_) {}
                              },
                              child: AnimatedOpacity(
                                  opacity: logoVisible ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 500),
                                  child: const ImageIcon(
                                      AssetImage("assets/logo512.png"),
                                      size: 44)))),
                      onSendPressed: (p0) async {
                        HapticFeedback.selectionClick();
                        setState(() {
                          sendable = false;
                        });

                        if (host == null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  AppLocalizations.of(context)!.noHostSelected),
                              showCloseIcon: true));
                          return;
                        }

                        if (!chatAllowed || model == null) {
                          if (model == null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(AppLocalizations.of(context)!
                                    .noModelSelected),
                                showCloseIcon: true));
                          }
                          return;
                        }

                        bool newChat = false;
                        if (chatUuid == null) {
                          newChat = true;
                          chatUuid = const Uuid().v4();
                          prefs!.setStringList(
                              "chats",
                              (prefs!.getStringList("chats") ?? []).append([
                                jsonEncode({
                                  "title": AppLocalizations.of(context)!
                                      .newChatTitle,
                                  "uuid": chatUuid,
                                  "messages": []
                                })
                              ]).toList());
                        }

                        var system = prefs?.getString("system") ??
                            "You are a helpful assistant";
                        if (prefs!.getBool("noMarkdown") ?? false) {
                          system +=
                              " You must not use markdown or any other formatting language in any way!";
                        }

                        List<llama.Message> history = [
                          llama.Message(
                              role: llama.MessageRole.system, content: system)
                        ];
                        List<String> images = [];
                        for (var i = 0; i < messages.length; i++) {
                          if (jsonDecode(jsonEncode(messages[i]))["text"] != null) {
                            history.add(llama.Message(
                                role: (messages[i].author.id == user.id)
                                    ? llama.MessageRole.user
                                    : llama.MessageRole.system,
                                content:
                                    jsonDecode(jsonEncode(messages[i]))["text"],
                                images: (images.isNotEmpty) ? images : null));
                          } else {
                            var uri = jsonDecode(jsonEncode(messages[i]))["uri"]
                                as String;
                            String content = (uri
                                    .startsWith("data:image/png;base64,"))
                                ? uri.removePrefix("data:image/png;base64,")
                                : base64.encode(await File(uri).readAsBytes());
                            uri = uri.removePrefix("data:image/png;base64,");
                            images.add(content);
                          }
                        }

                        history.add(llama.Message(
                            role: llama.MessageRole.user,
                            content: p0.text.trim(),
                            images: (images.isNotEmpty) ? images : null));
                        messages.insert(
                            0,
                            types.TextMessage(
                                author: user,
                                id: const Uuid().v4(),
                                text: p0.text.trim()));

                        saveChat(chatUuid!, setState);

                        setState(() {});
                        chatAllowed = false;

                        String newId = const Uuid().v4();
                        llama.OllamaClient client = llama.OllamaClient(
                            headers: (jsonDecode(
                                        prefs!.getString("hostHeaders") ?? "{}")
                                    as Map)
                                .cast<String, String>(),
                            baseUrl: "$host/api");

                        try {
                          if ((prefs!.getString("requestType") ?? "stream") ==
                              "stream") {
                            final stream = client
                                .generateChatCompletionStream(
                                  request: llama.GenerateChatCompletionRequest(
                                    model: model!,
                                    messages: history,
                                    keepAlive: 1,
                                  ),
                                )
                                .timeout(const Duration(seconds: 15));

                            String text = "";
                            await for (final res in stream) {
                              text += (res.message?.content ?? "");
                              for (var i = 0; i < messages.length; i++) {
                                if (messages[i].id == newId) {
                                  messages.removeAt(i);
                                  break;
                                }
                              }
                              if (chatAllowed) return;
                              if (text.trim() == "") {
                                throw Exception();
                              }
                              messages.insert(
                                  0,
                                  types.TextMessage(
                                      author: assistant,
                                      id: newId,
                                      text: text));
                              setState(() {});
                              HapticFeedback.lightImpact();
                            }
                          } else {
                            llama.GenerateChatCompletionResponse request;
                            request = await client
                                .generateChatCompletion(
                                  request: llama.GenerateChatCompletionRequest(
                                    model: model!,
                                    messages: history,
                                    keepAlive: 1,
                                  ),
                                )
                                .timeout(const Duration(seconds: 15));
                            if (chatAllowed) return;
                            if (request.message!.content.trim() == "") {
                              throw Exception();
                            }
                            messages.insert(
                                0,
                                types.TextMessage(
                                    author: assistant,
                                    id: newId,
                                    text: request.message!.content));
                            setState(() {});
                            HapticFeedback.lightImpact();
                          }
                        } catch (e) {
                          for (var i = 0; i < messages.length; i++) {
                            if (messages[i].id == newId) {
                              messages.removeAt(i);
                              break;
                            }
                          }
                          setState(() {
                            chatAllowed = true;
                            messages.removeAt(0);
                            if (messages.isEmpty) {
                              var tmp = (prefs!.getStringList("chats") ?? []);
                              chatUuid = null;
                              for (var i = 0; i < tmp.length; i++) {
                                if (jsonDecode((prefs!.getStringList("chats") ??
                                        [])[i])["uuid"] ==
                                    chatUuid) {
                                  tmp.removeAt(i);
                                  prefs!.setStringList("chats", tmp);
                                  break;
                                }
                              }
                            }
                          });
                          // ignore: use_build_context_synchronously
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              // ignore: use_build_context_synchronously
                              content: Text(AppLocalizations.of(context)!
                                  .settingsHostInvalid("timeout")),
                              showCloseIcon: true));
                          return;
                        }

                        saveChat(chatUuid!, setState);

                        if (newChat &&
                            (prefs!.getBool("generateTitles") ?? true)) {
                          void setTitle() async {
                            List<Map<String, String>> history = [];
                            for (var i = 0; i < messages.length; i++) {
                              if (jsonDecode(jsonEncode(messages[i]))["text"] ==
                                  null) {
                                continue;
                              }
                              history.add({
                                "role": (messages[i].author == user)
                                    ? "user"
                                    : "assistant",
                                "content":
                                    jsonDecode(jsonEncode(messages[i]))["text"]
                              });
                            }
                            history = history.reversed.toList();

                            try {
                              final generated = await client.generateCompletion(
                                request: llama.GenerateCompletionRequest(
                                  model: model!,
                                  prompt:
                                      "You must not use markdown or any other formatting language! Create a short title for the subject of the conversation described in the following json object. It is not allowed to be too general; no 'Assistance', 'Help' or similar!\n\n```json
${jsonEncode(history)}
```",
                                ),
                              );
                              var title = generated.response! \
                                  .replaceAll("*", "") \
                                  .replaceAll("_", "") \
                                  .trim();
                              var tmp = (prefs!.getStringList("chats") ?? []);
                              for (var i = 0; i < tmp.length; i++) {
                                if (jsonDecode((prefs!.getStringList("chats") ??
                                        [])[i])["uuid"] ==
                                    chatUuid) {
                                  var tmp2 = jsonDecode(tmp[i]);
                                  tmp2["title"] = title;
                                  tmp[i] = jsonEncode(tmp2);
                                  break;
                                }
                              }
                              prefs!.setStringList("chats", tmp);
                            } catch (_) {}

                            setState(() {});
                          }

                          setTitle();
                        }

                        setState(() {});
                        chatAllowed = true;
                      },
                      onMessageDoubleTap: (context, p1) {
                        HapticFeedback.selectionClick();
                        if (!chatAllowed) return;
                        if (p1.author == assistant) return;
                        for (var i = 0; i < messages.length; i++) {
                          if (messages[i].id == p1.id) {
                            List messageList = 
                                (jsonDecode(jsonEncode(messages)) as List)
                                    .reversed
                                    .toList();
                            bool found = false;
                            List index = [];
                            for (var j = 0; j < messageList.length; j++) {
                              if (messageList[j]["id"] == p1.id) {
                                found = true;
                              }
                              if (found) {
                                index.add(messageList[j]["id"]);
                              }
                            }
                            for (var j = 0; j < index.length; j++) {
                              for (var k = 0; k < messages.length; k++) {
                                if (messages[k].id == index[j]) {
                                  messages.removeAt(k);
                                }
                              }
                            }
                            break;
                          }
                        }
                        saveChat(chatUuid!, setState);
                        setState(() {});
                      },
                      onMessageLongPress: (context, p1) async {
                        HapticFeedback.selectionClick();

                        if (!(prefs!.getBool("enableEditing") ?? false)) {
                          return;
                        }

                        var index = -1;
                        if (!chatAllowed) return;
                        for (var i = 0; i < messages.length; i++) {
                          if (messages[i].id == p1.id) {
                            index = i;
                            break;
                          }
                        }

                        var text = (messages[index] as types.TextMessage).text;
                        var input = await prompt(
                          context,
                          title: AppLocalizations.of(context)!
                              .dialogEditMessageTitle,
                          value: text,
                          keyboard: TextInputType.multiline,
                          maxLines: (text.length >= 100)
                              ? 10
                              : ((text.length >= 50) ? 5 : 3),
                        );
                        if (input == "") return;

                        messages[index] = types.TextMessage(
                          author: p1.author,
                          createdAt: p1.createdAt,
                          id: p1.id,
                          text: input,
                        );
                        setState(() {});
                      },
                      onAttachmentPressed: (!multimodal)
                          ? null
                          :
                          () {
                              HapticFeedback.selectionClick();
                              if (!chatAllowed || model == null) return;
                              if (Platform.isWindows ||
                                  Platform.isLinux ||
                                  Platform.isMacOS) {
                                HapticFeedback.selectionClick();

                                FilePicker.platform
                                    .pickFiles(type: FileType.image)
                                    .then((value) async {
                                  if (value == null) return;
                                  if (!multimodal) return;

                                  var encoded = base64.encode(
                                      await File(value.files.first.path!)
                                          .readAsBytes());
                                  messages.insert(
                                      0,
                                      types.ImageMessage(
                                          author: user,
                                          id: const Uuid().v4(),
                                          name: value.files.first.name,
                                          size: value.files.first.size,
                                          uri:
                                              "data:image/png;base64,$encoded"));

                                  setState(() {});
                                  HapticFeedback.selectionClick();
                                });

                                return;
                              }
                              showModalBottomSheet(
                                  context: context,
                                  builder: (context) {
                                    return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.only(
                                            left: 16, right: 16, top: 16),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton.icon(
                                                      onPressed: () async {
                                                        HapticFeedback
                                                            .selectionClick();

                                                        Navigator.of(context)
                                                            .pop();
                                                        final result = 
                                                            await ImagePicker()
                                                                .pickImage(
                                                          source: ImageSource
                                                              .camera,
                                                        );
                                                        if (result == null) {
                                                          return;
                                                        }

                                                        final bytes = 
                                                            await result
                                                                .readAsBytes();
                                                        final image = 
                                                            await decodeImageFromList(
                                                                bytes);

                                                        final message = 
                                                            types.ImageMessage(
                                                          author: user,
                                                          createdAt: DateTime
                                                                  .now()
                                                                  .millisecondsSinceEpoch,
                                                          height: image.height
                                                              .toDouble(),
                                                          id: const Uuid().v4(),
                                                          name: result.name,
                                                          size: bytes.length,
                                                          uri: result.path,
                                                          width: image.width
                                                              .toDouble(),
                                                        );

                                                        messages.insert(
                                                            0, message);
                                                        setState(() {});
                                                        HapticFeedback
                                                            .selectionClick();
                                                      },
                                                      icon: const Icon(Icons
                                                          .photo_camera_rounded),
                                                      label: Text(
                                                          AppLocalizations.of(
                                                                  context)!
                                                              .takeImage))),
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton.icon(
                                                      onPressed: () async {
                                                        HapticFeedback
                                                            .selectionClick();

                                                        Navigator.of(context)
                                                            .pop();
                                                        final result = 
                                                            await ImagePicker()
                                                                .pickImage(
                                                          source: ImageSource
                                                              .gallery,
                                                        );
                                                        if (result == null) {
                                                          return;
                                                        }

                                                        final bytes = 
                                                            await result
                                                                .readAsBytes();
                                                        final image = 
                                                            await decodeImageFromList(
                                                                bytes);

                                                        final message = 
                                                            types.ImageMessage(
                                                          author: user,
                                                          createdAt: DateTime
                                                                  .now()
                                                                  .millisecondsSinceEpoch,
                                                          height: image.height
                                                              .toDouble(),
                                                          id: const Uuid().v4(),
                                                          name: result.name,
                                                          size: bytes.length,
                                                          uri: result.path,
                                                          width: image.width
                                                              .toDouble(),
                                                        );

                                                        messages.insert(
                                                            0, message);
                                                        setState(() {});
                                                        HapticFeedback
                                                            .selectionClick();
                                                      },
                                                      icon: const Icon(
                                                          Icons.image_rounded),
                                                      label: Text(
                                                          AppLocalizations.of(
                                                                  context)!
                                                              .uploadImage)))
                                            ]));
                                  });
                            },
                      l10n: ChatL10nEn(
                          inputPlaceholder: AppLocalizations.of(context)!
                              .messageInputPlaceholder),
                      inputOptions: InputOptions(
                          keyboardType: TextInputType.multiline,
                          onTextChanged: (p0) {
                            setState(() {
                              sendable = p0.trim().isNotEmpty;
                            });
                          },
                          sendButtonVisibilityMode: (Platform.isWindows ||
                                  Platform.isLinux ||
                                  Platform.isMacOS)
                              ? SendButtonVisibilityMode.always
                              : (sendable)
                                  ? SendButtonVisibilityMode.always
                                  : SendButtonVisibilityMode.hidden),
                      user: user,
                      hideBackgroundOnEmojiMessages: false,
                      theme: (Theme.of(context).brightness == Brightness.light)
                          ? DefaultChatTheme(
                              backgroundColor:
                                  (theme ?? ThemeData()).colorScheme.surface,
                              primaryColor:
                                  (theme ?? ThemeData()).colorScheme.primary,
                              attachmentButtonIcon:
                                  const Icon(Icons.add_a_photo_rounded),
                              sendButtonIcon: const SizedBox(
                                height: 24,
                                child: CircleAvatar(
                                    backgroundColor: Colors.black,
                                    radius: 12,
                                    child: Icon(Icons.arrow_upward_rounded)),
                              ),
                              sendButtonMargin: EdgeInsets.zero,
                              inputBackgroundColor: (theme ?? ThemeData())
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(10),
                              inputTextColor:
                                  (theme ?? ThemeData()).colorScheme.onSurface,
                              inputBorderRadius:
                                  const BorderRadius.all(Radius.circular(64)),
                              inputPadding: const EdgeInsets.all(16),
                              inputMargin: EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  bottom: (MediaQuery.of(context)
                                                  .viewInsets
                                                  .bottom ==
                                              0.0 &&
                                          !(Platform.isWindows ||
                                              Platform.isLinux ||
                                              Platform.isMacOS))
                                      ? 0
                                      : 8),
                              messageMaxWidth: (MediaQuery.of(context).size.width >=
                                      1000)
                                  ? (MediaQuery.of(context).size.width >= 1600)
                                      ? (MediaQuery.of(context).size.width >= 2200)
                                          ? 1900
                                          : 1300
                                      : 700
                                  : 440)
                          : DarkChatTheme(
                              backgroundColor: (themeDark ?? ThemeData.dark()).colorScheme.surface,
                              primaryColor: (themeDark ?? ThemeData.dark()).colorScheme.primary.withAlpha(40),
                              secondaryColor: (themeDark ?? ThemeData.dark()).colorScheme.primary.withAlpha(20),
                              attachmentButtonIcon: const Icon(Icons.add_a_photo_rounded),
                              sendButtonIcon: const Icon(Icons.send_rounded),
                              inputBackgroundColor: (themeDark ?? ThemeData()).colorScheme.onSurface.withAlpha(40),
                              inputTextColor: (themeDark ?? ThemeData()).colorScheme.onSurface,
                              inputBorderRadius: const BorderRadius.all(Radius.circular(64)),
                              inputPadding: const EdgeInsets.all(16),
                              inputMargin: EdgeInsets.only(left: 8, right: 8, bottom: (MediaQuery.of(context).viewInsets.bottom == 0.0 && !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) ? 0 : 8),
                              messageMaxWidth: (MediaQuery.of(context).size.width >= 1000)
                                  ? (MediaQuery.of(context).size.width >= 1600)
                                      ? (MediaQuery.of(context).size.width >= 2200)
                                          ? 1900
                                          : 1300
                                      : 700
                                  : 440))), 
            ],
          ),
          drawerEdgeDragWidth:
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  ? null
                  : MediaQuery.of(context).size.width,
          drawer: Builder(builder: (context) {
            if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
                MediaQuery.of(context).size.width >= 1000) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              });
            }
            return NavigationDrawer(
                onDestinationSelected: (value) {
                  if (value == 1) {
                  } else if (value == 2) {}
                },
                selectedIndex: 1,
                children: sidebar(context, setState));
          })),
    );
  }
}
