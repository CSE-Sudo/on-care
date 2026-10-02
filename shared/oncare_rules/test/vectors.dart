import 'dart:convert';
import 'dart:io';

/// `vectors/<name>.json` — 백엔드 pytest 와 같은 입력 표.
Map<String, Object?> loadVectors(String name) =>
    jsonDecode(File('vectors/$name.json').readAsStringSync())
        as Map<String, Object?>;
