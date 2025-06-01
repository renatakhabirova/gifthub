import 'package:supabase_flutter/supabase_flutter.dart';

class CityService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchUserCity() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final response = await supabase
          .from('Client')
          .select('ClientCity, City(City)')
          .eq('ClientID', user.id)
          .single();

      return {
        'userCityId': response['ClientCity'] as int?,
        'userCityName': response['City']?['City'] as String?,
      };
    } catch (error) {
      print('Ошибка при загрузке города пользователя: $error');
      return null;
    }
  }
}