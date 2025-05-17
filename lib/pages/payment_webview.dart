import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String paymentUrl;

  const PaymentWebViewScreen({Key? key, required this.paymentUrl}) : super(key: key);

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.paymentUrl))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (url.contains('success')) {
              // Обработка успешной оплаты
              Navigator.pop(context); // Вернуться на предыдущий экран
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Оплата успешно завершена!')),
              );
            } else if (url.contains('fail')) {
              // Обработка неудачной оплаты
              Navigator.pop(context); // Вернуться на предыдущий экран
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Оплата не удалась.')),
              );
            }
          },
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Оплата'),
        backgroundColor: Colors.green,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}