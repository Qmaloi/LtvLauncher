import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../database.dart';
import '../models/category.dart';
import '../models/link_card.dart';

class LinkCardsService extends ChangeNotifier {
  final FLauncherDatabase _database;
  final List<LinkCard> _cards = [];
  HttpServer? _server;
  String? _token;
  String? _managementUrl;
  Timer? _retryTimer;

  LinkCardsService(this._database) {
    _init();
  }

  List<LinkCard> get cards => List.unmodifiable(_cards);
  String? get managementUrl => _managementUrl;
  bool get isRunning => _server != null && _managementUrl != null;

  List<LinkCard> cardsForCategory(int categoryId) => _cards
      .where((card) => card.categoryId == categoryId)
      .toList(growable: false);

  Future<void> _init() async {
    try {
      await _database.ensureLinkCardsTable();
      await reload();
      await _startServer();
    } catch (error, stackTrace) {
      debugPrint('Link cards initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> reload() async {
    final rows = await _database.getLinkCards();
    _cards
      ..clear()
      ..addAll(rows.map(LinkCard.fromRow));
    _cards.sort((a, b) => a.order == b.order
        ? a.id.compareTo(b.id)
        : a.order.compareTo(b.order));
    notifyListeners();
  }

  Future<int> addCard({
    required int categoryId,
    required String title,
    required String imageUrl,
    required String targetUrl,
    String description = '',
    int? order,
  }) async {
    final id = await _database.insertLinkCard(
      categoryId: categoryId,
      title: title,
      imageUrl: imageUrl,
      targetUrl: targetUrl,
      description: description,
      order: order ?? _nextOrder(categoryId),
    );
    await reload();
    return id;
  }

  Future<void> updateCard({
    required int id,
    required int categoryId,
    required String title,
    required String imageUrl,
    required String targetUrl,
    String description = '',
    int order = 0,
  }) async {
    await _database.updateLinkCard(
      id: id,
      categoryId: categoryId,
      title: title,
      imageUrl: imageUrl,
      targetUrl: targetUrl,
      description: description,
      order: order,
    );
    await reload();
  }

  Future<void> deleteCard(int id) async {
    await _database.deleteLinkCard(id);
    await reload();
  }

  int _nextOrder(int categoryId) {
    final categoryCards = cardsForCategory(categoryId);
    if (categoryCards.isEmpty) return 0;
    return categoryCards.map((card) => card.order).reduce(max) + 1;
  }

  Future<void> _startServer() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addresses = interfaces
        .expand((networkInterface) => networkInterface.addresses)
        .where((item) => !item.isLoopback)
        .toList();
    if (addresses.isEmpty) {
      _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
        if (isRunning) {
          _retryTimer?.cancel();
          _retryTimer = null;
        } else {
          await _startServer();
        }
      });
      return;
    }
    final address = addresses.firstWhere(
      (item) => item.address.startsWith('192.168.') || item.address.startsWith('10.') || item.address.startsWith('172.'),
      orElse: () => addresses.first,
    );
    _retryTimer?.cancel();
    _retryTimer = null;

    _token = base64Url
        .encode(List<int>.generate(18, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    _managementUrl = 'http://${address.address}:${_server!.port}/?token=$_token';
    _server!.listen(_handleRequest, onError: (error) {
      debugPrint('Link cards server error: $error');
    });
    notifyListeners();
  }

  bool _authorized(HttpRequest request) =>
      _token != null && request.uri.queryParameters['token'] == _token;

  Future<void> _handleRequest(HttpRequest request) async {
    if (!_authorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_mobilePage);
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && path == '/api/state') {
        await _writeJson(request.response, await _state());
        return;
      }
      if (request.method == 'POST' && path == '/api/cards') {
        final payload = await _readJson(request);
        final categoryId = _intValue(payload['categoryId']);
        final title = _stringValue(payload['title']).trim();
        final imageUrl = _stringValue(payload['imageUrl']).trim();
        final targetUrl = _stringValue(payload['targetUrl']).trim();
        final description = _stringValue(payload['description']).trim();
        await _validateCard(categoryId, title, imageUrl, targetUrl);
        final id = await addCard(
          categoryId: categoryId!,
          title: title,
          imageUrl: imageUrl,
          targetUrl: targetUrl,
          description: description,
          order: _intValue(payload['order']),
        );
        await _writeJson(request.response, {'ok': true, 'id': id}, status: 201);
        return;
      }

      final cardId = _cardIdFromPath(path);
      if (cardId != null && request.method == 'PUT') {
        final payload = await _readJson(request);
        final categoryId = _intValue(payload['categoryId']);
        final title = _stringValue(payload['title']).trim();
        final imageUrl = _stringValue(payload['imageUrl']).trim();
        final targetUrl = _stringValue(payload['targetUrl']).trim();
        await _validateCard(categoryId, title, imageUrl, targetUrl);
        await updateCard(
          id: cardId,
          categoryId: categoryId!,
          title: title,
          imageUrl: imageUrl,
          targetUrl: targetUrl,
          description: _stringValue(payload['description']).trim(),
          order: _intValue(payload['order']) ?? 0,
        );
        await _writeJson(request.response, {'ok': true});
        return;
      }
      if (cardId != null && request.method == 'DELETE') {
        await deleteCard(cardId);
        await _writeJson(request.response, {'ok': true});
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (error) {
      await _writeJson(request.response, {'ok': false, 'error': error.toString()},
          status: HttpStatus.badRequest);
    }
  }

  Future<Map<String, dynamic>> _state() async {
    final categories = await _database.getCategories();
    final linkCategories = categories
        .where((category) => category.type == CategoryType.links)
        .map((category) => {
              'id': category.id,
              'name': category.name,
              'cards': cardsForCategory(category.id).map((card) => card.toJson()).toList(),
            })
        .toList();
    return {'categories': linkCategories};
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await request.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw FormatException('Invalid JSON payload');
    return decoded.cast<String, dynamic>();
  }

  Future<void> _writeJson(HttpResponse response, Map<String, dynamic> data,
      {int status = HttpStatus.ok}) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> _validateCard(int? categoryId, String title, String imageUrl, String targetUrl) async {
    if (categoryId == null || title.isEmpty || title.length > 120) {
      throw FormatException('Category and title are required');
    }
    final categories = await _database.getCategories();
    if (!categories.any((category) => category.id == categoryId && category.type == CategoryType.links)) {
      throw FormatException('The selected category is not a Links section');
    }
    if (!_isWebUrl(targetUrl) || (imageUrl.isNotEmpty && !_isWebUrl(imageUrl))) {
      throw FormatException('Only http:// and https:// URLs are allowed');
    }
    if (imageUrl.length > 2048 || targetUrl.length > 2048) {
      throw FormatException('One of the URLs is too long');
    }
  }

  bool _isWebUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  int? _cardIdFromPath(String path) {
    final match = RegExp(r'^/api/cards/(\d+)$').firstMatch(path);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _intValue(dynamic value) => value is int ? value : int.tryParse('$value');
  String _stringValue(dynamic value) => value is String ? value : '';

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_server?.close(force: true));
    super.dispose();
  }

  static const String _mobilePage = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LTvLauncher links</title>
<style>
:root{color-scheme:dark;font-family:system-ui,-apple-system,sans-serif}body{max-width:760px;margin:auto;padding:18px;background:#0a0a0a;color:#f5f5f5}h1{font-size:1.45rem}form,.card{background:#171717;border:1px solid #303030;border-radius:14px;padding:14px;margin:12px 0}label{display:block;font-size:.82rem;color:#aaa;margin-top:10px}input,textarea,select,button{box-sizing:border-box;width:100%;padding:11px;border-radius:9px;border:1px solid #444;background:#0f0f0f;color:#fff;font:inherit}textarea{min-height:68px;resize:vertical}button{margin-top:14px;background:#635bff;border:0;font-weight:700}.card{display:grid;grid-template-columns:96px 1fr;gap:12px}.card img{width:96px;height:54px;object-fit:cover;border-radius:8px;background:#252525}.card button{background:#7f1d1d;margin-top:8px}.muted{color:#aaa;font-size:.85rem}.error{color:#ff8d8d;margin-top:10px}.ok{color:#8dffb0;margin-top:10px}
</style></head><body><h1>LTvLauncher · Link cards</h1><p class="muted">This page works only while your phone is on the same Wi‑Fi network as the TV.</p>
<form id="form"><label>Section<select id="category"></select></label><label>Title<input id="title" maxlength="120" required></label><label>Image URL<input id="imageUrl" type="url" placeholder="https://..."></label><label>Target URL<input id="targetUrl" type="url" required placeholder="https://..."></label><label>Description<input id="description" maxlength="240"></label><label>Order<input id="order" type="number" min="0" value="0"></label><button>Add card</button><div id="message"></div></form><section id="cards"></section>
<script>
const token=new URLSearchParams(location.search).get('token');const categoryInput=document.getElementById('category');const titleInput=document.getElementById('title');const imageUrlInput=document.getElementById('imageUrl');const targetUrlInput=document.getElementById('targetUrl');const descriptionInput=document.getElementById('description');const orderInput=document.getElementById('order');const api=(path,options={})=>{const join=path.includes('?')?'&':'?';return fetch(path+join+'token='+encodeURIComponent(token),options)};
const esc=s=>String(s??'');let state;
async function refresh(){const r=await api('/api/state');state=await r.json();const select=categoryInput;select.innerHTML='';state.categories.forEach(c=>{const o=document.createElement('option');o.value=c.id;o.textContent=c.name;select.appendChild(o)});const root=document.getElementById('cards');root.innerHTML='';state.categories.forEach(c=>c.cards.forEach(card=>{const el=document.createElement('article');el.className='card';const img=document.createElement('img');img.src=card.imageUrl;img.alt='';img.onerror=()=>img.style.visibility='hidden';const body=document.createElement('div');const title=document.createElement('strong');title.textContent=card.title;const url=document.createElement('div');url.className='muted';url.textContent=card.targetUrl;const del=document.createElement('button');del.textContent='Delete';del.onclick=async()=>{await api('/api/cards/'+card.id,{method:'DELETE'});refresh()};body.append(title,url,del);el.append(img,body);root.append(el)}))}
document.getElementById('form').onsubmit=async e=>{e.preventDefault();const message=document.getElementById('message');message.className='';message.textContent='Saving…';const payload={categoryId:Number(categoryInput.value),title:titleInput.value,imageUrl:imageUrlInput.value,targetUrl:targetUrlInput.value,description:descriptionInput.value,order:Number(orderInput.value||0)};const r=await api('/api/cards',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const data=await r.json();if(!data.ok){message.className='error';message.textContent=data.error||'Could not save';return}message.className='ok';message.textContent='Saved';e.target.reset();refresh()};refresh();
</script></body></html>''';
}
