// Lossless JSON snapshot semantics aligned with @deepseek-ai/dsh-util-values 0.1.2-rc.1.
export function snapshotJsonValue(value) {
  const ancestors = new Set()

  function visit(current) {
    if (current === null || typeof current === 'string' || typeof current === 'boolean') return current
    if (typeof current === 'number') {
      if (!Number.isFinite(current) || Object.is(current, -0)) return undefined
      return current
    }
    if (typeof current !== 'object' || ancestors.has(current)) return undefined

    if (Array.isArray(current)) {
      if (Object.getPrototypeOf(current) !== Array.prototype) return undefined
      if (Reflect.ownKeys(current).length !== current.length + 1) return undefined
      ancestors.add(current)
      const output = []
      for (let index = 0; index < current.length; index++) {
        if (!Object.prototype.hasOwnProperty.call(current, index)) {
          ancestors.delete(current)
          return undefined
        }
        const item = visit(current[index])
        if (item === undefined) {
          ancestors.delete(current)
          return undefined
        }
        output.push(item)
      }
      ancestors.delete(current)
      return output
    }

    const prototype = Object.getPrototypeOf(current)
    if (prototype !== Object.prototype && prototype !== null) return undefined
    const keys = Reflect.ownKeys(current)
    if (keys.some((key) => typeof key !== 'string' || !Object.prototype.propertyIsEnumerable.call(current, key))) return undefined
    ancestors.add(current)
    const output = {}
    for (const key of keys) {
      const item = visit(current[key])
      if (item === undefined) {
        ancestors.delete(current)
        return undefined
      }
      Object.defineProperty(output, key, {
        value: item,
        enumerable: true,
        configurable: true,
        writable: true,
      })
    }
    ancestors.delete(current)
    return output
  }

  return visit(value)
}
