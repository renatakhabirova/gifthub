import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gifthub/pages/payment_webview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gifthub/themes/colors.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';


class CheckoutScreen extends StatefulWidget {
  final double totalCost;
  final List<Map<String, dynamic>> cartItems;

  const CheckoutScreen({
    Key? key,
    required this.totalCost,
    required this.cartItems,
  }) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  DateTime? _selectedDeliveryDate;
  String? selectedRecipientName;
  String? selectedRecipientId;

  List<Map<String, dynamic>> searchResults = [];
  bool isLoading = false;
  bool isOrderLoading = false;

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    try {
      setState(() => isLoading = true);
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase
          .from('clientpublicview')
          .select('ClientID, ClientName, ClientSurName, ClientDisplayname')
          .ilike('ClientDisplayname', '%$query%')
          .neq('ClientID', currentUserId)
          .limit(20);

      setState(() {
        searchResults = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (error) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при поиске пользователей: $error')),
      );
    }
  }

  void selectRecipient(Map<String, dynamic> recipient) {
    setState(() {
      selectedRecipientId = recipient['ClientID'];
      selectedRecipientName = recipient['ClientDisplayname'] ??
          '${recipient['ClientName']} ${recipient['ClientSurName']}';
    });
  }

  Future<Map<String, dynamic>?> fetchRecipientAddress(String recipientId) async {
    try {
      final response = await supabase
          .from('clientpublicview')
          .select('ClientStreet, ClientHouse, ClientApartment, ClientCity')
          .eq('ClientID', recipientId)
          .maybeSingle();

      print('Response from supabase: $response');

      if (response == null) {
        return null;
      }

      final street = response['ClientStreet']?.toString().trim();
      final house = response['ClientHouse']?.toString().trim();
      final apartment = response['ClientApartment'];
      final city = response['ClientCity'];

      print('Fetched address data: Street=$street, House=$house, Apartment=$apartment, City=$city');

      if ((street?.isNotEmpty ?? false) &&
          (house?.isNotEmpty ?? false)) {
        return response;
      }

      return null;
    } catch (error) {
      print('Error fetching address: $error');
      return null;
    }
  }

  Future<void> sendAddressRequestNotification(String recipientId) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final senderInfo = await supabase
          .from('clientpublicview')
          .select('ClientDisplayname, ClientName, ClientSurName')
          .eq('ClientID', currentUserId)
          .single();

      final senderName = senderInfo['ClientDisplayname'] ??
          '${senderInfo['ClientName']} ${senderInfo['ClientSurName']}';

      await supabase.from('Notification').insert({
        'RecipientID': recipientId,
        'SenderID': currentUserId,
        'Message': 'Пользователь $senderName хочет отправить вам подарок! Пожалуйста, укажите адрес доставки в настройках профиля.',
        'Type': 'address_request',
        'CreatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при отправке уведомления: $error'),
        ),
      );
    }
  }


  Future<String?> createTemporaryOrder() async {
    try {
      setState(() => isOrderLoading = true);

      // Проверка выбранного получателя
      if (selectedRecipientId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выберите получателя')),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      // Получение ID текущего пользователя
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        setState(() => isOrderLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: пользователь не авторизован')),
        );
        return null;
      }

      // Проверка выбранной даты доставки
      if (_selectedDeliveryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выберите дату доставки')),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      // Проверка адреса получателя
      final recipientAddress = await fetchRecipientAddress(selectedRecipientId!);
      if (recipientAddress == null) {
        await sendAddressRequestNotification(selectedRecipientId!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Адрес получателя не указан. Уведомление отправлено.'),
          ),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      // Создание временного заказа со статусом 1 (ожидает оплаты)
      final orderResponse = await supabase
          .from('Order')
          .insert({
        'OrderStatus': 1, // статус "ожидает оплаты"
        'OrderPlanDeliveryDate': _selectedDeliveryDate?.toIso8601String(),
        'OrderRecipient': selectedRecipientId,
        'OrderSender': currentUserId,
        'OrderSum': widget.totalCost,
        'OrderCity': recipientAddress['ClientCity'],
        'OrderStreet': recipientAddress['ClientStreet'],
        'OrderHouse': recipientAddress['ClientHouse'],
        'OrderApartment': recipientAddress['ClientApartment'],
      })
          .select()
          .single();

      final orderId = orderResponse['OrderID'].toString();

      // Добавление товаров в заказ
      for (var item in widget.cartItems) {
        await supabase.from('OrderProduct').insert({
          'OrderProduct': item['Product']['ProductID'],
          'OrderID': orderId,
          'OrderProductQuantity': item['Quantity'],
          'OrderProductParametr': item['Parametr']?['ParametrID'],
        });
      }

      return orderId;
    } catch (error) {
      setState(() => isOrderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при создании заказа: $error'),
        ),
      );
      return null;
    }
  }


  Future<void> handleSuccessfulPayment(String orderId) async {
    try {
      // Обновляем статус заказа через RPC
      final response = await supabase
          .rpc('update_order_status',
          params: {
            'p_order_id': int.parse(orderId),
            'p_status': 3
          }
      );

      if (response == null) {
        throw Exception('Не удалось обновить статус заказа');
      }

      // Очистка корзины
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await supabase.from('Cart').delete().eq('ClientID', currentUserId);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заказ успешно оплачен!'),
        ),
      );
    } catch (error) {
      print('Error updating order status: $error'); // Добавляем логирование
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при обновлении статуса заказа: $error'),
          backgroundColor: wishListIcon,
        ),
      );
    }
  }


  Future<void> processPayment() async {

    if (kIsWeb || (Platform.isWindows)) {

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Оплата недоступна'),
          content: Text('Оплата доступна только на мобильных устройствах Android.'),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: Text('OK'),
            )
          ],
        ),
      );
      return;
    }

    final orderId = await createTemporaryOrder();
    if (orderId == null) return;

    try {
      // Создание платежа
      final paymentUrl = await createYooKassaPayment(widget.totalCost, orderId);
      setState(() => isOrderLoading = false);

      if (paymentUrl != null) {
        // Переход на экран оплаты с передачей orderId
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentWebViewScreen(
              paymentUrl: paymentUrl,
              orderId: orderId,
            ),
          ),
        );

        // Проверяем результат оплаты
        if (result == true) {
          // Успешная оплата, возвращаемся на главный экран
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // Оплата не удалась или была отменена
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Оплата не была завершена'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при создании платежа в Юкассе'),
          ),
        );
      }
    } catch (error) {
      setState(() => isOrderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при обработке платежа: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Оформление заказа'),
        backgroundColor: backgroundBeige,
        foregroundColor: darkGreen,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Товары:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkGreen,
              ),
            ),
            SizedBox(height: 10),
            Container(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.cartItems.length,
                itemBuilder: (context, index) {
                  final item = widget.cartItems[index];
                  final product = item['Product'];
                  final imageUrl = product['ProductPhoto']?.isNotEmpty ?? false
                      ? product['ProductPhoto'][0]['Photo']
                      : 'https://picsum.photos/200/300';

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              imageUrl,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[200],
                                    child: Icon(Icons.image_not_supported),
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item['Quantity']}x',
                              style:
                              TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(height: 30),
            Text(
              'Поиск получателя:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: darkGreen,
              ),
            ),
            SizedBox(height: 10),
            TextField(
              onChanged: (query) => searchUsers(query),
              decoration: InputDecoration(
                hintText: 'Введите никнейм',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            SizedBox(height: 10),
            if (isLoading)
              Center(child: CircularProgressIndicator(color: darkGreen))
            else if (searchResults.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final recipient = searchResults[index];
                    final displayName =
                        recipient['ClientDisplayname'] ?? 'Без имени';
                    final fullName =
                        '${recipient['ClientName']} ${recipient['ClientSurName']}';

                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: darkGreen,
                          ),
                        ),
                        subtitle: Text(fullName),
                        onTap: () => selectRecipient(recipient),
                        tileColor: selectedRecipientId == recipient['ClientID']
                            ? Colors.green.withOpacity(0.1)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (selectedRecipientName != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Выбранный получатель: $selectedRecipientName',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: darkGreen,
                  ),
                ),
              ),
            Spacer(),
            Text(
              'Выберите дату и время доставки:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: darkGreen,
              ),
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final selectedDate = await showDatePicker(
                        context: context,

                        initialDate: DateTime.now().add(Duration(days: 1)),
                        firstDate: DateTime.now().add(Duration(days: 1)),
                        lastDate: DateTime.now().add(Duration(days: 30)),
                      );
                      if (selectedDate != null) {
                        final selectedTime = await showTimePicker(
                          context: context,

                          initialTime: TimeOfDay.now(),
                          builder: (BuildContext context, Widget? child) {
                            return MediaQuery(
                                data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                child: child ?? Container()
                            );
                          },
                        );
                        if (selectedTime != null) {
                          setState(() {
                            _selectedDeliveryDate = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              selectedTime.hour,
                              selectedTime.minute,
                            ).toUtc();
                          });
                        }
                      }
                    },
                    child: Text(
                      _selectedDeliveryDate == null
                          ? 'Выбрать дату и время'
                          : 'Выбрано: ${_selectedDeliveryDate!.toLocal()}',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Container(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isOrderLoading
                    ? null
                    : () {
                  if (selectedRecipientId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Выберите получателя')),
                    );
                    return;
                  }
                  processPayment();
                },
                child: isOrderLoading
                    ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Text(
                  'Оплатить ${widget.totalCost.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}