import 'package:flutter/material.dart';
import 'package:get/get.dart';

const String kAppName = "Hikari Novel";

const String kLatestUrl = "https://api.github.com/repos/15dd/hikari_novel_flutter/releases/latest";

const Map<String, String> kHeader = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36",
  // 补齐浏览器会带的应用层请求头。CF 除了 TLS 指纹，也会看请求头像不像真
  // 浏览器；只带 UA + 三个 Sec-Fetch-* 太单薄，和 WebView 的请求差得远。
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
  "Upgrade-Insecure-Requests": "1",
  "Sec-Fetch-Site": "same-origin",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Dest": "document",
};

const int kStatusBarPadding = 30;

const double kSmallIconSize = 16.0;

final TextStyle kBaseTileTitleTextStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);

final TextStyle kBaseTileSubtitleTextStyle = TextStyle(fontSize: 13);

const double kCardBorderRadius = 6.0;

const EdgeInsets kCommentAndReplyCardPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);

final TextStyle kCommentAndReplyUsernameTextStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(Get.context!).colorScheme.primary);

const int kScrollReadMode = 1;

const int kPageReadMode = 2;
