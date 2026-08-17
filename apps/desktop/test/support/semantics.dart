import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assertions against the semantics tree — what a screen reader actually
/// consumes, rather than which widgets happen to be in the tree.

/// Every semantics node currently in the tree, depth first.
Iterable<SemanticsNode> allSemanticsNodes(SemanticsNode node) sync* {
  yield node;
  final children = <SemanticsNode>[];
  node.visitChildren((SemanticsNode child) {
    children.add(child);
    return true;
  });
  for (final child in children) {
    yield* allSemanticsNodes(child);
  }
}

/// The root of the live semantics tree. Requires `tester.ensureSemantics()`.
SemanticsNode semanticsRoot(WidgetTester tester) {
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull, reason: 'semantics are not enabled in this test');
  return root!;
}

/// Asserts exactly [count] nodes are announced as [text].
///
/// Checks `label` *and* `tooltip`, because Flutter puts the two in different
/// places and both reach a screen reader. `IconButton(tooltip:)` — the
/// idiomatic way to name an icon button, and what this pass used — lands in
/// `SemanticsProperties.tooltip`; an explicit `Semantics(label:)` lands in
/// `.label`. Accepting either keeps these tests measuring what a reader says,
/// rather than forcing every button to announce its name twice just to satisfy
/// `find.bySemanticsLabel`.
void expectAnnouncedAs(WidgetTester tester, String text, {int count = 1}) {
  final matches = allSemanticsNodes(semanticsRoot(tester))
      .where((SemanticsNode node) => node.label == text || node.tooltip == text)
      .length;
  expect(
    matches,
    count,
    reason: 'expected $count control(s) announced as "$text", found $matches',
  );
}

/// Asserts some node reports [value] as its value.
void expectValueAnnounced(WidgetTester tester, String value) {
  expect(
    allSemanticsNodes(semanticsRoot(tester))
        .map((SemanticsNode node) => node.value),
    contains(value),
  );
}

/// Every non-empty label in the tree, in traversal order.
List<String> semanticsLabels(WidgetTester tester) => allSemanticsNodes(
      semanticsRoot(tester),
    )
        .map((SemanticsNode node) => node.label)
        .where((l) => l.isNotEmpty)
        .toList();
