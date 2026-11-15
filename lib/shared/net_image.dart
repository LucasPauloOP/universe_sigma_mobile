import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// URLs de imagem da API são assinadas e expiram em 1h. A chave do cache ignora a
/// query string (X-Amz-*), então a URL renovada reaproveita o arquivo já baixado.
String imageCacheKey(String url) => url.split('?').first;

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.size = 48, this.radius = 8, this.fallback = Icons.image_outlined});

  final String? url;
  final double size;
  final double radius;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: scheme.surfaceContainerHighest,
          child: Icon(fallback, size: size * 0.5, color: scheme.outline),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url == null || url!.isEmpty)
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: url!,
              cacheKey: imageCacheKey(url!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
  }
}
