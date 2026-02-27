import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
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
  await Hive.openBox<String>('rss_cache');
  await Hive.openBox<String>('settings');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => RssProvider()),
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

// =============== Models ===============

class Enclosure {
  final String url;
  final String type;
  final int length;
  Enclosure({required this.url, required this.type, required this.length});
  Map<String, dynamic> toJson() => {'url': url, 'type': type, 'length': length};
  factory Enclosure.fromJson(Map<String, dynamic> json) => Enclosure(
        url: json['url'] as String,
        type: json['type'] as String,
        length: json['length'] as int,
      );
}

class RssItem {
  final String title;
  final String description;
  final DateTime pubDate;
  final String link;
  final String guid;
  final Enclosure? enclosure;
  final String channel;

  RssItem({
    required this.title,
    required this.description,
    required this.pubDate,
    required this.link,
    required this.guid,
    this.enclosure,
    required this.channel,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'pubDate': pubDate.toIso8601String(),
        'link': link,
        'guid': guid,
        'enclosure': enclosure?.toJson(),
        'channel': channel,
      };

  factory RssItem.fromJson(Map<String, dynamic> json) => RssItem(
        title: json['title'] as String,
        description: json['description'] as String,
        pubDate: DateTime.parse(json['pubDate'] as String),
        link: json['link'] as String,
        guid: json['guid'] as String,
        enclosure: json['enclosure'] != null ? Enclosure.fromJson(json['enclosure']) : null,
        channel: json['channel'] as String,
      );
}

// =============== RSS Parser ===============

Future<List<RssItem>> parseRss(String url, String channelName) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) throw Exception('Failed to load RSS');
  final document = xml.XmlDocument.parse(response.body);
  final channel = document.findAllElements('channel').first;
  final items = channel.findElements('item');
  return items.map((item) {
    String getText(String tag) => item.findElements(tag).firstOrNull?.innerText ?? '';
    DateTime parseDate(String dateStr) {
      try {
        return DateFormat('EEE, dd MMM yyyy HH:mm:ss Z').parse(dateStr, true);
      } catch (e) {
        return DateTime.now();
      }
    }
    Enclosure? parseEnclosure() {
      final enc = item.findElements('enclosure').firstOrNull;
      if (enc == null) return null;
      return Enclosure(
        url: enc.getAttribute('url') ?? '',
        type: enc.getAttribute('type') ?? '',
        length: int.tryParse(enc.getAttribute('length') ?? '0') ?? 0,
      );
    }
    return RssItem(
      title: getText('title'),
      description: getText('description'),
      pubDate: parseDate(getText('pubDate')),
      link: getText('link'),
      guid: getText('guid'),
      enclosure: parseEnclosure(),
      channel: channelName,
    );
  }).toList();
}

// =============== Providers ===============

class SettingsProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';
  static const String _cacheEnabledKey = 'cache_enabled';
  static const String _activeChannelsKey = 'active_channels';
  static const String _sortAscendingKey = 'sort_ascending';
  static const String _itemsLimitKey = 'items_limit';
  static const String _showThumbnailsKey = 'show_thumbnails';

  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 14.0;
  bool _cacheEnabled = true;
  List<String> _activeChannels = ['FO_RK', 'M0_HM', 'FarsiOfficialX', 'AdsVipz'];
  bool _sortAscending = false; // false = نزولی (جدیدترین اول)
  int _itemsLimit = 50;
  bool _showThumbnails = true;

  SettingsProvider() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[_prefs.getInt(_themeKey) ?? 2];
    _fontSize = _prefs.getDouble(_fontSizeKey) ?? 14.0;
    _cacheEnabled = _prefs.getBool(_cacheEnabledKey) ?? true;
    _activeChannels = _prefs.getStringList(_activeChannelsKey) ?? _activeChannels;
    _sortAscending = _prefs.getBool(_sortAscendingKey) ?? false;
    _itemsLimit = _prefs.getInt(_itemsLimitKey) ?? 50;
    _showThumbnails = _prefs.getBool(_showThumbnailsKey) ?? true;
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get cacheEnabled => _cacheEnabled;
  List<String> get activeChannels => _activeChannels;
  bool get sortAscending => _sortAscending;
  int get itemsLimit => _itemsLimit;
  bool get showThumbnails => _showThumbnails;

  ThemeData get lightTheme => ThemeData.light().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.light().textTheme.apply(
              fontSizeFactor: _fontSize / 14,
              fontFamily: 'Vazir', // فعال شد
            ),
      );

  ThemeData get darkTheme => ThemeData.dark().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.dark().textTheme.apply(
              fontSizeFactor: _fontSize / 14,
              fontFamily: 'Vazir', // فعال شد
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

  void setActiveChannels(List<String> channels) {
    _activeChannels = channels;
    _prefs.setStringList(_activeChannelsKey, channels);
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

  Future<void> clearCache() async {
    final box = Hive.box<String>('rss_cache');
    await box.clear();
  }
}

class RssProvider extends ChangeNotifier {
  Map<String, List<RssItem>> _items = {};
  Map<String, bool> _loading = {};
  Map<String, String?> _errors = {};

  final List<String> channels = const [
    'FO_RK',
    'M0_HM',
    'FarsiOfficialX',
    'AdsVipz',
  ];

  List<RssItem> getItems(String channel) => _items[channel] ?? [];
  bool isLoading(String channel) => _loading[channel] ?? false;
  String? getError(String channel) => _errors[channel];

  List<RssItem> getMergedItems(List<String> activeChannels, bool ascending) {
    final allItems = <RssItem>[];
    for (var channel in activeChannels) {
      allItems.addAll(getItems(channel));
    }
    allItems.sort((a, b) => ascending
        ? a.pubDate.compareTo(b.pubDate)
        : b.pubDate.compareTo(a.pubDate));
    return allItems;
  }

  RssProvider() {
    for (var channel in channels) {
      _loadCached(channel);
    }
  }

  Future<void> _loadCached(String channel) async {
    final box = Hive.box<String>('rss_cache');
    final cachedJson = box.get(channel);
    if (cachedJson != null) {
      try {
        final List<dynamic> list = jsonDecode(cachedJson);
        _items[channel] = list.map((e) => RssItem.fromJson(e)).toList();
        notifyListeners();
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> fetchRss(String channel, int limit, {bool force = false}) async {
    if (_loading[channel] == true) return;
    _loading[channel] = true;
    _errors[channel] = null;
    notifyListeners();

    try {
      final url = 'https://tg.i-c-a.su/rss/$channel?limit=$limit';
      final items = await parseRss(url, channel);
      _items[channel] = items;
      _errors[channel] = null;

      final box = Hive.box<String>('rss_cache');
      final jsonStr = jsonEncode(items.map((i) => i.toJson()).toList());
      await box.put(channel, jsonStr);
    } catch (e) {
      _errors[channel] = e.toString();
    } finally {
      _loading[channel] = false;
      notifyListeners();
    }
  }

  Future<RssItem?> fetchSingleItem(String channel, int messageId) async {
    try {
      final url = 'https://tg.i-c-a.su/rss/$channel?id=$messageId&limit=1';
      final items = await parseRss(url, channel);
      if (items.isNotEmpty) return items.first;
    } catch (e) {
      debugPrint('Error fetching single item: $e');
    }
    return null;
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

int? extractMessageId(String link) {
  final uri = Uri.tryParse(link);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    return int.tryParse(uri.pathSegments.last);
  }
  return null;
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
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final rss = Provider.of<RssProvider>(context, listen: false);
      for (var channel in settings.activeChannels) {
        rss.fetchRss(channel, settings.itemsLimit);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final rss = Provider.of<RssProvider>(context);

    final mergedItems = rss.getMergedItems(settings.activeChannels, settings.sortAscending);

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
            onPressed: () {
              for (var channel in settings.activeChannels) {
                rss.fetchRss(channel, settings.itemsLimit, force: true);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          for (var channel in settings.activeChannels) {
            await rss.fetchRss(channel, settings.itemsLimit, force: true);
          }
        },
        child: mergedItems.isEmpty
            ? Center(
                child: settings.activeChannels.isEmpty
                    ? const Text('کانالی فعال نیست. به تنظیمات بروید.')
                    : const CircularProgressIndicator(),
              )
            : ListView.builder(
                itemCount: mergedItems.length,
                itemBuilder: (context, index) {
                  final item = mergedItems[index];
                  return ItemCard(item: item);
                },
              ),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final RssItem item;
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
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        relativeTimeJalali(item.pubDate),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${item.channel}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
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

class DetailPage extends StatefulWidget {
  final RssItem item;
  const DetailPage({Key? key, required this.item}) : super(key: key);

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  RssItem? _detailedItem;
  bool _loading = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _fetchDetailedItem();
  }

  Future<void> _fetchDetailedItem() async {
    final messageId = extractMessageId(widget.item.link);
    if (messageId == null) return;

    setState(() => _loading = true);
    try {
      final rss = Provider.of<RssProvider>(context, listen: false);
      final detailed = await rss.fetchSingleItem(widget.item.channel, messageId);
      if (detailed != null) {
        setState(() {
          _detailedItem = detailed;
          _loading = false;
        });
        _initVideoIfNeeded();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _initVideoIfNeeded() {
    final item = _detailedItem ?? widget.item;
    if (item.enclosure?.type.startsWith('video/') ?? false) {
      _videoController = VideoPlayerController.network(item.enclosure!.url);
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
    final item = _detailedItem ?? widget.item;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جزئیات خبر'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        fullJalaliDate(item.pubDate),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${relativeTimeJalali(item.pubDate)})',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (item.enclosure != null && item.enclosure!.type.startsWith('image/'))
                    CachedNetworkImage(
                      imageUrl: item.enclosure!.url,
                      placeholder: (_, __) => Container(height: 300, color: Colors.grey[300]),
                      errorWidget: (_, __, ___) => Container(height: 300, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                      fit: BoxFit.contain,
                    ),
                  if (item.enclosure != null && item.enclosure!.type.startsWith('video/') && _chewieController != null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Chewie(controller: _chewieController!),
                    ),
                  const SizedBox(height: 16),
                  Html(
                    data: item.description,
                    style: {
                      'body': Style(
                        fontSize: FontSize(Provider.of<SettingsProvider>(context).fontSize),
                        lineHeight: LineHeight(1.6),
                        textAlign: TextAlign.right,
                      ),
                    },
                  ),
                ],
              ),
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
  late List<String> _tempChannels;

  @override
  void initState() {
    super.initState();
    _settings = Provider.of<SettingsProvider>(context, listen: false);
    _tempChannels = List.from(_settings.activeChannels);
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
              const Text('تعداد آیتم در هر کانال', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: settings.itemsLimit.toDouble(),
                min: 20,
                max: 100,
                divisions: 4,
                label: settings.itemsLimit.toString(),
                onChanged: (v) => settings.setItemsLimit(v.round()),
              ),
              const Divider(),
              const Text('نمایش تصاویر', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('نمایش تصاویر بندانگشتی در لیست'),
                value: settings.showThumbnails,
                onChanged: (v) => settings.setShowThumbnails(v),
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
              const Divider(),
              const Text('کانال‌های فعال', style: TextStyle(fontWeight: FontWeight.bold)),
              ...['FO_RK', 'M0_HM', 'FarsiOfficialX', 'AdsVipz'].map((ch) => CheckboxListTile(
                    title: Text(ch),
                    value: _tempChannels.contains(ch),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _tempChannels.add(ch);
                        } else {
                          _tempChannels.remove(ch);
                        }
                      });
                    },
                  )),
              ElevatedButton(
                onPressed: () {
                  settings.setActiveChannels(_tempChannels);
                  final rss = Provider.of<RssProvider>(context, listen: false);
                  for (var channel in _tempChannels) {
                    rss.fetchRss(channel, settings.itemsLimit, force: true);
                  }
                  Navigator.pop(context);
                },
                child: const Text('ذخیره تغییرات کانال‌ها'),
              ),
            ],
          );
        },
      ),
    );
  }
}