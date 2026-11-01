import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/link_cards_service.dart';

class LinkCardsRemotePanel extends StatelessWidget {
  final bool savedCategory;

  const LinkCardsRemotePanel({super.key, required this.savedCategory});

  @override
  Widget build(BuildContext context) {
    final url = context.select<LinkCardsService, String?>((service) => service.managementUrl);
    if (!savedCategory) {
      return _message(context, Icons.save_outlined, 'Сначала сохраните раздел, затем появится ссылка для телефона.');
    }
    if (url == null) {
      return _message(context, Icons.wifi_off, 'Телевизор пока не получил IP-адрес в локальной сети.');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Добавление с телефона', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Подключите телефон к той же Wi‑Fi сети, отсканируйте QR-код и добавляйте карточки через браузер.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: url, size: 180),
              ),
              const SizedBox(height: 8),
              SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );
}
