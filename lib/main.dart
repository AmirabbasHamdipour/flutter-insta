import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ------------------- Models -------------------
class User {
  final int id;
  final String username;
  final String fullName;
  final String? bio;
  final String? avatar;
  final bool isVerified;
  final bool isAdmin;
  final int postsCount;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    this.bio,
    this.avatar,
    required this.isVerified,
    required this.isAdmin,
    required this.postsCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      bio: json['bio'],
      avatar: json['avatar'],
      isVerified: json['is_verified'] ?? false,
      isAdmin: json['is_admin'] ?? false,
      postsCount: json['posts_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'bio': bio,
        'avatar': avatar,
        'is_verified': isVerified,
        'is_admin': isAdmin,
        'posts_count': postsCount,
      };
}

class Comment {
  final int id;
  final User user;
  final String content;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      user: User.fromJson(json['user']),
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Post {
  final int id;
  final String? caption;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String mediaType;
  final DateTime createdAt;
  final User user;
  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final bool likedByUser;
  final bool savedByUser;
  final List<Comment> comments;

  Post({
    required this.id,
    this.caption,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.mediaType,
    required this.createdAt,
    required this.user,
    required this.likesCount,
    required this.commentsCount,
    required this.savesCount,
    required this.likedByUser,
    required this.savedByUser,
    required this.comments,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      caption: json['caption'],
      mediaUrl: json['media_url'],
      thumbnailUrl: json['thumbnail_url'],
      mediaType: json['media_type'],
      createdAt: DateTime.parse(json['created_at']),
      user: User.fromJson(json['user']),
      likesCount: json['likes_count'],
      commentsCount: json['comments_count'],
      savesCount: json['saves_count'],
      likedByUser: json['liked_by_user'] ?? false,
      savedByUser: json['saved_by_user'] ?? false,
      comments: (json['comments'] as List)
          .map((c) => Comment.fromJson(c))
          .toList(),
    );
  }
}

// ------------------- API Service (با نادیده گرفتن گواهی SSL) -------------------
class ApiService {
  static const String baseUrl = 'https://api-tweeter.runflare.run';
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

  http.Client get _client => IOClient(_httpClient);

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  // Auth
  Future<Map<String, dynamic>> register(
      String username, String password, String fullName, String bio) async {
    final client = _client;
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'full_name': fullName,
          'bio': bio,
        }),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'خطا در ثبت‌نام');
      }
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final client = _client;
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'خطا در ورود');
      }
    } finally {
      client.close();
    }
  }

  // Feed
  Future<List<Post>> getFeed() async {
    final client = _client;
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/feed'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((p) => Post.fromJson(p)).toList();
      } else {
        throw Exception('خطا در دریافت فید');
      }
    } finally {
      client.close();
    }
  }

  // Post detail
  Future<Post> getPost(int postId) async {
    final client = _client;
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/post/$postId'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        return Post.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('خطا در دریافت پست');
      }
    } finally {
      client.close();
    }
  }

  // Like
  Future<bool> likePost(int postId) async {
    final client = _client;
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/post/$postId/like'),
        headers: await _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['liked'];
      } else {
        throw Exception('خطا در لایک');
      }
    } finally {
      client.close();
    }
  }

  // Comment
  Future<Comment> commentPost(int postId, String content) async {
    final client = _client;
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/post/$postId/comment'),
        headers: await _headers(),
        body: jsonEncode({'content': content}),
      );
      if (response.statusCode == 201) {
        return Comment.fromJson(jsonDecode(response.body)['comment']);
      } else {
        throw Exception('خطا در ارسال کامنت');
      }
    } finally {
      client.close();
    }
  }

  // Save
  Future<bool> savePost(int postId) async {
    final client = _client;
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/post/$postId/save'),
        headers: await _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['saved'];
      } else {
        throw Exception('خطا در ذخیره');
      }
    } finally {
      client.close();
    }
  }

  // Create post
  Future<Post> createPost(String caption, File mediaFile, String mediaType) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/post'));
    request.headers.addAll(await _headers());
    request.fields['caption'] = caption;
    request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
    final client = _client;
    try {
      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 201) {
        return Post.fromJson(jsonDecode(response.body)['post']);
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'خطا در ایجاد پست');
      }
    } finally {
      client.close();
    }
  }

  // Upload avatar
  Future<String> uploadAvatar(File avatarFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/user/avatar'));
    request.headers.addAll(await _headers());
    request.files.add(await http.MultipartFile.fromPath('avatar', avatarFile.path));
    final client = _client;
    try {
      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['avatar_url'];
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'خطا در آپلود آواتار');
      }
    } finally {
      client.close();
    }
  }

  // Get user profile
  Future<Map<String, dynamic>> getUserProfile(String username) async {
    final client = _client;
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/user/$username'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('خطا در دریافت پروفایل');
      }
    } finally {
      client.close();
    }
  }

  // Admin verify
  Future<void> adminVerify(String username, bool verified) async {
    final client = _client;
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/admin/verify/$username'),
        headers: await _headers(),
        body: jsonEncode({'verified': verified}),
      );
      if (response.statusCode != 200) {
        throw Exception(jsonDecode(response.body)['error'] ?? 'خطا در تغییر تیک آبی');
      }
    } finally {
      client.close();
    }
  }
}

// ------------------- Providers -------------------
class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  AuthProvider() {
    _loadStoredData();
  }

  Future<void> _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final userJson = prefs.getString('user');
    if (_token != null && userJson != null) {
      _user = User.fromJson(jsonDecode(userJson));
      ApiService().setToken(_token!);
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService().login(username, password);
      _token = data['access_token'];
      _user = User.fromJson(data['user']);
      ApiService().setToken(_token!);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('user', jsonEncode(_user!.toJson()));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String password, String fullName, String bio) async {
    _isLoading = true;
    notifyListeners();
    try {
      await ApiService().register(username, password, fullName, bio);
      await login(username, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    ApiService().clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    notifyListeners();
  }

  Future<void> updateAvatar(String avatarUrl) async {
    if (_user != null) {
      _user = User(
        id: _user!.id,
        username: _user!.username,
        fullName: _user!.fullName,
        bio: _user!.bio,
        avatar: avatarUrl,
        isVerified: _user!.isVerified,
        isAdmin: _user!.isAdmin,
        postsCount: _user!.postsCount,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(_user!.toJson()));
      notifyListeners();
    }
  }

  Future<void> refreshUser() async {
    if (_user != null) {
      try {
        final data = await ApiService().getUserProfile(_user!.username);
        _user = User.fromJson({
          ...data,
          'is_admin': _user!.isAdmin,
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(_user!.toJson()));
        notifyListeners();
      } catch (e) {}
    }
  }
}

class FeedProvider extends ChangeNotifier {
  List<Post> _posts = [];
  bool _isLoading = false;

  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;
  List<Post> get videoPosts => _posts.where((p) => p.mediaType == 'video').toList();

  Future<void> loadFeed() async {
    _isLoading = true;
    notifyListeners();
    try {
      _posts = await ApiService().getFeed();
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updatePost(Post updatedPost) {
    final index = _posts.indexWhere((p) => p.id == updatedPost.id);
    if (index != -1) {
      _posts[index] = updatedPost;
      notifyListeners();
    }
  }
}

class ProfileProvider extends ChangeNotifier {
  User? _profileUser;
  List<Post> _posts = [];
  bool _isLoading = false;

  User? get profileUser => _profileUser;
  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;

  Future<void> loadProfile(String username) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService().getUserProfile(username);
      _profileUser = User.fromJson(data);
      _posts = (data['posts'] as List).map((p) => Post.fromJson(p)).toList();
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _profileUser = null;
    _posts = [];
    notifyListeners();
  }
}

// ------------------- Screens -------------------
// Login Screen (بدون تغییر)
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('ورود')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'نام کاربری'),
                validator: (v) => v!.isEmpty ? 'اجباری' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'رمز عبور'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'اجباری' : null,
              ),
              SizedBox(height: 20),
              if (auth.isLoading)
                CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      try {
                        await auth.login(_usernameController.text, _passwordController.text);
                        Navigator.pushReplacementNamed(context, '/home');
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                  child: Text('ورود'),
                ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: Text('ثبت‌نام'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Register Screen (بدون تغییر)
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('ثبت‌نام')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'نام کاربری'),
                validator: (v) => v!.isEmpty ? 'اجباری' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'رمز عبور'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'اجباری' : null,
              ),
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(labelText: 'نام کامل'),
                validator: (v) => v!.isEmpty ? 'اجباری' : null,
              ),
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(labelText: 'بیوگرافی'),
                maxLines: 3,
              ),
              SizedBox(height: 20),
              if (auth.isLoading)
                CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      try {
                        await auth.register(
                            _usernameController.text,
                            _passwordController.text,
                            _fullNameController.text,
                            _bioController.text);
                        Navigator.pushReplacementNamed(context, '/home');
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                  child: Text('ثبت‌نام'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('قبلاً ثبت‌نام کرده‌ام'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// صفحه اصلی با BottomNavigationBar
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    FeedTab(),
    ReelsScreen(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'خانه'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'ریلز'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'پروفایل'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/create_post'),
              child: Icon(Icons.add),
            )
          : null,
    );
  }
}

// تب فید (لیست پست‌ها)
class FeedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final feed = Provider.of<FeedProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('خانه')),
      body: feed.isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: feed.posts.length,
              itemBuilder: (ctx, i) => PostWidget(post: feed.posts[i]),
            ),
    );
  }
}

// تب پروفایل (پروفایل کاربر فعلی)
class ProfileTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return ProfileScreen(username: auth.user!.username);
  }
}

// ویجت نمایش پست در فید
class PostWidget extends StatelessWidget {
  final Post post;

  const PostWidget({Key? key, required this.post}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: post.user.avatar != null
                  ? CachedNetworkImageProvider(post.user.avatar!)
                  : null,
              child: post.user.avatar == null ? Icon(Icons.person) : null,
            ),
            title: Row(
              children: [
                Text(post.user.fullName),
                if (post.user.isVerified)
                  Icon(Icons.verified, color: Colors.blue, size: 16),
              ],
            ),
            subtitle: Text('@${post.user.username}'),
            onTap: () => Navigator.pushNamed(context, '/profile',
                arguments: post.user.username),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/post/${post.id}', arguments: post),
            child: post.mediaType == 'image'
                ? CachedNetworkImage(imageUrl: post.mediaUrl)
                : AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoPlayerWidget(url: post.mediaUrl, autoPlay: false),
                  ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  post.likedByUser ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByUser ? Colors.red : null,
                ),
                onPressed: () async {
                  try {
                    final liked = await ApiService().likePost(post.id);
                    final feed = Provider.of<FeedProvider>(context, listen: false);
                    final updatedPost = Post(
                      id: post.id,
                      caption: post.caption,
                      mediaUrl: post.mediaUrl,
                      thumbnailUrl: post.thumbnailUrl,
                      mediaType: post.mediaType,
                      createdAt: post.createdAt,
                      user: post.user,
                      likesCount: post.likesCount + (liked ? 1 : -1),
                      commentsCount: post.commentsCount,
                      savesCount: post.savesCount,
                      likedByUser: liked,
                      savedByUser: post.savedByUser,
                      comments: post.comments,
                    );
                    feed.updatePost(updatedPost);
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
              ),
              Text('${post.likesCount}'),
              IconButton(
                icon: Icon(Icons.comment),
                onPressed: () => Navigator.pushNamed(context, '/post/${post.id}', arguments: post),
              ),
              Text('${post.commentsCount}'),
              IconButton(
                icon: Icon(post.savedByUser ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  try {
                    final saved = await ApiService().savePost(post.id);
                    final feed = Provider.of<FeedProvider>(context, listen: false);
                    final updatedPost = Post(
                      id: post.id,
                      caption: post.caption,
                      mediaUrl: post.mediaUrl,
                      thumbnailUrl: post.thumbnailUrl,
                      mediaType: post.mediaType,
                      createdAt: post.createdAt,
                      user: post.user,
                      likesCount: post.likesCount,
                      commentsCount: post.commentsCount,
                      savesCount: post.savesCount + (saved ? 1 : -1),
                      likedByUser: post.likedByUser,
                      savedByUser: saved,
                      comments: post.comments,
                    );
                    feed.updatePost(updatedPost);
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
              ),
              Text('${post.savesCount}'),
            ],
          ),
          if (post.caption != null && post.caption!.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(8),
              child: Text(post.caption!),
            ),
        ],
      ),
    );
  }
}

// ویجت پخش ویدئو (با قابلیت autoPlay)
class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool autoPlay;

  const VideoPlayerWidget({Key? key, required this.url, this.autoPlay = false}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() {});
        if (widget.autoPlay) {
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(_controller),
          IconButton(
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 50,
            ),
            onPressed: () {
              setState(() {
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
              });
            },
          ),
        ],
      ),
    );
  }
}

// صفحه Reels (ویدئوهای تمام‌صفحه)
class ReelsScreen extends StatefulWidget {
  @override
  _ReelsScreenState createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  List<Post> videoPosts = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feed = Provider.of<FeedProvider>(context, listen: false);
      videoPosts = feed.videoPosts;
      if (videoPosts.isNotEmpty) {
        _initVideoController(0);
      }
    });
  }

  void _initVideoController(int index) async {
    if (videoPosts.isEmpty) return;
    _videoController?.dispose();
    final url = videoPosts[index].mediaUrl;
    _videoController = VideoPlayerController.network(url)
      ..initialize().then((_) {
        setState(() {});
        _videoController!.play();
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = Provider.of<FeedProvider>(context);
    videoPosts = feed.videoPosts;
    if (videoPosts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('ریلز')),
        body: Center(child: Text('ویدئویی وجود ندارد')),
      );
    }
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: videoPosts.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _initVideoController(index);
          });
        },
        itemBuilder: (context, index) {
          final post = videoPosts[index];
          final isCurrent = index == _currentIndex;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null && isCurrent && _videoController!.value.isInitialized)
                VideoPlayer(_videoController!)
              else
                CachedNetworkImage(
                  imageUrl: post.thumbnailUrl ?? post.mediaUrl,
                  fit: BoxFit.cover,
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                left: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: post.user.avatar != null
                              ? CachedNetworkImageProvider(post.user.avatar!)
                              : null,
                          child: post.user.avatar == null ? Icon(Icons.person) : null,
                        ),
                        SizedBox(width: 8),
                        Text(post.user.username, style: TextStyle(color: Colors.white)),
                        if (post.user.isVerified)
                          Icon(Icons.verified, color: Colors.blue, size: 16),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(post.caption ?? '', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              Positioned(
                bottom: 30,
                right: 10,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        post.likedByUser ? Icons.favorite : Icons.favorite_border,
                        color: post.likedByUser ? Colors.red : Colors.white,
                        size: 30,
                      ),
                      onPressed: () async {
                        try {
                          final liked = await ApiService().likePost(post.id);
                          feed.updatePost(Post(
                            id: post.id,
                            caption: post.caption,
                            mediaUrl: post.mediaUrl,
                            thumbnailUrl: post.thumbnailUrl,
                            mediaType: post.mediaType,
                            createdAt: post.createdAt,
                            user: post.user,
                            likesCount: post.likesCount + (liked ? 1 : -1),
                            commentsCount: post.commentsCount,
                            savesCount: post.savesCount,
                            likedByUser: liked,
                            savedByUser: post.savedByUser,
                            comments: post.comments,
                          ));
                        } catch (e) {}
                      },
                    ),
                    Text('${post.likesCount}', style: TextStyle(color: Colors.white)),
                    IconButton(
                      icon: Icon(Icons.comment, color: Colors.white, size: 30),
                      onPressed: () => _showComments(context, post),
                    ),
                    Text('${post.commentsCount}', style: TextStyle(color: Colors.white)),
                    IconButton(
                      icon: Icon(
                        post.savedByUser ? Icons.bookmark : Icons.bookmark_border,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () async {
                        try {
                          final saved = await ApiService().savePost(post.id);
                          feed.updatePost(Post(
                            id: post.id,
                            caption: post.caption,
                            mediaUrl: post.mediaUrl,
                            thumbnailUrl: post.thumbnailUrl,
                            mediaType: post.mediaType,
                            createdAt: post.createdAt,
                            user: post.user,
                            likesCount: post.likesCount,
                            commentsCount: post.commentsCount,
                            savesCount: post.savesCount + (saved ? 1 : -1),
                            likedByUser: post.likedByUser,
                            savedByUser: saved,
                            comments: post.comments,
                          ));
                        } catch (e) {}
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showComments(BuildContext context, Post post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('نظرات', style: TextStyle(fontSize: 18)),
            ),
            Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: post.comments.length,
                itemBuilder: (ctx, i) {
                  final c = post.comments[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: c.user.avatar != null
                          ? CachedNetworkImageProvider(c.user.avatar!)
                          : null,
                      child: c.user.avatar == null ? Icon(Icons.person) : null,
                    ),
                    title: Row(
                      children: [
                        Text(c.user.fullName),
                        if (c.user.isVerified) Icon(Icons.verified, color: Colors.blue, size: 16),
                      ],
                    ),
                    subtitle: Text(c.content),
                    trailing: Text(DateFormat.yMd().add_jm().format(c.createdAt)),
                  );
                },
              ),
            ),
            Divider(),
            Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(hintText: 'نظر خود را بنویسید...'),
                      onSubmitted: (value) async {
                        if (value.isNotEmpty) {
                          try {
                            final newComment = await ApiService().commentPost(post.id, value);
                            // بروزرسانی پست
                          } catch (e) {}
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// صفحه پست تکی
class PostDetailScreen extends StatefulWidget {
  final Post? post;
  final int? postId;

  const PostDetailScreen({Key? key, this.post, this.postId}) : super(key: key);

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<Post> _postFuture;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.post != null) {
      _postFuture = Future.value(widget.post);
    } else {
      _postFuture = ApiService().getPost(widget.postId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('پست')),
      body: FutureBuilder<Post>(
        future: _postFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطا: ${snapshot.error}'));
          }
          final post = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              children: [
                PostWidget(post: post),
                Divider(),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(hintText: 'نظر خود را بنویسید...'),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send),
                        onPressed: () async {
                          if (_commentController.text.isEmpty) return;
                          try {
                            final comment = await ApiService()
                                .commentPost(post.id, _commentController.text);
                            setState(() {
                              post.comments.insert(0, comment);
                            });
                            _commentController.clear();
                          } catch (e) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(e.toString())));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: post.comments.length,
                  itemBuilder: (ctx, i) {
                    final c = post.comments[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: c.user.avatar != null
                            ? CachedNetworkImageProvider(c.user.avatar!)
                            : null,
                        child: c.user.avatar == null ? Icon(Icons.person) : null,
                      ),
                      title: Row(
                        children: [
                          Text(c.user.fullName),
                          if (c.user.isVerified)
                            Icon(Icons.verified, color: Colors.blue, size: 16),
                        ],
                      ),
                      subtitle: Text(c.content),
                      trailing: Text(DateFormat.yMd().add_jm().format(c.createdAt)),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// صفحه ایجاد پست
class CreatePostScreen extends StatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _captionController = TextEditingController();
  File? _mediaFile;
  String? _mediaType;
  bool _isLoading = false;

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo),
              title: Text('گرفتن عکس'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.camera);
                if (picked != null) {
                  setState(() {
                    _mediaFile = File(picked.path);
                    _mediaType = 'image';
                  });
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.video_camera_back),
              title: Text('گرفتن ویدیو'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickVideo(source: ImageSource.camera);
                if (picked != null) {
                  setState(() {
                    _mediaFile = File(picked.path);
                    _mediaType = 'video';
                  });
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('انتخاب از گالری'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() {
                    _mediaFile = File(picked.path);
                    _mediaType = 'image';
                  });
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.video_library),
              title: Text('انتخاب ویدیو از گالری'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() {
                    _mediaFile = File(picked.path);
                    _mediaType = 'video';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_mediaFile == null || _mediaType == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('لطفاً یک رسانه انتخاب کنید')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final post = await ApiService()
          .createPost(_captionController.text, _mediaFile!, _mediaType!);
      Provider.of<FeedProvider>(context, listen: false).loadFeed();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('پست جدید')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (_mediaFile != null)
              _mediaType == 'image'
                  ? Image.file(_mediaFile!, height: 200)
                  : Container(
                      height: 200,
                      color: Colors.black,
                      child: Center(child: Text('ویدیو انتخاب شد')),
                    ),
            ElevatedButton(
              onPressed: _pickMedia,
              child: Text('انتخاب رسانه'),
            ),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(labelText: 'کپشن'),
              maxLines: 3,
            ),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text('اشتراک‌گذاری'),
                  ),
          ],
        ),
      ),
    );
  }
}

// صفحه پروفایل
class ProfileScreen extends StatefulWidget {
  final String username;
  const ProfileScreen({Key? key, required this.username}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProfileProvider>(context, listen: false).loadProfile(widget.username);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final isOwnProfile = auth.user?.username == widget.username;

    return Scaffold(
      appBar: AppBar(
        title: Text('پروفایل'),
        actions: [
          if (isOwnProfile)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => Navigator.pushNamed(context, '/edit_profile'),
            ),
        ],
      ),
      body: profile.isLoading
          ? Center(child: CircularProgressIndicator())
          : profile.profileUser == null
              ? Center(child: Text('کاربر یافت نشد'))
              : ListView(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: profile.profileUser!.avatar != null
                                ? CachedNetworkImageProvider(profile.profileUser!.avatar!)
                                : null,
                            child: profile.profileUser!.avatar == null
                                ? Icon(Icons.person, size: 50)
                                : null,
                          ),
                          SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profile.profileUser!.fullName,
                                style: TextStyle(fontSize: 20),
                              ),
                              if (profile.profileUser!.isVerified)
                                Icon(Icons.verified, color: Colors.blue),
                            ],
                          ),
                          Text('@${profile.profileUser!.username}'),
                          if (profile.profileUser!.bio != null)
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(profile.profileUser!.bio!),
                            ),
                          Text('${profile.profileUser!.postsCount} پست'),
                          if (auth.user?.isAdmin == true && !isOwnProfile)
                            SwitchListTile(
                              title: Text('تیک آبی'),
                              value: profile.profileUser!.isVerified,
                              onChanged: (value) async {
                                try {
                                  await ApiService()
                                      .adminVerify(profile.profileUser!.username, value);
                                  profile.loadProfile(widget.username);
                                } catch (e) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(e.toString())));
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    Divider(),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: profile.posts.length,
                      itemBuilder: (ctx, i) {
                        final p = profile.posts[i];
                        return GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/post/${p.id}', arguments: p),
                          child: CachedNetworkImage(
                            imageUrl: p.thumbnailUrl ?? p.mediaUrl,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ],
                ),
    );
  }
}

// صفحه ویرایش پروفایل (آواتار)
class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  File? _avatarFile;
  bool _isUploading = false;

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _avatarFile = File(picked.path);
      });
    }
  }

  ImageProvider? get _avatarImage {
    if (_avatarFile != null) return FileImage(_avatarFile!);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.user?.avatar != null) {
      return CachedNetworkImageProvider(auth.user!.avatar!);
    }
    return null;
  }

  Future<void> _uploadAvatar() async {
    if (_avatarFile == null) return;
    setState(() => _isUploading = true);
    try {
      final avatarUrl = await ApiService().uploadAvatar(_avatarFile!);
      await Provider.of<AuthProvider>(context, listen: false).updateAvatar(avatarUrl);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('ویرایش پروفایل')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundImage: _avatarImage,
              child: _avatarFile == null && auth.user?.avatar == null
                  ? Icon(Icons.person, size: 60)
                  : null,
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _pickAvatar,
              child: Text('انتخاب آواتار'),
            ),
            SizedBox(height: 20),
            if (_isUploading)
              CircularProgressIndicator()
            else if (_avatarFile != null)
              ElevatedButton(
                onPressed: _uploadAvatar,
                child: Text('آپلود'),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------- Main App -------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthProvider();
  await auth._loadStoredData();
  runApp(MyApp(auth: auth));
}

class MyApp extends StatelessWidget {
  final AuthProvider auth;
  const MyApp({Key? key, required this.auth}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ],
      child: MaterialApp(
        title: 'اینستاگرام کلون',
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: auth.isLoggedIn ? '/home' : '/login',
        routes: {
          '/login': (ctx) => LoginScreen(),
          '/register': (ctx) => RegisterScreen(),
          '/home': (ctx) => HomeScreen(),
          '/create_post': (ctx) => CreatePostScreen(),
          '/edit_profile': (ctx) => EditProfileScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/profile') {
            final username = settings.arguments as String;
            return MaterialPageRoute(
              builder: (ctx) => ProfileScreen(username: username),
            );
          }
          if (settings.name!.startsWith('/post/')) {
            final postId = int.tryParse(settings.name!.split('/').last);
            final post = settings.arguments as Post?;
            return MaterialPageRoute(
              builder: (ctx) => PostDetailScreen(post: post, postId: postId),
            );
          }
          return null;
        },
      ),
    );
  }
}