import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/locale_data.dart';
import '../../core/widgets/widgets.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  String? _country;
  String? _currency;
  bool _loaded = false;
  bool _saving = false;

  void _init(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.displayName;
    _bio.text = p.bio ?? '';
    _country = p.countryCode;
    _currency = p.currencyCode;
  }

  Future<void> _save(Profile p) async {
    if (_name.text.trim().isEmpty) return showToast(context, 'Your name can\'t be empty.');
    setState(() => _saving = true);
    try {
      await sb.from('profiles').update({
        'display_name': _name.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'country_code': _country,
        'currency_code': _currency,
      }).eq('id', p.id);
      if (mounted) showToast(context, 'Profile saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _photo(Profile p) async {
    final files = await MediaRepo.instance.pickPhotos(multiple: false, source: ImageSource.gallery);
    if (files.isEmpty || !mounted) return;
    await guard(context, () async {
      final path = await MediaRepo.instance.uploadAvatar(files.first);
      await sb.from('profiles').update({'avatar_path': path}).eq('id', p.id);
      ref.invalidate(partnerProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(myProfileProvider).valueOrNull;
    if (p == null) return const Scaffold(body: LoadingView());
    _init(p);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [TextButton(onPressed: _saving ? null : () => _save(p), child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Constrained(
          maxWidth: 520,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Stack(children: [
                LBAvatar(profile: p, size: 104, ring: true),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(tooltip: 'Change photo', onPressed: () => _photo(p), icon: const Icon(Icons.photo_camera_outlined)),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Only you and your partner can see your photo.')),
            const SizedBox(height: 20),
            TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: 'Display name')),
            const SizedBox(height: 8),
            TextField(controller: _bio, maxLength: 280, maxLines: 3, decoration: const InputDecoration(labelText: 'A little about you')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: countries.any((c) => c.$1 == _country) ? _country : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Country'),
              items: [for (final c in countries) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
              onChanged: (v) => setState(() {
                _country = v;
                _currency = currencyForCountry(v);
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: currencies.contains(_currency) ? _currency : null,
              decoration: const InputDecoration(labelText: 'Currency for prices'),
              items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _currency = v),
            ),
            const SizedBox(height: 14),
            Text('Email: ${sb.auth.currentUser?.email ?? ''}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
