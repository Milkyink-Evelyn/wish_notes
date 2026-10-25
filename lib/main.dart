import 'package:flutter/material.dart';
import 'utils/http.dart';
import 'utils/sp_utils.dart';

void main() async {
  // 确保在调用runApp之前初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化SharedPreferences
  await SPUtils.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _result = '等待请求...';

  @override
  void initState() {
    super.initState();
    _testNetwork();
  }

  Future<void> _testNetwork() async {
    try {
      // 访问公开测试接口的 posts/1
      final response = await Http().get('/posts/1');
      setState(() {
        _result = '请求成功！返回数据：\n${response.data}';
      });
    } catch (e) {
      setState(() {
        _result = '请求失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(_result, style: const TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );
  }
}