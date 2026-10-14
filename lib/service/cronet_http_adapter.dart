import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// 用一个 `package:http` 的 `Client`（这里是 Cronet）当 dio 的传输层。
///
/// **为什么需要它**：Cloudflare 是按**客户端指纹**区分请求的。真机实测
/// （2026-10-14）已经排除掉所有应用层因素——请求头补齐、cookie 新鲜
/// （当场解出的 cf_clearance）、等待、换连接——dio 依然 403 + challenge。
/// 剩下唯一的差异就是 TLS ClientHello / HTTP2 帧序列：`dart:io` 只讲
/// HTTP/1.1，握手参数也和 Chrome 不一样。
///
/// Cronet 是 Chrome 自己的网络栈，TLS 指纹、ALPN、HTTP/2 与 Chrome 一致，
/// 所以把它接到 dio 上换掉默认的 `IOHttpClientAdapter`。
class CronetDioAdapter implements HttpClientAdapter {
  CronetDioAdapter(this._client);

  final http.Client _client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = http.Request(options.method, options.uri)
      // dio 侧是 `followRedirects: false` + 手动跟 `location`，别让底层偷偷跟。
      ..followRedirects = options.followRedirects;

    options.headers.forEach((key, value) {
      if (value != null) request.headers[key] = value.toString();
    });

    if (requestStream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in requestStream) {
        builder.add(chunk);
      }
      request.bodyBytes = builder.takeBytes();
    }

    final streamed = await _client.send(request);
    final bytes = await streamed.stream.toBytes();

    return ResponseBody.fromBytes(
      bytes,
      streamed.statusCode,
      headers: streamed.headers.map((k, v) => MapEntry(k, [v])),
      statusMessage: streamed.reasonPhrase,
    );
  }

  @override
  void close({bool force = false}) {
    if (force) _client.close();
  }
}
