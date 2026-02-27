import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shamsi_date/shamsi_date.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  await Hive.openBox<String>('news_cache');
  await Hive.openBox<String>('settings');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'NokhodNews',
            debugShowCheckedModeBanner: false,
            theme: settings.lightTheme,
            darkTheme: settings.darkTheme,
            themeMode: settings.themeMode,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('fa', 'IR'),
              Locale('en'),
            ],
            locale: const Locale('fa', 'IR'),
            home: HomePage(),
          );
        },
      ),
    );
  }
}

// =============== Models (با تبدیل ایمن) ===============

class Enclosure {
  final String url;
  final String type;
  final int length;
  Enclosure({required this.url, required this.type, required this.length});
  Map<String, dynamic> toJson() => {'url': url, 'type': type, 'length': length};
  factory Enclosure.fromJson(Map<String, dynamic> json) {
    // تبدیل ایمن length
    int parseLength(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }
    return Enclosure(
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? '',
      length: parseLength(json['length']),
    );
  }
}

class Statistics {
  final int favorites;
  final int forwards;
  final int views;
  Statistics({required this.favorites, required this.forwards, required this.views});
  Map<String, dynamic> toJson() => {'favorites': favorites, 'forwards': forwards, 'views': views};
  factory Statistics.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }
    return Statistics(
      favorites: parseInt(json['favorites']),
      forwards: parseInt(json['forwards']),
      views: parseInt(json['views']),
    );
  }
}

class Reaction {
  final int count;
  final String emoji;
  Reaction({required this.count, required this.emoji});
  Map<String, dynamic> toJson() => {'count': count, 'emoji': emoji};
  factory Reaction.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }
    return Reaction(
      count: parseInt(json['count']),
      emoji: json['emoji'] as String? ?? '',
    );
  }
}

class NewsItem {
  final String title;
  final String description;
  final DateTime pubDate;
  final String link;
  final String guid;
  final Enclosure? enclosure;
  final List<Reaction> reactions;
  final Statistics statistics;

  NewsItem({
    required this.title,
    required this.description,
    required this.pubDate,
    required this.link,
    required this.guid,
    this.enclosure,
    this.reactions = const [],
    required this.statistics,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'pubDate': pubDate.toIso8601String(),
        'link': link,
        'guid': guid,
        'enclosure': enclosure?.toJson(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'statistics': statistics.toJson(),
      };

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String dateStr) {
      try {
        return DateFormat('EEE, dd MMM yyyy HH:mm:ss Z').parse(dateStr, true);
      } catch (e) {
        return DateTime.now();
      }
    }

    return NewsItem(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      pubDate: parseDate(json['pubDate'] as String? ?? ''),
      link: json['link'] as String? ?? '',
      guid: json['guid'] as String? ?? '',
      enclosure: json['enclosure'] != null ? Enclosure.fromJson(json['enclosure']) : null,
      reactions: (json['reactions'] as List?)?.map((e) => Reaction.fromJson(e)).toList() ?? [],
      statistics: Statistics.fromJson(json['statistics'] ?? {}),
    );
  }
}

// =============== API Service ===============

const String apiUrl = 'https://news-tweeter.runflare.run/api/news';

Future<List<NewsItem>> fetchNewsFromApi() async {
  final response = await http.get(Uri.parse(apiUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to load news');
  }
  final List<dynamic> data = jsonDecode(response.body);
  return data.map((e) => NewsItem.fromJson(e)).toList();
}

// =============== Providers ===============

class SettingsProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';
  static const String _cacheEnabledKey = 'cache_enabled';
  static const String _sortAscendingKey = 'sort_ascending';
  static const String _itemsLimitKey = 'items_limit';
  static const String _showThumbnailsKey = 'show_thumbnails';
  static const String _showReactionsKey = 'show_reactions';
  static const String _showStatisticsKey = 'show_statistics';

  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 14.0;
  bool _cacheEnabled = true;
  bool _sortAscending = false; // false = نزولی (جدیدترین اول)
  int _itemsLimit = 50;
  bool _showThumbnails = true;
  bool _showReactions = true;
  bool _showStatistics = true;

  SettingsProvider() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[_prefs.getInt(_themeKey) ?? 2];
    _fontSize = _prefs.getDouble(_fontSizeKey) ?? 14.0;
    _cacheEnabled = _prefs.getBool(_cacheEnabledKey) ?? true;
    _sortAscending = _prefs.getBool(_sortAscendingKey) ?? false;
    _itemsLimit = _prefs.getInt(_itemsLimitKey) ?? 50;
    _showThumbnails = _prefs.getBool(_showThumbnailsKey) ?? true;
    _showReactions = _prefs.getBool(_showReactionsKey) ?? true;
    _showStatistics = _prefs.getBool(_showStatisticsKey) ?? true;
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get cacheEnabled => _cacheEnabled;
  bool get sortAscending => _sortAscending;
  int get itemsLimit => _itemsLimit;
  bool get showThumbnails => _showThumbnails;
  bool get showReactions => _showReactions;
  bool get showStatistics => _showStatistics;

  ThemeData get lightTheme => ThemeData.light().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.light().textTheme.apply(
              fontSizeFactor: _fontSize / 14,
              fontFamily: 'Vazir',
            ),
      );

  ThemeData get darkTheme => ThemeData.dark().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.dark().textTheme.apply(
              fontSizeFactor: _fontSize / 14,
              fontFamily: 'Vazir',
            ),
      );

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  void setFontSize(double size) {
    _fontSize = size;
    _prefs.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  void setCacheEnabled(bool enabled) {
    _cacheEnabled = enabled;
    _prefs.setBool(_cacheEnabledKey, enabled);
    notifyListeners();
  }

  void setSortAscending(bool ascending) {
    _sortAscending = ascending;
    _prefs.setBool(_sortAscendingKey, ascending);
    notifyListeners();
  }

  void setItemsLimit(int limit) {
    _itemsLimit = limit;
    _prefs.setInt(_itemsLimitKey, limit);
    notifyListeners();
  }

  void setShowThumbnails(bool show) {
    _showThumbnails = show;
    _prefs.setBool(_showThumbnailsKey, show);
    notifyListeners();
  }

  void setShowReactions(bool show) {
    _showReactions = show;
    _prefs.setBool(_showReactionsKey, show);
    notifyListeners();
  }

  void setShowStatistics(bool show) {
    _showStatistics = show;
    _prefs.setBool(_showStatisticsKey, show);
    notifyListeners();
  }

  Future<void> clearCache() async {
    final box = Hive.box<String>('news_cache');
    await box.clear();
  }
}

class NewsProvider extends ChangeNotifier {
  List<NewsItem> _items = [];
  bool _loading = false;
  String? _error;

  List<NewsItem> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  NewsProvider() {
    _loadCached();
    fetchNews();
  }

  Future<void> _loadCached() async {
    final box = Hive.box<String>('news_cache');
    final cachedJson = box.get('news');
    if (cachedJson != null) {
      try {
        final List<dynamic> list = jsonDecode(cachedJson);
        _items = list.map((e) => NewsItem.fromJson(e)).toList();
        notifyListeners();
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> fetchNews({bool force = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final items = await fetchNewsFromApi();
      _items = items;
      _error = null;

      // ذخیره در کش
      final box = Hive.box<String>('news_cache');
      final jsonStr = jsonEncode(items.map((i) => i.toJson()).toList());
      await box.put('news', jsonStr);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

// =============== Utility Functions ===============

String relativeTimeJalali(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays > 0) {
    if (diff.inDays == 1) return 'دیروز';
    if (diff.inDays < 7) return '${diff.inDays} روز پیش';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} هفته پیش';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} ماه پیش';
    return '${(diff.inDays / 365).floor()} سال پیش';
  } else if (diff.inHours > 0) {
    return '${diff.inHours} ساعت پیش';
  } else if (diff.inMinutes > 0) {
    return '${diff.inMinutes} دقیقه پیش';
  } else {
    return 'چند لحظه پیش';
  }
}

const _persianMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
];

String fullJalaliDate(DateTime date) {
  final j = Jalali.fromDateTime(date);
  return '${j.day} ${_persianMonths[j.month - 1]} ${j.year}';
}

// =============== Pages ===============

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _initialFetchDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialFetchDone) {
      _initialFetchDone = true;
      final newsProvider = Provider.of<NewsProvider>(context, listen: false);
      newsProvider.fetchNews();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final newsProvider = Provider.of<NewsProvider>(context);

    List<NewsItem> displayItems = List.from(newsProvider.items);
    displayItems.sort((a, b) => settings.sortAscending
        ? a.pubDate.compareTo(b.pubDate)
        : b.pubDate.compareTo(a.pubDate));
    if (displayItems.length > settings.itemsLimit) {
      displayItems = displayItems.sublist(0, settings.itemsLimit);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NokhodNews'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => newsProvider.fetchNews(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => newsProvider.fetchNews(force: true),
        child: newsProvider.loading && newsProvider.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : newsProvider.error != null && newsProvider.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('خطا: ${newsProvider.error}'),
                        ElevatedButton(
                          onPressed: () => newsProvider.fetchNews(force: true),
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: displayItems.length,
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      return ItemCard(item: item);
                    },
                  ),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final NewsItem item;
  const ItemCard({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailPage(item: item)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settings.showThumbnails &&
                item.enclosure != null &&
                item.enclosure!.type.startsWith('image/'))
              CachedNetworkImage(
                imageUrl: item.enclosure!.url,
                placeholder: (_, __) => Container(height: 200, color: Colors.grey[300]),
                errorWidget: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            if (settings.showThumbnails &&
                item.enclosure != null &&
                item.enclosure!.type.startsWith('video/'))
              Container(
                height: 200,
                color: Colors.black,
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isNotEmpty ? item.title : 'بدون عنوان',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    relativeTimeJalali(item.pubDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (settings.showStatistics && item.statistics.views > 0)
                    Row(
                      children: [
                        _statChip(Icons.visibility, item.statistics.views),
                        const SizedBox(width: 8),
                        _statChip(Icons.share, item.statistics.forwards),
                        const SizedBox(width: 8),
                        _statChip(Icons.favorite, item.statistics.favorites),
                      ],
                    ),
                  if (settings.showReactions && item.reactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: item.reactions
                          .map((r) => Chip(label: Text('${r.emoji} ${r.count}')))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(count.toString()),
        ],
      ),
    );
  }
}

class DetailPage extends StatefulWidget {
  final NewsItem item;
  const DetailPage({Key? key, required this.item}) : super(key: key);

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initVideoIfNeeded();
  }

  void _initVideoIfNeeded() {
    if (widget.item.enclosure?.type.startsWith('video/') ?? false) {
      _videoController = VideoPlayerController.network(widget.item.enclosure!.url);
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        aspectRatio: 16 / 9,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
      );
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('جزئیات خبر'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.title.isNotEmpty ? widget.item.title : 'بدون عنوان',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  fullJalaliDate(widget.item.pubDate),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 8),
                Text(
                  '(${relativeTimeJalali(widget.item.pubDate)})',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.item.enclosure != null && widget.item.enclosure!.type.startsWith('image/'))
              CachedNetworkImage(
                imageUrl: widget.item.enclosure!.url,
                placeholder: (_, __) => Container(height: 300, color: Colors.grey[300]),
                errorWidget: (_, __, ___) => Container(height: 300, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                fit: BoxFit.contain,
              ),
            if (widget.item.enclosure != null && widget.item.enclosure!.type.startsWith('video/') && _chewieController != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Chewie(controller: _chewieController!),
              ),
            const SizedBox(height: 16),
            Html(
              data: widget.item.description,
              style: {
                'body': Style(
                  fontSize: FontSize(settings.fontSize),
                  lineHeight: LineHeight(1.6),
                  textAlign: TextAlign.right,
                ),
              },
            ),
            const SizedBox(height: 24),
            if (settings.showStatistics && widget.item.statistics.views > 0) ...[
              Text('آمار:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statBox(Icons.visibility, widget.item.statistics.views),
                  const SizedBox(width: 16),
                  _statBox(Icons.share, widget.item.statistics.forwards),
                  const SizedBox(width: 16),
                  _statBox(Icons.favorite, widget.item.statistics.favorites),
                ],
              ),
            ],
            if (settings.showReactions && widget.item.reactions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('واکنش‌ها:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.item.reactions
                    .map((r) => Chip(
                          label: Text('${r.emoji} ${r.count}'),
                          backgroundColor: Colors.grey[200],
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statBox(IconData icon, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 4),
          Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsProvider _settings;

  @override
  void initState() {
    super.initState();
    _settings = Provider.of<SettingsProvider>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('تم', style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<ThemeMode>(
                title: const Text('روشن'),
                value: ThemeMode.light,
                groupValue: settings.themeMode,
                onChanged: (v) => settings.setThemeMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('تاریک'),
                value: ThemeMode.dark,
                groupValue: settings.themeMode,
                onChanged: (v) => settings.setThemeMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('سیستم'),
                value: ThemeMode.system,
                groupValue: settings.themeMode,
                onChanged: (v) => settings.setThemeMode(v!),
              ),
              const Divider(),
              const Text('اندازه قلم', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: settings.fontSize,
                min: 10,
                max: 20,
                divisions: 10,
                label: settings.fontSize.toStringAsFixed(1),
                onChanged: (v) => settings.setFontSize(v),
              ),
              const Divider(),
              const Text('مرتب‌سازی', style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<bool>(
                title: const Text('جدیدترین اول'),
                value: false,
                groupValue: settings.sortAscending,
                onChanged: (v) => settings.setSortAscending(v!),
              ),
              RadioListTile<bool>(
                title: const Text('قدیمی‌ترین اول'),
                value: true,
                groupValue: settings.sortAscending,
                onChanged: (v) => settings.setSortAscending(v!),
              ),
              const Divider(),
              const Text('تعداد آیتم در صفحه', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: settings.itemsLimit.toDouble(),
                min: 10,
                max: 100,
                divisions: 9,
                label: settings.itemsLimit.toString(),
                onChanged: (v) => settings.setItemsLimit(v.round()),
              ),
              const Divider(),
              const Text('نمایش', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('نمایش تصاویر بندانگشتی در لیست'),
                value: settings.showThumbnails,
                onChanged: (v) => settings.setShowThumbnails(v),
              ),
              SwitchListTile(
                title: const Text('نمایش واکنش‌ها'),
                value: settings.showReactions,
                onChanged: (v) => settings.setShowReactions(v),
              ),
              SwitchListTile(
                title: const Text('نمایش آمار (بازدید، اشتراک، علاقه‌مندی)'),
                value: settings.showStatistics,
                onChanged: (v) => settings.setShowStatistics(v),
              ),
              const Divider(),
              const Text('کش کردن', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('فعال بودن کش'),
                value: settings.cacheEnabled,
                onChanged: (v) => settings.setCacheEnabled(v),
              ),
              ListTile(
                title: const Text('پاک کردن کش'),
                subtitle: const Text('حذف همه داده‌های ذخیره شده'),
                onTap: () async {
                  await settings.clearCache();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کش پاک شد')));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}