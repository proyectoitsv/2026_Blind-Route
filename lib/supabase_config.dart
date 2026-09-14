
class SupabaseConfig {
  /// URL del proyecto, del estilo `https://xxxxxxxx.supabase.co`.
  static const String url = 'https://nylnlrbzsahexzuipptz.supabase.co';

  /// Clave pública anónima (anon / publishable). Es segura para el
  /// cliente: el acceso real lo controlan las políticas RLS del server.
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im55bG5scmJ6c2FoZXh6dWlwcHR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1NzAwNjIsImV4cCI6MjEwMzE0NjA2Mn0.QXNC3j7b2tIgP9TvH8iCfMEgA3UoOB3jFvybUjPLW5I';

  /// Bucket de Storage donde viven las imágenes de los planos.
  static const String bucketImagenes = 'map-images';

  /// `true` sólo cuando url y anonKey ya fueron reemplazados por valores
  /// reales. Evita inicializar Supabase con los placeholders.
  static bool get configurado =>
      url.startsWith('https://') &&
      !url.contains('TU-PROYECTO') &&
      anonKey.length > 20 &&
      !anonKey.contains('TU-ANON-KEY');
}