.pragma library

function hasOwn(object, name) {
    return object && Object.prototype.hasOwnProperty.call(object, name)
}

function dependencyType(choice) {
    if (choice === "slideshow")
        return "directory"
    if (choice === "image" || choice === "video")
        return "file"
    return ""
}

function hasResource(value) {
    if (Array.isArray(value))
        return value.length > 0
    return typeof value === "string" && value.trim().length > 0
}

function effectiveValue(spec, definitions, active) {
    const requested = hasOwn(active, spec.name) ? active[spec.name] : spec.webValue
    const requiredType = dependencyType(requested)
    if (spec.type !== "combo" || !requiredType)
        return requested

    const dependencies = []
    const reference = spec.name + ".value"
    const quotedChoice = "'" + requested + "'"
    for (let index = 0; index < definitions.length; ++index) {
        const candidate = definitions[index]
        const condition = String(candidate.condition || "")
        if (candidate.type === requiredType
                && condition.indexOf(reference) >= 0
                && condition.indexOf(quotedChoice) >= 0)
            dependencies.push(candidate)
    }
    if (!dependencies.length)
        return requested

    for (let index = 0; index < dependencies.length; ++index) {
        const dependency = dependencies[index]
        const value = hasOwn(active, dependency.name) ? active[dependency.name] : dependency.webValue
        if (hasResource(value))
            return requested
    }

    if (hasOwn(spec, "presetValue"))
        return spec.presetValue
    if (hasOwn(spec, "default"))
        return spec.default
    return ""
}
