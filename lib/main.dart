import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_video_player/cached_video_player.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path_provider/path_provider.dart';

// ==================== Models ====================

class User {
  final int id;
  final String username;
  final String name;
  final String? avatar;
  final String bio;
  final bool isVerified;

  User({
    required this.id,
    required this.username,
    required this.name,
    this.avatar,
    required this.bio,
    required this.isVerified,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      name: json['name'] ?? '',
      avatar: json['avatar'],
      bio: json['bio'] ?? '',
      isVerified: json['is_verified'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'avatar': avatar,
        'bio': bio,
        'is_verified': isVerified,
      };
}

class Comment {
  final int id;
  final String text;
  final DateTime createdAt;
  final User user;

  Comment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.user,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
      user: User.fromJson(json['user']),
    );
  }
}

class Reel {
  final int id;
  final String type; // 'image' or 'video'
  final String fileUrl;
  final String caption;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final List<Comment> comments;
  final User user;
  final bool isLiked;

  Reel({
    required this.id,
    required this.type,
    required this.fileUrl,
    required this.caption,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.comments,
    required this.user,
    required this.isLiked,
  });

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id'],
      type: json['type'],
      fileUrl: json['file_url'],
      caption: json['caption'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      likesCount: json['likes_count'],
      commentsCount: json['comments_count'],
      comments: (json['comments'] as List)
          .map((c) => Comment.fromJson(c))
          .toList(),
      user: User.fromJson(json['user']),
      isLiked: json['isLiked'] ?? false,
    );
  }

  Reel copyWith({
    int? likesCount,
    bool? isLiked,
    List<Comment>? comments,
    int? commentsCount,
  }) {
    return Reel(
      id: id,
      type: type,
      fileUrl: fileUrl,
      caption: caption,
      createdAt: createdAt,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      comments: comments ?? this.comments,
      user: user,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

// ==================== API Service ====================

class ApiService {
  static const String baseUrl = 'https://api-tweeter.runflare.run';
  static const String sessionCookieKey = 'session_cookie';

  String? _cookie;
  final SharedPreferences _prefs;

  ApiService(this._prefs) {
    _cookie = _prefs.getString(sessionCookieKey);
  }

  Future<void> _saveCookie(String? cookie) async {
    _cookie = cookie;
    if (cookie != null) {
      await _prefs.setString(sessionCookieKey, cookie);
    } else {
      await _prefs.remove(sessionCookieKey);
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_cookie != null) {
      headers['Cookie'] = _cookie!;
    }
    return headers;
  }

  Future<Map<String, String>> _multipartHeaders() async {
    final headers = <String, String>{};
    if (_cookie != null) {
      headers['Cookie'] = _cookie!;
    }
    return headers;
  }

  void _updateCookie(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      _saveCookie(rawCookie.split(';')[0]);
    }
  }

  Future<User> register(String username, String password, String name, String bio) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'name': name,
        'bio': bio,
      }),
    );
    _updateCookie(response);
    if (response.statusCode == 201) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(_parseError(response));
    }
  }

  Future<User> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    _updateCookie(response);
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(_parseError(response));
    }
  }

  Future<void> logout() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/logout'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      await _saveCookie(null);
    } else {
      throw Exception('Logout failed');
    }
  }

  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/me'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Not authenticated');
    }
  }

  Future<User> updateProfile({String? name, String? bio, XFile? avatarFile}) async {
    var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/api/profile'));
    request.headers.addAll(await _multipartHeaders());
    if (name != null) request.fields['name'] = name;
    if (bio != null) request.fields['bio'] = bio;
    if (avatarFile != null) {
      final bytes = await avatarFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: avatarFile.name,
      );
      request.files.add(multipartFile);
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(_parseError(response));
    }
  }

  Future<Reel> createReel(XFile file, String type, String caption) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/reels'));
    request.headers.addAll(await _multipartHeaders());
    request.fields['type'] = type;
    if (caption.isNotEmpty) request.fields['caption'] = caption;
    final bytes = await file.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.name,
    );
    request.files.add(multipartFile);
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 201) {
      try {
        return Reel.fromJson(jsonDecode(response.body));
      } catch (e) {
        throw Exception('Invalid response from server');
      }
    } else {
      throw Exception(_parseError(response));
    }
  }

  Future<List<Reel>> getFeed({int page = 1, int perPage = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reels?page=$page&per_page=$perPage'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['reels'] as List).map((r) => Reel.fromJson(r)).toList();
    } else {
      throw Exception('Failed to load feed');
    }
  }

  Future<Reel> getReel(int reelId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reels/$reelId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return Reel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Reel not found');
    }
  }

  Future<Reel> toggleLike(int reelId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reels/$reelId/like'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return Reel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to toggle like');
    }
  }

  Future<Reel> addComment(int reelId, String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reels/$reelId/comment'),
      headers: _headers,
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode == 201) {
      return Reel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(_parseError(response));
    }
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['error'] ?? 'Unknown error';
    } catch (_) {
      return 'Server error (${response.statusCode})';
    }
  }
}

// ==================== Saved Posts Service ====================

class SavedPostsService {
  static const String savedKey = 'saved_posts';
  final SharedPreferences prefs;

  SavedPostsService(this.prefs);

  Set<int> getSavedIds() {
    final list = prefs.getStringList(savedKey) ?? [];
    return list.map((e) => int.parse(e)).toSet();
  }

  Future<void> savePost(int id) async {
    final set = getSavedIds();
    set.add(id);
    await prefs.setStringList(savedKey, set.map((e) => e.toString()).toList());
  }

  Future<void> unsavePost(int id) async {
    final set = getSavedIds();
    set.remove(id);
    await prefs.setStringList(savedKey, set.map((e) => e.toString()).toList());
  }

  bool isSaved(int id) => getSavedIds().contains(id);
}

// ==================== App State ====================

class AppState extends ChangeNotifier {
  ApiService? _api;
  SavedPostsService? _savedService;
  User? _currentUser;
  List<Reel> _feed = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  User? get currentUser => _currentUser;
  List<Reel> get feed => _feed;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  void init(ApiService api, SavedPostsService savedService) {
    _api = api;
    _savedService = savedService;
  }

  Future<void> loadCurrentUser() async {
    try {
      _currentUser = await _api!.getCurrentUser();
      notifyListeners();
    } catch (e) {
      _currentUser = null;
    }
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentUser = await _api!.login(username, password);
      await loadFeed(reset: true);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String password, String name, String bio) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentUser = await _api!.register(username, password, name, bio);
      await loadFeed(reset: true);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api!.logout();
    _currentUser = null;
    _feed = [];
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? bio, XFile? avatarFile}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentUser = await _api!.updateProfile(name: name, bio: bio, avatarFile: avatarFile);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createReel(XFile file, String type, String caption) async {
    final newReel = await _api!.createReel(file, type, caption);
    _feed.insert(0, newReel);
    notifyListeners();
  }

  Future<void> loadFeed({bool reset = false}) async {
    if (_isLoadingMore) return;
    if (reset) {
      _currentPage = 1;
      _feed = [];
      _hasMore = true;
    }
    if (!_hasMore) return;
    _isLoadingMore = true;
    if (!reset) _currentPage++;
    try {
      final newReels = await _api!.getFeed(page: _currentPage, perPage: 5);
      if (newReels.isEmpty) {
        _hasMore = false;
      } else {
        _feed.addAll(newReels);
      }
    } catch (e) {
      _hasMore = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // Optimistic like
  Future<void> toggleLike(int reelId) async {
    final index = _feed.indexWhere((r) => r.id == reelId);
    if (index == -1) return;

    final oldReel = _feed[index];
    final newLiked = !oldReel.isLiked;
    final delta = newLiked ? 1 : -1;
    final updatedReel = oldReel.copyWith(
      isLiked: newLiked,
      likesCount: oldReel.likesCount + delta,
    );
    _feed[index] = updatedReel;
    notifyListeners();

    try {
      await _api!.toggleLike(reelId);
    } catch (e) {
      // Revert on error
      _feed[index] = oldReel;
      notifyListeners();
    }
  }

  // Optimistic comment
  Future<void> addComment(int reelId, String text) async {
    final index = _feed.indexWhere((r) => r.id == reelId);
    if (index == -1) return;

    // We don't have the new comment data yet, so we just increment count optimistically
    final oldReel = _feed[index];
    final updatedReel = oldReel.copyWith(
      commentsCount: oldReel.commentsCount + 1,
    );
    _feed[index] = updatedReel;
    notifyListeners();

    try {
      final newReel = await _api!.addComment(reelId, text);
      _feed[index] = newReel; // replace with actual data
      notifyListeners();
    } catch (e) {
      // Revert on error
      _feed[index] = oldReel;
      notifyListeners();
      rethrow;
    }
  }

  bool isSaved(int reelId) => _savedService!.isSaved(reelId);

  Future<void> toggleSave(int reelId) async {
    if (_savedService!.isSaved(reelId)) {
      await _savedService!.unsavePost(reelId);
    } else {
      await _savedService!.savePost(reelId);
    }
    notifyListeners(); // Notify listeners to update UI
  }

  List<Reel> getSavedReels() {
    final savedIds = _savedService!.getSavedIds();
    return _feed.where((reel) => savedIds.contains(reel.id)).toList();
  }
}

// ==================== Main ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  await Permission.camera.request();
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService(prefs);
  final savedService = SavedPostsService(prefs);
  runApp(MyApp(api: api, savedService: savedService));
}

class MyApp extends StatelessWidget {
  final ApiService api;
  final SavedPostsService savedService;
  const MyApp({super.key, required this.api, required this.savedService});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState();
        state.init(api, savedService);
        state.loadCurrentUser();
        return state;
      },
      child: MaterialApp(
        title: 'Reels Clone',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          primaryColor: Colors.white,
        ),
        home: Consumer<AppState>(
          builder: (context, state, child) {
            if (state.currentUser != null) {
              return const MainScreen();
            } else {
              return const AuthScreen();
            }
          },
        ),
      ),
    );
  }
}

// ==================== Auth Screen ====================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  void _submit() async {
    final state = context.read<AppState>();
    try {
      if (_isLogin) {
        await state.login(_usernameController.text, _passwordController.text);
      } else {
        await state.register(
          _usernameController.text,
          _passwordController.text,
          _nameController.text,
          _bioController.text,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Reels Clone',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bioController,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 24),
              Consumer<AppState>(
                builder: (context, state, child) {
                  return state.isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: Text(_isLogin ? 'Login' : 'Register'),
                        );
                },
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(_isLogin
                    ? 'Need an account? Register'
                    : 'Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Main Screen (Bottom Navigation) ====================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final screens = [
    const FeedScreen(),
    const UploadReelScreen(),
    const SavedScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Saved'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ==================== Feed Screen ====================

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final PageController _pageController = PageController();
  final RefreshIndicator _refreshIndicator = const RefreshIndicator(
    onRefresh: _onRefresh,
    child: SizedBox.shrink(),
  );

  static Future<void> _onRefresh() async {
    // Implemented in build
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadFeed(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: () async {
        await state.loadFeed(reset: true);
      },
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: state.feed.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.feed.length) {
            if (state.hasMore && !state.isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                state.loadFeed();
              });
              return const Center(child: CircularProgressIndicator());
            }
            return const SizedBox.shrink();
          }
          final reel = state.feed[index];
          return ReelWidget(
            reel: reel,
            onLike: () => state.toggleLike(reel.id),
            onComment: () => _showComments(context, reel),
            onSave: () => state.toggleSave(reel.id),
            isSaved: state.isSaved(reel.id),
          );
        },
      ),
    );
  }

  void _showComments(BuildContext context, Reel reel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CommentSheet(reel: reel),
    );
  }
}

// ==================== Reel Widget ====================

class ReelWidget extends StatefulWidget {
  final Reel reel;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final bool isSaved;

  const ReelWidget({
    super.key,
    required this.reel,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.isSaved,
  });

  @override
  State<ReelWidget> createState() => _ReelWidgetState();
}

class _ReelWidgetState extends State<ReelWidget> {
  CachedVideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.reel.type == 'video') {
      _videoController = CachedVideoPlayerController.network(widget.reel.fileUrl)
        ..initialize().then((_) {
          setState(() {});
          _videoController?.play();
          _videoController?.setLooping(true);
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
    return Stack(
      children: [
        // Media
        Positioned.fill(
          child: widget.reel.type == 'image'
              ? CachedNetworkImage(
                  imageUrl: widget.reel.fileUrl,
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => Container(color: Colors.black),
                  errorWidget: (ctx, url, err) => const Center(child: Icon(Icons.error)),
                )
              : _videoController != null && _videoController!.value.isInitialized
                  ? CachedVideoPlayer(_videoController!)
                  : Container(color: Colors.black),
        ),
        // Gradient overlay
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
        ),
        // Info & Actions
        Positioned(
          left: 16,
          right: 70,
          bottom: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: widget.reel.user.avatar != null
                        ? CachedNetworkImageProvider(widget.reel.user.avatar!)
                        : null,
                    child: widget.reel.user.avatar == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.reel.user.username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (widget.reel.user.isVerified)
                              const Icon(Icons.verified, color: Colors.blue, size: 16),
                          ],
                        ),
                        if (widget.reel.caption.isNotEmpty)
                          Text(
                            widget.reel.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Right side actions
        Positioned(
          right: 10,
          bottom: 40,
          child: Column(
            children: [
              _buildActionButton(
                icon: widget.reel.isLiked ? Icons.favorite : Icons.favorite_border,
                color: widget.reel.isLiked ? Colors.red : Colors.white,
                label: widget.reel.likesCount.toString(),
                onTap: widget.onLike,
              ),
              const SizedBox(height: 20),
              _buildActionButton(
                icon: Icons.comment,
                label: widget.reel.commentsCount.toString(),
                onTap: widget.onComment,
              ),
              const SizedBox(height: 20),
              _buildActionButton(
                icon: widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                label: '',
                onTap: widget.onSave,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    Color color = Colors.white,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) const SizedBox(height: 4),
          if (label.isNotEmpty) Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ==================== Comment Sheet ====================

class CommentSheet extends StatefulWidget {
  final Reel reel;
  const CommentSheet({super.key, required this.reel});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await context.read<AppState>().addComment(widget.reel.id, text);
      _commentController.clear();
      _focusNode.unfocus();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send comment: $e')),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Comments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.reel.comments.length,
              itemBuilder: (ctx, i) {
                final comment = widget.reel.comments[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: comment.user.avatar != null
                        ? CachedNetworkImageProvider(comment.user.avatar!)
                        : null,
                    child: comment.user.avatar == null
                        ? const Icon(Icons.person, size: 16)
                        : null,
                  ),
                  title: Row(
                    children: [
                      Text(
                        comment.user.username,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (comment.user.isVerified)
                        const Icon(Icons.verified, color: Colors.blue, size: 14),
                    ],
                  ),
                  subtitle: Text(comment.text),
                  trailing: Text(
                    DateFormat('MMM d').format(comment.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
                if (_isSending)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendComment,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Upload Reel Screen ====================

class UploadReelScreen extends StatefulWidget {
  const UploadReelScreen({super.key});

  @override
  State<UploadReelScreen> createState() => _UploadReelScreenState();
}

class _UploadReelScreenState extends State<UploadReelScreen> {
  final _picker = ImagePicker();
  XFile? _selectedFile;
  String? _mediaType; // 'image' or 'video'
  final _captionController = TextEditingController();
  bool _uploading = false;

  Future<void> _pickMedia() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Media'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final file = await _picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                setState(() {
                  _selectedFile = file;
                  _mediaType = 'image';
                });
              }
            },
            child: const Text('Image'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final file = await _picker.pickVideo(source: ImageSource.gallery);
              if (file != null) {
                setState(() {
                  _selectedFile = file;
                  _mediaType = 'video';
                });
              }
            },
            child: const Text('Video'),
          ),
        ],
      ),
    );
  }

  Future<void> _upload() async {
    if (_selectedFile == null || _mediaType == null) return;
    setState(() => _uploading = true);
    try {
      await context.read<AppState>().createReel(
            _selectedFile!,
            _mediaType!,
            _captionController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reel uploaded!')),
        );
        // Clear form
        setState(() {
          _selectedFile = null;
          _mediaType = null;
          _captionController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Reel')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _selectedFile == null
                    ? const Center(child: Text('Tap to select image/video'))
                    : _mediaType == 'image'
                        ? Image.file(File(_selectedFile!.path), fit: BoxFit.cover)
                        : const Center(child: Text('Video selected')),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: 'Caption',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            _uploading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _selectedFile == null ? null : _upload,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('Upload'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ==================== Saved Screen ====================

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final savedReels = state.getSavedReels();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Reels')),
      body: savedReels.isEmpty
          ? const Center(child: Text('No saved reels yet'))
          : ListView.builder(
              itemCount: savedReels.length,
              itemBuilder: (ctx, i) {
                final reel = savedReels[i];
                return ListTile(
                  leading: reel.type == 'image'
                      ? CachedNetworkImage(
                          imageUrl: reel.fileUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey,
                          child: const Icon(Icons.video_library, size: 30),
                        ),
                  title: Text(reel.user.username),
                  subtitle: Text(reel.caption),
                  trailing: IconButton(
                    icon: const Icon(Icons.bookmark, color: Colors.blue),
                    onPressed: () => state.toggleSave(reel.id),
                  ),
                  onTap: () {
                    // Navigate to a detail view? Or just show in feed? For simplicity, we'll just show a snackbar.
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Reel by ${reel.user.username}')),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ==================== Profile Screen ====================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  XFile? _newAvatar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AppState>().currentUser;
      if (user != null) {
        _nameController.text = user.name;
        _bioController.text = user.bio;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _newAvatar = file);
    }
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    await state.updateProfile(
      name: _nameController.text,
      bio: _bioController.text,
      avatarFile: _newAvatar,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    }
  }

  Future<void> _logout() async {
    await context.read<AppState>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    if (user == null) return const SizedBox();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _getAvatarProvider(user),
                    child: user.avatar == null && _newAvatar == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(labelText: 'Bio'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: const Text('Update Profile'),
          ),
        ],
      ),
    );
  }

  ImageProvider? _getAvatarProvider(User user) {
    if (_newAvatar != null) {
      return FileImage(File(_newAvatar!.path));
    } else if (user.avatar != null) {
      return CachedNetworkImageProvider(user.avatar!);
    }
    return null;
  }
}