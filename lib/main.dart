// کتابخانه‌های مورد نیاز
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

// ---------- مدل داده‌ی Todo ----------
class Todo {
  int? id;
  String title;
  bool isCompleted;
  int createdAt; // timestamp (میلی‌ثانیه)
  String priority; // 'low', 'medium', 'high'

  Todo({
    this.id,
    required this.title,
    this.isCompleted = false,
    required this.createdAt,
    this.priority = 'medium',
  });

  // تبدیل به Map برای ذخیره در دیتابیس
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted ? 1 : 0,
      'createdAt': createdAt,
      'priority': priority,
    };
  }

  // ساخت یک Todo از Map (خوانده‌شده از دیتابیس)
  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as int?,
      title: map['title'] as String,
      isCompleted: (map['isCompleted'] as int) == 1,
      createdAt: map['createdAt'] as int,
      priority: map['priority'] as String? ?? 'medium',
    );
  }
}

// ---------- دستیار دیتابیس (Singleton) ----------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('todos.db');
    return _database!;
  }

  // ساخت و بازکردن دیتابیس
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // ایجاد جدول todos
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE todos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        priority TEXT NOT NULL DEFAULT 'medium'
      )
    ''');
  }

  // عملیات CRUD

  Future<int> insertTodo(Todo todo) async {
    final db = await database;
    return await db.insert('todos', todo.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateTodo(Todo todo) async {
    final db = await database;
    return await db.update('todos', todo.toMap(),
        where: 'id = ?', whereArgs: [todo.id]);
  }

  Future<int> deleteTodo(int id) async {
    final db = await database;
    return await db.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Todo>> getAllTodos() async {
    final db = await database;
    final result = await db.query('todos', orderBy: 'createdAt DESC');
    return result.map((map) => Todo.fromMap(map)).toList();
  }

  Future<List<Todo>> searchTodos(String query) async {
    final db = await database;
    final result = await db.query('todos',
        where: 'title LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'createdAt DESC');
    return result.map((map) => Todo.fromMap(map)).toList();
  }

  Future<int> deleteAllCompleted() async {
    final db = await database;
    return await db.delete('todos', where: 'isCompleted = ?', whereArgs: [1]);
  }
}

// ---------- مدیریت وضعیت با Provider ----------
class TodoProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Todo> _allTodos = [];
  String _searchQuery = '';
  Todo? _deletedTodo; // کار حذف‌شده برای بازگردانی (undo)

  List<Todo> get allTodos => _allTodos;

  List<Todo> get incompleteTodos =>
      _allTodos.where((todo) => !todo.isCompleted).toList();

  List<Todo> get completedTodos =>
      _allTodos.where((todo) => todo.isCompleted).toList();

  // لیست کارهای انجام‌نشده پس از اعمال جستجو
  List<Todo> get filteredIncompleteTodos {
    if (_searchQuery.isEmpty) return incompleteTodos;
    return incompleteTodos
        .where(
            (todo) => todo.title.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  // لیست کارهای انجام‌شده پس از اعمال جستجو
  List<Todo> get filteredCompletedTodos {
    if (_searchQuery.isEmpty) return completedTodos;
    return completedTodos
        .where(
            (todo) => todo.title.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  int get incompleteCount => incompleteTodos.length;

  String get searchQuery => _searchQuery;

  TodoProvider() {
    loadTodos(); // بارگذاری اولیه از دیتابیس
  }

  // بارگذاری همه‌ی کارها از دیتابیس
  Future<void> loadTodos() async {
    _allTodos = await _db.getAllTodos();
    notifyListeners();
  }

  // بروزرسانی عبارت جستجو
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // افزودن کار جدید
  Future<void> addTodo(String title, String priority) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = Todo(
      title: title,
      createdAt: now,
      priority: priority,
    );
    final id = await _db.insertTodo(todo);
    todo.id = id;
    _allTodos.insert(0, todo); // به‌صدر لیست اضافه می‌شود
    notifyListeners();
  }

  // تغییر وضعیت انجام/انجام‌نشده
  Future<void> toggleComplete(Todo todo) async {
    todo.isCompleted = !todo.isCompleted;
    await _db.updateTodo(todo);
    final index = _allTodos.indexWhere((t) => t.id == todo.id);
    if (index != -1) {
      _allTodos[index] = todo;
    }
    notifyListeners();
  }

  // ویرایش عنوان و اولویت
  Future<void> updateTodo(Todo todo, String newTitle, String newPriority) async {
    todo.title = newTitle;
    todo.priority = newPriority;
    await _db.updateTodo(todo);
    final index = _allTodos.indexWhere((t) => t.id == todo.id);
    if (index != -1) {
      _allTodos[index] = todo;
    }
    notifyListeners();
  }

  // حذف یک کار (با پشتیبانی از undo)
  Future<void> deleteTodo(Todo todo) async {
    await _db.deleteTodo(todo.id!);
    _allTodos.removeWhere((t) => t.id == todo.id);
    _deletedTodo = todo; // ذخیره برای بازگردانی
    notifyListeners();
  }

  // بازگردانی آخرین کار حذف‌شده
  Future<void> undoDelete() async {
    if (_deletedTodo != null) {
      await _db.insertTodo(_deletedTodo!);
      _allTodos.insert(0, _deletedTodo!);
      _deletedTodo = null;
      notifyListeners();
    }
  }

  // حذف همه‌ی کارهای انجام‌شده
  Future<void> deleteAllCompleted() async {
    await _db.deleteAllCompleted();
    _allTodos.removeWhere((todo) => todo.isCompleted);
    notifyListeners();
  }
}

// ---------- فرمت‌بندی نسبی تاریخ به فارسی ----------
String formatRelativeDate(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dateDay = DateTime(date.year, date.month, date.day);
  final difference = today.difference(dateDay).inDays;
  final time = DateFormat('HH:mm').format(date);

  if (difference == 0) {
    return 'امروز، $time';
  } else if (difference == 1) {
    return 'دیروز، $time';
  } else if (difference > 1) {
    return '$difference روز پیش';
  } else {
    // اگر تاریخ در آینده باشد (غیرمحتمل)
    return DateFormat('yyyy/MM/dd HH:mm').format(date);
  }
}

// ---------- نقطه‌ی ورود برنامه ----------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // اطمینان از ساخته شدن دیتابیس پیش از اجرای اپ
  await DatabaseHelper.instance.database;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TodoProvider(),
      child: MaterialApp(
        title: 'مدیریت کارها',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system, // هماهنگ با تم سیستم (روشن/تاریک)
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.blue,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.blue,
        ),
        home: const HomePage(),
      ),
    );
  }
}

// ---------- صفحه‌ی اصلی ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  String _selectedPriority = 'medium'; // اولویت پیش‌فرض برای کار جدید

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TodoProvider>(
      builder: (context, provider, child) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('کارهای من'),
              bottom: TabBar(
                tabs: [
                  // تب کارهای انجام نشده همراه با تعداد
                  Tab(text: 'انجام نشده (${provider.incompleteCount})'),
                  const Tab(text: 'انجام شده'),
                ],
              ),
            ),
            body: Column(
              children: [
                // فیلد جستجو
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => provider.setSearchQuery(value),
                    decoration: InputDecoration(
                      hintText: 'جستجو...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                // محتوای تب‌ها
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTodoList(provider.filteredIncompleteTodos),
                      _buildCompletedTab(provider),
                    ],
                  ),
                ),
                // ردیف افزودن کار جدید
                _buildAddTaskRow(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  // ویجت نمایش لیست کارها (انجام‌شده یا انجام‌نشده)
  Widget _buildTodoList(List<Todo> todos) {
    if (todos.isEmpty) {
      return const Center(child: Text('موردی یافت نشد'));
    }
    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) {
        final todo = todos[index];
        return _buildTodoItem(todo);
      },
    );
  }

  // تب کارهای انجام‌شده همراه با دکمه‌ی حذف همه
  Widget _buildCompletedTab(TodoProvider provider) {
    return Column(
      children: [
        if (provider.completedTodos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmDeleteAllCompleted(context, provider),
                icon: const Icon(Icons.delete_sweep),
                label: const Text('حذف همه کارهای انجام شده'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[100],
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ),
        Expanded(
          child: _buildTodoList(provider.filteredCompletedTodos),
        ),
      ],
    );
  }

  // دیالوگ تأیید حذف همه‌ی کارهای انجام‌شده
  void _confirmDeleteAllCompleted(BuildContext context, TodoProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف همه کارهای انجام شده'),
        content: const Text('آیا مطمئن هستید که می‌خواهید تمام کارهای انجام شده را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('خیر'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteAllCompleted();
              Navigator.pop(ctx);
            },
            child: const Text('بله'),
          ),
        ],
      ),
    );
  }

  // ردیف پایینی برای افزودن کار جدید (فیلد متن + انتخاب اولویت + دکمه)
  Widget _buildAddTaskRow(TodoProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'عنوان کار جدید',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // دراپ‌داون انتخاب اولویت
          DropdownButton<String>(
            value: _selectedPriority,
            items: const [
              DropdownMenuItem(value: 'low', child: Text('کم')),
              DropdownMenuItem(value: 'medium', child: Text('متوسط')),
              DropdownMenuItem(value: 'high', child: Text('زیاد')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedPriority = value);
            },
            underline: const SizedBox(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle, size: 36),
            onPressed: () {
              final title = _titleController.text.trim();
              if (title.isNotEmpty) {
                provider.addTodo(title, _selectedPriority);
                _titleController.clear();
                _selectedPriority = 'medium';
              }
            },
          ),
        ],
      ),
    );
  }

  // هر آیتم از لیست کارها (قابل سوایپ، چک‌باکس، نگه‌داشتن طولانی)
  Widget _buildTodoItem(Todo todo) {
    final priorityColor = _getPriorityColor(todo.priority);
    final relativeDate = formatRelativeDate(todo.createdAt);
    return Slidable(
      key: UniqueKey(),
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        children: [
          SlidableAction(
            onPressed: (context) => _deleteWithUndo(context, todo),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'حذف',
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: priorityColor,
          ),
        ),
        title: Text(
          todo.title,
          style: TextStyle(
            decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
            color: todo.isCompleted ? Colors.grey : null,
          ),
        ),
        subtitle: Text(relativeDate),
        trailing: Checkbox(
          value: todo.isCompleted,
          onChanged: (_) => context.read<TodoProvider>().toggleComplete(todo),
        ),
        onLongPress: () => _showEditDialog(context, todo),
      ),
    );
  }

  // رنگ هر اولویت
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // حذف یک کار با نمایش Snackbar برای بازگردانی
  void _deleteWithUndo(BuildContext context, Todo todo) {
    final provider = context.read<TodoProvider>();
    provider.deleteTodo(todo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('کار حذف شد'),
        action: SnackBarAction(
          label: 'بازگردانی',
          onPressed: () => provider.undoDelete(),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // دیالوگ ویرایش عنوان و اولویت (با لمس طولانی)
  void _showEditDialog(BuildContext context, Todo todo) {
    final titleController = TextEditingController(text: todo.title);
    String priority = todo.priority;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش کار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'عنوان'),
            ),
            DropdownButtonFormField<String>(
              value: priority,
              decoration: const InputDecoration(labelText: 'اولویت'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('کم')),
                DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                DropdownMenuItem(value: 'high', child: Text('زیاد')),
              ],
              onChanged: (value) {
                if (value != null) priority = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty) {
                context.read<TodoProvider>().updateTodo(todo, newTitle, priority);
                Navigator.pop(ctx);
              }
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}