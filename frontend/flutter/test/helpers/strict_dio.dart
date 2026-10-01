/// 로컬 목업 API 시험에서 저장소에 넘길 Dio. (#2743)
///
/// 인터셉터 시험은 응답의 상태 코드를 그대로 보려고 오류 응답도 응답으로 받는
/// Dio(`validateStatus: (_) => true`)를 쓴다. 그 Dio 를 저장소에 그대로 넘기면
/// 오류가 성공 본문처럼 닿는다 — 앱의 Dio 는 기본 검사라 오류가 예외로 온다.
/// 여기서는 같은 인터셉터를 기본 검사 Dio 에 옮겨 담아 앱과 같게 받는다.
library;

import 'package:dio/dio.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';

/// [raw] 에 **지금** 붙어 있는 로컬 목업 API 를 공유하는, 기본 상태 코드 검사
/// Dio. 인터셉터를 갈아 끼운 뒤에는 다시 만든다.
Dio strictDioOf(Dio raw) =>
    Dio(BaseOptions(baseUrl: raw.options.baseUrl))
      ..interceptors.addAll(raw.interceptors.whereType<LocalApiInterceptor>());
