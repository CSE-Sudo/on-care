import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'rules.dart';

/// 소스 한 곳에서 찾은 하드코딩.
class Finding {
  const Finding(this.rule, this.line, this.column, this.snippet);

  final Rule rule;
  final int line;
  final int column;

  /// 해당 줄의 앞뒤 공백을 뺀 원문.
  final String snippet;

  @override
  String toString() => '$line:$column ${rule.id} $snippet';
}

/// Dart 소스 한 파일을 읽어 [Rule] 에 걸리는 곳을 모두 돌려준다.
///
/// 정규식이 아니라 구문 트리로 본다 — 주석·문자열 속 글자를 잡지 않고, 같은 `height:`
/// 라도 `TextStyle` 줄 높이와 `SizedBox` 크기를 구분하기 위해서다. 타입 해석(resolve)은
/// 하지 않으므로 이름으로만 판단한다.
List<Finding> scanSource(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _Visitor(result.lineInfo, source);
  result.unit.accept(visitor);
  visitor.findings.sort((a, b) {
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  });
  return visitor.findings;
}

/// 호출식 하나를 `타입.이름` 꼴로 정리한 것.
///
/// - `TextStyle(...)` → type `TextStyle`, name `null`
/// - `const EdgeInsets.all(8)` → type `EdgeInsets`, name `all`
/// - `showDialog(...)` → type `showDialog`, name `null`
/// - `style.copyWith(...)` → type `null`, name `copyWith`
class _Call {
  const _Call(this.type, this.name, this.arguments);

  final String? type;
  final String? name;
  final ArgumentList arguments;

  bool isType(String t, [String? n]) => type == t && name == n;

  static _Call? of(AstNode node) {
    if (node is InstanceCreationExpression) {
      final ctor = node.constructorName;
      final prefix = ctor.type.importPrefix;
      // 타입을 해석하지 않으면 `const EdgeInsets.all(8)` 의 `EdgeInsets` 가 import
      // 접두사로 읽힌다. 화면 코드는 material 을 접두사 없이 쓰므로 타입.생성자로 되돌린다.
      if (ctor.name == null && prefix != null) {
        return _Call(
          prefix.name.lexeme,
          ctor.type.name.lexeme,
          node.argumentList,
        );
      }
      return _Call(ctor.type.name.lexeme, ctor.name?.name, node.argumentList);
    }
    if (node is MethodInvocation) {
      final target = node.target;
      final method = node.methodName.name;
      if (target == null) return _Call(method, null, node.argumentList);
      if (target is SimpleIdentifier) {
        return _Call(target.name, method, node.argumentList);
      }
      return _Call(null, method, node.argumentList);
    }
    return null;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._lineInfo, this._source);

  final LineInfo _lineInfo;
  final String _source;
  final findings = <Finding>[];

  void _add(Rule rule, AstNode node) {
    final location = _lineInfo.getLocation(node.offset);
    final lineStart = _lineInfo.getOffsetOfLine(location.lineNumber - 1);
    final lineEnd = location.lineNumber < _lineInfo.lineCount
        ? _lineInfo.getOffsetOfLine(location.lineNumber)
        : _source.length;
    final snippet = _source.substring(lineStart, lineEnd).trim();
    findings.add(
      Finding(rule, location.lineNumber, location.columnNumber, snippet),
    );
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _checkCall(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _checkCall(node);
    super.visitMethodInvocation(node);
  }

  void _checkCall(AstNode node) {
    final call = _Call.of(node);
    if (call == null) return;
    final type = call.type;
    final args = call.arguments.arguments;

    if (type == 'Color' && call.name == null ||
        type == 'Color' &&
            (call.name == 'fromARGB' || call.name == 'fromRGBO')) {
      if (args.any(_hasNonZeroNumber)) _add(Rule.colorLiteral, node);
    }

    if (call.name == 'withValues' && _named(call.arguments, 'alpha') != null ||
        call.name == 'withOpacity' ||
        call.name == 'withAlpha') {
      _add(Rule.opacity, node);
    }

    if ((call.isType('BorderRadius', 'circular') ||
            call.isType('BorderRadiusDirectional', 'circular') ||
            call.isType('Radius', 'circular')) &&
        args.any(_hasNonZeroNumber)) {
      _add(Rule.radius, node);
    }

    if ((type == 'EdgeInsets' || type == 'EdgeInsetsDirectional') &&
        call.name != null &&
        args.any(_hasNonZeroNumber)) {
      _add(Rule.edgeInsets, node);
    }

    if (type == 'SizedBox') {
      final sizes = [
        'width',
        'height',
        'dimension',
      ].map((n) => _named(call.arguments, n)).whereType<Expression>();
      if (sizes.any(_hasNonZeroNumber)) _add(Rule.sizedBox, node);
    }
    if ((type == 'Gap' || type == 'SliverGap') &&
        call.name == null &&
        args.whereType<Expression>().any(
          (a) => a is! NamedExpression && _hasNonZeroNumber(a),
        )) {
      _add(Rule.sizedBox, node);
    }

    if (type == 'BoxShadow' && call.name == null) _add(Rule.boxShadow, node);

    if (type == 'Duration' && call.name == null) {
      final ms = _named(call.arguments, 'milliseconds');
      if (ms != null && _hasNonZeroNumber(ms) && _isAnimationDuration(node)) {
        _add(Rule.animationDuration, node);
      }
    }

    if (type != null &&
        (materialWidgetNames.contains(type) ||
            type.startsWith(materialWidgetPrefix))) {
      _add(Rule.materialWidget, node);
    }
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final value = node.expression;
    switch (node.name.label.name) {
      case 'fontSize':
        if (_hasNonZeroNumber(value)) _add(Rule.fontSize, node);
      case 'fontWeight':
        if (_hasNonZeroNumber(value) || _mentionsFontWeight(value)) {
          _add(Rule.fontWeight, node);
        }
      case 'letterSpacing':
        if (_hasNonZeroNumber(value)) _add(Rule.letterSpacing, node);
      case 'height':
        if (_isTextStyleArgument(node) && _hasNonZeroNumber(value)) {
          _add(Rule.lineHeight, node);
        }
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    final name = node.identifier.name;
    if (prefix == 'Colors' && name != 'transparent') {
      _add(Rule.materialColor, node);
    }
    if (prefix == 'Icons' && !name.endsWith('_rounded')) {
      _add(Rule.nonRoundedIcon, node);
    }
    super.visitPrefixedIdentifier(node);
  }

  /// `height:` 가 글자 스타일의 줄 높이인지. `SizedBox(height:)` 같은 크기는 아니다.
  bool _isTextStyleArgument(NamedExpression node) {
    final list = node.parent;
    if (list is! ArgumentList) return false;
    final call = _Call.of(list.parent!);
    if (call == null) return false;
    return call.isType('TextStyle') ||
        call.isType('StrutStyle') ||
        call.name == 'copyWith' ||
        call.type == 'GoogleFonts';
  }

  /// 애니메이션 시간인지. 대기·디바운스·타이머 간격은 모션 토큰 대상이 아니므로 뺀다.
  bool _isAnimationDuration(AstNode duration) {
    final node = duration.parent;
    // `duration: const Duration(...)` 처럼 이름 붙은 인자 값이면 그 이름을 본다.
    if (node is NamedExpression) {
      return !_isWaitName(node.name.label.name);
    }
    if (node is ArgumentList) {
      final call = _Call.of(node.parent!);
      if (call == null) return true;
      final isWait =
          call.isType('Future', 'delayed') ||
          call.isType('Timer') ||
          call.isType('Timer', 'periodic') ||
          call.isType('Stream', 'periodic') ||
          (call.type == null && call.name == 'delayed');
      return !isWait;
    }
    if (node is VariableDeclaration) {
      return !_isWaitName(node.name.lexeme);
    }
    return true;
  }

  static final _waitName = RegExp(
    r'delay|debounce|timeout|interval|poll|throttle',
    caseSensitive: false,
  );

  bool _isWaitName(String name) => _waitName.hasMatch(name);

  Expression? _named(ArgumentList list, String name) {
    for (final arg in list.arguments) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg.expression;
      }
    }
    return null;
  }

  bool _hasNonZeroNumber(Expression expression) {
    final finder = _NumberFinder();
    expression.accept(finder);
    return finder.found;
  }

  bool _mentionsFontWeight(Expression expression) {
    final finder = _FontWeightFinder();
    expression.accept(finder);
    return finder.found;
  }
}

/// 식 안에 0 이 아닌 숫자 리터럴이 있는지. `AppSpacing.md * 2` 도 숫자를 적은 것으로 본다.
class _NumberFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    if ((node.value ?? 1) != 0) found = true;
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (node.value != 0) found = true;
  }
}

class _FontWeightFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'FontWeight') found = true;
  }
}
