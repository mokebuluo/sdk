// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Functions for asserting equivalence across different compiler
/// implementations.

library dart2js.test.equivalence;

import 'package:compiler/src/common/resolution.dart';
import 'package:compiler/src/constants/expressions.dart';
import 'package:compiler/src/constants/values.dart';
import 'package:compiler/src/elements/elements.dart';
import 'package:compiler/src/elements/entities.dart';
import 'package:compiler/src/elements/names.dart';
import 'package:compiler/src/elements/resolution_types.dart';
import 'package:compiler/src/elements/types.dart';
import 'package:compiler/src/elements/visitor.dart';
import 'package:compiler/src/native/native.dart'
    show NativeBehavior, SpecialType;
import 'package:compiler/src/tree/nodes.dart';
import 'package:compiler/src/universe/feature.dart';
import 'package:compiler/src/universe/selector.dart';
import 'package:compiler/src/universe/use.dart';
import 'package:compiler/src/util/util.dart';

import 'package:front_end/src/fasta/scanner.dart';

typedef bool Equivalence<E>(E a, E b, {TestStrategy strategy});

/// Equality based equivalence function.
bool equality(a, b) => a == b;

/// Returns `true` if the elements in [a] and [b] are pair-wise equivalent
/// according to [elementEquivalence].
bool areListsEquivalent<T>(List<T> a, List<T> b,
    [bool elementEquivalence(T a, T b) = equality]) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length && i < b.length; i++) {
    if (!elementEquivalence(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

/// Returns `true` if the elements in [a] and [b] are equivalent as sets using
/// [elementEquivalence] to determine element equivalence.
bool areSetsEquivalent<E>(Iterable<E> set1, Iterable<E> set2,
    [bool elementEquivalence(E a, E b) = equality]) {
  Set<E> remaining = set2.toSet();
  for (dynamic element1 in set1) {
    bool found = false;
    for (dynamic element2 in set2) {
      if (elementEquivalence(element1, element2)) {
        found = true;
        remaining.remove(element2);
        break;
      }
    }
    if (!found) {
      return false;
    }
  }
  return remaining.isEmpty;
}

/// Returns `true` if the content of [map1] and [map2] is equivalent using
/// [keyEquivalence] and [valueEquivalence] to determine key/value equivalence.
bool areMapsEquivalent<K, V>(Map<K, V> map1, Map<K, V> map2,
    [bool keyEquivalence(K a, K b) = equality,
    bool valueEquivalence(V a, V b) = equality]) {
  Set remaining = map2.keys.toSet();
  for (dynamic key1 in map1.keys) {
    bool found = false;
    for (dynamic key2 in map2.keys) {
      if (keyEquivalence(key1, key2)) {
        found = true;
        remaining.remove(key2);
        if (!valueEquivalence(map1[key1], map2[key2])) {
          return false;
        }
        break;
      }
    }
    if (!found) {
      return false;
    }
  }
  return remaining.isEmpty;
}

/// Returns `true` if elements [a] and [b] are equivalent.
bool areElementsEquivalent(Element a, Element b, {TestStrategy strategy}) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return new ElementIdentityEquivalence(strategy ?? const TestStrategy())
      .visit(a, b);
}

bool areEntitiesEquivalent(Entity a, Entity b, {TestStrategy strategy}) {
  return areElementsEquivalent(a, b, strategy: strategy);
}

/// Returns `true` if types [a] and [b] are equivalent.
bool areTypesEquivalent(DartType a, DartType b, {TestStrategy strategy}) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return new TypeEquivalence(strategy ?? const TestStrategy()).visit(a, b);
}

/// Returns `true` if constants [exp1] and [exp2] are equivalent.
bool areConstantsEquivalent(ConstantExpression exp1, ConstantExpression exp2,
    {TestStrategy strategy}) {
  if (identical(exp1, exp2)) return true;
  if (exp1 == null || exp2 == null) return false;
  return new ConstantEquivalence(strategy ?? const TestStrategy())
      .visit(exp1, exp2);
}

/// Returns `true` if constant values [value1] and [value2] are equivalent.
bool areConstantValuesEquivalent(ConstantValue value1, ConstantValue value2,
    {TestStrategy strategy}) {
  if (identical(value1, value2)) return true;
  if (value1 == null || value2 == null) return false;
  return new ConstantValueEquivalence(strategy ?? const TestStrategy())
      .visit(value1, value2);
}

/// Returns `true` if the lists of elements, [a] and [b], are equivalent.
bool areElementListsEquivalent(List<Element> a, List<Element> b) {
  return areListsEquivalent(a, b, areElementsEquivalent);
}

/// Returns `true` if the lists of types, [a] and [b], are equivalent.
bool areTypeListsEquivalent(
    List<ResolutionDartType> a, List<ResolutionDartType> b) {
  return areListsEquivalent(a, b, areTypesEquivalent);
}

/// Returns `true` if the lists of constants, [a] and [b], are equivalent.
bool areConstantListsEquivalent(
    List<ConstantExpression> a, List<ConstantExpression> b) {
  return areListsEquivalent(a, b, areConstantsEquivalent);
}

/// Returns `true` if the lists of constant values, [a] and [b], are equivalent.
bool areConstantValueListsEquivalent(
    List<ConstantValue> a, List<ConstantValue> b) {
  return areListsEquivalent(a, b, areConstantValuesEquivalent);
}

/// Returns `true` if the selectors [a] and [b] are equivalent.
bool areSelectorsEquivalent(Selector a, Selector b,
    {TestStrategy strategy: const TestStrategy()}) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.kind == b.kind &&
      a.callStructure == b.callStructure &&
      areNamesEquivalent(a.memberName, b.memberName, strategy: strategy);
}

/// Returns `true` if the names [a] and [b] are equivalent.
bool areNamesEquivalent(Name a, Name b,
    {TestStrategy strategy: const TestStrategy()}) {
  return a.text == b.text &&
      a.isSetter == b.isSetter &&
      strategy.testElements(a, b, 'library', a.library, b.library);
}

/// Returns `true` if the dynamic uses [a] and [b] are equivalent.
bool areDynamicUsesEquivalent(DynamicUse a, DynamicUse b,
    {TestStrategy strategy: const TestStrategy()}) {
  return areSelectorsEquivalent(a.selector, b.selector, strategy: strategy);
}

/// Returns `true` if the static uses [a] and [b] are equivalent.
bool areStaticUsesEquivalent(StaticUse a, StaticUse b,
    {TestStrategy strategy: const TestStrategy()}) {
  return a.kind == b.kind &&
      strategy.testElements(a, b, 'element', a.element, b.element);
}

/// Returns `true` if the type uses [a] and [b] are equivalent.
bool areTypeUsesEquivalent(TypeUse a, TypeUse b,
    {TestStrategy strategy: const TestStrategy()}) {
  return a.kind == b.kind && strategy.testTypes(a, b, 'type', a.type, b.type);
}

/// Returns `true` if the list literal uses [a] and [b] are equivalent.
bool areListLiteralUsesEquivalent(ListLiteralUse a, ListLiteralUse b,
    {TestStrategy strategy: const TestStrategy()}) {
  return strategy.testTypes(a, b, 'type', a.type, b.type) &&
      a.isConstant == b.isConstant &&
      a.isEmpty == b.isEmpty;
}

/// Returns `true` if the map literal uses [a] and [b] are equivalent.
bool areMapLiteralUsesEquivalent(MapLiteralUse a, MapLiteralUse b,
    {TestStrategy strategy: const TestStrategy()}) {
  return strategy.testTypes(a, b, 'type', a.type, b.type) &&
      a.isConstant == b.isConstant &&
      a.isEmpty == b.isEmpty;
}

/// Returns `true` if nodes [a] and [b] are equivalent.
bool areNodesEquivalent(Node node1, Node node2) {
  if (identical(node1, node2)) return true;
  if (node1 == null || node2 == null) return false;
  return node1.accept1(const NodeEquivalenceVisitor(), node2);
}

/// Strategy for testing equivalence.
///
/// Use this strategy to determine equivalence without failing on inequivalence.
class TestStrategy {
  final Equivalence<Entity> elementEquivalence;
  final Equivalence<DartType> typeEquivalence;
  final Equivalence<ConstantExpression> constantEquivalence;
  final Equivalence<ConstantValue> constantValueEquivalence;

  const TestStrategy(
      {this.elementEquivalence: areEntitiesEquivalent,
      this.typeEquivalence: areTypesEquivalent,
      this.constantEquivalence: areConstantsEquivalent,
      this.constantValueEquivalence: areConstantValuesEquivalent});

  /// An equivalence [TestStrategy] that doesn't throw on inequivalence.
  TestStrategy get testOnly => this;

  bool test<T>(
      dynamic object1, dynamic object2, String property, T value1, T value2,
      [bool equivalence(T a, T b) = equality]) {
    return equivalence(value1, value2);
  }

  bool testLists(
      Object object1, Object object2, String property, List list1, List list2,
      [bool elementEquivalence(a, b) = equality]) {
    return areListsEquivalent(list1, list2, elementEquivalence);
  }

  bool testSets<E>(dynamic object1, dynamic object2, String property,
      Iterable<E> set1, Iterable<E> set2,
      [bool elementEquivalence(E a, E b) = equality]) {
    return areSetsEquivalent(set1, set2, elementEquivalence);
  }

  bool testMaps<K, V>(dynamic object1, dynamic object2, String property,
      Map<K, V> map1, Map<K, V> map2,
      [bool keyEquivalence(K a, K b) = equality,
      bool valueEquivalence(V a, V b) = equality]) {
    return areMapsEquivalent(map1, map2, keyEquivalence, valueEquivalence);
  }

  bool testElements(Object object1, Object object2, String property,
      Entity element1, Entity element2) {
    return test(object1, object2, property, element1, element2,
        (a, b) => elementEquivalence(a, b, strategy: this));
  }

  bool testTypes(Object object1, Object object2, String property,
      DartType type1, DartType type2) {
    return test(object1, object2, property, type1, type2,
        (a, b) => typeEquivalence(a, b, strategy: this));
  }

  bool testConstants(Object object1, Object object2, String property,
      ConstantExpression exp1, ConstantExpression exp2) {
    return test(object1, object2, property, exp1, exp2,
        (a, b) => constantEquivalence(a, b, strategy: this));
  }

  bool testConstantValues(Object object1, Object object2, String property,
      ConstantValue value1, ConstantValue value2) {
    return test(object1, object2, property, value1, value2,
        (a, b) => constantValueEquivalence(a, b, strategy: this));
  }

  bool testTypeLists(Object object1, Object object2, String property,
      List<DartType> list1, List<DartType> list2) {
    return testLists(object1, object2, property, list1, list2,
        (a, b) => typeEquivalence(a, b, strategy: this));
  }

  bool testConstantLists(Object object1, Object object2, String property,
      List<ConstantExpression> list1, List<ConstantExpression> list2) {
    return testLists(object1, object2, property, list1, list2,
        (a, b) => constantEquivalence(a, b, strategy: this));
  }

  bool testConstantValueLists(Object object1, Object object2, String property,
      List<ConstantValue> list1, List<ConstantValue> list2) {
    return testLists(object1, object2, property, list1, list2,
        (a, b) => constantValueEquivalence(a, b, strategy: this));
  }

  bool testNodes(
      Object object1, Object object2, String property, Node node1, Node node2) {
    return areNodesEquivalent(node1, node2);
  }
}

/// Visitor that checks for equivalence of [Element]s.
class ElementIdentityEquivalence extends BaseElementVisitor<bool, Element> {
  final TestStrategy strategy;

  const ElementIdentityEquivalence([this.strategy = const TestStrategy()]);

  bool visit(Element element1, Element element2) {
    if (element1 == null && element2 == null) {
      return true;
    } else if (element1 == null || element2 == null) {
      return false;
    }
    element1 = element1.declaration;
    element2 = element2.declaration;
    if (element1 == element2) {
      return true;
    }
    return strategy.test(
            element1, element2, 'kind', element1.kind, element2.kind) &&
        element1.accept(this, element2);
  }

  @override
  bool visitElement(Element e, Element arg) {
    throw new UnsupportedError("Unsupported element $e");
  }

  @override
  bool visitLibraryElement(
      LibraryElement element1, covariant LibraryElement element2) {
    return strategy.test(element1, element2, 'canonicalUri',
        element1.canonicalUri, element2.canonicalUri);
  }

  @override
  bool visitCompilationUnitElement(CompilationUnitElement element1,
      covariant CompilationUnitElement element2) {
    return strategy.test(element1, element2, 'script.resourceUri',
            element1.script.resourceUri, element2.script.resourceUri) &&
        visit(element1.library, element2.library);
  }

  @override
  bool visitClassElement(
      ClassElement element1, covariant ClassElement element2) {
    if (!strategy.test(
        element1,
        element2,
        'isUnnamedMixinApplication',
        element1.isUnnamedMixinApplication,
        element2.isUnnamedMixinApplication)) {
      return false;
    }
    if (element1.isUnnamedMixinApplication) {
      MixinApplicationElement mixin1 = element1;
      MixinApplicationElement mixin2 = element2;
      return strategy.testElements(
              mixin1, mixin2, 'subclass', mixin1.subclass, mixin2.subclass) &&
          // Using the [mixinType] is more precise but requires the test to
          // handle self references: The identity of a type variable is based on
          // its type declaration and if [mixin1] is generic the [mixinType]
          // will contain the type variables declared by [mixin1], i.e.
          // `abstract class Mixin<T> implements MixinType<T> {}`
          strategy.testElements(
              mixin1, mixin2, 'mixin', mixin1.mixin, mixin2.mixin);
    } else {
      return strategy.test(
              element1, element2, 'name', element1.name, element2.name) &&
          visit(element1.library, element2.library);
    }
  }

  bool checkMembers(Element element1, covariant Element element2) {
    if (!strategy.test(
        element1, element2, 'name', element1.name, element2.name)) {
      return false;
    }
    if (element1.enclosingClass != null || element2.enclosingClass != null) {
      return visit(element1.enclosingClass, element2.enclosingClass);
    } else {
      return visit(element1.library, element2.library);
    }
  }

  @override
  bool visitFieldElement(
      FieldElement element1, covariant FieldElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitConstructorElement(
      ConstructorElement element1, covariant ConstructorElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitMethodElement(
      covariant MethodElement element1, covariant MethodElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitGetterElement(
      GetterElement element1, covariant GetterElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitSetterElement(
      SetterElement element1, covariant SetterElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitLocalFunctionElement(
      LocalFunctionElement element1, covariant LocalFunctionElement element2) {
    // TODO(johnniwinther): Define an equivalence on locals.
    MemberElement member1 = element1.memberContext;
    MemberElement member2 = element2.memberContext;
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        checkMembers(member1, member2);
  }

  @override
  bool visitLocalVariableElement(
      LocalVariableElement element1, covariant LocalVariableElement element2) {
    // TODO(johnniwinther): Define an equivalence on locals.
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        checkMembers(element1.memberContext, element2.memberContext);
  }

  bool visitAbstractFieldElement(
      AbstractFieldElement element1, covariant AbstractFieldElement element2) {
    return checkMembers(element1, element2);
  }

  @override
  bool visitTypeVariableElement(
      TypeVariableElement element1, covariant TypeVariableElement element2) {
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        visit(element1.typeDeclaration, element2.typeDeclaration);
  }

  @override
  bool visitTypedefElement(
      TypedefElement element1, covariant TypedefElement element2) {
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        visit(element1.library, element2.library);
  }

  @override
  bool visitParameterElement(
      ParameterElement element1, covariant ParameterElement element2) {
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        visit(element1.functionDeclaration, element2.functionDeclaration);
  }

  @override
  bool visitImportElement(
      ImportElement element1, covariant ImportElement element2) {
    return visit(element1.importedLibrary, element2.importedLibrary) &&
        visit(element1.library, element2.library);
  }

  @override
  bool visitExportElement(
      ExportElement element1, covariant ExportElement element2) {
    return visit(element1.exportedLibrary, element2.exportedLibrary) &&
        visit(element1.library, element2.library);
  }

  @override
  bool visitPrefixElement(
      PrefixElement element1, covariant PrefixElement element2) {
    return strategy.test(
            element1, element2, 'name', element1.name, element2.name) &&
        visit(element1.library, element2.library);
  }

  @override
  bool visitErroneousElement(
      ErroneousElement element1, covariant ErroneousElement element2) {
    return strategy.test(element1, element2, 'messageKind',
        element1.messageKind, element2.messageKind);
  }

  @override
  bool visitWarnOnUseElement(
      WarnOnUseElement element1, covariant WarnOnUseElement element2) {
    return strategy.testElements(element1, element2, 'wrappedElement',
        element1.wrappedElement, element2.wrappedElement);
  }
}

/// Visitor that checks for equivalence of [ResolutionDartType]s.
class TypeEquivalence
    implements ResolutionDartTypeVisitor<bool, ResolutionDartType> {
  final TestStrategy strategy;

  const TypeEquivalence([this.strategy = const TestStrategy()]);

  bool visit(
      covariant ResolutionDartType type1, covariant ResolutionDartType type2) {
    return strategy.test(type1, type2, 'kind', type1.kind, type2.kind) &&
        type1.accept(this, type2);
  }

  @override
  bool visitDynamicType(covariant ResolutionDynamicType type,
          covariant ResolutionDynamicType other) =>
      true;

  @override
  bool visitFunctionType(covariant ResolutionFunctionType type,
      covariant ResolutionFunctionType other) {
    return strategy.testTypeLists(type, other, 'parameterTypes',
            type.parameterTypes, other.parameterTypes) &&
        strategy.testTypeLists(type, other, 'optionalParameterTypes',
            type.optionalParameterTypes, other.optionalParameterTypes) &&
        strategy.testTypeLists(type, other, 'namedParameterTypes',
            type.namedParameterTypes, other.namedParameterTypes) &&
        strategy.testLists(type, other, 'namedParameters', type.namedParameters,
            other.namedParameters);
  }

  bool visitGenericType(GenericType type, GenericType other) {
    return strategy.testElements(
            type, other, 'element', type.element, other.element) &&
        strategy.testTypeLists(type, other, 'typeArguments', type.typeArguments,
            other.typeArguments);
  }

  @override
  bool visitMalformedType(MalformedType type, covariant MalformedType other) =>
      true;

  @override
  bool visitTypeVariableType(covariant ResolutionTypeVariableType type,
      covariant ResolutionTypeVariableType other) {
    return strategy.testElements(
            type, other, 'element', type.element, other.element) &&
        strategy.test(type, other, 'is MethodTypeVariableType',
            type is MethodTypeVariableType, other is MethodTypeVariableType);
  }

  @override
  bool visitVoidType(covariant ResolutionVoidType type,
          covariant ResolutionVoidType argument) =>
      true;

  @override
  bool visitInterfaceType(covariant ResolutionInterfaceType type,
      covariant ResolutionInterfaceType other) {
    return visitGenericType(type, other);
  }

  @override
  bool visitTypedefType(covariant ResolutionTypedefType type,
      covariant ResolutionTypedefType other) {
    return visitGenericType(type, other);
  }

  @override
  bool visitFunctionTypeVariable(
      FunctionTypeVariable type, ResolutionDartType other) {
    throw new UnsupportedError("Function type variables are not supported.");
  }

  @override
  bool visitFutureOrType(
      covariant FutureOrType type, covariant ResolutionDartType other) {
    throw new UnsupportedError("FutureOr is not supported.");
  }
}

/// Visitor that checks for structural equivalence of [ConstantExpression]s.
class ConstantEquivalence
    implements ConstantExpressionVisitor<bool, ConstantExpression> {
  final TestStrategy strategy;

  const ConstantEquivalence([this.strategy = const TestStrategy()]);

  @override
  bool visit(ConstantExpression exp1, covariant ConstantExpression exp2) {
    if (identical(exp1, exp2)) return true;
    return strategy.test(exp1, exp2, 'kind', exp1.kind, exp2.kind) &&
        exp1.accept(this, exp2);
  }

  @override
  bool visitAs(AsConstantExpression exp1, covariant AsConstantExpression exp2) {
    return strategy.test(
            exp1, exp2, 'expression', exp1.expression, exp2.expression) &&
        strategy.testTypes(exp1, exp2, 'type', exp1.type, exp2.type);
  }

  @override
  bool visitBinary(
      BinaryConstantExpression exp1, covariant BinaryConstantExpression exp2) {
    return strategy.test(
            exp1, exp2, 'operator', exp1.operator, exp2.operator) &&
        strategy.testConstants(exp1, exp2, 'left', exp1.left, exp2.left) &&
        strategy.testConstants(exp1, exp2, 'right', exp1.right, exp2.right);
  }

  @override
  bool visitConcatenate(ConcatenateConstantExpression exp1,
      covariant ConcatenateConstantExpression exp2) {
    return strategy.testConstantLists(
        exp1, exp2, 'expressions', exp1.expressions, exp2.expressions);
  }

  @override
  bool visitConditional(ConditionalConstantExpression exp1,
      covariant ConditionalConstantExpression exp2) {
    return strategy.testConstants(
            exp1, exp2, 'condition', exp1.condition, exp2.condition) &&
        strategy.testConstants(
            exp1, exp2, 'trueExp', exp1.trueExp, exp2.trueExp) &&
        strategy.testConstants(
            exp1, exp2, 'falseExp', exp1.falseExp, exp2.falseExp);
  }

  @override
  bool visitConstructed(ConstructedConstantExpression exp1,
      covariant ConstructedConstantExpression exp2) {
    return strategy.testTypes(exp1, exp2, 'type', exp1.type, exp2.type) &&
        strategy.testElements(exp1, exp2, 'target', exp1.target, exp2.target) &&
        strategy.testConstantLists(
            exp1, exp2, 'arguments', exp1.arguments, exp2.arguments) &&
        strategy.test(exp1, exp2, 'callStructure', exp1.callStructure,
            exp2.callStructure);
  }

  @override
  bool visitFunction(FunctionConstantExpression exp1,
      covariant FunctionConstantExpression exp2) {
    return strategy.testElements(
        exp1, exp2, 'element', exp1.element, exp2.element);
  }

  @override
  bool visitIdentical(IdenticalConstantExpression exp1,
      covariant IdenticalConstantExpression exp2) {
    return strategy.testConstants(exp1, exp2, 'left', exp1.left, exp2.left) &&
        strategy.testConstants(exp1, exp2, 'right', exp1.right, exp2.right);
  }

  @override
  bool visitList(
      ListConstantExpression exp1, covariant ListConstantExpression exp2) {
    return strategy.testTypes(exp1, exp2, 'type', exp1.type, exp2.type) &&
        strategy.testConstantLists(
            exp1, exp2, 'values', exp1.values, exp2.values);
  }

  @override
  bool visitMap(
      MapConstantExpression exp1, covariant MapConstantExpression exp2) {
    return strategy.testTypes(exp1, exp2, 'type', exp1.type, exp2.type) &&
        strategy.testConstantLists(exp1, exp2, 'keys', exp1.keys, exp2.keys) &&
        strategy.testConstantLists(
            exp1, exp2, 'values', exp1.values, exp2.values);
  }

  @override
  bool visitNamed(
      NamedArgumentReference exp1, covariant NamedArgumentReference exp2) {
    return strategy.test(exp1, exp2, 'name', exp1.name, exp2.name);
  }

  @override
  bool visitPositional(PositionalArgumentReference exp1,
      covariant PositionalArgumentReference exp2) {
    return strategy.test(exp1, exp2, 'index', exp1.index, exp2.index);
  }

  @override
  bool visitSymbol(
      SymbolConstantExpression exp1, covariant SymbolConstantExpression exp2) {
    // TODO(johnniwinther): Handle private names. Currently not even supported
    // in resolution.
    return strategy.test(exp1, exp2, 'name', exp1.name, exp2.name);
  }

  @override
  bool visitType(
      TypeConstantExpression exp1, covariant TypeConstantExpression exp2) {
    return strategy.testTypes(exp1, exp2, 'type', exp1.type, exp2.type);
  }

  @override
  bool visitUnary(
      UnaryConstantExpression exp1, covariant UnaryConstantExpression exp2) {
    return strategy.test(
            exp1, exp2, 'operator', exp1.operator, exp2.operator) &&
        strategy.testConstants(
            exp1, exp2, 'expression', exp1.expression, exp2.expression);
  }

  @override
  bool visitField(
      FieldConstantExpression exp1, covariant FieldConstantExpression exp2) {
    return strategy.testElements(
        exp1, exp2, 'element', exp1.element, exp2.element);
  }

  @override
  bool visitLocalVariable(LocalVariableConstantExpression exp1,
      covariant LocalVariableConstantExpression exp2) {
    return strategy.testElements(
        exp1, exp2, 'element', exp1.element, exp2.element);
  }

  @override
  bool visitBool(
      BoolConstantExpression exp1, covariant BoolConstantExpression exp2) {
    return strategy.test(
        exp1, exp2, 'boolValue', exp1.boolValue, exp2.boolValue);
  }

  @override
  bool visitDouble(
      DoubleConstantExpression exp1, covariant DoubleConstantExpression exp2) {
    return strategy.test(
        exp1, exp2, 'doubleValue', exp1.doubleValue, exp2.doubleValue);
  }

  @override
  bool visitInt(
      IntConstantExpression exp1, covariant IntConstantExpression exp2) {
    return strategy.test(exp1, exp2, 'intValue', exp1.intValue, exp2.intValue);
  }

  @override
  bool visitNull(
      NullConstantExpression exp1, covariant NullConstantExpression exp2) {
    return true;
  }

  @override
  bool visitString(
      StringConstantExpression exp1, covariant StringConstantExpression exp2) {
    return strategy.test(
        exp1, exp2, 'stringValue', exp1.stringValue, exp2.stringValue);
  }

  @override
  bool visitBoolFromEnvironment(BoolFromEnvironmentConstantExpression exp1,
      covariant BoolFromEnvironmentConstantExpression exp2) {
    return strategy.testConstants(exp1, exp2, 'name', exp1.name, exp2.name) &&
        strategy.testConstants(
            exp1, exp2, 'defaultValue', exp1.defaultValue, exp2.defaultValue);
  }

  @override
  bool visitIntFromEnvironment(IntFromEnvironmentConstantExpression exp1,
      covariant IntFromEnvironmentConstantExpression exp2) {
    return strategy.testConstants(exp1, exp2, 'name', exp1.name, exp2.name) &&
        strategy.testConstants(
            exp1, exp2, 'defaultValue', exp1.defaultValue, exp2.defaultValue);
  }

  @override
  bool visitStringFromEnvironment(StringFromEnvironmentConstantExpression exp1,
      covariant StringFromEnvironmentConstantExpression exp2) {
    return strategy.testConstants(exp1, exp2, 'name', exp1.name, exp2.name) &&
        strategy.testConstants(
            exp1, exp2, 'defaultValue', exp1.defaultValue, exp2.defaultValue);
  }

  @override
  bool visitStringLength(StringLengthConstantExpression exp1,
      covariant StringLengthConstantExpression exp2) {
    return strategy.testConstants(
        exp1, exp2, 'expression', exp1.expression, exp2.expression);
  }

  @override
  bool visitDeferred(DeferredConstantExpression exp1,
      covariant DeferredConstantExpression exp2) {
    return strategy.testElements(
            exp1, exp2, 'import', exp1.import, exp2.import) &&
        strategy.testConstants(
            exp1, exp2, 'expression', exp1.expression, exp2.expression);
  }

  @override
  bool visitAssert(
      AssertConstantExpression exp1, covariant AssertConstantExpression exp2) {
    return strategy.testConstants(
            exp1, exp2, 'condition', exp1.condition, exp2.condition) &&
        strategy.testConstants(
            exp1, exp2, 'message', exp1.message, exp2.message);
  }

  @override
  bool visitInstantiation(InstantiationConstantExpression exp1,
      covariant InstantiationConstantExpression exp2) {
    return strategy.testTypeLists(exp1, exp2, 'typeArguments',
            exp1.typeArguments, exp2.typeArguments) &&
        strategy.testConstants(
            exp1, exp2, 'expression', exp1.expression, exp2.expression);
  }
}

/// Visitor that checks for structural equivalence of [ConstantValue]s.
class ConstantValueEquivalence
    implements ConstantValueVisitor<bool, ConstantValue> {
  final TestStrategy strategy;

  const ConstantValueEquivalence([this.strategy = const TestStrategy()]);

  bool visit(ConstantValue value1, covariant ConstantValue value2) {
    if (identical(value1, value2)) return true;
    return strategy.test(value1, value2, 'kind', value1.kind, value2.kind) &&
        value1.accept(this, value2);
  }

  @override
  bool visitConstructed(ConstructedConstantValue value1,
      covariant ConstructedConstantValue value2) {
    return strategy.testTypes(
            value1, value2, 'type', value1.type, value2.type) &&
        strategy.testMaps(
            value1,
            value2,
            'fields',
            value1.fields,
            value2.fields,
            strategy.elementEquivalence,
            (a, b) => strategy.testConstantValues(
                value1, value2, 'fields.values', a, b));
  }

  @override
  bool visitFunction(
      FunctionConstantValue value1, covariant FunctionConstantValue value2) {
    return strategy.testElements(
        value1, value2, 'element', value1.element, value2.element);
  }

  @override
  bool visitList(ListConstantValue value1, covariant ListConstantValue value2) {
    return strategy.testTypes(
            value1, value2, 'type', value1.type, value2.type) &&
        strategy.testConstantValueLists(
            value1, value2, 'entries', value1.entries, value2.entries);
  }

  @override
  bool visitMap(MapConstantValue value1, covariant MapConstantValue value2) {
    return strategy.testTypes(
            value1, value2, 'type', value1.type, value2.type) &&
        strategy.testConstantValueLists(
            value1, value2, 'keys', value1.keys, value2.keys) &&
        strategy.testConstantValueLists(
            value1, value2, 'values', value1.values, value2.values);
  }

  @override
  bool visitType(TypeConstantValue value1, covariant TypeConstantValue value2) {
    return strategy.testTypes(value1, value2, 'type', value1.type, value2.type);
  }

  @override
  bool visitBool(BoolConstantValue value1, covariant BoolConstantValue value2) {
    return strategy.test(
        value1, value2, 'boolValue', value1.boolValue, value2.boolValue);
  }

  @override
  bool visitDouble(
      DoubleConstantValue value1, covariant DoubleConstantValue value2) {
    return strategy.test(
        value1, value2, 'doubleValue', value1.doubleValue, value2.doubleValue);
  }

  @override
  bool visitInt(IntConstantValue value1, covariant IntConstantValue value2) {
    return strategy.test(
        value1, value2, 'intValue', value1.intValue, value2.intValue);
  }

  @override
  bool visitNull(NullConstantValue value1, covariant NullConstantValue value2) {
    return true;
  }

  @override
  bool visitString(
      StringConstantValue value1, covariant StringConstantValue value2) {
    return strategy.test(
        value1, value2, 'stringValue', value1.stringValue, value2.stringValue);
  }

  @override
  bool visitDeferred(
      DeferredConstantValue value1, covariant DeferredConstantValue value2) {
    return strategy.testElements(
            value1, value2, 'prefix', value1.import, value2.import) &&
        strategy.testConstantValues(
            value1, value2, 'referenced', value1.referenced, value2.referenced);
  }

  @override
  bool visitDeferredGlobal(DeferredGlobalConstantValue value1,
      covariant DeferredGlobalConstantValue value2) {
    return strategy.testSets(
            value1,
            value2,
            'imports',
            value1.unit.importsForTesting,
            value2.unit.importsForTesting,
            strategy.elementEquivalence) &&
        strategy.testConstantValues(
            value1, value2, 'referenced', value1.referenced, value2.referenced);
  }

  @override
  bool visitNonConstant(
      NonConstantValue value1, covariant NonConstantValue value2) {
    return true;
  }

  @override
  bool visitSynthetic(
      SyntheticConstantValue value1, covariant SyntheticConstantValue value2) {
    return strategy.test(
            value1, value2, 'payload', value1.payload, value2.payload) &&
        strategy.test(
            value1, value2, 'valueKind', value1.valueKind, value2.valueKind);
  }

  @override
  bool visitInterceptor(InterceptorConstantValue value1,
      covariant InterceptorConstantValue value2) {
    return strategy.testElements(value1, value2, 'cls', value1.cls, value2.cls);
  }

  @override
  bool visitInstantiation(InstantiationConstantValue value1,
      covariant InstantiationConstantValue value2) {
    return strategy.testTypeLists(value1, value2, 'typeArguments',
            value1.typeArguments, value2.typeArguments) &&
        strategy.testConstantValues(
            value1, value2, 'function', value1.function, value2.function);
  }
}

/// Tests the equivalence of [impact1] and [impact2] using [strategy].
bool testResolutionImpactEquivalence(
    ResolutionImpact impact1, ResolutionImpact impact2,
    {TestStrategy strategy = const TestStrategy(),
    Iterable<ConstantExpression> filterConstantLiterals(
        Iterable<ConstantExpression> constants,
        {bool fromFirstImpact})}) {
  return strategy.testSets(impact1, impact2, 'constSymbolNames',
          impact1.constSymbolNames, impact2.constSymbolNames) &&
      strategy.testSets(
          impact1,
          impact2,
          'constantLiterals',
          filterConstantLiterals != null
              ? filterConstantLiterals(impact1.constantLiterals,
                  fromFirstImpact: true)
              : impact1.constantLiterals,
          filterConstantLiterals != null
              ? filterConstantLiterals(impact2.constantLiterals,
                  fromFirstImpact: false)
              : impact2.constantLiterals,
          areConstantsEquivalent) &&
      strategy.testSets(
          impact1,
          impact2,
          'dynamicUses',
          impact1.dynamicUses,
          impact2.dynamicUses,
          (a, b) =>
              areDynamicUsesEquivalent(a, b, strategy: strategy.testOnly)) &&
      strategy.testSets(
          impact1, impact2, 'features', impact1.features, impact2.features) &&
      strategy.testSets(
          impact1,
          impact2,
          'listLiterals',
          impact1.listLiterals,
          impact2.listLiterals,
          (a, b) => areListLiteralUsesEquivalent(a, b,
              strategy: strategy.testOnly)) &&
      strategy.testSets(
          impact1,
          impact2,
          'mapLiterals',
          impact1.mapLiterals,
          impact2.mapLiterals,
          (a, b) =>
              areMapLiteralUsesEquivalent(a, b, strategy: strategy.testOnly)) &&
      strategy.testSets(
          impact1,
          impact2,
          'staticUses',
          impact1.staticUses,
          impact2.staticUses,
          (a, b) =>
              areStaticUsesEquivalent(a, b, strategy: strategy.testOnly)) &&
      strategy.testSets(
          impact1,
          impact2,
          'typeUses',
          impact1.typeUses,
          impact2.typeUses,
          (a, b) => areTypeUsesEquivalent(a, b, strategy: strategy.testOnly)) &&
      strategy.testSets(
          impact1,
          impact2,
          'nativeData',
          impact1.nativeData,
          impact2.nativeData,
          (a, b) => testNativeBehavior(a, b, strategy: strategy));
}

bool testNativeBehavior(NativeBehavior a, NativeBehavior b,
    {TestStrategy strategy = const TestStrategy()}) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return strategy.test(
          a, b, 'codeTemplateText', a.codeTemplateText, b.codeTemplateText) &&
      strategy.test(a, b, 'isAllocation', a.isAllocation, b.isAllocation) &&
      strategy.test(a, b, 'sideEffects', a.sideEffects, b.sideEffects) &&
      strategy.test(a, b, 'throwBehavior', a.throwBehavior, b.throwBehavior) &&
      strategy.testTypeLists(
          a,
          b,
          'dartTypesReturned',
          NativeBehaviorFilters.filterDartTypes(a.typesReturned),
          NativeBehaviorFilters.filterDartTypes(b.typesReturned)) &&
      strategy.testLists(
          a,
          b,
          'specialTypesReturned',
          NativeBehaviorFilters.filterSpecialTypes(a.typesReturned),
          NativeBehaviorFilters.filterSpecialTypes(b.typesReturned)) &&
      strategy.testTypeLists(
          a,
          b,
          'dartTypesInstantiated',
          NativeBehaviorFilters.filterDartTypes(a.typesInstantiated),
          NativeBehaviorFilters.filterDartTypes(b.typesInstantiated)) &&
      strategy.testLists(
          a,
          b,
          'specialTypesInstantiated',
          NativeBehaviorFilters.filterSpecialTypes(a.typesInstantiated),
          NativeBehaviorFilters.filterSpecialTypes(b.typesInstantiated)) &&
      strategy.test(a, b, 'useGvn', a.useGvn, b.useGvn);
}

class NodeEquivalenceVisitor implements Visitor1<bool, Node> {
  final TestStrategy strategy;

  const NodeEquivalenceVisitor([this.strategy = const TestStrategy()]);

  bool testNodes(dynamic object1, dynamic object2, String property, Node node1,
      Node node2) {
    return strategy.test(object1, object2, property, node1, node2,
        (Node n1, Node n2) {
      if (n1 == n2) return true;
      if (n1 == null || n2 == null) return false;
      return n1.accept1(this, n2);
    });
  }

  bool testNodeLists(dynamic object1, dynamic object2, String property,
      Link<Node> list1, Link<Node> list2) {
    return strategy.test(object1, object2, property, list1, list2,
        (Link<Node> l1, Link<Node> l2) {
      if (l1 == l2) return true;
      if (l1 == null || l2 == null) return false;
      while (l1.isNotEmpty && l2.isNotEmpty) {
        if (!l1.head.accept1(this, l2.head)) {
          return false;
        }
        l1 = l1.tail;
        l2 = l2.tail;
      }
      return l1.isEmpty && l2.isEmpty;
    });
  }

  bool testTokens(dynamic object1, dynamic object2, String property,
      Token token1, Token token2) {
    return strategy.test(object1, object2, property, token1, token2,
        (Token t1, Token t2) {
      if (t1 == t2) return true;
      if (t1 == null || t2 == null) return false;
      return strategy.test(
              t1, t2, 'charOffset', t1.charOffset, t2.charOffset) &&
          strategy.test(t1, t2, 'info', t1.type, t2.type) &&
          strategy.test(t1, t2, 'value', t1.lexeme, t2.lexeme);
    });
  }

  @override
  bool visitAssert(Assert node1, covariant Assert node2) {
    return testTokens(node1, node2, 'assertToken', node1.assertToken,
            node2.assertToken) &&
        testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'message', node1.message, node2.message);
  }

  @override
  bool visitAsyncForIn(AsyncForIn node1, covariant AsyncForIn node2) {
    return visitForIn(node1, node2) &&
        testTokens(
            node1, node2, 'awaitToken', node1.awaitToken, node2.awaitToken);
  }

  @override
  bool visitAsyncModifier(AsyncModifier node1, covariant AsyncModifier node2) {
    return testTokens(
            node1, node2, 'asyncToken', node1.asyncToken, node2.asyncToken) &&
        testTokens(node1, node2, 'starToken', node1.starToken, node2.starToken);
  }

  @override
  bool visitAwait(Await node1, covariant Await node2) {
    return testTokens(
            node1, node2, 'awaitToken', node1.awaitToken, node2.awaitToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitBlock(Block node1, covariant Block node2) {
    return testNodes(
        node1, node2, 'statements', node1.statements, node2.statements);
  }

  @override
  bool visitBreakStatement(
      BreakStatement node1, covariant BreakStatement node2) {
    return testTokens(node1, node2, 'keywordToken', node1.keywordToken,
            node2.keywordToken) &&
        testNodes(node1, node2, 'target', node1.target, node2.target);
  }

  @override
  bool visitCascade(Cascade node1, covariant Cascade node2) {
    return testNodes(
        node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitCascadeReceiver(
      CascadeReceiver node1, covariant CascadeReceiver node2) {
    return testTokens(node1, node2, 'cascadeOperator', node1.cascadeOperator,
            node2.cascadeOperator) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitCaseMatch(CaseMatch node1, covariant CaseMatch node2) {
    return testTokens(node1, node2, 'caseKeyword', node1.caseKeyword,
            node2.caseKeyword) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitCatchBlock(CatchBlock node1, covariant CatchBlock node2) {
    return testTokens(node1, node2, 'catchKeyword', node1.catchKeyword,
            node2.catchKeyword) &&
        testTokens(
            node1, node2, 'onKeyword', node1.onKeyword, node2.onKeyword) &&
        testNodes(node1, node2, 'type', node1.type, node2.type) &&
        testNodes(node1, node2, 'formals', node1.formals, node2.formals) &&
        testNodes(node1, node2, 'block', node1.block, node2.block);
  }

  @override
  bool visitClassNode(ClassNode node1, covariant ClassNode node2) {
    return testTokens(
            node1, node2, 'beginToken', node1.beginToken, node2.beginToken) &&
        testTokens(node1, node2, 'extendsKeyword', node1.extendsKeyword,
            node2.extendsKeyword) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'modifiers', node1.modifiers, node2.modifiers) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(
            node1, node2, 'superclass', node1.superclass, node2.superclass) &&
        testNodes(
            node1, node2, 'interfaces', node1.interfaces, node2.interfaces) &&
        testNodes(node1, node2, 'typeParameters', node1.typeParameters,
            node2.typeParameters) &&
        testNodes(node1, node2, 'body', node1.body, node2.body);
  }

  @override
  bool visitCombinator(Combinator node1, covariant Combinator node2) {
    return testTokens(node1, node2, 'keywordToken', node1.keywordToken,
            node2.keywordToken) &&
        testNodes(
            node1, node2, 'identifiers', node1.identifiers, node2.identifiers);
  }

  @override
  bool visitConditional(Conditional node1, covariant Conditional node2) {
    return testTokens(node1, node2, 'questionToken', node1.questionToken,
            node2.questionToken) &&
        testTokens(
            node1, node2, 'colonToken', node1.colonToken, node2.colonToken) &&
        testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'thenExpression', node1.thenExpression,
            node2.thenExpression) &&
        testNodes(node1, node2, 'elseExpression', node1.elseExpression,
            node2.elseExpression);
  }

  @override
  bool visitConditionalUri(
      ConditionalUri node1, covariant ConditionalUri node2) {
    return testTokens(node1, node2, 'ifToken', node1.ifToken, node2.ifToken) &&
        testNodes(node1, node2, 'key', node1.key, node2.key) &&
        testNodes(node1, node2, 'value', node1.value, node2.value) &&
        testNodes(node1, node2, 'uri', node1.uri, node2.uri);
  }

  @override
  bool visitContinueStatement(
      ContinueStatement node1, covariant ContinueStatement node2) {
    return testTokens(node1, node2, 'keywordToken', node1.keywordToken,
            node2.keywordToken) &&
        testNodes(node1, node2, 'target', node1.target, node2.target);
  }

  @override
  bool visitDoWhile(DoWhile node1, covariant DoWhile node2) {
    return testTokens(
            node1, node2, 'doKeyword', node1.doKeyword, node2.doKeyword) &&
        testTokens(node1, node2, 'whileKeyword', node1.whileKeyword,
            node2.whileKeyword) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'body', node1.body, node2.body);
  }

  @override
  bool visitDottedName(DottedName node1, covariant DottedName node2) {
    return testTokens(node1, node2, 'token', node1.token, node2.token) &&
        testNodes(
            node1, node2, 'identifiers', node1.identifiers, node2.identifiers);
  }

  @override
  bool visitEmptyStatement(
      EmptyStatement node1, covariant EmptyStatement node2) {
    return testTokens(node1, node2, 'semicolonToken', node1.semicolonToken,
        node2.semicolonToken);
  }

  @override
  bool visitEnum(Enum node1, covariant Enum node2) {
    return testTokens(
            node1, node2, 'enumToken', node1.enumToken, node2.enumToken) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(node1, node2, 'names', node1.names, node2.names);
  }

  @override
  bool visitExport(Export node1, covariant Export node2) {
    return visitLibraryDependency(node1, node2) &&
        testTokens(node1, node2, 'exportKeyword', node1.exportKeyword,
            node2.exportKeyword);
  }

  @override
  bool visitExpressionStatement(
      ExpressionStatement node1, covariant ExpressionStatement node2) {
    return testTokens(
            node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitFor(For node1, covariant For node2) {
    return testTokens(
            node1, node2, 'forToken', node1.forToken, node2.forToken) &&
        testNodes(node1, node2, 'initializer', node1.initializer,
            node2.initializer) &&
        testNodes(node1, node2, 'conditionStatement', node1.conditionStatement,
            node2.conditionStatement) &&
        testNodes(node1, node2, 'update', node1.update, node2.update) &&
        testNodes(node1, node2, 'body', node1.body, node2.body);
  }

  @override
  bool visitForIn(ForIn node1, covariant ForIn node2) {
    return testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression) &&
        testNodes(node1, node2, 'body', node1.body, node2.body) &&
        testNodes(node1, node2, 'declaredIdentifier', node1.declaredIdentifier,
            node2.declaredIdentifier);
  }

  @override
  bool visitFunctionDeclaration(
      FunctionDeclaration node1, covariant FunctionDeclaration node2) {
    return testNodes(node1, node2, 'function', node1.function, node2.function);
  }

  @override
  bool visitFunctionExpression(
      FunctionExpression node1, covariant FunctionExpression node2) {
    return testTokens(
            node1, node2, 'getOrSet', node1.getOrSet, node2.getOrSet) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(
            node1, node2, 'parameters', node1.parameters, node2.parameters) &&
        testNodes(node1, node2, 'body', node1.body, node2.body) &&
        testNodes(
            node1, node2, 'returnType', node1.returnType, node2.returnType) &&
        testNodes(
            node1, node2, 'modifiers', node1.modifiers, node2.modifiers) &&
        testNodes(node1, node2, 'initializers', node1.initializers,
            node2.initializers) &&
        testNodes(node1, node2, 'asyncModifier', node1.asyncModifier,
            node2.asyncModifier);
  }

  @override
  bool visitGotoStatement(GotoStatement node1, covariant GotoStatement node2) {
    return testTokens(node1, node2, 'keywordToken', node1.keywordToken,
            node2.keywordToken) &&
        testTokens(node1, node2, 'semicolonToken', node1.semicolonToken,
            node2.semicolonToken) &&
        testNodes(node1, node2, 'target', node1.target, node2.target);
  }

  @override
  bool visitIdentifier(Identifier node1, covariant Identifier node2) {
    return testTokens(node1, node2, 'token', node1.token, node2.token);
  }

  @override
  bool visitIf(If node1, covariant If node2) {
    return testTokens(node1, node2, 'ifToken', node1.ifToken, node2.ifToken) &&
        testTokens(
            node1, node2, 'elseToken', node1.elseToken, node2.elseToken) &&
        testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'thenPart', node1.thenPart, node2.thenPart) &&
        testNodes(node1, node2, 'elsePart', node1.elsePart, node2.elsePart);
  }

  @override
  bool visitImport(Import node1, covariant Import node2) {
    return visitLibraryDependency(node1, node2) &&
        testTokens(node1, node2, 'importKeyword', node1.importKeyword,
            node2.importKeyword) &&
        testNodes(node1, node2, 'prefix', node1.prefix, node2.prefix) &&
        strategy.test(
            node1, node2, 'isDeferred', node1.isDeferred, node2.isDeferred);
  }

  @override
  bool visitLabel(Label node1, covariant Label node2) {
    return testTokens(
            node1, node2, 'colonToken', node1.colonToken, node2.colonToken) &&
        testNodes(
            node1, node2, 'identifier', node1.identifier, node2.identifier);
  }

  @override
  bool visitLabeledStatement(
      LabeledStatement node1, covariant LabeledStatement node2) {
    return testNodes(node1, node2, 'labels', node1.labels, node2.labels) &&
        testNodes(node1, node2, 'statement', node1.statement, node2.statement);
  }

  @override
  bool visitLibraryDependency(
      LibraryDependency node1, covariant LibraryDependency node2) {
    return visitLibraryTag(node1, node2) &&
        testNodes(node1, node2, 'uri', node1.uri, node2.uri) &&
        testNodes(node1, node2, 'conditionalUris', node1.conditionalUris,
            node2.conditionalUris) &&
        testNodes(
            node1, node2, 'combinators', node1.combinators, node2.combinators);
  }

  @override
  bool visitLibraryName(LibraryName node1, covariant LibraryName node2) {
    return visitLibraryTag(node1, node2) &&
        testTokens(node1, node2, 'libraryKeyword', node1.libraryKeyword,
            node2.libraryKeyword) &&
        testNodes(node1, node2, 'name', node1.name, node2.name);
  }

  @override
  bool visitLibraryTag(LibraryTag node1, covariant LibraryTag node2) {
    // TODO(johnniwinther): Check metadata?
    return true;
  }

  @override
  bool visitLiteral(Literal node1, covariant Literal node2) {
    return testTokens(node1, node2, 'token', node1.token, node2.token);
  }

  @override
  bool visitLiteralBool(LiteralBool node1, covariant LiteralBool node2) {
    return visitLiteral(node1, node2);
  }

  @override
  bool visitLiteralDouble(LiteralDouble node1, covariant LiteralDouble node2) {
    return visitLiteral(node1, node2);
  }

  @override
  bool visitLiteralInt(LiteralInt node1, covariant LiteralInt node2) {
    return visitLiteral(node1, node2);
  }

  @override
  bool visitLiteralList(LiteralList node1, covariant LiteralList node2) {
    return testTokens(node1, node2, 'constKeyword', node1.constKeyword,
            node2.constKeyword) &&
        testNodes(node1, node2, 'typeArguments', node1.typeArguments,
            node2.typeArguments) &&
        testNodes(node1, node2, 'elements', node1.elements, node2.elements);
  }

  @override
  bool visitLiteralMap(LiteralMap node1, covariant LiteralMap node2) {
    return testTokens(node1, node2, 'constKeyword', node1.constKeyword,
            node2.constKeyword) &&
        testNodes(node1, node2, 'typeArguments', node1.typeArguments,
            node2.typeArguments) &&
        testNodes(node1, node2, 'entries', node1.entries, node2.entries);
  }

  @override
  bool visitLiteralMapEntry(
      LiteralMapEntry node1, covariant LiteralMapEntry node2) {
    return testTokens(
            node1, node2, 'colonToken', node1.colonToken, node2.colonToken) &&
        testNodes(node1, node2, 'key', node1.key, node2.key) &&
        testNodes(node1, node2, 'value', node1.value, node2.value);
  }

  @override
  bool visitLiteralNull(LiteralNull node1, covariant LiteralNull node2) {
    return visitLiteral(node1, node2);
  }

  @override
  bool visitLiteralString(LiteralString node1, covariant LiteralString node2) {
    return testTokens(node1, node2, 'token', node1.token, node2.token) &&
        strategy.test(
            node1, node2, 'dartString', node1.dartString, node2.dartString);
  }

  @override
  bool visitLiteralSymbol(LiteralSymbol node1, covariant LiteralSymbol node2) {
    return testTokens(
            node1, node2, 'hashToken', node1.hashToken, node2.hashToken) &&
        testNodes(
            node1, node2, 'identifiers', node1.identifiers, node2.identifiers);
  }

  @override
  bool visitLoop(Loop node1, covariant Loop node2) {
    return testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'body', node1.body, node2.body);
  }

  @override
  bool visitMetadata(Metadata node1, covariant Metadata node2) {
    return testTokens(node1, node2, 'token', node1.token, node2.token) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitMixinApplication(
      MixinApplication node1, covariant MixinApplication node2) {
    return testNodes(
            node1, node2, 'superclass', node1.superclass, node2.superclass) &&
        testNodes(node1, node2, 'mixins', node1.mixins, node2.mixins);
  }

  @override
  bool visitModifiers(Modifiers node1, covariant Modifiers node2) {
    return strategy.test(node1, node2, 'flags', node1.flags, node2.flags) &&
        testNodes(node1, node2, 'nodes', node1.nodes, node2.nodes);
  }

  @override
  bool visitNamedArgument(NamedArgument node1, covariant NamedArgument node2) {
    return testTokens(
            node1, node2, 'colonToken', node1.colonToken, node2.colonToken) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitNamedMixinApplication(
      NamedMixinApplication node1, covariant NamedMixinApplication node2) {
    return testTokens(node1, node2, 'classKeyword', node1.classKeyword,
            node2.classKeyword) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(node1, node2, 'typeParameters', node1.typeParameters,
            node2.typeParameters) &&
        testNodes(
            node1, node2, 'modifiers', node1.modifiers, node2.modifiers) &&
        testNodes(node1, node2, 'mixinApplication', node1.mixinApplication,
            node2.mixinApplication) &&
        testNodes(
            node1, node2, 'interfaces', node1.interfaces, node2.interfaces);
  }

  @override
  bool visitNewExpression(NewExpression node1, covariant NewExpression node2) {
    return testTokens(
            node1, node2, 'newToken', node1.newToken, node2.newToken) &&
        testNodes(node1, node2, 'send', node1.send, node2.send);
  }

  @override
  bool visitNodeList(NodeList node1, covariant NodeList node2) {
    return testTokens(
            node1, node2, 'beginToken', node1.beginToken, node2.beginToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        strategy.test(
            node1, node2, 'delimiter', node1.delimiter, node2.delimiter) &&
        testNodeLists(node1, node2, 'nodes', node1.nodes, node2.nodes);
  }

  @override
  bool visitOperator(Operator node1, covariant Operator node2) {
    return visitIdentifier(node1, node2);
  }

  @override
  bool visitParenthesizedExpression(
      ParenthesizedExpression node1, covariant ParenthesizedExpression node2) {
    return testTokens(
            node1, node2, 'beginToken', node1.beginToken, node2.beginToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitPart(Part node1, covariant Part node2) {
    return visitLibraryTag(node1, node2) &&
        testTokens(node1, node2, 'partKeyword', node1.partKeyword,
            node2.partKeyword) &&
        testNodes(node1, node2, 'uri', node1.uri, node2.uri);
  }

  @override
  bool visitPartOf(PartOf node1, covariant PartOf node2) {
    // TODO(johnniwinther): Check metadata?
    return testTokens(node1, node2, 'partKeyword', node1.partKeyword,
            node2.partKeyword) &&
        testNodes(node1, node2, 'name', node1.name, node2.name);
  }

  @override
  bool visitPostfix(Postfix node1, covariant Postfix node2) {
    return visitNodeList(node1, node2);
  }

  @override
  bool visitPrefix(Prefix node1, covariant Prefix node2) {
    return visitNodeList(node1, node2);
  }

  @override
  bool visitRedirectingFactoryBody(
      RedirectingFactoryBody node1, covariant RedirectingFactoryBody node2) {
    return testTokens(
            node1, node2, 'beginToken', node1.beginToken, node2.beginToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(node1, node2, 'constructorReference',
            node1.constructorReference, node2.constructorReference);
  }

  @override
  bool visitRethrow(Rethrow node1, covariant Rethrow node2) {
    return testTokens(
            node1, node2, 'throwToken', node1.throwToken, node2.throwToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken);
  }

  @override
  bool visitReturn(Return node1, covariant Return node2) {
    return testTokens(
            node1, node2, 'beginToken', node1.beginToken, node2.beginToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitSend(Send node1, covariant Send node2) {
    return strategy.test(node1, node2, 'isConditional', node1.isConditional,
            node2.isConditional) &&
        testNodes(node1, node2, 'receiver', node1.receiver, node2.receiver) &&
        testNodes(node1, node2, 'selector', node1.selector, node2.selector) &&
        testNodes(node1, node2, 'argumentsNode', node1.argumentsNode,
            node2.argumentsNode);
  }

  @override
  bool visitSendSet(SendSet node1, covariant SendSet node2) {
    return visitSend(node1, node2) &&
        testNodes(node1, node2, 'assignmentOperator', node1.assignmentOperator,
            node2.assignmentOperator);
  }

  @override
  bool visitStringInterpolation(
      StringInterpolation node1, covariant StringInterpolation node2) {
    return testNodes(node1, node2, 'string', node1.string, node2.string) &&
        testNodes(node1, node2, 'parts', node1.parts, node2.parts);
  }

  @override
  bool visitStringInterpolationPart(
      StringInterpolationPart node1, covariant StringInterpolationPart node2) {
    return testNodes(
        node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitStringJuxtaposition(
      StringJuxtaposition node1, covariant StringJuxtaposition node2) {
    return testNodes(node1, node2, 'first', node1.first, node2.first) &&
        testNodes(node1, node2, 'second', node1.second, node2.second);
  }

  @override
  bool visitSwitchCase(SwitchCase node1, covariant SwitchCase node2) {
    return testTokens(node1, node2, 'defaultKeyword', node1.defaultKeyword,
            node2.defaultKeyword) &&
        testTokens(
            node1, node2, 'startToken', node1.startToken, node2.startToken) &&
        testNodes(node1, node2, 'labelsAndCases', node1.labelsAndCases,
            node2.labelsAndCases) &&
        testNodes(
            node1, node2, 'statements', node1.statements, node2.statements);
  }

  @override
  bool visitSwitchStatement(
      SwitchStatement node1, covariant SwitchStatement node2) {
    return testTokens(node1, node2, 'switchKeyword', node1.switchKeyword,
            node2.switchKeyword) &&
        testNodes(node1, node2, 'parenthesizedExpression',
            node1.parenthesizedExpression, node2.parenthesizedExpression) &&
        testNodes(node1, node2, 'cases', node1.cases, node2.cases);
  }

  @override
  bool visitSyncForIn(SyncForIn node1, covariant SyncForIn node2) {
    return visitForIn(node1, node2);
  }

  @override
  bool visitThrow(Throw node1, covariant Throw node2) {
    return testTokens(
            node1, node2, 'throwToken', node1.throwToken, node2.throwToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitTryStatement(TryStatement node1, covariant TryStatement node2) {
    return testTokens(
            node1, node2, 'tryKeyword', node1.tryKeyword, node2.tryKeyword) &&
        testTokens(node1, node2, 'finallyKeyword', node1.finallyKeyword,
            node2.finallyKeyword) &&
        testNodes(node1, node2, 'tryBlock', node1.tryBlock, node2.tryBlock) &&
        testNodes(node1, node2, 'catchBlocks', node1.catchBlocks,
            node2.catchBlocks) &&
        testNodes(node1, node2, 'finallyBlock', node1.finallyBlock,
            node2.finallyBlock);
  }

  @override
  bool visitNominalTypeAnnotation(
      NominalTypeAnnotation node1, covariant NominalTypeAnnotation node2) {
    return testNodes(
            node1, node2, 'typeName', node1.typeName, node2.typeName) &&
        testNodes(node1, node2, 'typeArguments', node1.typeArguments,
            node2.typeArguments);
  }

  @override
  bool visitFunctionTypeAnnotation(
      FunctionTypeAnnotation node1, covariant FunctionTypeAnnotation node2) {
    return testNodes(
            node1, node2, 'returnType', node1.returnType, node2.returnType) &&
        testNodes(node1, node2, 'formals', node1.formals, node2.formals) &&
        testNodes(node1, node2, 'typeParameters', node1.typeParameters,
            node2.typeParameters);
  }

  @override
  bool visitTypeVariable(TypeVariable node1, covariant TypeVariable node2) {
    return testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(node1, node2, 'bound', node1.bound, node2.bound);
  }

  @override
  bool visitTypedef(Typedef node1, covariant Typedef node2) {
    return testTokens(node1, node2, 'typedefKeyword', node1.typedefKeyword,
            node2.typedefKeyword) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'returnType', node1.returnType, node2.returnType) &&
        testNodes(node1, node2, 'name', node1.name, node2.name) &&
        testNodes(node1, node2, 'typeParameters', node1.templateParameters,
            node2.templateParameters) &&
        testNodes(node1, node2, 'formals', node1.formals, node2.formals);
  }

  @override
  bool visitVariableDefinitions(
      VariableDefinitions node1, covariant VariableDefinitions node2) {
    return testNodes(
            node1, node2, 'metadata', node1.metadata, node2.metadata) &&
        testNodes(node1, node2, 'type', node1.type, node2.type) &&
        testNodes(
            node1, node2, 'modifiers', node1.modifiers, node2.modifiers) &&
        testNodes(
            node1, node2, 'definitions', node1.definitions, node2.definitions);
  }

  @override
  bool visitWhile(While node1, covariant While node2) {
    return testTokens(node1, node2, 'whileKeyword', node1.whileKeyword,
            node2.whileKeyword) &&
        testNodes(
            node1, node2, 'condition', node1.condition, node2.condition) &&
        testNodes(node1, node2, 'body', node1.body, node2.body);
  }

  @override
  bool visitYield(Yield node1, covariant Yield node2) {
    return testTokens(
            node1, node2, 'yieldToken', node1.yieldToken, node2.yieldToken) &&
        testTokens(
            node1, node2, 'starToken', node1.starToken, node2.starToken) &&
        testTokens(node1, node2, 'endToken', node1.endToken, node2.endToken) &&
        testNodes(
            node1, node2, 'expression', node1.expression, node2.expression);
  }

  @override
  bool visitNode(Node node1, covariant Node node2) {
    throw new UnsupportedError('Unexpected nodes: $node1 <> $node2');
  }

  @override
  bool visitExpression(Expression node1, covariant Expression node2) {
    throw new UnsupportedError('Unexpected nodes: $node1 <> $node2');
  }

  @override
  bool visitStatement(Statement node1, covariant Statement node2) {
    throw new UnsupportedError('Unexpected nodes: $node1 <> $node2');
  }

  @override
  bool visitStringNode(StringNode node1, covariant StringNode node2) {
    throw new UnsupportedError('Unexpected nodes: $node1 <> $node2');
  }

  @override
  bool visitTypeAnnotation(
      TypeAnnotation node1, covariant TypeAnnotation node2) {
    throw new UnsupportedError('Unexpected nodes: $node1 <> $node2');
  }
}

bool areMetadataAnnotationsEquivalent(
    MetadataAnnotation metadata1, MetadataAnnotation metadata2) {
  if (metadata1 == metadata2) return true;
  if (metadata1 == null || metadata2 == null) return false;
  return areElementsEquivalent(
          metadata1.annotatedElement, metadata2.annotatedElement) &&
      areConstantsEquivalent(metadata1.constant, metadata2.constant);
}

class NativeBehaviorFilters {
  static const int NORMAL_TYPE = 0;
  static const int THIS_TYPE = 1;
  static const int SPECIAL_TYPE = 2;

  static int getTypeKind(var type) {
    if (type is DartType) {
      // TODO(johnniwinther): Remove this when annotation are no longer resolved
      // to this-types.
      if (type is InterfaceType &&
          type.typeArguments.isNotEmpty &&
          type.typeArguments.first is TypeVariableType) {
        return THIS_TYPE;
      }
      return NORMAL_TYPE;
    }
    return SPECIAL_TYPE;
  }

  /// Returns a list of the non-this-type [ResolutionDartType]s in [types].
  static List<ResolutionDartType> filterDartTypes(List types) {
    return types.where((type) => getTypeKind(type) == NORMAL_TYPE).toList();
  }

  // TODO(johnniwinther): Remove this when annotation are no longer resolved
  // to this-types.
  /// Returns a list of the classes of this-types in [types].
  static List<Element> filterThisTypes(List types) {
    return types
        .where((type) => getTypeKind(type) == THIS_TYPE)
        .map((type) => type.element)
        .toList();
  }

  /// Returns a list of the names of the [SpecialType]s in [types].
  static List<String> filterSpecialTypes(List types) {
    return types.where((type) => getTypeKind(type) == SPECIAL_TYPE).map((t) {
      SpecialType type = t;
      return type.name;
    }).toList();
  }
}

/// Visitor that computes a node-index mapping.
class AstIndexComputer extends Visitor {
  final Map<Node, int> nodeIndices = <Node, int>{};
  final List<Node> nodeList = <Node>[];

  @override
  visitNode(Node node) {
    nodeIndices.putIfAbsent(node, () {
      // Some nodes (like Modifier and empty NodeList) can be reused.
      nodeList.add(node);
      return nodeIndices.length;
    });
    node.visitChildren(this);
  }
}
