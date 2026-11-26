
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl =
      'https://ozwflasypxvknwhhpavb.supabase.co';

  static const String supabasePublishableKey =
      'sb_publishable_eTuayPXgd00hnHSjYk1mgA_GvCAyS6N';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  static SupabaseClient get client =>
      Supabase.instance.client;
}
