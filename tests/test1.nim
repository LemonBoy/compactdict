import unittest
import compactdict

test "Add & remove cycle":
  var x: Dict[string, int]

  for i in 0 ..< 0xffff: x.add("foo" & $i, i)
  check(x.len == 0xffff)
  for i in 0 ..< 0xffff: x.del("foo" & $i)
  check(x.len == 0)
  for i in 0 ..< 0xffff: x.add("foo" & $i, i)
  check(x.len == 0xffff)
  for i in 0 ..< 0xffff: x.del("foo" & $i)
  check(x.len == 0)

test "String representation":
  var x1 = {"foo": 42, "bar": 9}.toDict
  check($x1 == "{\"foo\": 42, \"bar\": 9}")
  var x2: Dict[int, int]
  check($x2 == "{:}")

test "Raises KeyError":
  var x1 = {"foo": 42, "bar": 9}.toDict

  check:
    x1["foo"] == 42
    x1["bar"] == 9
  expect KeyError:
    discard x1["baz"]

test "Equality check":
  let x1 = {"foo": 4, "bar": 5}.toDict
  let x2 = {"foo": 4, "bar": 5}.toDict
  var x3 = {"foo": 4, "qux": 99, "bar": 5}.toDict()
  check:
    x1 == x2
    x1 != x3
  x3.del("qux")
  check(x1 == x3)

test "Operations on empty dicts":
  var x: Dict[string, string]
  check:
    $x == "{:}"
    x.getOrDefault("aaa", "0") == "0"
  x.del("foo")
  expect KeyError:
    discard x.get("foo")

test "getOrDefault":
  var x: Dict[string, string]
  x.add("foo", "bar")
  x.add("bar", "foo")
  check:
    x.getOrDefault("foo", "123") == "bar"
    x.getOrDefault("baz", "123") == "123"
