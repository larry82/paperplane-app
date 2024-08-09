import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lig_scanner_sdk/lig_scanner_sdk.dart';
import 'dart:async';
import 'package:flutter/services.dart'; // Add this import

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LineSDK.instance.setup('1657420198').then((_) {
    print('LineSDK 準備完成');
  });
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => UserState()),
        ChangeNotifierProvider(create: (context) => WebViewState()),
        ChangeNotifierProvider(create: (context) => AppState()),
      ],
      child: MyApp(),
    ),
  );
}

class UserState extends ChangeNotifier {
  UserProfile? _userProfile;
  String? _userEmail;
  AccessToken? _accessToken;
  String? _userId;

  UserProfile? get userProfile => _userProfile;
  String? get userEmail => _userEmail;
  AccessToken? get accessToken => _accessToken;
  String? get userId => _userId;

  void setUser(UserProfile profile, String? email, AccessToken token) {
    _userProfile = profile;
    _userEmail = email;
    _accessToken = token;
    _userId = profile.userId;
    notifyListeners();
  }

  void clearUser() {
    _userProfile = null;
    _userEmail = null;
    _accessToken = null;
    _userId = null;
    notifyListeners();
  }

  bool get isLoggedIn => _userProfile != null;

  Future<void> resetUserState() async {
    _userProfile = null;
    _userEmail = null;
    _accessToken = null;
    _userId = null;
    notifyListeners();
  }
}

class WebViewState extends ChangeNotifier {
  String _currentUrl = 'https://flyingclub.io/stores?guide=true';

  String get currentUrl => _currentUrl;

  void updateUrl(String newUrl) {
    _currentUrl = newUrl;
    notifyListeners();
  }
}

class AppState extends ChangeNotifier {
  bool _isFirstLaunch = true;
  bool _tutorialCompleted = false;
  bool _authCompleted = false;
  bool _firstTimeOpeningGuide = true;

  bool get isFirstLaunch => _isFirstLaunch;
  bool get tutorialCompleted => _tutorialCompleted;
  bool get authCompleted => _authCompleted;
  bool get firstTimeOpeningGuide => _firstTimeOpeningGuide;

  void setFirstLaunch(bool value) {
    _isFirstLaunch = value;
    notifyListeners();
  }

  void setTutorialCompleted(bool value) {
    _tutorialCompleted = value;
    notifyListeners();
  }

  void setAuthCompleted(bool value) {
    _authCompleted = value;
    notifyListeners();
  }

  void setFirstTimeOpeningGuide(bool value) {
    _firstTimeOpeningGuide = value;
    notifyListeners();
  }

  Future<void> loadAppState() async {
    final prefs = await SharedPreferences.getInstance();
    _isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;
    _tutorialCompleted = prefs.getBool('tutorialCompleted') ?? false;
    _authCompleted = prefs.getBool('authCompleted') ?? false;
    _firstTimeOpeningGuide = prefs.getBool('firstTimeOpeningGuide') ?? true;
    notifyListeners();
  }

  Future<void> saveAppState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstLaunch', _isFirstLaunch);
    await prefs.setBool('tutorialCompleted', _tutorialCompleted);
    await prefs.setBool('authCompleted', _authCompleted);
    await prefs.setBool('firstTimeOpeningGuide', _firstTimeOpeningGuide);
  }

  Future<void> resetAppState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _isFirstLaunch = true;
    _tutorialCompleted = false;
    _authCompleted = false;
    _firstTimeOpeningGuide = true;

    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '酒吧指南應用',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginPage(),
    );
  }
}

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          child: Text('LINE 登入'),
          onPressed: () => _signIn(context),
        ),
      ),
    );
  }

  void _signIn(BuildContext context) async {
    try {
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid', 'email'],
      );
      Provider.of<UserState>(context, listen: false).setUser(
        result.userProfile!,
        result.accessToken.email,
        result.accessToken,
      );
      Provider.of<AppState>(context, listen: false).setFirstLaunch(false);
      Provider.of<AppState>(context, listen: false).saveAppState();

      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => MainScreen()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗: $e')),
      );
    }
  }
}

class MainScreen extends StatefulWidget {
  MainScreen({Key? key}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          WebViewPage(),
          ARScannerPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.local_bar),
            label: '酒吧指南',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.view_in_ar),
            label: 'AR',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '我的',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _isDataInjected = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (JavaScriptMessage message) {
          print('Message from Web App: ${message.message}');
          if (message.message == 'login_required') {
            _reLogin();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            if (!_isDataInjected) {
              _injectUserData();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://flyingclub.io/webview/auth'));
  }

  void _injectUserData() {
    final userState = Provider.of<UserState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);

    if (userState.isLoggedIn && userState.accessToken != null) {
      final accessToken = userState.accessToken!.data['access_token'] as String;
      final name = userState.userProfile?.displayName ?? '';
      final email = userState.userEmail ?? '';
      final userId = userState.userId ?? '';

      final script = '''
        window.localStorage.setItem('line_access_token', '$accessToken');
        window.localStorage.setItem('line_name', '$name');
        window.localStorage.setItem('line_email', '$email');
        window.localStorage.setItem('line_user_id', '$userId');
        if (window.onUserDataInjected) {
          window.onUserDataInjected();
        }
      ''';

      _controller.runJavaScript(script).then((_) {
        print('User data injected successfully');
        setState(() {
          _isDataInjected = true;
          _isLoading = true; // 重新設置加載狀態
        });
        // 重新載入 auth 頁面
        _controller
            .loadRequest(Uri.parse('https://flyingclub.io/webview/auth'));
      }).catchError((error) {
        print('Error injecting user data: $error');
        setState(() {
          _isLoading = false;
        });
        // 可以在這裡添加錯誤處理邏輯
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }

    if (!appState.authCompleted) {
      appState.setAuthCompleted(true);
      appState.saveAppState();
    }
  }

  void _reLogin() {
    final userState = Provider.of<UserState>(context, listen: false);
    userState.clearUser();
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WebView'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (userState.isLoggedIn)
              UserInfoWidget(
                userProfile: userState.userProfile!,
                userEmail: userState.userEmail,
                accessToken: userState.accessToken!,
                onSignOutPressed: () => _signOut(context),
              )
            else
              ElevatedButton(
                child: Text('LINE 登入'),
                onPressed: () => _signIn(context),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text('重置應用狀態'),
              onPressed: () => _resetAppState(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  void _signIn(BuildContext context) async {
    try {
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid', 'email'],
      );
      Provider.of<UserState>(context, listen: false).setUser(
        result.userProfile!,
        result.accessToken.email,
        result.accessToken,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入成功: ${result.userProfile?.displayName}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗: $e')),
      );
    }
  }

  void _signOut(BuildContext context) async {
    try {
      await LineSDK.instance.logout();
      Provider.of<UserState>(context, listen: false).clearUser();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已登出')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登出失敗: $e')),
      );
    }
  }

  void _resetAppState(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userState = Provider.of<UserState>(context, listen: false);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('重置應用'),
          content: Text('這將清除所有數據並重啟應用。確定要繼續嗎？'),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('確定'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await appState.resetAppState();
      await userState.resetUserState();

      try {
        await LineSDK.instance.logout();
      } catch (e) {
        print('登出 LINE SDK 時出錯: $e');
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginPage()),
        (Route<dynamic> route) => false,
      );
    }
  }
}

class UserInfoWidget extends StatelessWidget {
  const UserInfoWidget({
    Key? key,
    required this.userProfile,
    this.userEmail,
    required this.accessToken,
    required this.onSignOutPressed,
  }) : super(key: key);

  final UserProfile userProfile;
  final String? userEmail;
  final AccessToken accessToken;
  final VoidCallback onSignOutPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        (userProfile.pictureUrl ?? "").isNotEmpty
            ? Image.network(
                userProfile.pictureUrl!,
                width: 100,
                height: 100,
              )
            : Icon(Icons.person, size: 100),
        SizedBox(height: 20),
        Text(
          userProfile.displayName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (userEmail != null) ...[
          SizedBox(height: 10),
          Text(userEmail!),
        ],
        if (userProfile.statusMessage != null) ...[
          SizedBox(height: 10),
          Text(userProfile.statusMessage!),
        ],
        SizedBox(height: 20),
        ElevatedButton(
          child: Text('登出'),
          onPressed: onSignOutPressed,
        ),
      ],
    );
  }
}

class ARScannerPage extends StatefulWidget {
  @override
  _ARScannerPageState createState() => _ARScannerPageState();
}

class _ARScannerPageState extends State<ARScannerPage> {
  String _platformVersion = 'Unknown';
  final _ligScannerSdkPlugin = LigScannerSdk();
  static const statusChannel = EventChannel("lig_scanner_sdk_status");
  static const resultChannel = EventChannel("lig_scanner_sdk_results");
  bool _supported = false;
  bool _authenticated = false;
  Offset _center = const Offset(0.9, 0.85);
  int _ligTagID = 0;

  final Permission _permission = Permission.camera;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  StreamSubscription? _statusSubscription;
  StreamSubscription? _resultSubscription;

  @override
  void initState() {
    super.initState();

    _listenForPermissionStatus();

    _statusSubscription = statusChannel
        .receiveBroadcastStream()
        .listen(_onStatusReported, onError: _onChannelError);
    _resultSubscription = resultChannel
        .receiveBroadcastStream()
        .listen(_onResultDelivered, onError: _onChannelError);

    _ligScannerSdkPlugin.initialize(
        "79AA5-5F64B-2D40F-FE67B-145C3", "D68E2-6ABFE-4AC12-95033-11102");
    initPlatformState();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _resultSubscription?.cancel();
    super.dispose();
  }

  void _listenForPermissionStatus() async {
    final status = await _permission.status;
    print('AR Scanner: $status');
    if (mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  void _onStatusReported(Object? status) {
    print('AR Scanner: $status');
    if (status == null || status is! int || !mounted) {
      return;
    }

    switch (status) {
      case 17: // device is supported
      case 126:
        setState(() {
          _supported = true;
        });
      case 20: // Authentication is ok
      case 300:
        setState(() {
          _authenticated = true;
        });
      default:
      // no-op
    }
  }

  void _onResultDelivered(Object? result) {
    if (result == null || result is! List<Object?> || !mounted) {
      return;
    }

    for (final lightMap in result) {
      var map = lightMap as Map<Object?, Object?>;
      setState(() {
        var id = map['deviceId'] as int;
        if (id != _ligTagID) {
          _ligTagID = id;
        }
        _center =
            Offset(map['coordinateX'] as double, map['coordinateY'] as double);
      });
    }
  }

  void _onChannelError(Object error) {
    print(error);
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _ligScannerSdkPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AR Scanner'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: CustomCirclePainter(center: _center, id: _ligTagID),
                child: Container(),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      TextButton(
                        onPressed: () async {
                          // Log current permission status
                          print(
                              'Current camera permission status: $_permissionStatus');
                          final status = await _permission.request();
                          setState(() => _permissionStatus = status);
                          // Log updated permission status
                          print('Updated camera permission status: $status');
                        },
                        child: const Text('Request Permission'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (_permissionStatus.isGranted) {
                            _ligScannerSdkPlugin.start();
                            print('AR 掃描器已啟動');
                          } else {
                            print('當前相機權限狀態: $_permissionStatus');
                            final status = await _permission.request();
                            setState(() => _permissionStatus = status);
                            print('更新後的相機權限狀態: $status');

                            if (status.isGranted) {
                              _ligScannerSdkPlugin.start();
                              print('權限已獲取，AR 掃描器已啟動');
                            } else {
                              print('無法獲取相機權限，AR 掃描器無法啟動');
                            }
                          }
                        },
                        child: const Text('開始'),
                      ),
                      TextButton(
                        onPressed: () async {
                          _ligScannerSdkPlugin.stop();
                        },
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomCirclePainter extends CustomPainter {
  final Offset center;
  final int id;

  CustomCirclePainter({required this.center, required this.id});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    final point = Offset(center.dx * size.width, center.dy * size.height);

    canvas.drawCircle(point, 30, paint);
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 16,
    );
    final textSpan = TextSpan(
      text: '$id',
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );
    final textPoint = Offset(point.dx - 10, point.dy - 10);
    textPainter.paint(canvas, textPoint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
