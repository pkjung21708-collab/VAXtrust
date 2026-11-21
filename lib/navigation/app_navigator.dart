import 'package:flutter/widgets.dart';

/// 로그아웃 뒤 로그인 화면으로 스택을 비울 때 사용합니다.
/// 화면 파일끼리 서로 import하지 않도록 키만 따로 둡니다.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

const String loginRouteName = '/login';
