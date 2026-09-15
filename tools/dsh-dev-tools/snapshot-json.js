// Lossless JSON snapshot semantics aligned with @deepseek-ai/dsh-util-values 0.1.6-alpha.1.
function hasIntrinsicConstructor(prototype, name) {
  const descriptor = Object.getOwnPropertyDescriptor(prototype, 'constructor')
  const constructor = descriptor?.value
  if (typeof constructor !== 'function') return false
  try {
    return constructor.name === name
      && constructor.prototype === prototype
      && Function.prototype.toString.call(constructor) === `function ${name}() { [native code] }`
  } catch {
    return false
  }
}

function isIntrinsicObjectPrototype(value) {
  return Object.getPrototypeOf(value) === null && hasIntrinsicConstructor(value, 'Object')
}

function hasPlainArrayPrototype(value) {
  const prototype = Object.getPrototypeOf(value)
  if (!Array.isArray(prototype) || !hasIntrinsicConstructor(prototype, 'Array')) return false
  const objectPrototype = Object.getPrototypeOf(prototype)
  return typeof objectPrototype === 'object'
    && objectPrototype !== null
    && isIntrinsicObjectPrototype(objectPrototype)
}

function hasPlainObjectPrototype(value) {
  const prototype = Object.getPrototypeOf(value)
  return prototype === null
    || typeof prototype === 'object' && isIntrinsicObjectPrototype(prototype)
}

function enumerableStringKeys(value) {
  const keys = Reflect.ownKeys(value)
  if (keys.some((key) => typeof key !== 'string' || !Object.prototype.propertyIsEnumerable.call(value, key))) return undefined
  return keys
}

export function snapshotJsonValue(value) {
  const ancestors = new Set()
  let root
  const assign = (destination, item) => {
    if (destination === undefined) return
    if (destination.kind === 'root') {
      root = item
    } else if (destination.kind === 'array') {
      destination.target[destination.index] = item
    } else {
      Object.defineProperty(destination.target, destination.key, {
        value: item,
        enumerable: true,
        configurable: true,
        writable: true,
      })
    }
  }

  const tasks = [{ kind: 'visit', value, destination: { kind: 'root' } }]
  for (let task = tasks.pop(); task !== undefined; task = tasks.pop()) {
    if (task.kind === 'leave') {
      ancestors.delete(task.source)
      continue
    }
    if (task.kind === 'array-item') {
      if (!Object.prototype.hasOwnProperty.call(task.source, task.index)) return undefined
      tasks.push({
        kind: 'visit',
        value: task.source[task.index],
        destination: { kind: 'array', target: task.target, index: task.index },
      })
      continue
    }
    if (task.kind === 'object-property') {
      tasks.push({
        kind: 'visit',
        value: task.source[task.key],
        destination: { kind: 'object', target: task.target, key: task.key },
      })
      continue
    }

    const current = task.value
    if (current === null) {
      assign(task.destination, null)
      continue
    }
    if (typeof current === 'boolean' || typeof current === 'string') {
      assign(task.destination, current)
      continue
    }
    if (typeof current === 'number') {
      if (!Number.isFinite(current) || Object.is(current, -0)) return undefined
      assign(task.destination, current)
      continue
    }
    if (typeof current !== 'object' || ancestors.has(current)) return undefined

    if (Array.isArray(current)) {
      if (!hasPlainArrayPrototype(current)) return undefined
      const length = current.length
      if (Reflect.ownKeys(current).length !== length + 1) return undefined
      const target = []
      assign(task.destination, target)
      ancestors.add(current)
      tasks.push({ kind: 'leave', source: current })
      for (let index = length - 1; index >= 0; index--) {
        tasks.push({ kind: 'array-item', source: current, index, target })
      }
      continue
    }

    if (!hasPlainObjectPrototype(current)) return undefined
    const keys = enumerableStringKeys(current)
    if (keys === undefined) return undefined
    const target = {}
    assign(task.destination, target)
    ancestors.add(current)
    tasks.push({ kind: 'leave', source: current })
    for (let index = keys.length - 1; index >= 0; index--) {
      const key = keys[index]
      if (key === undefined) return undefined
      tasks.push({ kind: 'object-property', source: current, key, target })
    }
  }
  return root
}
