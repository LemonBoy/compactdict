CompactDict
===========

A compact dictionary implementation kindly borrowed from Python.

### Features

- The insertion order is preserved
- No need to initialize the `Dict` object before using it
- More memory efficient for small & medium sized collections
- Same API as stdlib's `Table`

### Examples

```nim
var x = {"foo": 1, "bar": 2}.toDict()
echo x["foo"] # prints 1
for k, v in x.pairs():
  echo k, " = ", v # prints "foo" = 1 and "bar" = 2
```
