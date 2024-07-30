import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  String? _userId; // 新增 User ID 欄位

  UserProfile? get userProfile => _userProfile;
  String? get userEmail => _userEmail;
  AccessToken? get accessToken => _accessToken;
  String? get userId => _userId; // 新增 getter

  void setUser(UserProfile profile, String? email, AccessToken token) {
    _userProfile = profile;
    _userEmail = email;
    _accessToken = token;
    _userId = profile.userId; // 設置 User ID
    notifyListeners();
  }

  void clearUser() {
    _userProfile = null;
    _userEmail = null;
    _accessToken = null;
    _userId = null; // 清除 User ID
    notifyListeners();
  }

  bool get isLoggedIn => _userProfile != null;

  Future<void> resetUserState() async {
    _userProfile = null;
    _userEmail = null;
    _accessToken = null;
    _userId = null; // 重置 User ID
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
    await prefs.clear(); // 清除所有保存的偏好設置

    // 重置所有狀態到默認值
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
      return LoginPage();
    } else if (!appState.tutorialCompleted) {
      return TutorialPage();
    } else {
      return MainScreen();
    }
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
          .pushReplacement(MaterialPageRoute(builder: (_) => TutorialPage()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗: $e')),
      );
    }
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
  final int initialIndex;

  MainScreen({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final userState = Provider.of<UserState>(context);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          WebViewPage(
            initialUrl: appState.firstTimeOpeningGuide && userState.isLoggedIn
                ? 'https://flyingclub.io/webview/auth'
                : 'https://flyingclub.io/stores?guide=true',
          ),
          QRScannerPage(),
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
            icon: Icon(Icons.qr_code_scanner),
            label: '掃一掃',
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
          if (index == 0 && appState.firstTimeOpeningGuide) {
            appState.setFirstTimeOpeningGuide(false);
            appState.saveAppState();
          }
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (JavaScriptMessage message) {
          print('Message from Web App: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _injectUserData();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  void _injectUserData() {
    final userState = Provider.of<UserState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);
    if (userState.isLoggedIn && userState.accessToken != null) {
      final accessToken = userState.accessToken!.data['access_token']
          as String; // 只獲取 access_token 值
      final name = userState.userProfile?.displayName ?? '';
      final email = userState.userEmail ?? '';
      final userId = userState.userId ?? ''; // 獲取 User ID

      final script = '''
        window.localStorage.setItem('line_access_token', '$accessToken');
        window.localStorage.setItem('line_name', '$name');
        window.localStorage.setItem('line_email', '$email');
        window.localStorage.setItem('line_user_id', '$userId');  // 存儲 User ID
        
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

  void _handleQRCode(String code) async {
    if (!mounted) return; // 檢查 widget 是否仍然掛載

    if (await canLaunch(code)) {
      final webViewState = Provider.of<WebViewState>(context, listen: false);
      webViewState.updateUrl(code);

      // 使用 Navigator.of(context).pushReplacement 而不是 pop
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MainScreen(initialIndex: 0),
        ),
      );
    } else {
      if (mounted) {
        // 再次檢查，因為 canLaunch 是異步的
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無效的 QR Code')),
        );
      }
    }

    // 確保相機在組件被卸載後不會繼續運行
    if (mounted) {
      controller?.resumeCamera();
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
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

    // 顯示確認對話框
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

      // 登出 LINE SDK
      try {
        await LineSDK.instance.logout();
      } catch (e) {
        print('登出 LINE SDK 時出錯: $e');
      }

      // 重啟應用
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
