import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

// -------------------- Configuration --------------------
const String baseUrl = 'https://api-tweeter.runflare.run';
const String apiEntry = '$baseUrl/index.php';
const String mediaBase = '$baseUrl/media.php';

// -------------------- Main App --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Setup Dio with CookieJar
  final dio = Dio(BaseOptions(
    baseUrl: apiEntry,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));
  final appDocDir = await getApplicationDocumentsDirectory();
  final cookieJar = PersistCookieJar(
    storage: FileStorage(appDocDir.path),
  );
  dio.interceptors.add(CookieManager(cookieJar));

  runApp(MyApp(dio: dio));
}

class MyApp extends StatelessWidget {
  final Dio dio;
  const MyApp({super.key, required this.dio});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService(dio)),
        ChangeNotifierProvider(create: (_) => ReelsProvider(dio)),
        ChangeNotifierProvider(create: (_) => StoriesProvider(dio)),
      ],
      child: MaterialApp(
        title: 'InstaReels',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.black,
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.black,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
          ),
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            secondary: Colors.grey,
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// -------------------- Splash Screen --------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.tryAutoLogin();
    if (auth.isLoggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library, size: 80, color: Colors.white),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// -------------------- Authentication Service --------------------
class AuthService with ChangeNotifier {
  final Dio dio;
  User? _currentUser;
  bool _isLoading = false;

  AuthService(this.dio);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;

  Future<void> tryAutoLogin() async {
    try {
      final response = await dio.get('?action=me');
      if (response.data['success'] == true) {
        _currentUser = User.fromJson(response.data['user']);
        notifyListeners();
      }
    } catch (e) {
      // Not logged in
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await dio.post('?action=login', data: {
        'username': username,
        'password': password,
      });
      if (response.data['success'] == true) {
        _currentUser = User.fromJson(response.data['user']);
        notifyListeners();
        return true;
      }
      _showError(response.data['error'] ?? 'Login failed');
      return false;
    } catch (e) {
      _showError('Network error');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String username, String email, String password,
      {String? fullName}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await dio.post('?action=register', data: {
        'username': username,
        'email': email,
        'password': password,
        'full_name': fullName ?? '',
      });
      if (response.data['success'] == true) {
        // After register, we need to fetch user info via 'me'
        final meResp = await dio.get('?action=me');
        if (meResp.data['success'] == true) {
          _currentUser = User.fromJson(meResp.data['user']);
          notifyListeners();
        }
        return true;
      }
      _showError(response.data['error'] ?? 'Registration failed');
      return false;
    } catch (e) {
      _showError('Network error');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await dio.post('?action=logout');
    _currentUser = null;
    notifyListeners();
  }

  void _showError(String msg) {
    Fluttertoast.showToast(msg: msg, toastLength: Toast.LENGTH_LONG);
  }
}

// -------------------- Models --------------------
class User {
  final int id;
  final String username;
  final String? email;
  final String? fullName;
  final String? bio;
  final String? profilePic;
  final bool blueTick;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    this.bio,
    this.profilePic,
    required this.blueTick,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      fullName: json['full_name'],
      bio: json['bio'],
      profilePic: json['profile_pic_url'] ?? json['profile_pic'],
      blueTick: json['blue_tick'] == 1 || json['blue_tick'] == true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get displayName => fullName?.isNotEmpty == true ? fullName! : username;
  String get profilePicUrl => profilePic != null && profilePic!.startsWith('http')
      ? profilePic!
      : '$mediaBase?file=${profilePic ?? ''}';
}

class Reel {
  final int id;
  final int userId;
  final String? videoPath;
  final String? imagePath;
  final String mediaType; // 'video' or 'image'
  final String? caption;
  final String? music;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final DateTime createdAt;
  final String username;
  final String fullName;
  final String? profilePic;
  final bool blueTick;
  bool liked;
  bool isPlaying;

  Reel({
    required this.id,
    required this.userId,
    this.videoPath,
    this.imagePath,
    required this.mediaType,
    this.caption,
    this.music,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.createdAt,
    required this.username,
    required this.fullName,
    this.profilePic,
    required this.blueTick,
    this.liked = false,
    this.isPlaying = false,
  });

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id'],
      userId: json['user_id'],
      videoPath: json['video_url'],
      imagePath: json['image_url'],
      mediaType: json['media_type'] ?? 'video',
      caption: json['caption'],
      music: json['music'],
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      sharesCount: json['shares_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      fullName: json['full_name'] ?? '',
      profilePic: json['profile_pic_url'],
      blueTick: json['blue_tick'] == 1 || json['blue_tick'] == true,
      liked: json['liked'] ?? false,
    );
  }

  String get mediaUrl {
    if (mediaType == 'video' && videoPath != null) return videoPath!;
    if (imagePath != null) return imagePath!;
    return '';
  }

  String get displayName => fullName.isNotEmpty ? fullName : username;
  String get profilePicUrl => profilePic != null && profilePic!.startsWith('http')
      ? profilePic!
      : '$mediaBase?file=${profilePic ?? ''}';
}

class Story {
  final int id;
  final int userId;
  final String mediaPath;
  final String mediaType;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int viewsCount;
  final String username;
  final String fullName;
  final String? profilePic;
  final bool blueTick;
  bool viewed;

  Story({
    required this.id,
    required this.userId,
    required this.mediaPath,
    required this.mediaType,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    required this.viewsCount,
    required this.username,
    required this.fullName,
    this.profilePic,
    required this.blueTick,
    this.viewed = false,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'],
      userId: json['user_id'],
      mediaPath: json['media_url'],
      mediaType: json['media_type'],
      caption: json['caption'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: DateTime.parse(json['expires_at']),
      viewsCount: json['views_count'] ?? 0,
      username: json['username'],
      fullName: json['full_name'] ?? '',
      profilePic: json['profile_pic_url'],
      blueTick: json['blue_tick'] == 1 || json['blue_tick'] == true,
      viewed: json['viewed'] ?? false,
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : username;
  String get profilePicUrl => profilePic != null && profilePic!.startsWith('http')
      ? profilePic!
      : '$mediaBase?file=${profilePic ?? ''}';
}

class Comment {
  final int id;
  final int userId;
  final int reelId;
  final String text;
  final DateTime createdAt;
  final String username;
  final String fullName;
  final String? profilePic;
  final bool blueTick;

  Comment({
    required this.id,
    required this.userId,
    required this.reelId,
    required this.text,
    required this.createdAt,
    required this.username,
    required this.fullName,
    this.profilePic,
    required this.blueTick,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      userId: json['user_id'],
      reelId: json['reel_id'],
      text: json['comment_text'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      fullName: json['full_name'] ?? '',
      profilePic: json['profile_pic_url'],
      blueTick: json['blue_tick'] == 1 || json['blue_tick'] == true,
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : username;
  String get profilePicUrl => profilePic != null && profilePic!.startsWith('http')
      ? profilePic!
      : '$mediaBase?file=${profilePic ?? ''}';
}

// -------------------- API Providers --------------------
class ReelsProvider with ChangeNotifier {
  final Dio dio;
  List<Reel> _reels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final RefreshController _refreshController = RefreshController();

  ReelsProvider(this.dio);

  List<Reel> get reels => _reels;
  bool get isLoading => _isLoading;
  RefreshController get refreshController => _refreshController;

  Future<void> fetchReels({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;
    _isLoading = true;
    if (refresh) _offset = 0;
    notifyListeners();

    try {
      final response = await dio.get('?action=reels', queryParameters: {
        'limit': 10,
        'offset': _offset,
      });
      if (response.data['success'] == true) {
        final List newReels = (response.data['reels'] as List)
            .map((e) => Reel.fromJson(e))
            .toList();
        if (refresh) {
          _reels = newReels;
        } else {
          _reels.addAll(newReels);
        }
        _offset += newReels.length;
        _hasMore = newReels.length == 10;
        if (refresh) _refreshController.refreshCompleted();
        if (!_hasMore) _refreshController.loadNoData();
        else _refreshController.loadComplete();
      }
    } catch (e) {
      if (refresh) _refreshController.refreshFailed();
      else _refreshController.loadFailed();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> likeReel(int reelId) async {
    try {
      await dio.post('?action=like', data: {'reel_id': reelId});
      final index = _reels.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        _reels[index].liked = true;
        _reels[index] = _reels[index].copyWith(likesCount: _reels[index].likesCount + 1);
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> unlikeReel(int reelId) async {
    try {
      await dio.delete('?action=like', data: {'reel_id': reelId});
      final index = _reels.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        _reels[index].liked = false;
        _reels[index] = _reels[index].copyWith(likesCount: _reels[index].likesCount - 1);
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> shareReel(int reelId) async {
    try {
      await dio.post('?action=share', data: {'reel_id': reelId});
      final index = _reels.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        _reels[index] = _reels[index].copyWith(sharesCount: _reels[index].sharesCount + 1);
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<Reel?> createReel(File mediaFile, String caption, String? music) async {
    final mimeType = lookupMimeType(mediaFile.path);
    final isVideo = mimeType?.startsWith('video') ?? false;
    final formData = FormData.fromMap({
      'caption': caption,
      'music': music ?? '',
      'media': await MultipartFile.fromFile(mediaFile.path,
          filename: mediaFile.path.split('/').last),
    });
    try {
      final response = await dio.post('?action=reels', data: formData);
      if (response.data['success'] == true) {
        Fluttertoast.showToast(msg: 'Reel created!');
        fetchReels(refresh: true);
        return null;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to create reel');
    }
    return null;
  }
}

class StoriesProvider with ChangeNotifier {
  final Dio dio;
  List<Map<String, dynamic>> _storiesFeed = []; // user + stories list
  bool _isLoading = false;

  StoriesProvider(this.dio);

  List<Map<String, dynamic>> get storiesFeed => _storiesFeed;
  bool get isLoading => _isLoading;

  Future<void> fetchStories() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await dio.get('?action=stories');
      if (response.data['success'] == true) {
        final List feed = response.data['stories_feed'] as List;
        _storiesFeed = feed.map((item) {
          final user = User.fromJson(item['user']);
          final stories = (item['stories'] as List)
              .map((s) => Story.fromJson(s))
              .toList();
          return {'user': user, 'stories': stories};
        }).toList();
      }
    } catch (e) {
      // handle
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createStory(File mediaFile, String? caption) async {
    final formData = FormData.fromMap({
      'caption': caption ?? '',
      'media': await MultipartFile.fromFile(mediaFile.path,
          filename: mediaFile.path.split('/').last),
    });
    try {
      final response = await dio.post('?action=stories', data: formData);
      if (response.data['success'] == true) {
        Fluttertoast.showToast(msg: 'Story created!');
        fetchStories();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to create story');
    }
  }

  Future<void> viewStory(int storyId) async {
    try {
      await dio.post('?action=story_view', data: {'story_id': storyId});
    } catch (e) {}
  }
}

// -------------------- Login / Register Screen --------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();
  final _regUsername = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPassword = TextEditingController();
  final _regFullName = TextEditingController();
  bool _obscureLogin = true;
  bool _obscureReg = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsername.dispose();
    _loginPassword.dispose();
    _regUsername.dispose();
    _regEmail.dispose();
    _regPassword.dispose();
    _regFullName.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_loginFormKey.currentState!.validate()) {
      final auth = Provider.of<AuthService>(context, listen: false);
      final success = await auth.login(_loginUsername.text, _loginPassword.text);
      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    }
  }

  Future<void> _handleRegister() async {
    if (_registerFormKey.currentState!.validate()) {
      final auth = Provider.of<AuthService>(context, listen: false);
      final success = await auth.register(
        _regUsername.text,
        _regEmail.text,
        _regPassword.text,
        fullName: _regFullName.text,
      );
      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.video_library, size: 60, color: Colors.white),
            const SizedBox(height: 10),
            const Text('InstaReels', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'LOGIN'), Tab(text: 'REGISTER')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLoginForm(),
                  _buildRegisterForm(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _loginFormKey,
        child: Column(
          children: [
            TextFormField(
              controller: _loginUsername,
              decoration: const InputDecoration(labelText: 'Username or Email'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _loginPassword,
              obscureText: _obscureLogin,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscureLogin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 30),
            Consumer<AuthService>(
              builder: (ctx, auth, _) => auth.isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _handleLogin,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Login'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _registerFormKey,
        child: Column(
          children: [
            TextFormField(
              controller: _regUsername,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _regEmail,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _regFullName,
              decoration: const InputDecoration(labelText: 'Full Name (optional)'),
            ),
            TextFormField(
              controller: _regPassword,
              obscureText: _obscureReg,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscureReg ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureReg = !_obscureReg),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 30),
            Consumer<AuthService>(
              builder: (ctx, auth, _) => auth.isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _handleRegister,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Register'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Main Screen with Bottom Navigation --------------------
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const ReelsFeedPage(),
      const SearchPage(),
      const UploadPage(),
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// -------------------- Reels Feed Page --------------------
class ReelsFeedPage extends StatefulWidget {
  const ReelsFeedPage({super.key});

  @override
  State<ReelsFeedPage> createState() => _ReelsFeedPageState();
}

class _ReelsFeedPageState extends State<ReelsFeedPage> {
  late ReelsProvider _reelsProvider;
  late StoriesProvider _storiesProvider;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _reelsProvider = Provider.of<ReelsProvider>(context, listen: false);
    _storiesProvider = Provider.of<StoriesProvider>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _storiesProvider.fetchStories();
      _reelsProvider.fetchReels(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reels', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final auth = Provider.of<AuthService>(context, listen: false);
              await auth.logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer2<ReelsProvider, StoriesProvider>(
        builder: (ctx, reelsProv, storiesProv, _) {
          return SmartRefresher(
            controller: reelsProv.refreshController,
            enablePullUp: true,
            onRefresh: () => reelsProv.fetchReels(refresh: true),
            onLoading: () => reelsProv.fetchReels(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildStoriesSection(storiesProv),
                ),
                SliverFillRemaining(
                  child: reelsProv.reels.isEmpty && !reelsProv.isLoading
                      ? const Center(child: Text('No reels yet'))
                      : PageView.builder(
                          controller: _pageController,
                          scrollDirection: Axis.vertical,
                          itemCount: reelsProv.reels.length,
                          itemBuilder: (ctx, index) {
                            return ReelItem(
                              reel: reelsProv.reels[index],
                              onLike: () {
                                final reel = reelsProv.reels[index];
                                if (reel.liked) {
                                  reelsProv.unlikeReel(reel.id);
                                } else {
                                  reelsProv.likeReel(reel.id);
                                }
                              },
                              onComment: () => _showComments(reelsProv.reels[index]),
                              onShare: () {
                                final reel = reelsProv.reels[index];
                                reelsProv.shareReel(reel.id);
                                Share.share('Check out this reel by ${reel.displayName}');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStoriesSection(StoriesProvider storiesProv) {
    if (storiesProv.storiesFeed.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: storiesProv.storiesFeed.length,
        itemBuilder: (ctx, idx) {
          final entry = storiesProv.storiesFeed[idx];
          final user = entry['user'] as User;
          final stories = entry['stories'] as List<Story>;
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewer(user: user, stories: stories),
                ),
              );
            },
            child: Container(
              width: 70,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: stories.any((s) => !s.viewed) ? Colors.pink : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: CachedNetworkImageProvider(user.profilePicUrl),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.username,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showComments(Reel reel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => CommentSheet(reel: reel),
    );
  }
}

// -------------------- Reel Item Widget --------------------
class ReelItem extends StatefulWidget {
  final Reel reel;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const ReelItem({
    super.key,
    required this.reel,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    if (widget.reel.mediaType == 'video') {
      _videoController = VideoPlayerController.network(widget.reel.mediaUrl)
        ..initialize().then((_) {
          if (mounted) setState(() => _isVideoInitialized = true);
          _videoController!.setLooping(true);
          if (_isVisible) _videoController!.play();
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('reel_${widget.reel.id}'),
      onVisibilityChanged: (info) {
        _isVisible = info.visibleFraction > 0.5;
        if (widget.reel.mediaType == 'video' && _videoController != null) {
          if (_isVisible) {
            _videoController!.play();
          } else {
            _videoController!.pause();
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media
          if (widget.reel.mediaType == 'video')
            _isVideoInitialized
                ? VideoPlayer(_videoController!)
                : Container(color: Colors.black)
          else
            CachedNetworkImage(
              imageUrl: widget.reel.mediaUrl,
              fit: BoxFit.cover,
            ),
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                stops: const [0.7, 1.0],
              ),
            ),
          ),
          // Content
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: CachedNetworkImageProvider(widget.reel.profilePicUrl),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.reel.displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (widget.reel.blueTick)
                                const Icon(Icons.verified, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                timeago.format(widget.reel.createdAt),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (widget.reel.caption != null && widget.reel.caption!.isNotEmpty)
                            Text(widget.reel.caption!),
                          if (widget.reel.music != null && widget.reel.music!.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.music_note, size: 14),
                                const SizedBox(width: 4),
                                Text(widget.reel.music!, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // Action buttons
                    Column(
                      children: [
                        IconButton(
                          icon: Icon(
                            widget.reel.liked ? Icons.favorite : Icons.favorite_border,
                            color: widget.reel.liked ? Colors.red : Colors.white,
                          ),
                          onPressed: widget.onLike,
                        ),
                        Text('${widget.reel.likesCount}'),
                        const SizedBox(height: 10),
                        IconButton(
                          icon: const Icon(Icons.comment),
                          onPressed: widget.onComment,
                        ),
                        Text('${widget.reel.commentsCount}'),
                        const SizedBox(height: 10),
                        IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: widget.onShare,
                        ),
                        Text('${widget.reel.sharesCount}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------- Comment Sheet --------------------
class CommentSheet extends StatefulWidget {
  final Reel reel;
  const CommentSheet({super.key, required this.reel});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final Dio _dio = Dio(BaseOptions(baseUrl: apiEntry));
  List<Comment> _comments = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    setState(() => _loading = true);
    try {
      final response = await _dio.get('?action=comment', queryParameters: {'reel_id': widget.reel.id});
      if (response.data['success'] == true) {
        _comments = (response.data['comments'] as List)
            .map((e) => Comment.fromJson(e))
            .toList();
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  Future<void> _postComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    try {
      final response = await _dio.post('?action=comment', data: {
        'reel_id': widget.reel.id,
        'comment': _commentCtrl.text,
      });
      if (response.data['success'] == true) {
        _commentCtrl.clear();
        _fetchComments();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _comments.length,
                    itemBuilder: (ctx, idx) {
                      final c = _comments[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: CachedNetworkImageProvider(c.profilePicUrl),
                        ),
                        title: Row(
                          children: [
                            Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (c.blueTick) const Icon(Icons.verified, size: 14, color: Colors.blue),
                          ],
                        ),
                        subtitle: Text(c.text),
                        trailing: Text(timeago.format(c.createdAt), style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(hintText: 'Add a comment...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _postComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Story Viewer --------------------
class StoryViewer extends StatefulWidget {
  final User user;
  final List<Story> stories;
  const StoryViewer({super.key, required this.user, required this.stories});

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });
    _animationController.forward();
    _loadMedia(widget.stories[_currentIndex]);
    // Mark as viewed
    final storiesProv = Provider.of<StoriesProvider>(context, listen: false);
    storiesProv.viewStory(widget.stories[_currentIndex].id);
  }

  void _loadMedia(Story story) {
    _videoController?.dispose();
    if (story.mediaType == 'video') {
      _videoController = VideoPlayerController.network(story.mediaPath)
        ..initialize().then((_) {
          if (mounted) setState(() => _isVideoInitialized = true);
          _videoController!.play();
          _videoController!.addListener(() {
            if (_videoController!.value.position >= _videoController!.value.duration) {
              _nextStory();
            }
          });
        });
    } else {
      _isVideoInitialized = true;
      // Timer handled by animation
    }
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _loadMedia(widget.stories[index]);
      _animationController.forward(from: 0);
    });
    // Mark viewed
    final storiesProv = Provider.of<StoriesProvider>(context, listen: false);
    storiesProv.viewStory(widget.stories[index].id);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.stories.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (ctx, idx) {
              final story = widget.stories[idx];
              if (story.mediaType == 'video') {
                return _isVideoInitialized && _videoController != null
                    ? VideoPlayer(_videoController!)
                    : Container(color: Colors.black);
              } else {
                return PhotoView(
                  imageProvider: CachedNetworkImageProvider(story.mediaPath),
                );
              }
            },
          ),
          // Header
          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: CachedNetworkImageProvider(widget.user.profilePicUrl),
                ),
                const SizedBox(width: 10),
                Text(widget.user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Progress bars
          Positioned(
            top: 20,
            left: 10,
            right: 10,
            child: Row(
              children: List.generate(widget.stories.length, (i) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: LinearProgressIndicator(
                      value: i == _currentIndex ? _animationController.value : (i < _currentIndex ? 1.0 : 0.0),
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Search Page --------------------
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Dio _dio = Dio(BaseOptions(baseUrl: apiEntry));
  List<User> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _results.clear());
      return;
    }
    setState(() => _loading = true);
    try {
      // We'll fetch profile by username (no direct search endpoint; we simulate by fetching profile)
      final response = await _dio.get('?action=profile', queryParameters: {'username': query});
      if (response.data['success'] == true) {
        _results = [User.fromJson(response.data['profile'])];
      } else {
        _results = [];
      }
    } catch (e) {
      _results = [];
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Search username',
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, idx) {
                final user = _results[idx];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: CachedNetworkImageProvider(user.profilePicUrl),
                  ),
                  title: Text(user.displayName),
                  subtitle: Text('@${user.username}'),
                  trailing: user.blueTick ? const Icon(Icons.verified, color: Colors.blue, size: 16) : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfilePage(userId: user.id)),
                    );
                  },
                );
              },
            ),
    );
  }
}

// -------------------- Upload Page --------------------
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _captionCtrl = TextEditingController();
  final _musicCtrl = TextEditingController();
  File? _mediaFile;
  bool _isVideo = false;
  bool _uploading = false;

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final picked = await picker.pickMedia(); // requires image_picker 1.0+
    if (picked != null) {
      setState(() {
        _mediaFile = File(picked.path);
        _isVideo = picked.path.contains('.mp4') || picked.path.contains('.mov'); // simplistic
      });
    }
  }

  Future<void> _upload() async {
    if (_mediaFile == null) {
      Fluttertoast.showToast(msg: 'Please select media');
      return;
    }
    setState(() => _uploading = true);
    final reelsProv = Provider.of<ReelsProvider>(context, listen: false);
    await reelsProv.createReel(_mediaFile!, _captionCtrl.text, _musicCtrl.text);
    setState(() {
      _uploading = false;
      _mediaFile = null;
      _captionCtrl.clear();
      _musicCtrl.clear();
    });
    // Switch to home
    // Find parent bottom nav controller? Not easily accessible, but we can pop to main.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Reel')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _mediaFile == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 50),
                          Text('Tap to select media'),
                        ],
                      )
                    : _isVideo
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayerWidget(file: _mediaFile!),
                              const Icon(Icons.play_circle, size: 60, color: Colors.white),
                            ],
                          )
                        : Image.file(_mediaFile!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _captionCtrl,
              decoration: const InputDecoration(labelText: 'Caption'),
              maxLines: 3,
            ),
            TextField(
              controller: _musicCtrl,
              decoration: const InputDecoration(labelText: 'Music (optional)'),
            ),
            const SizedBox(height: 30),
            _uploading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    onPressed: _upload,
                    icon: const Icon(Icons.upload),
                    label: const Text('Post Reel'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  ),
          ],
        ),
      ),
    );
  }
}

// Simple video player for preview
class VideoPlayerWidget extends StatefulWidget {
  final File file;
  const VideoPlayerWidget({super.key, required this.file});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : Container(color: Colors.black);
  }
}

// -------------------- Profile Page --------------------
class ProfilePage extends StatefulWidget {
  final int? userId; // if null, show current user
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final Dio _dio = Dio(BaseOptions(baseUrl: apiEntry));
  User? _user;
  List<Reel> _userReels = [];
  int _followers = 0, _following = 0, _reelsCount = 0;
  bool _isFollowing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final username = widget.userId == null
          ? auth.currentUser!.username
          : null; // need to fetch by ID? API uses username. We'll use me for current.
      if (widget.userId == null) {
        final response = await _dio.get('?action=profile', queryParameters: {'username': auth.currentUser!.username});
        _parseProfile(response.data);
      } else {
        // Not directly supported, but we can search via user id? We'll skip for brevity.
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  void _parseProfile(Map<String, dynamic> data) {
    if (data['success'] == true) {
      _user = User.fromJson(data['profile']);
      _followers = data['stats']['followers'];
      _following = data['stats']['following'];
      _reelsCount = data['stats']['reels'];
      _isFollowing = data['is_following'] ?? false;
      _userReels = (data['reels'] as List)
          .map((e) => Reel.fromJson(e))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    if (widget.userId == null && auth.currentUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_user?.username ?? 'Profile'),
        actions: [
          if (widget.userId == null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showEditProfile(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: _user?.profilePic != null
                            ? CachedNetworkImageProvider(_user!.profilePicUrl)
                            : null,
                        child: _user?.profilePic == null ? const Icon(Icons.person, size: 50) : null,
                      ),
                      const SizedBox(height: 10),
                      Text(_user?.displayName ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_user?.bio != null) Text(_user!.bio!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatColumn('$_reelsCount', 'Reels'),
                          _buildStatColumn('$_followers', 'Followers'),
                          _buildStatColumn('$_following', 'Following'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (widget.userId != null)
                        ElevatedButton(
                          onPressed: () async {
                            final action = _isFollowing ? 'unfollow' : 'follow';
                            await _dio.post('?action=$action', data: {'user_id': widget.userId});
                            setState(() => _isFollowing = !_isFollowing);
                          },
                          child: Text(_isFollowing ? 'Unfollow' : 'Follow'),
                        ),
                      const Divider(),
                    ],
                  ),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, idx) {
                      final reel = _userReels[idx];
                      return GestureDetector(
                        onTap: () {
                          // Show reel detail? For simplicity we ignore.
                        },
                        child: CachedNetworkImage(
                          imageUrl: reel.mediaUrl,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                    childCount: _userReels.length,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  void _showEditProfile() {
    // Simple edit profile dialog
    showDialog(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: _user?.fullName);
        final bioCtrl = TextEditingController(text: _user?.bio);
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
              TextField(controller: bioCtrl, decoration: const InputDecoration(labelText: 'Bio')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final formData = FormData.fromMap({
                  'full_name': nameCtrl.text,
                  'bio': bioCtrl.text,
                });
                await _dio.put('?action=profile', data: formData);
                Navigator.pop(ctx);
                _loadProfile();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

// Extension for copyWith (simplified)
extension ReelCopy on Reel {
  Reel copyWith({int? likesCount, int? commentsCount, int? sharesCount}) {
    return Reel(
      id: id,
      userId: userId,
      videoPath: videoPath,
      imagePath: imagePath,
      mediaType: mediaType,
      caption: caption,
      music: music,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      createdAt: createdAt,
      username: username,
      fullName: fullName,
      profilePic: profilePic,
      blueTick: blueTick,
      liked: liked,
    );
  }
}