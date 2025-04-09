import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'タスクリマインダー',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(fontSize: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.indigo, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const TaskReminder(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TaskReminder extends StatefulWidget {
  const TaskReminder({super.key});

  @override
  State<TaskReminder> createState() => _TaskReminderState();
}

class _TaskReminderState extends State<TaskReminder>
    with SingleTickerProviderStateMixin {
  final FlutterTts flutterTts = FlutterTts();
  TextEditingController taskController = TextEditingController();
  int selectedMinutes = 25; // デフォルト値
  List<int> timeOptions = [5, 10, 15, 25, 30, 45, 60, 90, 120]; // 選択できる時間（分）
  Timer? timer;
  int totalTimeInSeconds = 0;
  int initialTimeInSeconds = 0; // 初期時間を保存
  bool isTimerRunning = false;
  bool isTimerPaused = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  // 通知用
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // 通知の初期化
    _initializeNotifications();
    // アプリがバックグラウンドから復帰したときの処理を登録
    WidgetsBinding.instance.addObserver(
      LifecycleObserver(
        resumeCallback: () {
          if (isTimerRunning && !isTimerPaused) {
            // タイマーが中断されていたら再開
            if (timer == null || !timer!.isActive) {
              startTimer();
            }
          }
        },
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );
  }

  // 通知を表示する
  Future<void> _showOngoingNotification() async {
    // 進行状況を計算（初期状態から減少）
    int progressPercentage = (initialTimeInSeconds > 0)
        ? ((totalTimeInSeconds / initialTimeInSeconds) * 100).round()
        : 0;

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'task_reminder_channel',
      'タスクリマインダー',
      channelDescription: 'タスクの進行状況を表示します',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      progress: progressPercentage,
      maxProgress: 100,
      channelShowBadge: true,
    );

    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      '実行中: ${taskController.text}',
      '残り時間: $timeLeftString',
      platformChannelSpecifics,
    );
  }

  // 通知を更新する
  Future<void> _updateNotification() async {
    if (!isTimerRunning) return;

    int progressPercentage = (initialTimeInSeconds > 0)
        ? ((totalTimeInSeconds / initialTimeInSeconds) * 100).round()
        : 0;

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'task_reminder_channel',
      'タスクリマインダー',
      channelDescription: 'タスクの進行状況を表示します',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      progress: progressPercentage,
      maxProgress: 100,
      channelShowBadge: true,
    );

    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      '実行中: ${taskController.text}',
      '残り時間: $timeLeftString ($progressPercentage%)',
      platformChannelSpecifics,
    );
  }

  // 通知を消去する
  Future<void> _cancelNotification() async {
    await flutterLocalNotificationsPlugin.cancel(0);
  }

  String get timeLeftString =>
      '${(totalTimeInSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalTimeInSeconds % 60).toString().padLeft(2, '0')}';

  // 時間表示を分:秒形式に変換する新しいメソッド追加
  String get selectedTimeString =>
      '${selectedMinutes.toString().padLeft(2, '0')}:00';

  double get progressValue {
    if (initialTimeInSeconds == 0) return 1.0;
    // 時間の経過とともに値が減少するように変更
    return totalTimeInSeconds / initialTimeInSeconds;
  }

  void toggleTimer() async {
    if (taskController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("タスク名を入力してください。")));
      return;
    }

    if (isTimerRunning && !isTimerPaused) {
      pauseTimer();
    } else if (isTimerPaused) {
      resumeTimer();
    } else {
      if (!isTimerPaused) {
        final task = taskController.text;
        totalTimeInSeconds = selectedMinutes * 60;
        initialTimeInSeconds = totalTimeInSeconds;
        await flutterTts.speak("$taskを$selectedMinutes分頑張りましょう。ではスタート。");
      }
      startTimer();
    }
  }

  void startTimer() {
    setState(() {
      isTimerRunning = true;
      isTimerPaused = false;
    });

    _animationController.repeat(reverse: true);

    // 通知を表示
    _showOngoingNotification();

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (totalTimeInSeconds > 0) {
          totalTimeInSeconds--;
          // 通知を更新
          _updateNotification();
          if (totalTimeInSeconds > 0 && totalTimeInSeconds % 60 == 0) {
            flutterTts.speak(
                "${taskController.text}を続けてください。残り時間は${totalTimeInSeconds ~/ 60}分です。");
          }
        } else {
          flutterTts.speak("${taskController.text}のタスク時間は終了しました。お疲れ様でした。");
          timer.cancel();
          _animationController.stop();
          // 通知を消去
          _cancelNotification();
          setState(() {
            totalTimeInSeconds = 0;
            initialTimeInSeconds = 0;
            isTimerRunning = false;
            isTimerPaused = false;
          });
        }
      });
    });
  }

  void pauseTimer() {
    flutterTts.speak("${taskController.text}を一時停止します。");
    timer?.cancel();
    _animationController.stop();
    // 通知を消去
    _cancelNotification();
    setState(() {
      isTimerPaused = true;
      isTimerRunning = false;
    });
  }

  void resumeTimer() {
    startTimer();
    flutterTts.speak("${taskController.text}を再開します。");
  }

  void resetTimer() {
    flutterTts.speak("タスク時間をリセットしました。");
    timer?.cancel();
    _animationController.stop();
    // 通知を消去
    _cancelNotification();
    setState(() {
      totalTimeInSeconds = 0;
      initialTimeInSeconds = 0;
      isTimerRunning = false;
      isTimerPaused = false;
    });
  }

  void _showTimePicker() {
    if (isTimerRunning || isTimerPaused) return;

    showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: selectedMinutes ~/ 60, minute: selectedMinutes % 60),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    ).then((TimeOfDay? time) {
      if (time != null) {
        setState(() {
          selectedMinutes = time.hour * 60 + time.minute;
          if (selectedMinutes < 1) selectedMinutes = 1;
        });
      }
    });
  }

  Widget buildActionButton() {
    // タイマー実行中または一時停止中は表示しない
    if (isTimerRunning || isTimerPaused) {
      return const SizedBox.shrink();
    }

    // タスク開始ボタンのみ表示
    return ElevatedButton.icon(
      onPressed: toggleTimer,
      icon: const Icon(Icons.play_arrow, size: 28),
      label: const Text(
        "タスクを開始",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // タイマー実行中のみインディゴブルーのグラデーション背景にする
    final backgroundGradient = isTimerRunning && !isTimerPaused
        ? [
            Colors.indigo.shade700,
            Colors.indigo.shade500,
          ]
        : [
            colorScheme.surfaceVariant,
            colorScheme.background,
          ];

    return Scaffold(
      // 背景色をAppBarとBodyで統一するためにここで設定
      backgroundColor:
          isTimerRunning && !isTimerPaused ? Colors.indigo.shade600 : null,
      appBar: AppBar(
        title: const Text('タスクリマインダー'),
        backgroundColor: isTimerRunning && !isTimerPaused
            ? Colors.indigo.shade700
            : colorScheme.surfaceVariant,
        foregroundColor: isTimerRunning && !isTimerPaused ? Colors.white : null,
        centerTitle: true,
        elevation: 0,
      ),
      // SafeAreaを使って画面全体にコンテンツを表示
      body: Container(
        // 画面全体に背景を適用
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: backgroundGradient,
          ),
        ),
        child: SafeArea(
          // SafeAreaの上部マージンを0にして、AppBarの下からすぐに始まるようにする
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 20),
                          // タイマー実行中表示か設定画面表示かを切り替え
                          if (isTimerRunning && !isTimerPaused)
                            _buildRunningTimerView(colorScheme)
                          else
                            _buildTaskSettingsView(colorScheme),
                        ],
                      ),
                    ),
                  ),
                ),
                // ボタン部分を画面下部に固定
                Container(
                  padding: const EdgeInsets.only(bottom: 24, top: 16),
                  // 一時停止ボタンとタスクを再開ボタンを削除
                  child: !isTimerPaused
                      ? buildActionButton()
                      : const SizedBox.shrink(), // 一時停止中はボタンを表示しない
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // タイマー実行中の表示
  Widget _buildRunningTimerView(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // タスク名を大きく表示
        Card(
          elevation: 8,
          color: const Color.fromARGB(255, 202, 184, 21),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '実行中のタスク',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color.fromARGB(255, 37, 37, 37),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final taskText = taskController.text;
                    // 文字数に応じてフォントサイズを計算
                    double fontSize = 28;
                    if (taskText.length > 15) {
                      fontSize = 24;
                    }
                    if (taskText.length > 25) {
                      fontSize = 20;
                    }
                    if (taskText.length > 40) {
                      fontSize = 18;
                    }

                    return Text(
                      taskText,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        // タイマー表示
        _buildTimerDisplay(colorScheme, isRunning: true),
        const SizedBox(height: 40), // 下部にも余白を追加して上下のバランスを取る
      ],
    );
  }

  // タスク設定画面
  Widget _buildTaskSettingsView(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Card(
          elevation: 4,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'タスク情報',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: taskController,
                  decoration: const InputDecoration(
                    labelText: 'タスク名',
                    prefixIcon: Icon(Icons.task),
                  ),
                ),
                // 既存の時間設定部分を削除
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        // 常にタイマー表示を出す
        _buildTimerDisplay(colorScheme, isRunning: false),
        // リセットボタンを一時停止中のみ表示（プログレスの下に表示）
        if (isTimerPaused)
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: _buildResetButton(),
          ),
        const SizedBox(height: 40), // 下部にも余白を追加して上下のバランスを取る
      ],
    );
  }

  // リセットボタンを丸形に変更
  Widget _buildResetButton() {
    return Center(
      child: FloatingActionButton(
        onPressed: resetTimer,
        backgroundColor: Colors.red.shade100,
        foregroundColor: Colors.red.shade700,
        tooltip: 'リセット',
        child: const Icon(Icons.stop, size: 32),
      ),
    );
  }

  // 共通のタイマー表示ウィジェット - サイズと位置を統一
  Widget _buildTimerDisplay(ColorScheme colorScheme,
      {required bool isRunning}) {
    // 共通サイズを大きく修正
    const double timerSize = 280.0; // プログレスを大きくするため値を増やす
    const double fontSize = 54.0;

    final baseColor = isRunning
        ? Colors.indigo.shade300.withOpacity(0.3)
        : colorScheme.primaryContainer;

    final progressColor = isRunning ? Colors.white : colorScheme.primary;

    final textColor = isRunning ? Colors.white : colorScheme.onPrimaryContainer;

    final circleColor = isRunning
        ? Colors.indigo.shade600.withOpacity(0.1)
        : colorScheme.primary.withOpacity(0);

    // タップ時のアクション設定
    void onTapAction() {
      if (isTimerRunning && !isTimerPaused) {
        // タイマー実行中 → 一時停止
        pauseTimer();
      } else if (isTimerPaused) {
        // 一時停止中 → 再開
        resumeTimer();
      } else if (!isTimerRunning && !isTimerPaused) {
        // 設定画面 → タイムピッカー表示
        _showTimePicker();
      }
    }

    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: onTapAction,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: timerSize,
                  height: timerSize,
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: TimerPainter(
                          progressValue: progressValue,
                          baseColor: baseColor,
                          progressColor: progressColor,
                          pulseValue:
                              isTimerRunning && !isTimerPaused && isRunning
                                  ? _animation.value * 0.05
                                  : 0,
                          strokeWidth: 20.0, // ストロークの太さを増やす
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isTimerRunning || isTimerPaused ? '残り時間' : 'タップして時間設定',
                        style: TextStyle(
                          fontSize: 16,
                          color: textColor.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isTimerRunning || isTimerPaused
                            ? timeLeftString
                            : selectedTimeString, // 「25分」→「25:00」形式に変更
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      // タイマー動作中や一時停止中は操作のヒントを表示
                      if (isTimerRunning || isTimerPaused)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            isTimerRunning && !isTimerPaused
                                ? 'タップして一時停止'
                                : 'タップして再開',
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withOpacity(0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    taskController.dispose();
    _animationController.dispose();
    _cancelNotification(); // アプリ終了時に通知をキャンセル
    WidgetsBinding.instance
        .removeObserver(LifecycleObserver(resumeCallback: () {})); // オブザーバーを削除
    super.dispose();
  }
}

class TimerPainter extends CustomPainter {
  final double progressValue;
  final Color baseColor;
  final Color progressColor;
  final double pulseValue;
  final double strokeWidth;

  TimerPainter({
    required this.progressValue,
    required this.baseColor,
    required this.progressColor,
    this.pulseValue = 0,
    this.strokeWidth = 15.0, // デフォルト値を持つストローク幅パラメーター追加
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    // 背景の円
    final bgPaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // プログレス円弧
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + pulseValue * 3 // ストローク幅を外部から指定可能に
      ..strokeCap = StrokeCap.round;

    const startAngle = -pi / 2; // 12時の位置から開始

    // 完全な円（背景の円と同じ大きさ）を先に描く
    final completePaint = Paint()
      ..color = progressColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // ストローク幅を外部から指定可能に
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - (strokeWidth / 2), completePaint);

    // 実際のプログレス部分 - 右回り（時計回り）に減少するよう描画
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
      startAngle, // 12時の位置から開始
      -2 * pi * progressValue, // 負の値で右回り（時計回り）に描画
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(TimerPainter oldDelegate) {
    return oldDelegate.progressValue != progressValue ||
        oldDelegate.pulseValue != pulseValue;
  }
}

// アプリのライフサイクルを監視するためのクラス
class LifecycleObserver extends WidgetsBindingObserver {
  final Function resumeCallback;

  LifecycleObserver({required this.resumeCallback});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      resumeCallback();
    }
  }
}
