import 'dart:convert';
import 'dart:typed_data';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  await Hive.openBox<String>('rss_cache'); // برای ذخیره JSON آیتم‌ها
  await Hive.openBox<String>('settings'); // برای تنظیمات
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
            title: 'RSS Reader',
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

class Statistics {
  final int views;
  final int forwards;
  final int favorites;
  Statistics({required this.views, required this.forwards, required this.favorites});
  Map<String, dynamic> toJson() => {'views': views, 'forwards': forwards, 'favorites': favorites};
  factory Statistics.fromJson(Map<String, dynamic> json) => Statistics(
        views: json['views'] as int,
        forwards: json['forwards'] as int,
        favorites: json['favorites'] as int,
      );
}

class Reaction {
  final String emoji;
  final int count;
  Reaction({required this.emoji, required this.count});
  Map<String, dynamic> toJson() => {'emoji': emoji, 'count': count};
  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        emoji: json['emoji'] as String,
        count: json['count'] as int,
      );
}

class RssItem {
  final String title;
  final String description;
  final DateTime pubDate;
  final String link;
  final String guid;
  final Enclosure? enclosure;
  final Statistics? statistics;
  final List<Reaction> reactions;
  RssItem({
    required this.title,
    required this.description,
    required this.pubDate,
    required this.link,
    required this.guid,
    this.enclosure,
    this.statistics,
    this.reactions = const [],
  });
  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'pubDate': pubDate.toIso8601String(),
        'link': link,
        'guid': guid,
        'enclosure': enclosure?.toJson(),
        'statistics': statistics?.toJson(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
      };
  factory RssItem.fromJson(Map<String, dynamic> json) => RssItem(
        title: json['title'] as String,
        description: json['description'] as String,
        pubDate: DateTime.parse(json['pubDate'] as String),
        link: json['link'] as String,
        guid: json['guid'] as String,
        enclosure: json['enclosure'] != null ? Enclosure.fromJson(json['enclosure']) : null,
        statistics: json['statistics'] != null ? Statistics.fromJson(json['statistics']) : null,
        reactions: (json['reactions'] as List?)?.map((e) => Reaction.fromJson(e)).toList() ?? [],
      );
}

// =============== RSS Parser ===============

Future<List<RssItem>> parseRss(String url) async {
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
    Statistics? parseStatistics() {
      final community = item.findElements('community', namespace: 'https://www.rssboard.org/media-rss').firstOrNull;
      if (community == null) return null;
      final stats = community.findElements('statistics', namespace: 'https://www.rssboard.org/media-rss').firstOrNull;
      if (stats == null) return null;
      return Statistics(
        views: int.tryParse(stats.getAttribute('views') ?? '0') ?? 0,
        forwards: int.tryParse(stats.getAttribute('forwards') ?? '0') ?? 0,
        favorites: int.tryParse(stats.getAttribute('favorites') ?? '0') ?? 0,
      );
    }
    List<Reaction> parseReactions() {
      final community = item.findElements('community', namespace: 'https://www.rssboard.org/media-rss').firstOrNull;
      if (community == null) return [];
      final reactionsElem = community.findElements('reactions', namespace: 'https://www.rssboard.org/media-rss').firstOrNull;
      if (reactionsElem == null) return [];
      return reactionsElem.findElements('reaction', namespace: 'https://www.rssboard.org/media-rss').map((r) {
        return Reaction(
          emoji: r.getAttribute('emoji') ?? '',
          count: int.tryParse(r.getAttribute('count') ?? '0') ?? 0,
        );
      }).toList();
    }
    return RssItem(
      title: getText('title'),
      description: getText('description'),
      pubDate: parseDate(getText('pubDate')),
      link: getText('link'),
      guid: getText('guid'),
      enclosure: parseEnclosure(),
      statistics: parseStatistics(),
      reactions: parseReactions(),
    );
  }).toList();
}

// =============== Providers ===============

class SettingsProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';
  static const String _cacheEnabledKey = 'cache_enabled';
  static const String _activeChannelsKey = 'active_channels';

  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 14.0;
  bool _cacheEnabled = true;
  List<String> _activeChannels = [
    'FO_RK',
    'M0_HM',
    'FarsiOfficialX',
    'AdsVipz',
  ];

  SettingsProvider() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[_prefs.getInt(_themeKey) ?? 2];
    _fontSize = _prefs.getDouble(_fontSizeKey) ?? 14.0;
    _cacheEnabled = _prefs.getBool(_cacheEnabledKey) ?? true;
    _activeChannels = _prefs.getStringList(_activeChannelsKey) ?? _activeChannels;
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get cacheEnabled => _cacheEnabled;
  List<String> get activeChannels => _activeChannels;

  ThemeData get lightTheme => ThemeData.light().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.light().textTheme.apply(fontSizeFactor: _fontSize / 14),
      );
  ThemeData get darkTheme => ThemeData.dark().copyWith(
        platform: TargetPlatform.iOS,
        typography: Typography.material2021(),
        textTheme: ThemeData.dark().textTheme.apply(fontSizeFactor: _fontSize / 14),
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

  final Map<String, String> channelUrls = const {
    'FO_RK': 'https://tg.i-c-a.su/rss/FO_RK?limit=100',
    'M0_HM': 'https://tg.i-c-a.su/rss/M0_HM?limit=100',
    'FarsiOfficialX': 'https://tg.i-c-a.su/rss/FarsiOfficialX?limit=100',
    'AdsVipz': 'https://tg.i-c-a.su/rss/AdsVipz?limit=100',
  };

  List<RssItem> getItems(String channel) => _items[channel] ?? [];
  bool isLoading(String channel) => _loading[channel] ?? false;
  String? getError(String channel) => _errors[channel];

  RssProvider() {
    for (var channel in channels) {
      _loadCached(channel);
      fetchRss(channel);
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

  Future<void> fetchRss(String channel, {bool force = false}) async {
    final settings = Provider.container?.read<SettingsProvider>(); // نمی‌توانیم از Provider در اینجا استفاده کنیم، باید از طریق context یا جداگانه مدیریت کنیم.
    // برای سادگی، از کش همیشه استفاده می‌کنیم و در صورت آنلاین بودن به‌روز می‌کنیم.
    if (_loading[channel] == true) return;
    _loading[channel] = true;
    _errors[channel] = null;
    notifyListeners();
    try {
      final url = channelUrls[channel]!;
      final items = await parseRss(url);
      _items[channel] = items;
      _errors[channel] = null;

      // ذخیره در کش
      final box = Hive.box<String>('rss_cache');
      final jsonStr = jsonEncode(items.map((i) => i.toJson()).toList());
      await box.put(channel, jsonStr);
    } catch (e) {
      _errors[channel] = e.toString();
      // اگر خطا داشت و کش موجود است، همان را نگه می‌داریم
    } finally {
      _loading[channel] = false;
      notifyListeners();
    }
  }
}

// =============== Pages ===============

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _allChannels = const ['FO_RK', 'M0_HM', 'FarsiOfficialX', 'AdsVipz'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _allChannels.length, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final activeChannels = settings.activeChannels;
    final filteredChannels = _allChannels.where((c) => activeChannels.contains(c)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('خبرخوان RSS'),
        bottom: filteredChannels.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: filteredChannels.map((c) => Tab(text: c)).toList(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage())),
          ),
        ],
      ),
      body: filteredChannels.isEmpty
          ? const Center(child: Text('کانالی فعال نیست. به تنظیمات بروید.'))
          : filteredChannels.length == 1
              ? _buildChannelPage(filteredChannels.first)
              : TabBarView(
                  controller: _tabController,
                  children: filteredChannels.map((c) => _buildChannelPage(c)).toList(),
                ),
    );
  }

  Widget _buildChannelPage(String channel) {
    return Consumer2<RssProvider, SettingsProvider>(
      builder: (context, rss, settings, _) {
        final items = rss.getItems(channel);
        final loading = rss.isLoading(channel);
        final error = rss.getError(channel);

        if (loading && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (error != null && items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('خطا: $error'),
                ElevatedButton(
                  onPressed: () => rss.fetchRss(channel, force: true),
                  child: const Text('تلاش مجدد'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => rss.fetchRss(channel, force: true),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ItemCard(item: item, channel: channel);
            },
          ),
        );
      },
    );
  }
}

class ItemCard extends StatelessWidget {
  final RssItem item;
  final String channel;
  const ItemCard({Key? key, required this.item, required this.channel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailPage(item: item, channel: channel)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.enclosure != null && item.enclosure!.type.startsWith('image/'))
              CachedNetworkImage(
                imageUrl: item.enclosure!.url,
                placeholder: (_, __) => Container(height: 200, color: Colors.grey[300]),
                errorWidget: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            if (item.enclosure != null && item.enclosure!.type.startsWith('video/'))
              Container(
                height: 200,
                color: Colors.black,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.play_circle_fill, size: 50, color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DetailPage(item: item, channel: channel)),
                    ),
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
                  Text(
                    DateFormat.yMMMd('fa').add_jm().format(item.pubDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (item.statistics != null)
                    Row(
                      children: [
                        _statChip(Icons.visibility, item.statistics!.views),
                        const SizedBox(width: 8),
                        _statChip(Icons.share, item.statistics!.forwards),
                        const SizedBox(width: 8),
                        _statChip(Icons.favorite, item.statistics!.favorites),
                      ],
                    ),
                  if (item.reactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: item.reactions.map((r) => Chip(label: Text('${r.emoji} ${r.count}'))).toList(),
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
  final RssItem item;
  final String channel;
  const DetailPage({Key? key, required this.item, required this.channel}) : super(key: key);

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
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
    return Scaffold(
      appBar: AppBar(
        title: Text('جزئیات خبر'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat.yMMMd('fa').add_jm().format(widget.item.pubDate),
              style: Theme.of(context).textTheme.bodyMedium,
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
                  fontSize: FontSize(Provider.of<SettingsProvider>(context).fontSize),
                  lineHeight: LineHeight(1.6),
                  textAlign: TextAlign.right,
                ),
              },
            ),
            const SizedBox(height: 24),
            if (widget.item.statistics != null) ...[
              Text('آمار:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statBox(Icons.visibility, widget.item.statistics!.views),
                  const SizedBox(width: 16),
                  _statBox(Icons.share, widget.item.statistics!.forwards),
                  const SizedBox(width: 16),
                  _statBox(Icons.favorite, widget.item.statistics!.favorites),
                ],
              ),
            ],
            if (widget.item.reactions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('واکنش‌ها:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.item.reactions.map((r) => Chip(
                  label: Text('${r.emoji} ${r.count}'),
                  backgroundColor: Colors.grey[200],
                )).toList(),
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