import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:gifthub/env_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentWebView extends StatefulWidget {
  final String url;
  final String returnUrl;
  final String orderId;

  const PaymentWebView({
    required this.url,
    required this.returnUrl,
    required this.orderId,
    Key? key,
  }) : super(key: key);

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  final SupabaseClient supabase = Supabase.instance.client;
  bool hasNavigatedBack = false;
  late final DateTime startTime;

  Future<void> _markOrderAsPaid(String orderId) async {
    try {
      await supabase.from('Order').update({
        'OrderStatus': 'Оплачен',
      }).eq('OrderID', orderId);
      debugPrint('Order $orderId marked as Оплачен');
    } catch (e) {
      debugPrint('Failed to update order status: $e');
    }
  }

  Future<void> _markOrderAsCanceled(String orderId) async {
    try {
      await supabase.from('Order').update({
        'OrderStatus': 'Отменен',
      }).eq('OrderID', orderId);
      debugPrint('Order $orderId marked as Отменен');
    } catch (e) {
      debugPrint('Failed to cancel order: $e');
    }
  }

  Future<void> _checkPaymentStatus(String orderId) async {
    final String basicAuth =
        'Basic ' + base64Encode(utf8.encode('$yookassaShopId:$yookassaSecretKey'));

    try {
      final response = await http.get(
        Uri.parse('https://api.yookassa.ru/v3/payments?limit=1&created_gte=  ${startTime.toIso8601String()}'),
        headers: {
          'Authorization': basicAuth,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List payments = data['items'];
        if (payments.isNotEmpty && payments.first['status'] == 'succeeded') {
          await _markOrderAsPaid(orderId);
        } else {
          await _markOrderAsCanceled(orderId);
        }
      } else {
        debugPrint('Failed to fetch payment status: ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception while checking payment status: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    startTime = DateTime.now();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!hasNavigatedBack && request.url.startsWith(widget.returnUrl)) {
              hasNavigatedBack = true;
              _markOrderAsPaid(widget.orderId);
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    if (!hasNavigatedBack) {
      _checkPaymentStatus(widget.orderId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Оплата')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

Future<void> launchYookassaPayment({
  required BuildContext context,
  required String url,
  required String orderId,
}) async {
  if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch payment URL';
    }
  } else if (Platform.isAndroid || Platform.isIOS) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentWebView(
          url: url,
          returnUrl: 'https://renatakhabirva.github.io/gifthub/  ',
          orderId: orderId,
        ),
      ),
    );
  }
}

Future<String?> createYooKassaPayment(double amount, String orderId) async {
  final String basicAuth =
      'Basic ' + base64Encode(utf8.encode('$yookassaShopId:$yookassaSecretKey'));

  final response = await http.post(
    Uri.parse('https://api.yookassa.ru/v3/payments  '),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': basicAuth,
      'Idempotence-Key': orderId,
    },
    body: jsonEncode({
      "amount": {
        "value": amount.toStringAsFixed(2),
        "currency": "RUB"
      },
      "confirmation": {
        "type": "redirect",
        "return_url": "https://renatakhabirva.github.io/gifthub/  "
      },
      "capture": true,
      "description": "Оплата заказа #$orderId"
    }),
  );

  if (response.statusCode == 200 || response.statusCode == 201) {
    final data = jsonDecode(response.body);
    return data['confirmation']['confirmation_url'];
  } else {
    debugPrint('YooKassa error: ${response.body}');
    return null;
  }
}