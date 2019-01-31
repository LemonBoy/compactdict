## A compact dictionary implementation based on CPython's implementation.
##
## The insertion order of the elements is preserved.
import hashes
from sequtils import filterIt

type
  DictItem[K, V] = ref object
    hash: Hash
    key: K
    val: V

  SparseArray = distinct pointer

  Dict*[K, V] = object
    alloc: int # Number of allocated elements in the indices array
    avail: int # Number of available slots
    used:  int # Number of used slots (non free & non deleted)
    items: seq[DictItem[K, V]]
    indices: SparseArray

template availFromAlloc(s: int): int = (s shl 1) div 3
template allocFromAvail(a: int): int = (3 * a + 1) shr 1

const
  SLOT_EMPTY   = -1
  SLOT_DELETED = -2

  DEFAULT_SIZE  = 42
  DEFAULT_ALLOC = 64

template isPowerOfTwo(x: untyped): untyped = x != 0 and ((x and (x - 1)) == 0)

static:
  doAssert isPowerOfTwo(DEFAULT_ALLOC),
    "The default allocation size for the indices array must be a power of two"

template nextTry(h, maxHash: Hash): untyped = ((5*h) + 1) and maxHash

template `[]`(s: SparseArray, i: int): int =
  var v: int
  if d.alloc <= 0xff:
    v = cast[ptr UncheckedArray[int8]](s)[i]
  elif d.alloc <= 0xffff:
    v = cast[ptr UncheckedArray[int16]](s)[i]
  elif d.alloc <= 0xffffffff:
    v = cast[ptr UncheckedArray[int32]](s)[i]
  else:
    doAssert false
  v

template `[]=`(s: SparseArray, i: int, val: int) =
  if d.alloc <= 0xff:
    cast[ptr UncheckedArray[int8]](s)[i] = int8(val)
  elif d.alloc <= 0xffff:
    cast[ptr UncheckedArray[int16]](s)[i] = int16(val)
  elif d.alloc <= 0xffffffff:
    cast[ptr UncheckedArray[int32]](s)[i] = int32(val)
  else:
    doAssert false

proc c_memset(p: pointer, value: cint, size: csize): pointer {.
  importc: "memset", header: "<string.h>", discardable.}
proc nimSetMem(a: pointer, v: cint, size: Natural) {.inline.} =
  c_memset(a, v, size)

proc rehash[K, V](d: var Dict[K, V], newAlloc: int) =
  assert isPowerOfTwo(newAlloc)

  let perElem =
    if newAlloc <= 0xff: 1
    elif newAlloc <= 0xffff: 2
    elif newAlloc <= 0xffffffff: 4
    else: 8

  if newAlloc != d.alloc:
    d.indices = SparseArray(realloc(d.indices.pointer, perElem * newAlloc))
    nimSetMem(d.indices.pointer, -1, perElem * newAlloc)
  d.alloc = newAlloc
  d.avail = availFromAlloc(newAlloc)
  # Drop all the deleted items
  d.items = d.items.filterIt(it != nil)

  # Re-populate the hash table
  for i, it in d.items:
    let (i1, _) = d.lookup(it.key, it.hash)
    d.indices[i1] = i

proc initDict*[K, V](initialSize = DEFAULT_SIZE): Dict[K, V] =
  var allocSize = 1
  while allocSize < initialSize:
    allocSize = allocSize shl 1
  result.rehash(allocSize)

proc lookup*[K, V](d: Dict[K, V], key: K, h: Hash): (int, int) =
  let mask = d.alloc - 1
  var i = h and mask

  while true:
    let idx = d.indices[i]

    if idx == SLOT_EMPTY:
      return (i, idx)
    elif idx != SLOT_DELETED:
      if d.items[idx].hash == h and d.items[idx].key == key:
        return (i, idx)

    i = nextTry(i, mask)

  doAssert false

proc add*[K, V](d: var Dict[K, V], key: K, val: V) =
  # Don't check `used` here as that doesn't take into account the slots marked
  # as deleted
  if d.items.len == d.avail:
    # Double the size for every reallocation. If `alloc` is zero the object may
    # be uninitialized so let's use a safe value
    d.rehash(if d.alloc > 0: d.alloc shl 1 else: DEFAULT_ALLOC)

  let h = hash(key)
  let (i1, i2) = d.lookup(key, h)

  case i2:
  of SLOT_EMPTY:
    # Insert the item in the dictionary
    d.items.add(DictItem[K, V](hash: h, key: key, val: val))
    d.indices[i1] = d.items.high
    inc d.used
  of SLOT_DELETED:
    doAssert false
  else:
    # Replace an existing item w/ matching key, replace the value only
    d.items[i2].val = val

proc get*[K, V](d: Dict[K, V], key: K): V =
  let h = hash(key)
  let (_, i2) = d.lookup(key, h)

  if i2 == SLOT_EMPTY:
    when compiles($key):
      raise newException(KeyError, "key not found: " & $key)
    else:
      raise newException(KeyError, "key not found")

  result = d.items[i2].val

proc del*[K, V](d: var Dict[K, V], key: K) =
  let h = hash(key)
  let (i1, i2) = d.lookup(key, h)

  if i2 < 0: return

  d.items[i2] = nil
  d.indices[i1] = SLOT_DELETED

  dec d.used

proc contains*[K, V](d: Dict[K, V], key: K): bool =
  let h = hash(key)
  let (_, i2) = d.lookup(key, h)

  return (i2 >= 0)

proc `[]=`*[K, V](d: var Dict[K, V], key: K, val: V) =
  d.add(key, val)

proc `[]`*[K, V](d: Dict[K, V], key: K): V =
  d.get(key)

proc toDict*[K, V](pairs: openArray[(K,V)]): Dict[K, V] =
  result = initDict[K, V](pairs.len)
  for kv in pairs:
    result[kv[0]] = kv[1]

proc len*[K, V](d: Dict[K, V]): int =
  d.used

proc clear*[K, V](d: var Dict[K, V]) =
  d.items.setLen(0)
  d.used = 0
  # Lazy way to reset the inner state
  d.rehash(d.alloc)

proc `==`*[K, V](d1, d2: Dict[K, V]): bool =
  if d1.len != d2.len:
    return false

  var i1 = 0
  var i2 = 0

  while i1 < d1.items.len and i2 < d2.items.len:
    while d1.items[i1] == nil: inc i1
    while d2.items[i2] == nil: inc i2

    if d1.items[i1][] != d2.items[i2][]:
      return false

    inc i1
    inc i2

  result = true

iterator pairs*[K, V](d: Dict[K, V]): (K, V) =
  for it in d.items:
    if it != nil:
      yield (it.key, it.val)

proc `$`*[K, V](d: Dict[K, V]): string =
  if d.len == 0:
    result = "{:}"
  else:
    result = "{"
    for key, val in pairs(d):
      if result.len > 1: result.add(", ")
      result.addQuoted(key)
      result.add(": ")
      result.addQuoted(val)
    result.add("}")

when isMainModule:
  var x: Dict[string, int]
  echo x.repr

  for i in 0..<255:
    x.add("foo" & $i, i)

  echo "added!"

  echo x.get("foo128")
  x.del("foo129")
  echo x.len

  echo x

  let x1 = {"foo": 4, "bar": 5}.toDict()
  echo x1.len
  for x, y in pairs(x1): echo x, "=", y
  doAssert x1["foo"] == 4
  doAssert x1["bar"] == 5
  doAssertRaises(KeyError):
    discard x1["baz"]
  let x2 = {"foo": 4, "bar": 5}.toDict()
  doAssert x1 == x2
  var x3 = {"foo": 4, "qux": 99, "bar": 5}.toDict()
  doAssert x1 != x3
  x3.del("qux")
  doAssert x1 == x3
  echo x1
  echo x2
  echo x3
