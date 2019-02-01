import unittest
import compactdict

test "Add & remove cycle":
  var x: Dict[string, int]

  for i in 0 ..< 0xffff: x.add("foo" & $i, i)
  doAssert(x.len == 0xffff)
  for i in 0 ..< 0xffff: x.del("foo" & $i)
  doAssert(x.len == 0) 
  for i in 0 ..< 0xffff: x.add("foo" & $i, i)
  doAssert(x.len == 0xffff) 
  for i in 0 ..< 0xffff: x.del("foo" & $i)
  doAssert(x.len == 0)

test "String representation":
  var x1 = {"foo": 42, "bar": 9}.toDict
  doAssert($x1 == "{\"foo\": 42, \"bar\": 9}")
  var x2: Dict[int, int]
  doAssert($x2 == "{:}")

test "Raises KeyError":
  var x1 = {"foo": 42, "bar": 9}.toDict

  doAssert(x1["foo"] == 42)
  doAssert(x1["bar"] == 9)
  doAssertRaises(KeyError): discard x1["baz"]

test "Equality check":
  let x1 = {"foo": 4, "bar": 5}.toDict
  let x2 = {"foo": 4, "bar": 5}.toDict
  var x3 = {"foo": 4, "qux": 99, "bar": 5}.toDict()
  doAssert(x1 == x2)
  doAssert(x1 != x3)
  x3.del("qux")
  doAssert(x1 == x3)
