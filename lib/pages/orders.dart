import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

final client = Supabase.instance.client;

class OrderPage extends StatefulWidget {
  @override
  _OrderPageState createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> sentOrders = [];
  List<Map<String, dynamic>> receivedOrders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    setState(() => isLoading = true);
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      // Fetch отправленные заказы
      final sentRes = await client
          .from('Order')
          .select('''
            *,
            OrderStatus (StatusName),
            OrderRecipient:clientpublicview!Order_OrderRecipient_fkey (
              ClientName, 
              ClientSurName
            ),
            OrderProduct (
              OrderProduct (
                ProductID,
                ProductPhoto (Photo)
              )
            )
          ''')
          .eq('OrderSender', user.id)
          .order('OrderCreateDate', ascending: false);

      // Fetch полученные заказы
      final receivedRes = await client
          .from('Order')
          .select('''
            *,
            OrderStatus (StatusName),
            OrderSender:clientpublicview!Order_OrderSender_fkey (
              ClientName, 
              ClientSurName
            )
          ''')
          .eq('OrderRecipient', user.id)
          .order('OrderCreateDate', ascending: false);

      setState(() {
        sentOrders = List<Map<String, dynamic>>.from(sentRes as List);
        receivedOrders = List<Map<String, dynamic>>.from(receivedRes as List);
        isLoading = false;
      });
    } catch (e) {
      print('Ошибка при получении заказов: $e');
      setState(() => isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Дата не указана';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd.MM.yyyy HH:mm').format(date);
    } catch (e) {
      return 'Некорректная дата';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'оплачен':
        return Colors.blue;
      case 'отменен':
        return Colors.orange;
      case 'в пути':
        return Colors.purple;
      case 'выполнен':
        return Colors.green;
      case 'получен':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget buildSentOrderCard(Map<String, dynamic> order) {

    final statusName = order['OrderStatus']?['StatusName'] ?? 'Статус неизвестен';
    final recipient = order['OrderRecipient'];
    final recipientName = recipient != null
        ? '${recipient['ClientName']} ${recipient['ClientSurName']}'
        : 'Получатель не найден';

    final List<dynamic> products = order['OrderProduct'] ?? [];

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('№ ${order['OrderID']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(statusName).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getStatusColor(statusName), width: 1),
                ),
                child: Text(
                  statusName,
                  style: TextStyle(color: _getStatusColor(statusName), fontWeight: FontWeight.w500),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.person, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Кому: $recipientName', style: const TextStyle(fontSize: 16))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 16),
              const SizedBox(width: 8),
              ]),
            const SizedBox(height: 12),

            // Прокручиваемая строка с изображениями товаров
            if (products.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final photoUrl = product['OrderProduct']?['ProductPhoto']?[0]?['Photo'];

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: photoUrl ?? 'https://ivelkowygsgeutmxhdwd.supabase.co/storage/v1/object/public/PhotoProduct//no_product_photo.png ',
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const CircularProgressIndicator(),
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const Text('Нет товаров в заказе', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget buildReceivedOrderCard(Map<String, dynamic> order) {
    final statusName = order['OrderStatus']?['StatusName'] ?? 'Статус неизвестен';
    final sender = order['OrderSender'];
    final senderName = sender != null
        ? '${sender['ClientName']} ${sender['ClientSurName']}'
        : 'Отправитель не найден';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('№ ${order['OrderID']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                 ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(statusName).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getStatusColor(statusName), width: 1),
                ),
                child: Text(
                  statusName,
                  style: TextStyle(color: _getStatusColor(statusName), fontWeight: FontWeight.w500),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.person, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('От: $senderName', style: const TextStyle(fontSize: 16))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 16),
              const SizedBox(width: 8),
               ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заказы'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Отправленные'), Tab(text: 'Для меня')],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchOrders,
        child: TabBarView(
          controller: _tabController,
          children: [
            sentOrders.isEmpty
                ? Center(
              child: Text(
                'У вас пока нет отправленных заказов',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              itemCount: sentOrders.length,
              itemBuilder: (context, index) => buildSentOrderCard(sentOrders[index]),
            ),
            receivedOrders.isEmpty
                ? Center(
              child: Text(
                'Для вас пока нет заказов',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              itemCount: receivedOrders.length,
              itemBuilder: (context, index) => buildReceivedOrderCard(receivedOrders[index]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}