import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gifthub/pages/payment_webview.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gifthub/themes/colors.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/payment_service.dart';

final client = Supabase.instance.client;
Future<void> markPromoAsUsed(String userId, int promoCodeId) async {
  await Supabase.instance.client
      .from('ClientPromoCode')
      .update({
    'IsUsed': true,
    'UsedAt': DateTime.now().toUtc().toIso8601String(),
  })
      .eq('ClientID', userId)
      .eq('PromoCodeID', promoCodeId);
}
class CheckoutScreen extends StatefulWidget {
  final double totalCost;
  final List<Map<String, dynamic>> cartItems;
  final String? promoCode;
  const CheckoutScreen({
    Key? key,
    required this.totalCost,
    required this.cartItems,
    this.promoCode,
  }) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  DateTime? _selectedDeliveryDate;
  String? street;
  String? house;
  String? apartment;
  int? selectedCityId;
  bool isLoading = false;
  bool isOrderLoading = false;
  List<Map<String, dynamic>> cities = [];

  Future<void> loadCities() async {
    try {
      final response = await client.from('City').select('CityID, City');
      setState(() {
        cities = List<Map<String, dynamic>>.from(response);
        if (cities.isNotEmpty) {
          selectedCityId = cities[0]['CityID'];
        }
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке городов: $error')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadCities();
    initializeDateFormatting();
    _markPromoIfNeeded();
  }
  void _markPromoIfNeeded() async {
    if (widget.promoCode != null && widget.promoCode!.isNotEmpty) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final promoCodeId = await getPromoCodeIdByCode(widget.promoCode!);
      if (userId != null && promoCodeId != null) {
        await markPromoAsUsed(userId, promoCodeId);
      }
    }
  }
  Future<int?> getPromoCodeIdByCode(String code) async {
    final promo = await Supabase.instance.client
        .from('PromoCode')
        .select('PromoCodeID')
        .eq('Code', code)
        .maybeSingle();
    return promo?['PromoCodeID'] as int?;
  }
  Future<String?> createTemporaryOrder() async {
    try {
      setState(() => isOrderLoading = true);

      // Проверка выбранного города
      if (selectedCityId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выберите город')),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      // Проверка улицы и дома
      if ((street?.trim().isEmpty ?? true) || (house?.trim().isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Заполните улицу и дом')),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      // Проверка даты доставки
      if (_selectedDeliveryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выберите дату доставки')),
        );
        setState(() => isOrderLoading = false);
        return null;
      }

      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) return null;

      // Создание временного заказа
      final orderResponse = await client
          .from('Order')
          .insert({
        'OrderStatus': 1,
        'OrderPlanDeliveryDate': _selectedDeliveryDate?.toIso8601String(),
        'OrderRecipient': currentUserId,
        'OrderSender': currentUserId,
        'OrderSum': widget.totalCost,
        'OrderCity': selectedCityId,
        'OrderStreet': street,
        'OrderHouse': house,
        'OrderApartment': apartment,
      })
          .select()
          .single();

      final orderId = orderResponse['OrderID'].toString();

      // Добавление товаров в OrderProduct
      for (var item in widget.cartItems) {
        await client.from('OrderProduct').insert({
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
        SnackBar(content: Text('Ошибка при создании заказа: $error')),
      );
      return null;
    }
  }

  Future<void> handleSuccessfulPayment(String orderId) async {
    try {
      // Обновляем статус заказа на "оплачен" (предположим, что ID статуса = 3)
      final result = await client
          .from('Order')
          .update({'OrderStatus': 3})
          .eq('OrderID', orderId)
          .select()
          .single();

      print('Результат обновления: $result');

      // Получаем ID текущего пользователя
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId != null) {
        // Очищаем корзину
        await client.from('Cart').delete().eq('ClientID', currentUserId);


        await client.from('Notification').insert({
          'RecipientID': currentUserId,
          'SenderID': currentUserId,
          'Message': 'Ваш заказ №$orderId успешно оплачен!',
          'Type': 'order_paid',
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заказ успешно оплачен!')),
      );

      Navigator.pushNamed(
          context,
          '/main'
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при обновлении статуса заказа: $error'),
        ),
      );
    }
  }

  Future<void> processPayment() async {
    if (kIsWeb || Platform.isWindows) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Оплата недоступна'),
          content:
          Text('Оплата доступна только на мобильных устройствах Android.'),
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
      final paymentUrl =
      await createYooKassaPayment(widget.totalCost, orderId);
      setState(() => isOrderLoading = false);

      if (paymentUrl != null) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentWebViewScreen(
              paymentUrl: paymentUrl,
              orderId: orderId,
            ),
          ),
        );

        if (result == true) {
          await handleSuccessfulPayment(orderId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Оплата не была завершена')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при создании платежа в Юкассе')),
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
    body: SafeArea(
    child: LayoutBuilder(
    builder: (context, constraints) {
    return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
    constraints: BoxConstraints(minHeight: constraints.maxHeight),
    child: IntrinsicHeight(
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
                  final imageUrl = product['ProductPhoto']?.isNotEmpty == true
                      ? product['ProductPhoto'][0]['Photo']
                      : 'https://ivelkowygsgeutmxhdwd.supabase.co/storage/v1/object/public/PhotoProduct//no_product_photo.png ';

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(
                          imageUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.image_not_supported),
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
                              style: TextStyle(color: Colors.white, fontSize: 12),
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
              'Выберите город:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (cities.isNotEmpty)
              DropdownButtonFormField<int>(
                value: selectedCityId,
                items: cities.map((city) {
                  return DropdownMenuItem<int>(
                    value: city['CityID'],
                    child: Text(city['City']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedCityId = value;
                  });
                },
                decoration: InputDecoration(border: OutlineInputBorder()),
                dropdownColor: lightGrey,
                style: TextStyle(
                  color: darkGreen,
                  fontFamily: 'segoeui',
                  fontSize: 16,
                ),
              ),

            SizedBox(height: 10),

            TextField(
              onChanged: (value) => street = value,
              decoration: InputDecoration(labelText: 'Улица'),
            ),

            SizedBox(height: 10),

            TextField(
              onChanged: (value) => house = value,
              decoration: InputDecoration(labelText: 'Дом'),
            ),

            SizedBox(height: 10),

            TextField(
              onChanged: (value) => apartment = value,
              decoration:
              InputDecoration(labelText: 'Квартира (необязательно)'),
            ),

            SizedBox(height: 20),

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
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child ?? SizedBox.shrink(),
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
                          : 'Выбрано: ${DateFormat('d MMMM y, HH:mm', 'ru').format(_selectedDeliveryDate!.toLocal())}',
                    ),

                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Container(

              width: double.infinity,
              child: ElevatedButton(
                onPressed: isOrderLoading ? null : processPayment,
                child: isOrderLoading
                    ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                )
                    : Text(
                  'Оплатить ${widget.totalCost.toStringAsFixed(2)} ₽',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                )),
    ),

    ],
    ),
    ),
    ),
    );
    },
    ),
    ),
    resizeToAvoidBottomInset: true
    );}}