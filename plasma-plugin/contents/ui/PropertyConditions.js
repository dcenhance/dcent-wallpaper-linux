.pragma library

function tokenize(source) {
    var tokens = []
    var index = 0
    var operators = ["===", "!==", "==", "!=", ">=", "<=", "&&", "||", ">", "<", "!", "+", "-", "*", "/", "%"]
    while (index < source.length) {
        var character = source[index]
        if (/\s/.test(character)) {
            index += 1
            continue
        }
        if (character === "'" || character === '"') {
            var quote = character
            var value = ""
            var closed = false
            index += 1
            while (index < source.length) {
                character = source[index]
                if (character === quote) {
                    index += 1
                    closed = true
                    break
                }
                if (character === "\\") {
                    index += 1
                    if (index >= source.length)
                        return null
                    var escaped = source[index]
                    var escapeMap = { "n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v" }
                    if (escaped === "u") {
                        var hex = source.slice(index + 1, index + 5)
                        if (!/^[0-9a-fA-F]{4}$/.test(hex))
                            return null
                        value += String.fromCharCode(parseInt(hex, 16))
                        index += 5
                        continue
                    }
                    value += escapeMap[escaped] !== undefined ? escapeMap[escaped] : escaped
                    index += 1
                    continue
                }
                value += character
                index += 1
            }
            if (!closed)
                return null
            tokens.push({ kind: "literal", value: value })
            continue
        }
        var numberMatch = source.slice(index).match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/)
        if (numberMatch) {
            tokens.push({ kind: "literal", value: Number(numberMatch[0]) })
            index += numberMatch[0].length
            continue
        }
        var identifierMatch = source.slice(index).match(/^[A-Za-z_$][A-Za-z0-9_$]*/)
        if (identifierMatch) {
            var name = identifierMatch[0]
            if (name === "true")
                tokens.push({ kind: "literal", value: true })
            else if (name === "false")
                tokens.push({ kind: "literal", value: false })
            else if (name === "null")
                tokens.push({ kind: "literal", value: null })
            else
                tokens.push({ kind: "identifier", value: name })
            index += name.length
            continue
        }
        if ("()[],.".indexOf(character) >= 0) {
            tokens.push({ kind: character, value: character })
            index += 1
            continue
        }
        var matchedOperator = ""
        for (var operatorIndex = 0; operatorIndex < operators.length; ++operatorIndex) {
            var candidate = operators[operatorIndex]
            if (source.slice(index, index + candidate.length) === candidate) {
                matchedOperator = candidate
                break
            }
        }
        if (!matchedOperator)
            return null
        tokens.push({ kind: "operator", value: matchedOperator })
        index += matchedOperator.length
    }
    return tokens
}

function parse(source) {
    if (typeof source !== "string" || !source.trim())
        return { type: "literal", value: true }
    source = source.trim()
    while (source.length > 0 && source[source.length - 1] === ";")
        source = source.slice(0, -1).trim()
    if (source.indexOf(";") >= 0)
        return null
    var tokens = tokenize(source)
    if (tokens === null)
        return null
    var position = 0
    var precedence = {
        "||": 1,
        "&&": 2,
        "==": 3, "!=": 3, "===": 3, "!==": 3,
        ">": 3, ">=": 3, "<": 3, "<=": 3,
        "+": 4, "-": 4,
        "*": 5, "/": 5, "%": 5
    }

    function current() {
        return position < tokens.length ? tokens[position] : null
    }

    function consume(kind, value) {
        var token = current()
        if (!token || token.kind !== kind || (value !== undefined && token.value !== value))
            return null
        position += 1
        return token
    }

    function primary() {
        var token = current()
        var node = null
        if (!token)
            return null
        if (token.kind === "literal") {
            position += 1
            node = { type: "literal", value: token.value }
        } else if (token.kind === "identifier") {
            position += 1
            node = { type: "identifier", name: token.value }
        } else if (consume("(")) {
            node = expression(0)
            if (!node || !consume(")"))
                return null
        } else if (consume("[")) {
            var elements = []
            if (!consume("]")) {
                while (true) {
                    var element = expression(0)
                    if (!element)
                        return null
                    elements.push(element)
                    if (consume("]"))
                        break
                    if (!consume(","))
                        return null
                }
            }
            node = { type: "array", elements: elements }
        } else {
            return null
        }

        while (consume(".")) {
            var member = consume("identifier")
            if (!member)
                return null
            var memberNode = { type: "member", object: node, name: member.value }
            if (consume("(")) {
                var argumentsList = []
                if (!consume(")")) {
                    while (true) {
                        var argument = expression(0)
                        if (!argument)
                            return null
                        argumentsList.push(argument)
                        if (consume(")"))
                            break
                        if (!consume(","))
                            return null
                    }
                }
                node = { type: "call", callee: memberNode, arguments: argumentsList }
            } else {
                node = memberNode
            }
        }
        return node
    }

    function unary() {
        var token = current()
        if (token && token.kind === "operator" && (token.value === "!" || token.value === "+" || token.value === "-")) {
            position += 1
            var argument = unary()
            return argument ? { type: "unary", operator: token.value, argument: argument } : null
        }
        return primary()
    }

    function expression(minimumPrecedence) {
        var left = unary()
        if (!left)
            return null
        while (true) {
            var token = current()
            if (!token || token.kind !== "operator")
                break
            var tokenPrecedence = precedence[token.value]
            if (tokenPrecedence === undefined || tokenPrecedence < minimumPrecedence)
                break
            position += 1
            var right = expression(tokenPrecedence + 1)
            if (!right)
                return null
            left = { type: "binary", operator: token.value, left: left, right: right }
        }
        return left
    }

    var result = expression(0)
    return result && position === tokens.length ? result : null
}

function validNode(node) {
    if (!node)
        return false
    if (node.type === "literal" || node.type === "identifier")
        return true
    if (node.type === "array") {
        for (var elementIndex = 0; elementIndex < node.elements.length; ++elementIndex) {
            if (!validNode(node.elements[elementIndex]))
                return false
        }
        return true
    }
    if (node.type === "unary")
        return ["!", "+", "-"].indexOf(node.operator) >= 0 && validNode(node.argument)
    if (node.type === "binary")
        return ["||", "&&", "==", "!=", "===", "!==", ">", ">=", "<", "<=", "+", "-", "*", "/", "%"].indexOf(node.operator) >= 0 && validNode(node.left) && validNode(node.right)
    if (node.type === "member")
        return ["value", "min", "max", "text"].indexOf(node.name) >= 0 && validNode(node.object)
    if (node.type === "call") {
        if (!node.callee || node.callee.type !== "member" || ["startsWith", "includes"].indexOf(node.callee.name) < 0)
            return false
        if (!validNode(node.callee.object) || node.arguments.length !== 1 || !validNode(node.arguments[0]))
            return false
        return true
    }
    return false
}

function isSupported(condition) {
    return validNode(parse(condition))
}

function evaluateNode(node, values) {
    if (node.type === "literal")
        return node.value
    if (node.type === "identifier") {
        if (!Object.prototype.hasOwnProperty.call(values, node.name))
            throw new Error("Missing property " + node.name)
        return values[node.name]
    }
    if (node.type === "array") {
        var arrayResult = []
        for (var elementIndex = 0; elementIndex < node.elements.length; ++elementIndex)
            arrayResult.push(evaluateNode(node.elements[elementIndex], values))
        return arrayResult
    }
    if (node.type === "member") {
        var objectValue = evaluateNode(node.object, values)
        if (objectValue === null || objectValue === undefined || typeof objectValue !== "object")
            throw new Error("Invalid property member")
        return objectValue[node.name]
    }
    if (node.type === "unary") {
        var unaryValue = evaluateNode(node.argument, values)
        if (node.operator === "!") return !unaryValue
        if (node.operator === "+") return +unaryValue
        return -unaryValue
    }
    if (node.type === "call") {
        var receiver = evaluateNode(node.callee.object, values)
        var argument = evaluateNode(node.arguments[0], values)
        if (node.callee.name === "startsWith")
            return String(receiver).indexOf(String(argument)) === 0
        if (node.callee.name === "includes") {
            if (Array.isArray(receiver))
                return receiver.indexOf(argument) >= 0
            return String(receiver).indexOf(String(argument)) >= 0
        }
        throw new Error("Unsupported method")
    }
    if (node.type === "binary") {
        if (node.operator === "&&")
            return Boolean(evaluateNode(node.left, values)) && Boolean(evaluateNode(node.right, values))
        if (node.operator === "||")
            return Boolean(evaluateNode(node.left, values)) || Boolean(evaluateNode(node.right, values))
        var left = evaluateNode(node.left, values)
        var right = evaluateNode(node.right, values)
        switch (node.operator) {
        case "==": return left == right
        case "!=": return left != right
        case "===": return left === right
        case "!==": return left !== right
        case ">": return left > right
        case ">=": return left >= right
        case "<": return left < right
        case "<=": return left <= right
        case "+": return left + right
        case "-": return left - right
        case "*": return left * right
        case "/": return left / right
        case "%": return left % right
        }
    }
    throw new Error("Unsupported condition")
}

function evaluate(condition, values) {
    var tree = parse(condition)
    if (!validNode(tree))
        return true
    try {
        return Boolean(evaluateNode(tree, values || {}))
    } catch (error) {
        return true
    }
}
