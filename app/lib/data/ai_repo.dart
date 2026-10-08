import '../core/supabase.dart';

/// Thin client for the `ai-assist` edge function. Only form inputs are sent —
/// never chat, diary or photos.
class AiRepo {
  static Future<Map<String, dynamic>> ask(String mode, Map<String, dynamic> input) async {
    final res = await sb.functions.invoke('ai-assist', body: {'mode': mode, 'input': input});
    final data = Map<String, dynamic>.from(res.data as Map);
    return Map<String, dynamic>.from(data['result'] as Map);
  }
}
