## A compact dictionary implementation based on CPython's implementation.
##
## The insertion order of the elements is preserved.
import hashes
from bitops import fastLog2

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

  GROWTH_FACTOR = 2

  DICT_DEFAULT_SIZE  = 10

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

proc rehash[K, V](d: var Dict[K, V], newSize: int) =
  # Find the next power of two so that we're able to hold at least ``newSize``
  # entries
  var newAlloc = 1 shl (1 + fastLog2(allocFromAvail(newSize)))
  # Element size for each entry in the indices array
  let perElem =
    if newAlloc <= 0xff: 1
    elif newAlloc <= 0xffff: 2
    elif newAlloc <= 0xffffffff: 4
    else: 8

  # Do we have any SLOT_EMPTY in the ``items`` seq?
  let hasDeletedItems = d.used != d.avail

  d.alloc = newAlloc
  d.avail = availFromAlloc(newAlloc)
  d.indices = SparseArray(realloc(d.indices.pointer, perElem * newAlloc))
  # Set all the slots to SLOT_EMPTY
  nimSetMem(d.indices.pointer, -1, perElem * newAlloc)

  if hasDeletedItems:
    let oldItems = d.items
    d.items = newSeqOfCap[type(d.items[0])](d.used)
    # Drop all the deleted items
    for it in oldItems:
      if it != nil: d.items.add(it)

  assert(d.items.len == d.used)

  # Re-populate the hash table
  for i, it in d.items:
    let (i1, _) = d.lookup(it.key, it.hash)
    d.indices[i1] = i

proc initDict*[K, V](initialSize = DICT_DEFAULT_SIZE): Dict[K, V] =
  result.rehash(initialSize)

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
  # Is there room for another element?
  # Don't check `used` here as that doesn't take into account the slots marked
  # as deleted
  if d.items.len == d.avail:
    if d.alloc > 0:
      # Calculate the new size according to how full the table is
      d.rehash(d.used * GROWTH_FACTOR)
    else:
      # If `alloc` is zero the object may be uninitialized so let's use a safe
      # value
      d.rehash(DICT_DEFAULT_SIZE)

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
  d.rehash(DICT_DEFAULT_SIZE)

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

iterator keys*[K, V](d: Dict[K, V]): K =
  for it in d.items:
    if it != nil:
      yield it.key

iterator values*[K, V](d: Dict[K, V]): V =
  for it in d.items:
    if it != nil:
      yield it.val

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

proc `=destroy`*[K, V](d: var Dict[K, V]) =
  d.alloc = 0
  d.avail = 0
  d.used = 0
  if d.indices.pointer != nil:
    dealloc(d.indices.pointer)
  d.indices = SparseArray(nil)
  d.items.setLen(0)
