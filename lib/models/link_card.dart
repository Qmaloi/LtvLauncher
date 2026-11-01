class LinkCard {
  final int id;
  final int categoryId;
  String title;
  String imageUrl;
  String targetUrl;
  String description;
  int order;

  LinkCard({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.imageUrl,
    required this.targetUrl,
    this.description = '',
    this.order = 0,
  });

  factory LinkCard.fromRow(Map<String, dynamic> row) => LinkCard(
        id: row['id'] as int,
        categoryId: row['category_id'] as int,
        title: row['title'] as String? ?? '',
        imageUrl: row['image_url'] as String? ?? '',
        targetUrl: row['target_url'] as String? ?? '',
        description: row['description'] as String? ?? '',
        order: row['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'title': title,
        'imageUrl': imageUrl,
        'targetUrl': targetUrl,
        'description': description,
        'order': order,
      };
}
