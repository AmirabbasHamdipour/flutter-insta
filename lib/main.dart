import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

// -------------------- Models --------------------
class User {
  final int id;
  final String username;
  final String bio;
  final String? avatar;
  final bool isBlue;
  final bool isAdmin;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.bio,
    this.avatar,
    required this.isBlue,
    required this.isAdmin,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      bio: json['bio'] ?? '',
      avatar: json['avatar'],
      isBlue: json['is_blue'] ?? false,
      isAdmin: json['is_admin'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Reel {
  final int id;
  final String type; // 'image' or 'video'
  final String caption;
  final String fileUrl;
  final DateTime createdAt;
  final User user;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;

  Reel({
    required this.id,
    required this.type,
    required this.caption,
    required this.fileUrl,
    required this.createdAt,
    required this.user,
    required this.likesCount,
    required this.commentsCount,
    required this.isLiked,
  });

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id'],
      type: json['type'],
      caption: json['caption'] ?? '',
      fileUrl: json['file_url'],
      createdAt: DateTime.parse(json['created_at']),
      user: User(
        id: json['user']['id'],
        username: json['user']['username'],
        bio: '', // not provided in reel response
        avatar: json['user']['avatar'],
        isBlue: json['user']['is_blue'] ?? false,
        isAdmin: false,
        createdAt: DateTime.now(), // not provided
      ),
      likesCount: json['likes_count'],
      commentsCount: json['comments_count'],
      isLiked: json['isLiked'] ?? false,
    );
  }
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
      user: User(
        id: json['user']['id'],
        username: json['user']['username'],
        bio: '',
        avatar: json['user']['avatar'],
        isBlue: json['user']['is_blue'] ?? false,
        isAdmin: false,
        createdAt: DateTime.now(),
      ),
    );
  }
}

// -------------------- API Service --------------------
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  late Dio dio;
  late CookieJar cookieJar;
  static const baseUrl = 'https://api-tweeter.runflare.run';

  ApiService._internal() {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    _initCookieJar();
  }

  _initCookieJar() async {
    final dir = await getApplicationDocumentsDirectory();
    cookieJar = PersistCookieJar(
      storage: FileStorage(dir.path + '/.cookies/'),
    );
    dio.interceptors.add(CookieManager(cookieJar));
  }

  // Auth
  Future<Map<String, dynamic>> register(String username, String password) async {
    try {
      final response = await dio.post('/register', data: {'username': username, 'password': password});
      return response.data;
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await dio.post('/login', data: {'username': username, 'password': password});
      return response.data;
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> logout() async {
    try {
      final response = await dio.post('/logout');
      return response.data;
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> getProfile() async {
    try {
      final response = await dio.get('/profile');
      return User.fromJson(response.data);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateProfile({String? bio}) async {
    try {
      await dio.put('/profile', data: {'bio': bio});
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> uploadAvatar(File image) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(image.path, filename: image.path.split('/').last),
      });
      final response = await dio.post('/avatar', data: formData);
      return response.data['avatar_url'];
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  // Reels
  Future<Map<String, dynamic>> fetchReels({int page = 1, int perPage = 10}) async {
    try {
      final response = await dio.get('/api/reels', queryParameters: {'page': page, 'per_page': perPage});
      return response.data;
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Reel> getReel(int id) async {
    try {
      final response = await dio.get('/api/reels/$id');
      return Reel.fromJson(response.data);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> toggleLike(int reelId) async {
    try {
      final response = await dio.post('/api/reels/$reelId/like');
      return response.data;
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Comment>> getComments(int reelId) async {
    try {
      final response = await dio.get('/api/reels/$reelId/comments');
      return (response.data as List).map((c) => Comment.fromJson(c)).toList();
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Comment> postComment(int reelId, String text) async {
    try {
      final response = await dio.post('/api/reels/$reelId/comments', data: {'text': text});
      return Comment.fromJson(response.data);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Reel> createReel(File file, String caption) async {
    try {
      String fileName = file.path.split('/').last;
      String ext = fileName.split('.').last.toLowerCase();
      // نوع فایل توسط سرور تشخیص داده می‌شود، اما برای اطمینان می‌فرستیم
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
        'caption': caption,
      });
      final response = await dio.post('/api/reels', data: formData);
      // after creation, fetch the reel details
      return await getReel(response.data['reel_id']);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioError e) {
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('error')) {
        return data['error'];
      }
      return 'Server error: ${e.response!.statusCode}';
    }
    return 'Network error: ${e.message}';
  }
}

// -------------------- Providers --------------------
class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  final ApiService _api = ApiService();

  Future<bool> register(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.register(username, password);
      // بعد از ثبت‌نام، لاگین کن
      return await login(username, password);
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.login(username, password);
      await loadProfile();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.logout();
      _user = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadProfile() async {
    try {
      _user = await _api.getProfile();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateBio(String bio) async {
    try {
      await _api.updateProfile(bio: bio);
      await loadProfile(); // reload
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<String?> uploadAvatar(File image) async {
    try {
      final url = await _api.uploadAvatar(image);
      await loadProfile(); // reload to get new avatar
      return url;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
}

class ReelsProvider extends ChangeNotifier {
  List<Reel> _reels = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  List<Reel> get reels => _reels;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  final ApiService _api = ApiService();

  Future<void> fetchReels({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _reels.clear();
    }
    if (!_hasMore || _isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.fetchReels(page: _currentPage);
      final List<Reel> newReels = (data['items'] as List).map((r) => Reel.fromJson(r)).toList();
      _reels.addAll(newReels);
      _totalPages = data['pages'];
      _currentPage++;
      _hasMore = _currentPage <= _totalPages;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleLike(int reelId) async {
    try {
      final result = await _api.toggleLike(reelId);
      // update local reel
      final index = _reels.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        final old = _reels[index];
        _reels[index] = Reel(
          id: old.id,
          type: old.type,
          caption: old.caption,
          fileUrl: old.fileUrl,
          createdAt: old.createdAt,
          user: old.user,
          likesCount: result['likes_count'],
          commentsCount: old.commentsCount,
          isLiked: result['liked'],
        );
        notifyListeners();
      }
    } catch (e) {
      // ignore error for now
    }
  }

  // --- متد جدید برای ایجاد ریل ---
  Future<Reel> createReel(File file, String caption) async {
    try {
      return await _api.createReel(file, caption);
    } catch (e) {
      throw e; // propagate to UI
    }
  }
}

class CommentsProvider extends ChangeNotifier {
  List<Comment> _comments = [];
  bool _isLoading = false;
  String? _error;

  List<Comment> get comments => _comments;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final ApiService _api = ApiService();

  Future<void> fetchComments(int reelId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _comments = await _api.getComments(reelId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addComment(int reelId, String text) async {
    try {
      final newComment = await _api.postComment(reelId, text);
      _comments.insert(0, newComment);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}

// -------------------- Main App --------------------
void main() {
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ReelsProvider()),
      ChangeNotifierProvider(create: (_) => CommentsProvider()),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Instagram Reels Clone',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoggedIn) {
            return const ReelsPage();
          }
          return const LoginPage();
        },
      ),
    );
  }
}

// -------------------- Login & Register --------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Instagram Reels',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 30),
                  if (auth.isLoading) const CircularProgressIndicator(),
                  if (!auth.isLoading)
                    ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          bool success;
                          if (_isLogin) {
                            success = await auth.login(_usernameController.text, _passwordController.text);
                          } else {
                            success = await auth.register(_usernameController.text, _passwordController.text);
                          }
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(auth.error ?? 'Error')),
                            );
                          }
                        }
                      },
                      child: Text(_isLogin ? 'Login' : 'Register'),
                    ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                      });
                    },
                    child: Text(_isLogin ? 'Need an account? Register' : 'Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Reels Page --------------------
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReelsProvider>().fetchReels(refresh: true);
    });
    _pageController.addListener(_onPageChanged);
  }

  void _onPageChanged() {
    final newIndex = _pageController.page?.round();
    if (newIndex != null && newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      // load more when near end
      final provider = context.read<ReelsProvider>();
      if (newIndex >= provider.reels.length - 3 && provider.hasMore) {
        provider.fetchReels();
      }
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<ReelsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.reels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null && provider.reels.isEmpty) {
            return Center(child: Text('Error: ${provider.error}'));
          }
          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: provider.reels.length,
                itemBuilder: (context, index) {
                  final reel = provider.reels[index];
                  return ReelItem(
                    reel: reel,
                    isCurrent: index == _currentIndex,
                    onLike: () => provider.toggleLike(reel.id),
                    onComment: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommentsPage(reelId: reel.id),
                        ),
                      ).then((_) => provider.fetchReels(refresh: true)); // refresh after comment
                    },
                  );
                },
              ),
              Positioned(
                top: 40,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.person, color: Colors.white, size: 30),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    );
                  },
                ),
              ),
              Positioned(
                top: 40,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white, size: 30),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateReelPage()),
                    ).then((_) => provider.fetchReels(refresh: true));
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -------------------- Reel Item --------------------
class ReelItem extends StatefulWidget {
  final Reel reel;
  final bool isCurrent;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const ReelItem({
    super.key,
    required this.reel,
    required this.isCurrent,
    required this.onLike,
    required this.onComment,
  });

  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.reel.type == 'video') {
      _initializeVideo();
    }
  }

  void _initializeVideo() {
    _videoController = VideoPlayerController.network(widget.reel.fileUrl)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          if (widget.isCurrent) {
            _videoController?.play();
          }
        }
      }).catchError((e) {
        print('Video error: $e');
      });
  }

  @override
  void didUpdateWidget(covariant ReelItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent != oldWidget.isCurrent) {
      if (widget.isCurrent) {
        _videoController?.play();
      } else {
        _videoController?.pause();
      }
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
      fit: StackFit.expand,
      children: [
        // Media
        if (widget.reel.type == 'image')
          CachedNetworkImage(
            imageUrl: widget.reel.fileUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[900]),
            errorWidget: (_, __, ___) => const Center(child: Icon(Icons.error)),
          )
        else if (_isInitialized && _videoController != null)
          VideoPlayer(_videoController!)
        else
          Container(color: Colors.black),

        // Gradient overlay
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),

        // User info and actions
        Positioned(
          bottom: 30,
          left: 10,
          right: 10,
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
                          radius: 20,
                          backgroundImage: widget.reel.user.avatar != null
                              ? CachedNetworkImageProvider(widget.reel.user.avatar!)
                              : null,
                          child: widget.reel.user.avatar == null
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.reel.user.username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (widget.reel.user.isBlue)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, color: Colors.blue, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(widget.reel.caption),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: widget.onLike,
                    icon: Icon(
                      widget.reel.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: widget.reel.isLiked ? Colors.red : Colors.white,
                      size: 30,
                    ),
                  ),
                  Text('${widget.reel.likesCount}'),
                  const SizedBox(height: 15),
                  IconButton(
                    onPressed: widget.onComment,
                    icon: const Icon(Icons.comment, color: Colors.white, size: 30),
                  ),
                  Text('${widget.reel.commentsCount}'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------- Comments Page --------------------
class CommentsPage extends StatefulWidget {
  final int reelId;
  const CommentsPage({super.key, required this.reelId});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommentsProvider>().fetchComments(widget.reelId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: Consumer<CommentsProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.comments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.error != null) {
                  return Center(child: Text('Error: ${provider.error}'));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: provider.comments.length,
                  itemBuilder: (context, index) {
                    final comment = provider.comments[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: comment.user.avatar != null
                            ? CachedNetworkImageProvider(comment.user.avatar!)
                            : null,
                        child: comment.user.avatar == null ? const Icon(Icons.person) : null,
                      ),
                      title: Row(
                        children: [
                          Text(comment.user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (comment.user.isBlue)
                            const Icon(Icons.verified, color: Colors.blue, size: 14),
                        ],
                      ),
                      subtitle: Text(comment.text),
                      trailing: Text(
                        _timeAgo(comment.createdAt),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    );
                  },
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
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    if (_commentController.text.isNotEmpty) {
                      final provider = context.read<CommentsProvider>();
                      await provider.addComment(widget.reelId, _commentController.text);
                      _commentController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}

// -------------------- Profile Page --------------------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery);
                      if (picked != null) {
                        await auth.uploadAvatar(File(picked.path));
                      }
                    },
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: user.avatar != null
                          ? CachedNetworkImageProvider(user.avatar!)
                          : null,
                      child: user.avatar == null
                          ? const Icon(Icons.camera_alt, size: 50, color: Colors.grey)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('@${user.username}', style: const TextStyle(fontSize: 20)),
                  if (user.isBlue) const Icon(Icons.verified, color: Colors.blue),
                  const SizedBox(height: 20),
                  Text(user.bio.isEmpty ? 'No bio yet' : user.bio),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _editBio(context, user.bio),
                    child: const Text('Edit Bio'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      await auth.logout();
                      // navigates to login automatically via MyApp
                    },
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
    );
  }

  void _editBio(BuildContext context, String currentBio) {
    final controller = TextEditingController(text: currentBio);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Bio'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthProvider>().updateBio(controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// -------------------- Create Reel Page --------------------
class CreateReelPage extends StatefulWidget {
  const CreateReelPage({super.key});

  @override
  State<CreateReelPage> createState() => _CreateReelPageState();
}

class _CreateReelPageState extends State<CreateReelPage> {
  File? _selectedFile;
  final TextEditingController _captionController = TextEditingController();
  bool _isUploading = false;

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.gallery);
                if (picked != null) setState(() => _selectedFile = File(picked.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Video Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) setState(() => _selectedFile = File(picked.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.camera);
                if (picked != null) setState(() => _selectedFile = File(picked.path));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    if (_selectedFile == null) return;
    setState(() => _isUploading = true);
    try {
      final provider = context.read<ReelsProvider>();
      await provider.createReel(_selectedFile!, _captionController.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Reel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_selectedFile != null)
              Container(
                height: 200,
                color: Colors.grey[900],
                child: _selectedFile!.path.toLowerCase().endsWith('.mp4') ||
                        _selectedFile!.path.toLowerCase().endsWith('.mov')
                    ? const Center(child: Text('Video selected'))
                    : Image.file(_selectedFile!),
              )
            else
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  height: 200,
                  color: Colors.grey[900],
                  child: const Center(child: Icon(Icons.add, size: 50)),
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(labelText: 'Caption'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            if (_isUploading) const CircularProgressIndicator(),
            if (!_isUploading)
              ElevatedButton(
                onPressed: _selectedFile == null ? null : _upload,
                child: const Text('Post'),
              ),
          ],
        ),
      ),
    );
  }
}