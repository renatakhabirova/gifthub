import 'package:flutter/material.dart';
import 'package:gifthub/themes/colors.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

class PaymentWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  final String orderId;

  const PaymentWebViewScreen({
    Key? key,
    required this.paymentUrl,
    required this.orderId,
  }) : super(key: key);

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Открываем форму оплаты в новом окне
      html.window.open(widget.paymentUrl, '_self');
    } else {
      _initializeWebView();
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.paymentUrl))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) async {
            if (url.contains('success')) {
              await updateOrderStatus();
              Navigator.pop(context, true);
            } else if (url.contains('fail')) {
              Navigator.pop(context, false);
            }
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      );
  }

  Future<void> updateOrderStatus() async {
    try {
      await supabase
          .from('Order')
          .update({'OrderStatus': 3})
          .eq('OrderID', widget.orderId);

      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await supabase.from('Cart').delete().eq('ClientID', currentUserId);
      }
    } catch (error) {
      print('Error updating order status: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Оплата'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}