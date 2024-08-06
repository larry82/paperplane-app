import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:lig_scanner_sdk/lig_scanner_sdk.dart';
import 'package:flutter/services.dart';
import 'dart:async';

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
      home: FutureBuilder(
        future: Provider.of<AppState>(context, listen: false).loadAppState(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return AppRouter();
          }
          return CircularProgressIndicator();
        },
      ),
    );
  }
}

class AppRouter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final userState = Provider.of<UserState>(context);

    if (!userState.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _signIn(context);
      });
      return LoginPage();
    } else if (!appState.tutorialCompleted) {
      return TutorialPage();
    } else {
      return MainScreen();
    }
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

      if (Provider.of<AppState>(context, listen: false).tutorialCompleted) {
        Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => MainScreen()));
      } else {
        Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => TutorialPage()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗: $e')),
      );
    }
  }
}

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('正在登入...'),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class TutorialPage extends StatefulWidget {
  @override
  _TutorialPageState createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Widget> _tutorialPages = [
    TutorialPageContent(
      title: "歡迎使用酒吧指南",
      content: "這是一個幫助你找到最好酒吧的應用程式。",
      image: Icons.local_bar,
    ),
    TutorialPageContent(
      title: "探索附近的酒吧",
      content: "使用地圖功能找到你附近的酒吧。",
      image: Icons.map,
    ),
    TutorialPageContent(
      title: "掃描 QR 碼",
      content: "在酒吧掃描 QR 碼，獲取特別優惠。",
      image: Icons.qr_code_scanner,
    ),
    TutorialPageContent(
      title: "開始你的酒吧之旅",
      content: "準備好了嗎？讓我們開始探索吧！",
      image: Icons.celebration,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: _tutorialPages,
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _tutorialPages.length,
                (index) => Container(
                  margin: EdgeInsets.symmetric(horizontal: 5),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index ? Colors.blue : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
          if (_currentPage == _tutorialPages.length - 1)
            Positioned(
              bottom: 20,
              right: 20,
              child: ElevatedButton(
                child: Text('開始使用'),
                onPressed: () {
                  Provider.of<AppState>(context, listen: false)
                      .setTutorialCompleted(true);
                  Provider.of<AppState>(context, listen: false).saveAppState();
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => MainScreen()));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class TutorialPageContent extends StatelessWidget {
  final String title;
  final String content;
  final IconData image;

  const TutorialPageContent({
    Key? key,
    required this.title,
    required this.content,
    required this.image,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(image, size: 100, color: Colors.blue),
          SizedBox(height: 40),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 20),
          Text(content,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
        ],
      ),
    );
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
    final appState = Provider.of<AppState>(context);
    final userState = Provider.of<UserState>(context);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          WebViewPage(
            initialUrl: 'https://flyingclub.io/webview/auth',
          ),
          QRScannerPage(),
          ARScannerPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.local_bar),
            label: '酒吧指南',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: '掃一掃',
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
  final String initialUrl;

  WebViewPage({required this.initialUrl});

  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _hasCompletedAuth = false;

  @override
  void initState() {
    super.initState();
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
            _injectUserData();
            if (!_hasCompletedAuth &&
                url.contains('flyingclub.io/webview/auth')) {
              _hasCompletedAuth = true;
              _navigateToGuide();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
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
      ''';
      _controller.runJavaScript(script).then((_) {
        print('User data injected successfully');
      }).catchError((error) {
        print('Error injecting user data: $error');
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

  void _navigateToGuide() {
    _controller
        .loadRequest(Uri.parse('https://flyingclub.io/stores?guide=true'));
  }

  void _navigateToAuth() {
    _controller.loadRequest(Uri.parse('https://flyingclub.io/webview/auth'));
  }

  Future<Map<String, String>> getLocalStorageContent() async {
    final result = await _controller.runJavaScriptReturningResult('''
    var result = {};
    for (var i = 0; i < localStorage.length; i++) {
      var key = localStorage.key(i);
      result[key] = localStorage.getItem(key);
    }
    JSON.stringify(result);
  ''');

    return Map<String, String>.from(json.decode(result.toString()));
  }

  void showLocalStorageDialog() async {
    final content = await getLocalStorageContent();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('localStorage 內容'),
          content: SingleChildScrollView(
            child: ListBody(
              children: content.entries
                  .map((entry) => Text('${entry.key}: ${entry.value}'))
                  .toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('關閉'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WebView'),
        actions: [
          ElevatedButton(
            child: Text('登入'),
            onPressed: _navigateToAuth,
          ),
          IconButton(
            icon: Icon(Icons.info),
            onPressed: showLocalStorageDialog,
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class QRScannerPage extends StatefulWidget {
  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QRView(
        key: qrKey,
        onQRViewCreated: _onQRViewCreated,
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        controller.pauseCamera();
        _handleQRCode(scanData.code!);
      }
    });
  }

  void _handleQRCode(String code) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => QRWebViewPage(url: code),
      ),
    )
        .then((_) {
      if (mounted) {
        controller?.resumeCamera();
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

class QRWebViewPage extends StatefulWidget {
  final String url;

  QRWebViewPage({required this.url});

  @override
  _QRWebViewPageState createState() => _QRWebViewPageState();
}

class _QRWebViewPageState extends State<QRWebViewPage> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('掃描結果'),
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(),
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
  final _ligScannerSdkPlugin = LigScannerSdk();
  static const statusChannel = EventChannel("lig_scanner_sdk_status");
  static const resultChannel = EventChannel("lig_scanner_sdk_results");
  bool _supported = false;
  bool _authenticated = false;
  Offset _center = const Offset(0.9, 0.85);
  int _ligTagID = 0;

  final Permission _permission = Permission.camera;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  late StreamSubscription _statusSubscription;
  late StreamSubscription _resultSubscription;

  bool _mounted = true;
  String _scanStatus = '等待掃描...'; // 新增：掃描狀態

  @override
  void initState() {
    super.initState();

    _checkPermission();

    _listenForPermissionStatus();

    _statusSubscription = statusChannel
        .receiveBroadcastStream()
        .listen(_onStatusReported, onError: _onChannelError);
    _resultSubscription = resultChannel
        .receiveBroadcastStream()
        .listen(_onResultDelivered, onError: _onChannelError);

    _ligScannerSdkPlugin.initialize(
        "79AA5-5F64B-2D40F-FE67B-145C3", "D68E2-6ABFE-4AC12-95033-11102");
  }

  @override
  void dispose() {
    _mounted = false;
    _statusSubscription.cancel();
    _resultSubscription.cancel();
    super.dispose();
  }

  void _listenForPermissionStatus() async {
    final status = await _permission.status;
    if (_mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  void _onStatusReported(Object? status) {
    print('Status reported: $status');
    if (status == null || !_mounted) {
      return;
    }

    if (status is! int) {
      return;
    }

    switch (status) {
      case 17: // device is supported
      case 126:
        if (_mounted) {
          setState(() {
            _supported = true;
            _scanStatus = '設備支持 AR 掃描';
          });
        }
      case 20: // Authentication is ok
      case 300:
        if (_mounted) {
          setState(() {
            _authenticated = true;
            _scanStatus = 'AR 掃描器已準備就緒';
          });
        }
      default:
        if (_mounted) {
          setState(() {
            _scanStatus = 'AR 掃描器狀態: $status';
          });
        }
    }
  }

  void _onResultDelivered(Object? result) {
    if (result == null || !_mounted) {
      return;
    }

    if (result is! List<Object?>) {
      return;
    }

    for (final lightMap in result) {
      var map = lightMap as Map<Object?, Object?>;
      if (_mounted) {
        setState(() {
          var id = map['deviceId'] as int;
          if (id != _ligTagID) {
            _ligTagID = id;
          }
          _center = Offset(
              map['coordinateX'] as double, map['coordinateY'] as double);
          _scanStatus = '檢測到 LiG Tag: $_ligTagID';
        });
      }
    }
  }

  void _onChannelError(Object error) {
    print(error);
    if (_mounted) {
      setState(() {
        _scanStatus = 'AR 掃描錯誤: $error';
      });
    }
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (_mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (_mounted) {
      setState(() => _permissionStatus = status);
    }

    if (status.isGranted) {
      _startScanning();
    } else if (status.isDenied) {
      _showPermissionDeniedDialog();
    } else if (status.isPermanentlyDenied) {
      _showOpenSettingsDialog();
    }
  }

  void _startScanning() {
    _ligScannerSdkPlugin.start();
    setState(() {
      _scanStatus = 'AR 掃描已啟動';
    });
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('需要相機權限'),
        content: Text('AR 掃描需要相機權限才能運作。請授予權限以繼續。'),
        actions: [
          TextButton(
            child: Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text('重試'),
            onPressed: () {
              Navigator.of(context).pop();
              _requestPermission();
            },
          ),
        ],
      ),
    );
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('需要相機權限'),
        content: Text('AR 掃描需要相機權限才能運作。請在設置中授予權限。'),
        actions: [
          TextButton(
            child: Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text('打開設置'),
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AR Scanner'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CustomPaint(
                  painter: CustomCirclePainter(center: _center, id: _ligTagID),
                  child: Container(),
                ),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    color: Colors.black.withOpacity(0.7),
                    child: Text(
                      _scanStatus,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
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
                      onPressed: _requestPermission,
                      child: const Text('請求權限並開始掃描'),
                    ),
                    TextButton(
                      onPressed: () async {
                        _ligScannerSdkPlugin.stop();
                        setState(() {
                          _scanStatus = 'AR 掃描已停止';
                        });
                      },
                      child: const Text('停止掃描'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
