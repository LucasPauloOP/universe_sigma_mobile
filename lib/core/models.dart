/// Registros da API são mapas JSON (o CRUD é genérico, dirigido por [Resource]).
typedef Entity = Map<String, dynamic>;

extension EntityX on Entity {
  String get id => this['id'] as String;
  String? str(String k) => this[k] as String?;
  num? numOf(String k) => this[k] as num?;
  Entity? obj(String k) => this[k] is Map ? Map<String, dynamic>.from(this[k] as Map) : null;
  List<Entity> list(String k) => (this[k] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

/// Resposta paginada das listas: {data,total,limit,offset}.
class Page {
  Page(this.data, this.total);
  final List<Entity> data;
  final int total;
}
