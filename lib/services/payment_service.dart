import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:gifthub/env_config.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String?> createYooKassaPayment(double totalCost, String orderId) async {
  if (kIsWeb) {
    // Для web используем прямое перенаправление на форму оплаты
    final String shopId = yookassaShopId;
    final returnUrl = 'https://renatakhabirova.github.io/gifthub/';

    // Создаем URL для формы оплаты
    final String paymentFormUrl = 'https://yookassa.ru/checkout/payments/v2/payment-form?' +
        'shop_id=$shopId' +
        '&amount=${totalCost.toStringAsFixed(2)}' +
        '&currency=RUB' +
        '&description=${Uri.encodeComponent("Оплата заказа #$orderId")}' +
        '&return_url=$returnUrl' +
        '&order_id=$orderId';

    return paymentFormUrl;
  } else {
    // Для мобильных устройств используем существующий API
    final String shopId = yookassaShopId;
    final String secretKey = yookassaSecretKey;
    final String paymentUrl = 'https://api.yookassa.ru/v3/payments';

    try {
      final Map<String, dynamic> paymentData = {
        "amount": {
          "value": totalCost.toStringAsFixed(2),
          "currency": "RUB"
        },
        "confirmation": {
          "type": "redirect",
          "return_url": 'https://renatakhabirova.github.io/gifthub/'
        },
        "capture": true,
        "description": "Оплата заказа #$orderId",
      };

      final response = await http.post(
        Uri.parse(paymentUrl),
        headers: {
          'Content-Type': 'application/json',
          'Idempotence-Key': DateTime.now().millisecondsSinceEpoch.toString(),
          'Authorization': 'Basic ${base64Encode(utf8.encode('$shopId:$secretKey'))}',
        },
        body: jsonEncode(paymentData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final String? confirmationUrl = responseData['confirmation']?['confirmation_url'];
        return confirmationUrl;
      } else {
        print('Ошибка при создании платежа: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (error) {
      print('Ошибка при отправке запроса в ЮKassa: $error');
      return null;
    }
  }
}