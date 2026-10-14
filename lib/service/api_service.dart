import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui';

import 'package:cookie_jar/cookie_jar.dart' as ckjar;
import 'package:cronet_http/cronet_http.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:get/get.dart' hide Response;
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/common/extension.dart';
import 'package:hikari_novel_flutter/models/common/charset_type.dart';
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/custom_exception.dart';
import 'package:hikari_novel_flutter/models/resource.dart';

import '../common/log.dart';
import 'cronet_http_adapter.dart';
import 'local_storage_service.dart';

class ApiService extends GetxService {
  static ApiService get instance => Get.find<ApiService>();

  Wenku8Node get wenku8Node => LocalStorageService.instance.getWenku8Node();

  final _ApiClient _client = _ApiClient();

  Dio get dio => _client.dio;

  void initCookie() => _client.initCookie();

  void deleteCookie() => _client.deleteCookie();

  Language get _language => LocalStorageService.instance.getLanguage();

  CharsetType get charsetType {
    if (_language == Language.followSystem) {
      if (Get.deviceLocale == Locale("zh", "CN")) {
        return CharsetType.gbk;
      } else if (Get.deviceLocale == Locale("zh", "TW")) {
        return CharsetType.big5Hkscs;
      } else {
        return CharsetType.gbk;
      }
    }
    return switch (_language) {
      Language.simplifiedChinese => CharsetType.gbk,
      Language.traditionalChinese => CharsetType.big5Hkscs,
      _ => CharsetType.gbk,
    };
  }

  /// 根据排名获取小说列表
  /// - [ranking] 排行榜种类
  /// - [index] 第几页
  Future<Resource> getNovelByRanking({required String ranking, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/toplist.php?sort=$ranking&page=$index";
    return _client.get(url, charsetType: charsetType);
  }

  /// 根据分类获取小说列表
  /// - [category] 小说的分类，即tag
  /// - [sort] 按什么排序
  /// - [index] 第几页
  Future<Resource> getNovelByCategory({required String category, required String sort, required int index}) {
    switch (charsetType) {
      case CharsetType.gbk:
        {
          category = GbkCodec().encode(category).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join().trim();
        }
      case CharsetType.big5Hkscs:
        {
          category = Big5Codec().encode(category).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join().trim();
        }
    }
    String url = "${wenku8Node.node}/modules/article/tags.php?t=$category&v=$sort&page=$index";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取小说信息
  /// - [aid] 小说的id
  Future<Resource> getNovelDetail({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/articleinfo.php?id=$aid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取小说的章节目录
  /// - [aid] 小说的id
  Future<Resource> getCatalogue({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/reader.php?aid=$aid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 加入书库
  /// - [aid] 小说的id
  Future<Resource> addNovel({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/addbookcase.php?bid=$aid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 移出书库
  /// - [delid] 该书在书架中的id，即bid
  Future<Resource> removeNovel({required String delid}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php?delid=$delid";
    // 带 charset 会被 CF WAF 硬 403（无 cf-mitigated），详见 get() 的注释。
    return _client.get(url, charsetType: charsetType, appendCharset: false);
  }

  /// 从列表移出书库
  /// - [list] 要删除的书籍列表
  /// - [classId] 要将这些书从哪个书架中删除
  Future<Resource> removeNovelFromList({required List<String> list, required int classId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php";
    final Map<String, dynamic> params = {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": -1, "classid": classId};
    return _client.postForm(url, data: params, charsetType: charsetType);
  }

  /// 移动到其它书架
  /// - [list] 要移动的书籍列表
  /// - [classId] 要将这些书从哪个书架中移出
  /// - [newClassId] 要将这些书移动到那个书架中
  Future<Resource> moveNovelToOther({required List<String> list, required int classId, required int newClassId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php";
    final Map<String, dynamic> params = {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": newClassId, "classid": classId};
    return _client.postForm(url, data: params, charsetType: charsetType);
  }

  /// 获取书架
  /// - [classId] 要获取的书架编号
  Future<Resource> getBookshelf({required int classId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php?classid=$classId";
    // 带 charset 会被 CF WAF 硬 403（无 cf-mitigated），详见 get() 的注释（书架）。
    return _client.get(url, charsetType: charsetType, appendCharset: false);
  }

  /// 获取其它用户收藏的书籍
  /// - [uid] 该用户的id
  Future<Resource> getBookshelfFromUser({required String uid}) {
    final String url = "${wenku8Node.node}/userpage.php?uid=$uid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取评论区
  /// - [aid] 该评论区所属的书籍的id
  /// - [index] 第几页
  Future<Resource> getComment({required String aid, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/reviews.php?aid=$aid&page=$index";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取回复
  /// - [rid] 该回复的id
  /// - [index] 第几页
  Future<Resource> getReply({required String rid, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/reviewshow.php?rid=$rid&page=$index";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取推荐页
  Future<Resource> getRecommend() {
    final String url = "${wenku8Node.node}/index.php";
    return _client.get(url, charsetType: charsetType);
  }

  /// 为小说投票
  /// - [aid] 被投票的小说的id
  Future<Resource> novelVote({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/uservote.php?id=$aid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 根据标题搜索小说
  /// - [title] 标题关键字
  /// - [index] 第几页
  Future<Resource> searchNovelByTitle({required String title, required int index}) {
    switch (charsetType) {
      //url编码
      case CharsetType.gbk:
        title = GbkEncoder().convert(title).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
      case CharsetType.big5Hkscs:
        title = Big5Encoder().convert(title).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
    }
    final String url = "${wenku8Node.node}/modules/article/search.php?searchtype=articlename&searchkey=$title&page=$index";
    // 带 charset 会被 CF WAF 硬 403（无 cf-mitigated），详见 get() 的注释。
    return _client.get(url, charsetType: charsetType, appendCharset: false);
  }

  /// 根据作者搜索小说
  /// - [author] 作者关键字
  /// - [index] 第几页
  Future<Resource> searchNovelByAuthor({required String author, required int index}) {
    switch (charsetType) {
      //url编码
      case CharsetType.gbk:
        author = GbkEncoder().convert(author).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
      case CharsetType.big5Hkscs:
        author = Big5Encoder().convert(author).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
    }
    final String url = "${wenku8Node.node}/modules/article/search.php?searchtype=author&searchkey=$author&page=$index";
    // 带 charset 会被 CF WAF 硬 403（无 cf-mitigated），详见 get() 的注释。
    return _client.get(url, charsetType: charsetType, appendCharset: false);
  }

  /// 获取用户信息
  Future<Resource> getUserInfo() {
    final String url = "${wenku8Node.node}/userdetail.php";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取已完结小说的列表
  /// - [index] 第几页
  Future<Resource> getCompletionNovel({required int index}) {
    final String url = "${wenku8Node.node}/modules/article/articlelist.php?fullflag=1&page=$index";
    return _client.get(url, charsetType: charsetType);
  }

  /// 发表书评
  /// - [aid] 书号
  /// - [title] 书评的标题
  /// - [content] 书评的内容
  Future<Resource> sendComment({required String aid, required String title, required String content}) {
    final String url = "${wenku8Node.node}/modules/article/reviews.php?aid=$aid";

    String submit;
    switch (charsetType) {
      case CharsetType.gbk:
        submit = GbkEncoder().convert("发表书评").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        title = title.gbkUrlEncodingIfNotAscii();
        content = content.gbkUrlEncodingIfNotAscii();
      case CharsetType.big5Hkscs:
        submit = Big5Encoder().convert("發表書評").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        title = title.big5UrlEncodingIfNotAscii();
        content = content.big5UrlEncodingIfNotAscii();
    }
    //加上url编码的空格，即"+"
    submit = "+$submit+";

    final String params = "ptitle=$title&pcontent=$content&Submit=$submit";
    return _client.postForm(url, data: params, charsetType: charsetType);
  }

  /// 发表回复
  /// - [aid] 书号
  /// - [rid] 要回复的书评id
  /// - [content] 回复的内容
  Future<Resource> sendReply({required String aid, required String rid, required String content}) {
    final String url = "${wenku8Node.node}/modules/article/reviewshow.php?rid=$rid&aid=$aid";

    String submit;
    switch (charsetType) {
      case CharsetType.gbk:
        submit = GbkEncoder().convert("发表书评").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        content = content.gbkUrlEncodingIfNotAscii();
      case CharsetType.big5Hkscs:
        submit = Big5Encoder().convert("發表書評").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        content = content.big5UrlEncodingIfNotAscii();
    }
    //加上url编码的空格，即"+"
    submit = "+$submit+";

    final String params = "pcontent=$content&Submit=$submit";

    return _client.postForm(url, data: params, charsetType: charsetType);
  }

  /// 获取小说章节内容
  /// - [aid] 小说id
  /// - [cid] 章节id
  Future<Resource> getNovelContent({required String aid, required String cid}) {
    final String url = "${wenku8Node.node}/modules/article/reader.php?aid=$aid&cid=$cid";
    return _client.get(url, charsetType: charsetType);
  }

  /// 获取Github上面的最新版本
  Future<Resource> fetchLatestRelease() {
    return _client.getCommonData(kLatestUrl);
  }
}

class _ApiClient {
  final ckjar.CookieJar _cookieJar = ckjar.CookieJar();

  late final Dio dio = _createDio();

  Dio _createDio() {
    final client =
        Dio(BaseOptions(headers: {...kHeader, "Referer": "${LocalStorageService.instance.getWenku8Node().node}/index.php"}, responseType: ResponseType.bytes, followRedirects: false, validateStatus: (status) => status != null))
          ..interceptors.add(_CloudflareInterceptor())
          ..interceptors.add(CookieManager(_cookieJar));
    _enableCronet(client);
    return client;
  }

  /// 把 dio 的传输层换成 Cronet（Chrome 自己的网络栈）。
  ///
  /// CF 是按客户端 TLS 指纹决定挑不挑战的：dart:io 会被一律 403 + challenge，
  /// 而 cf_clearance 跨客户端不通用（实测 2026-10-14：带着当场解出的新鲜凭证
  /// 照样被拒，请求头/cookie/时机/连接都排除过了）。换成 Cronet 后 challenge 归零。
  /// 失败就安静回退 dart:io，不影响其它平台。
  void _enableCronet(Dio client) {
    if (!Platform.isAndroid) return;
    try {
      final engine = CronetEngine.build(
        cacheMode: CacheMode.memory,
        cacheMaxSize: 8 * 1024 * 1024,
        userAgent: kHeader['User-Agent']!,
      );
      // CronetClient 会持有 engine，GC 不会把它回收掉。
      client.httpClientAdapter = CronetDioAdapter(CronetClient.fromCronetEngine(engine));
      Log.d('[CF] Cronet 已启用为 dio 传输层');
    } catch (e) {
      Log.w('[CF] Cronet 启用失败，回退 dart:io：$e');
    }
  }

  void initCookie() {
    final localCookie = LocalStorageService.instance.getCookie();
    if (localCookie == null) return;

    // 值里可能带 , ; 等 dart:io Cookie 不接受的字符（如 Hm_lvt_xxx=1,2）；
    // 逐条解析、跳过坏值——它在调用方的 try 之外，抛出来会打断登录流程。
    final cookies = <ckjar.Cookie>[];
    for (final e in localCookie.split(';')) {
      final i = e.indexOf('=');
      if (i <= 0) continue;
      try {
        cookies.add(ckjar.Cookie(e.substring(0, i).trim(), e.substring(i + 1).trim()));
      } catch (_) {}
    }

    _cookieJar.saveFromResponse(Uri.parse(Wenku8Node.wwwWenku8Cc.node), cookies);
    _cookieJar.saveFromResponse(Uri.parse(Wenku8Node.wwwWenku8Net.node), cookies);
  }

  void deleteCookie() => _cookieJar.deleteAll();

  Future<Resource> getCommonData(String url) async {
    try {
      final response = await Dio(BaseOptions(headers: kHeader)).get(url);
      return Success(response.data);
    } catch (e) {
      return Error(e.toString());
    }
  }

  /// [appendCharset] 为 false 时不附加 `charset` 参数。
  ///
  /// `bookcase.php` 与 `search.php` 带上该参数会被 Cloudflare WAF 直接 403
  /// （403 且无 `cf-mitigated`，即硬拒绝而非挑战；去掉参数则正常返回）。
  /// 这是请求特征判定，换传输层也救不了，只能不发这个参数。
  /// 响应编码不受影响：站点默认就是 GBK/Big5。
  Future<Resource> get(String url, {required CharsetType charsetType, bool appendCharset = true}) async {
    try {
      if (appendCharset) {
        if (!url.contains("?")) url += "?";
        switch (charsetType) {
          case CharsetType.gbk:
            url += "&charset=gbk";
          case CharsetType.big5Hkscs:
            url += "&charset=big5";
        }
      }

      Log.d("$url ${charsetType.name}");
      final response = await dio.get(url);
      final raw = await _checkRedirects(response) as Uint8List;
      late String decodedHtml;
      switch (charsetType) {
        case CharsetType.gbk:
          decodedHtml = GbkDecoder().convert(raw);
        case CharsetType.big5Hkscs:
          decodedHtml = Big5Decoder().convert(raw);
      }
      return Success(decodedHtml);
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }

  Future<dynamic> _checkRedirects(Response response) async {
    if (response.statusCode != null && response.statusCode! >= 300 && response.statusCode! < 400) {
      final location = response.headers.value('location');
      if (location != null) {
        // location 可能是绝对地址，按请求 URL 解析，避免拼成 "https://node/http://other/..."。
        final redirectedResponse = await dio.get(response.requestOptions.uri.resolve(location).toString());
        return redirectedResponse.data;
      }
    }
    return response.data;
  }

  Future<Resource> postForm(String url, {required Object? data, required CharsetType charsetType}) async {
    try {
      final response = await dio.post(
        url,
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      String decodedHtml;
      switch (charsetType) {
        case CharsetType.gbk:
          decodedHtml = GbkCodec().decode(response.data as Uint8List);
        case CharsetType.big5Hkscs:
          decodedHtml = Big5Codec().decode(response.data as Uint8List);
      }
      return Success(decodedHtml);
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }
}

class _CloudflareInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final statusCode = response.statusCode;
    if (statusCode == 403) {
      handler.reject(Cloudflare403Exception(requestOptions: response.requestOptions));
      return;
    }

    final cfMitigated = response.headers['cf-mitigated'];
    if (cfMitigated == null || !cfMitigated.contains('challenge')) {
      handler.next(response);
      return;
    }
    handler.reject(CloudflareChallengeException(requestOptions: response.requestOptions));
  }
}
