
// Represents an array literal expression (e.g., [1, 2, 3]) in the AST

// ArrayLiteral "constructor"
def makeArrayLiteral(elements, position) {
    let literal = {};
    literal["type"] = "ArrayLiteral";
    // Always store a shallow-unique array (never null: default to empty)
    if (elements == null) {
        literal["elements"] = [];
    } else {
        literal["elements"] = elements;
    }
    literal["position"] = position;
    // Attach evaluate and toJson "methods" (as map fields)
    literal["evaluate"] = evaluateArrayLiteral;
    literal["toJson"] = arrayLiteralToJson;
    literal["toGo"] = arrayLiteralToGo;
    return literal;
}

// Evaluates the array literal node to a runtime array of values
def evaluateArrayLiteral(self, context) {
    // Build new array for evaluated element values
    let values = [];
    let i = 0;
    let elems = self["elements"];
    let n = len(elems);

    while (i < n) {
        let element = elems[i];
        // "Node" is assumed to be represented as a map with ["evaluate"]
        let result = element["evaluate"](element, context);
        push(values, result);
        i = i + 1;
    }
    return values;
}

// Converts ArrayLiteral node to JSON string representation
def arrayLiteralToJson(self) {
    let elems = self["elements"];
    let n = len(elems);

    // Build JSON for elements
    let i = 0;
    let elementsParts = [];

    while (i < n) {
        let element = elems[i];
        let part = "null";
        if (element != null) {
            part = element["toJson"](element);
        }
        push(elementsParts, part);
        i = i + 1;
    }

    // Join elements with comma + space
    // let elementsJson = joinWithCommaSpace(elementsParts); // No longer needed

    // return '{ "type": "ArrayLiteral", "position": "' + self["position"] + '", "elements": [ ' + elementsJson + ' ] }';
    let result = {};
    result["type"] = "ArrayLiteral";
    result["position"] = self["position"];
    result["elements"] = elementsParts;
    return result;
}

def arrayLiteralToGo(self) {
    // Phase 2: emit Node tree; evalArrayLit handles construction
    print('&Node{kind: nkArrayLit, list: []*Node{');

    let elems = self["elements"];
    let n = len(elems);
    let i = 0;
    while (i < n) {
        if (i > 0) {
            print(',');
        }
        let element = elems[i];
        if (element["toGo"] != null) {
            element["toGo"](element);
        }
        i = i + 1;
    }

    print('}}');
}

// Helper: join array of strings with ", "
def joinWithCommaSpace(strs) {
    let n = len(strs);
    if (n == 0) {
        return "";
    }
    let result = strs[0];
    let i = 1;
    while (i < n) {
        result = result + ", " + strs[i];
        i = i + 1;
    }
    return result;
}



def isTruthy(value) {
    if (value == null) {
        return false;
    }
    if (typeof(value) == "boolean") {
        return value;
    }
    if (typeof(value) == "number") {
        if (value != 0) {
            return true;
        } else {
            return false;
        }
    }
    if (typeof(value) == "string") {
        if (len(value) > 0) {
            return true;
        } else {
            return false;
        }
    }
    // All other objects are truthy
    return true;
}

def EvaluatorIsTruthy(val) { // INTEGRATION
    return isTruthy(val);
}

def applyPrefixOperator(operator, value) {
    if (operator == "-") {
        if (typeof(value) == "number") {
            return 0 - value;
        }
        return null;
    }
    if (operator == "!") {
        if (isTruthy(value)) {
            return false;
        } else {
            return true;
        }
    }
    return null;
}

def Evaluator_applyPrefixOperator(operator, rightValue) { //INTEGRATION
    return applyPrefixOperator(operator, rightValue);
}



def applyInfixOperator(left, operator, right) {
    // Check numeric operations first (most common)
    if (typeof(left) == "number" && typeof(right) == "number") {
        let leftVal = left;
        let rightVal = right;
        if (operator == "+") {
            return leftVal + rightVal;
        }
        if (operator == "-") {
            return leftVal - rightVal;
        }
        if (operator == "*") {
            return leftVal * rightVal;
        }
        if (operator == "/") {
            return leftVal / rightVal;
        }
        if (operator == "%") {
            return leftVal % rightVal;
        }
        if (operator == "<") {
            return leftVal < rightVal;
        }
        if (operator == ">") {
            return leftVal > rightVal;
        }
        if (operator == "<=") {
            return leftVal <= rightVal;
        }
        if (operator == ">=") {
            return leftVal >= rightVal;
        }
        if (operator == "==") {
            return leftVal == rightVal;
        }
        if (operator == "!=") {
            return leftVal != rightVal;
        }
    }
    
    if (operator == "+") {
        if (typeof(left) == "array" && typeof(right) == "array") {
            // More efficient array concatenation
            let leftLen = len(left);
            let rightLen = len(right);
            let resultList = [];
            
            // Pre-allocate result size if possible by pushing elements
            let i = 0;
            while (i < leftLen) {
                push(resultList, left[i]);
                i = i + 1;
            }
            i = 0;
            while (i < rightLen) {
                push(resultList, right[i]);
                i = i + 1;
            }
            return resultList;
        }
        if (typeof(left) == "string" || typeof(right) == "string") {
            let leftStr = "";
            let rightStr = "";
            if (left == null) { leftStr = "null"; } else { leftStr = stringValue(left); }
            if (right == null) { rightStr = "null"; } else { rightStr = stringValue(right); }
            
            return leftStr + rightStr;
        }
    }
    
    if (operator == "&&") {
        if (isTruthy(left) && isTruthy(right)) {
            return true;
        } else {
            return false;
        }
    }
    if (operator == "||") {
        if (isTruthy(left) || isTruthy(right)) {
            return true;
        } else {
            return false;
        }
    }
    if (operator == "==") {
        if (left == null) {
            if (right == null) {
                return true;
            } else {
                return false;
            }
        } else {
            if (leftEquals(left, right)) {
                return true;
            } else {
                return false;
            }
        }
    }
    if (operator == "!=") {
        if (left == null) {
            if (right != null) {
                return true;
            } else {
                return false;
            }
        } else {
            if (!leftEquals(left, right)) {
                return true;
            } else {
                return false;
            }
        }
    }
    return null;
}

def stringValue(value) {
    if (typeof(value) == "string") {
        return value;
    }
    if (typeof(value) == "number") {
        return numberToString(value);
    }
    if (typeof(value) == "boolean") {
        if (value) {
            return "true";
        } else {
            return "false";
        }
    }
    if (value == null) {
        return "null";
    }
    // For arrays and maps, simplified representation:
    if (typeof(value) == "array") {
        let result = "[";
        let i = 0;
        while (i < len(value)) {
            if (i != 0) {
                result = result + ",";
            }
            result = result + stringValue(value[i]);
            i = i + 1;
        }
        return result + "]";
    }
    if (typeof(value) == "map") {
        let result = "{";
        let k = keys(value);
        let i = 0;
        while (i < len(k)) {
            if (i != 0) {
                result = result + ",";
            }
            let keyStr = "";
            if (typeof(k[i]) == "string") {
                keyStr = k[i];
            } else {
                keyStr = numberToString(k[i]);
            }
            result = result + keyStr + ":" + stringValue(value[k[i]]);
            i = i + 1;
        }
        return result + "}";
    }
    // Unknown types fallback
    return "";
}

def numberToString(num) {
    return string(num);
}

def leftEquals(left, right) {
    // We must manually compare primitive types only
    if (typeof(left) != typeof(right)) {
        return false;
    }
    if (typeof(left) == "string" || typeof(left) == "number" || typeof(left) == "boolean") {
        return left == right;
    }
    // For null
    if (left == null && right == null) {
        return true;
    }
    // For arrays and maps, we consider unequal.
    return false;
}





// Create an IndexExpression AST node as a map with methods attached
def makeIndexExpression(collectionNode, indexNode, position) {
    let node = {
        "type": "IndexExpression",
        "collection": collectionNode,
        "index": indexNode,
        "position": position
    }

    def evaluate(self,context) {
    
        // Evaluate collection
        let collectionObject = node["collection"]["evaluate"](node["collection"], context)
        // Evaluate index
        let indexValue = node["index"]["evaluate"](node["index"],context)

        if (isArray(collectionObject)) {
            return node["evaluateArrayIndex"](collectionObject, indexValue)
        } else {
            let mapType = false
            if (collectionObject != null) {
                // Check if all keys are not consecutive integers from 0...N-1 with "_isArray"==true
                let k = 0
                let keyList = keys(collectionObject)
                // Naive detection: treat any non-array non-null map as a map
                if (len(keyList) > 0) {
                    mapType = true
                    // But if only "_isArray" as key, treat as array (empty array)
                    if (len(keyList) == 1) {
                        if (keyList[0] == "_isArray") {
                            mapType = false
                        }
                    }
                } else {
                    mapType = true
                }
            }
            if (mapType) {
                return node["evaluateMapIndex"](collectionObject, indexValue)
            }
        }
        throwRuntimeError(
            "Cannot use index operator on non-collection value, got: " + collectionObject,
            node["position"]["line"],
            node["position"]["column"] // FIXME throw, catch, halt, etc not supported
        )
        return null
    }
    node["evaluate"] = evaluate;

    def evaluateArrayIndex(array, indexValue) {
        //puts("DEBUG: evaluateArrayIndex(" + array + "," + indexValue + ")"); // FIXME remove DEBUG code
        // Only numbers allowed for array index
        /*let numeric = false
        if (indexValue != null) {
            if ((indexValue + 0) == indexValue) {
                numeric = true
            }
        }
        if (!(numeric)) {
            throwRuntimeError(
                "Array index must be a number, got: " + indexValue,
                node["position"]["line"],
                node["position"]["column"]
            )
        }*/

        let idx = indexValue /* + 0 */
        let arrayLength = len(array)
        //if ("_isArray" in array) { // ???
        //    arrayLength = array["length"]
        //}
        // Bounds check
        if (idx < 0 || idx >= arrayLength) {
            throwRuntimeError(
                "Array index out of bounds: " + idx + ", array size: " + arrayLength,
                node["position"]["line"],
                node["position"]["column"]
            )
        }

        // Return array element by index
        return array[idx]
    }
    node["evaluateArrayIndex"] = evaluateArrayIndex;

    def evaluateMapIndex(map, key) {
        //puts("DEBUG: evaluateMapIndex(" + map + "," + key + ")"); // FIXME remove DEBUG code
        let isString = false
        let isNumber = false
        if (key != null) {
            if ((key + "") == key) {
                isString = true
            }
            if ((key + 0) == key) {
                isNumber = true
            }
        }
        if (!(isString || isNumber)) {
            // Position info (node) not available in this scope, using placeholders.
            throwRuntimeError(
                "Map key must be a string or number, got: " + key,
                -1, // Placeholder for line (original was node["position"]["line"])
                -1  // Placeholder for column (original was node["position"]["column"])
            )
        }

        // Optimized: Directly return map[key], assuming non-existent keys result in null.
        // This relies on the behavior observed in 'lookupKeyword' where 'keywords[identifier] != null' is used.
        return map[key];
    }
    node["evaluateMapIndex"]=evaluateMapIndex;

    // Manual toJson attached
    def toJson(self) {
        let collectionJson = "null"
        let indexJson = "null"
        if (node["collection"] != null) {
            collectionJson = node["collection"]["toJson"](node["collection"])
        }
        if (node["index"] != null) {
            indexJson = node["index"]["toJson"](node["index"])
        }
        // position should be stringified, assuming position already a string
        // return '{ "type": "IndexExpression", "position": "' + node["position"] + '", "collection": ' + collectionJson + ', "index": ' + indexJson + ' }'
        let result = {};
        result["type"] = "IndexExpression";
        result["position"] = node["position"];
        result["collection"] = collectionJson; // collectionJson is already map or null
        result["index"] = indexJson; // indexJson is already map or null
        return result;
    }
    node["toJson"] = toJson;

    def toGo(self) {
        // Phase 2: emit Node tree; evalIndex handles Get
        print('&Node{kind: nkIndex, left: ');
        if (self["collection"]["toGo"] != null) {
            self["collection"]["toGo"](self["collection"]);
        }
        print(', right: ');
        if (node["index"]["toGo"] != null) {
            node["index"]["toGo"](node["index"]);
        }
        print('}');
    }
    node["toGo"] = toGo;

    return node
}



// FYI: Node is an abstract class and cannot be represented properly, but nested class Position can

// Position "class" as a map constructor and related functions

def makePosition(line, column) {
    let pos = {
        "line": line,
        "column": column
    };
    pos["getLine"] = positionGetLine;
    pos["getColumn"] = positionGetColumn;
    pos["toString"] = positionToString;
    return pos;
}

def positionGetLine(self) {
    return self["line"];
}

def positionGetColumn(self) {
    return self["column"];
}

def positionToString(self) {
    return "" + self["line"] + ":" + self["column"];
}


// ReturnStatement node representation in InterpreterJ

let ReturnStatement = {};

// Constructor: def ReturnStatement_create(value, position)
def ReturnStatement_create(value, position) {
    let node = {};
    node["type"] = "ReturnStatement";
    node["value"] = value;
    node["position"] = position;

    // Attach evaluate function
    node["evaluate"] = ReturnStatement_evaluate;

    // Attach toJson function
    node["toJson"] = ReturnStatement_toJson;
    node["toGo"] = ReturnStatement_toGo;

    return node;
}

let returnValueIndicatorMagicValue = "isReturnValue" + random(); //DIRTY HACK

// def ReturnStatement_evaluate(self, context)
def ReturnStatement_evaluate(self, context) {

    //puts("DEBUG: return eval!"); //FIXME remove DEBUG code

    let valueResult = null;
    if (self["value"] != null) {
        valueResult = self["value"]["evaluate"](self["value"], context);
    } else {
        valueResult = null;
    }

    // ReturnValue wrapper
    let returnValue = {};
    returnValue["value"] = valueResult;
    returnValue[returnValueIndicatorMagicValue]  = true;
    return returnValue;
}

// def ReturnStatement_toJson(self)
def ReturnStatement_toJson(self) {
    let valueJson = "null";
    if (self["value"] != null) {
        valueJson = self["value"]["toJson"](self["value"]);
    }
    // return '{ "type": "ReturnStatement", "position": "' + self["position"] + '", "value": ' + valueJson + ' }';
    let result = {};
    result["type"] = "ReturnStatement";
    result["position"] = self["position"];
    result["value"] = valueJson; // valueJson is already a map or null
    return result;
}

def ReturnStatement_toGo(self) {
    // Phase 2: emit Node tree; evalReturn handles propagation
    print('&Node{kind: nkReturn');
    if (self["value"] != null) {
        print(', right: ');
        if (self["value"]["toGo"] != null) {
            self["value"]["toGo"](self["value"]);
        }
    }
    print('}');
}



// WhileStatement node as procedural map

  def makeWhileStatement(condition, body, position) {
    let node = {
      "type": "WhileStatement",
      "position": position,
      "condition": condition,
      "body": body
    };
    
    def evaluate(self,context) {
      let result = null;
      // Cache references to avoid repeated lookups
      let condition = node["condition"];
      let conditionEval = condition["evaluate"];
      let body = node["body"];
      let bodyEval = body["evaluate"];
      
      // Loop
      while (EvaluatorIsTruthy(conditionEval(condition, context))) {

        result = bodyEval(body, context);
        // If result is a ReturnValue, stop loop and propagate
        if (isReturnValue(result)) {
          return result;
        }
      }
      return result;
    }
    node["evaluate"] = evaluate;

    def toJson(self) {
      let conditionJson = null; 
      if (node["condition"] != null) {
        conditionJson = node["condition"]["toJson"](node["condition"]);
      } else {
        // do nothing
      }
      let bodyJson = null; 
      if (node["body"] != null) {
        bodyJson = node["body"]["toJson"](node["body"]);
      } else {
        // do nothing
      }
      // return '{ "type": "WhileStatement", "position": "' + node["position"] + '", "condition": ' + conditionJson + ', "body": ' + bodyJson + ' }';
      let result = {};
      result["type"] = "WhileStatement";
      result["position"] = node["position"];
      result["condition"] = conditionJson; // conditionJson is already a map or null
      result["body"] = bodyJson; // bodyJson is already a map or null
      return result;
    }
    node["toJson"] = toJson;

    def toGo(self) {
      // Phase 2: emit Node tree; evalWhile handles looping
      print('&Node{kind: nkWhileStmt, left: ');
      conditionToGoBool(self["condition"]);
      print(', body: ');
      if (self["body"]["toGo"] != null) {
        self["body"]["toGo"](self["body"]);
      }
      print('}');
    }
    node["toGo"] = toGo;

    return node;
  }
  

// Helper to check ReturnValue duplicate
/* def isReturnValue(result) {
    if (result == null) {
        return false;
    } else {
        if (isMap(result)) { // FIXME result handling to support return
            let keysArr = keys(result);
            let i = 0;
            while (i < len(keysArr)) {
                if (keysArr[i] == "isReturnValue") {
                    return result["isReturnValue"] == true;
                }
                i = i + 1;
            }
        }
        return false;
    }
} */



// AssignmentStatement representation as a map with helper functions attached manually.
// Object-Oriented structure and methods replaced with procedural style.

def makeAssignmentStatement(name, value, position) {
    let node = {
        "type": "AssignmentStatement",
        "name": name,
        "value": value,
        "position": position
    };

    // Attach toJson function explicitly
    node["toJson"] = assignmentStatementToJson;
    node["toGo"] = assignmentStatementToGo;
    // Attach evaluate function explicitly
    node["evaluate"] = assignmentStatementEvaluate;
    return node;
}

// assignmentStatementToJson function: returns JSON representation
def assignmentStatementToJson(self) {
    let valueJson = "null";
    if (self["value"] != null) {
        // Assumes that value has "toJson" function attached if it's not null
        valueJson = self["value"]["toJson"](self["value"]);
    } else {
        valueJson = null; 
    }
    // return '{ "type": "AssignmentStatement", "position": "' + self["position"] +
    //     '", "name": "' + self["name"] +
    //     '", "value": ' + valueJson + ' }';
    let result = {};
    result["type"] = "AssignmentStatement";
    result["position"] = self["position"];
    result["name"] = self["name"];
    result["value"] = valueJson; // valueJson is already a map or null
    return result;
}

def assignmentStatementToGo(self) {
    // Phase 2.5: project resolver annotation so evalAssign can skip the
    // ctx.Exists + ctx.Update two-walks-per-write cost on the rkParam /
    // rkLocal / rkLib hot paths. Unannotated nodes (the bootstrap
    // identity case) fall through to the default Exists/Update/Create.
    print('&Node{kind: nkAssign, name: "' + self["name"] + '"');
    if (self["resolvedKind"] != null) {
        print(", resolvedKind: ");
        print(resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
    }
    print(', right: ');
    if (self["value"]["toGo"] != null) {
        self["value"]["toGo"](self["value"]);
    }
    print('}');
}

// assignmentStatementEvaluate function: calls value's evaluate and assigns to context
def assignmentStatementEvaluate(self, context) {
    // Evaluate the value expression and assign in one step
    let value = self["value"];
    let valueResult = null;
    if (value != null) {
        valueResult = value["evaluate"](value, context);
    }
    // Direct assignment
    return context["assign"](context, self["name"], valueResult, self["position"]);
}



// ExpressionStatement representation in InterpreterJ

// Create a new ExpressionStatement node as a map
def makeExpressionStatement(expression, position) {
    let node = { 
        "type": "ExpressionStatement", 
        "position": position, 
        "expression": expression
    };
    node["evaluate"] = evaluateExpressionStatement;
    node["toJson"] = toJsonExpressionStatement;
    node["toGo"] = toGoJsonExpressionStatement;

    return node;
}

// Evaluates the expression (procedurally, null if missing)
def evaluateExpressionStatement(self, context) {
    if (self["expression"] == null) {
        return null;
    } else {
        // Assumes expression node has "evaluate" as a field
        return self["expression"]["evaluate"](self["expression"], context);
    }
}

// Serializes the node as JSON-like string (strings are NOT escaped)
def toJsonExpressionStatement(self) {
    let expr = "null";
    if (self["expression"] != null) {
        // Assumes expression node has "toJson" as a field
        expr = self["expression"]["toJson"](self["expression"]);
    } else {
        expr = null;
    }
    // return '{ "type": "ExpressionStatement", "position": "' + self["position"] + '", "expression": ' + expr + ' }';
    let result = {};
    result["type"] = "ExpressionStatement";
    result["position"] = self["position"];
    result["expression"] = expr; // expr is already a map or null
    return result;
}

def toGoJsonExpressionStatement(self) {
    // Phase 2: emit Node tree for expression statement
    let expr = self["expression"];
    if (expr == null) {
        print('&Node{kind: nkExprStmt}');
        return;
    }
    print('&Node{kind: nkExprStmt, left: ');
    if (expr["toGo"] != null) {
        expr["toGo"](expr);
    }
    print('}');
}



// InfixExpression node constructor and functions in InterpreterJ

def makeInfixExpression(left, operator, right, position) {
    let node = {
        "type": "InfixExpression",
        "left": left,
        "operator": operator,
        "right": right,
        "position": position
    };
    // Attach functions manually as fields
    node["evaluate"] = evaluateInfixExpression;
    node["toJson"] = infixExpressionToJson;
    node["toGo"] = infixExpressionToGo;
    return node;
}

// Phase 2: operator string -> op code constant name
def opCodeFor(op) {
    if (op == "+") { return "opAdd"; }
    if (op == "-") { return "opSub"; }
    if (op == "*") { return "opMul"; }
    if (op == "/") { return "opDiv"; }
    if (op == "%") { return "opMod"; }
    if (op == "==") { return "opEq"; }
    if (op == "!=") { return "opNeq"; }
    if (op == "<") { return "opLt"; }
    if (op == "<=") { return "opLte"; }
    if (op == ">") { return "opGt"; }
    if (op == ">=") { return "opGte"; }
    if (op == "&&") { return "opAnd"; }
    if (op == "||") { return "opOr"; }
    if (op == "!") { return "opNot"; }
    return "opAdd";
}

// Evaluate the infix expression: wraps tracking, evaluation, and operator application
def evaluateInfixExpression(self, context) {
    // Evaluate left and right operands
    let left = self["left"];
    let leftValue = left["evaluate"](left, context);
    
    let right = self["right"];
    let rightValue = right["evaluate"](right, context);
    
    // Apply operator and return
    return applyInfixOperator(leftValue, self["operator"], rightValue);
}

// Export to JSON string (no newlines or escapes in string literals)
def infixExpressionToJson(self) {
    let leftJson = "null";
    let rightJson = "null";
    let operatorString = "";
    if (self["left"] != null) {
        leftJson = self["left"]["toJson"](self["left"]);
    } else {
        leftJson = "null";
    }
    if (self["right"] != null) {
        rightJson = self["right"]["toJson"](self["right"]);
    } else {
        rightJson = "null";
    }
    operatorString = self["operator"];
    let positionString = self["position"];
    // let json = '{ "type": "InfixExpression", "position": "' + positionString + '", "left": ' + leftJson + ', "operator": "' + operatorString + '", "right": ' + rightJson + ' }';
    // return json;
    let result = {};
    result["type"] = "InfixExpression";
    result["position"] = positionString;
    result["left"] = leftJson; // leftJson is already map or null
    result["operator"] = operatorString;
    result["right"] = rightJson; // rightJson is already map or null
    return result;
}

def infixExpressionToGo(self) {
    // Phase 2: emit Node tree; evalInfix handles operator dispatch
    print('&Node{kind: nkInfix, op: ' + opCodeFor(self["operator"]) + ', left: ');
    if (self["left"]["toGo"] != null) {
        self["left"]["toGo"](self["left"]);
    }
    print(', right: ');
    if (self["right"]["toGo"] != null) {
        self["right"]["toGo"](self["right"]);
    }
    print('}');
}



// NullLiteral node representation for InterpreterJ

// Creates a NullLiteral node: { "type": "NullLiteral", "position": ..., "evaluate": ..., "toJson": ... }
def makeNullLiteral(position) {
    let node = {
        "type": "NullLiteral",
        "position": position
    };
    node["evaluate"] = nullLiteralEvaluate;
    node["toJson"] = nullLiteralToJson;
    node["toGo"] = nullLiteralToGo;
    return node;
}

// Evaluates the NullLiteral node (always returns null)
def nullLiteralEvaluate(self, context) {
    return null;
}

// Produces JSON for the NullLiteral node, strictly no string escaping
def nullLiteralToJson(self) {
    // let json = '{ "type": "NullLiteral", "position": "' + self["position"] + '", "value": null }';
    // return json;
    let result = {};
    result["type"] = "NullLiteral";
    result["position"] = self["position"];
    result["value"] = null;
    return result;
}

def nullLiteralToGo(self) {
    print('&Node{kind: nkNullLit}');
}



def makeReturnValue(value, position) { // FIXME called?
  let rv = {};
  rv["value"] = value;

  def getValue() {
    return rv["value"];
  }

  def toString() {
    let result = "Return(";
    if (rv["value"] == null) {
      result = result + "null";
    } else {
      result = result + toStringValue(rv["value"]);
    }
    result = result + ")";
    return result;
  }

  rv["getValue"] = getValue;
  rv["toString"] = toString;
  return rv;
}

// Helper function to convert a value to string representation
def toStringValue(val) {
  if (val == null) {
    return "null";
  }

  //if (val["toString"] != null) { // FIXME
  //  return val["toString"]();
  //}

  if (typeof(val) == "string") {
    return val;
  }
  
  if (typeof(val) == "number") {
    return "" + val;
  }
  
  if (typeof(val) == "boolean") {
    if (val == true) {
      return "true";
    } else {
      return "false";
    }
  }
  
  // Fallback: just convert to string as best effort
  return "" + val;
}



// BlockStatement "constructor"
def makeBlockStatement(statements, position) {
    let node = {
        "type": "BlockStatement",
        "position": position,
        "statements": []
    };
    if (statements != null) {
        let idx = 0;
        let stmtsLen = len(statements);
        while (idx < stmtsLen) {
            push(node["statements"], statements[idx]);
            idx = idx + 1;
        }
    }
    // Attach behavior functions
    node["addStatement"] = blockStatementAddStatement;
    node["evaluate"] = blockStatementEvaluate;
    node["toJson"] = blockStatementToJson;
    node["toGo"] = blockStatementToGo;
    return node;
}

// Add a statement to block (null-guard)
def blockStatementAddStatement(self, statement) {
    if (statement != null) {
        push(self["statements"], statement);
    }
}

// Evaluation logic
def blockStatementEvaluate(self, context) {
    // block scope
    let blockContext = null;
    if (context["extend"] != null) {
        blockContext = context["extend"](context);
    } else {
        blockContext = context; // fallback, non-scoped
    }
    let result = null;
    let idx = 0;
    let stmts = self["statements"];
    let stmtsLen = len(stmts);
    while (idx < stmtsLen) {
        let statement = stmts[idx];
        result = statement["evaluate"](statement, blockContext);
        // Simplified return value check - removed redundant null check
        if (isReturnValue(result)) {
            return result;
        }
        idx = idx + 1;
    }
    return result;
}

// Helper: test for ReturnValue (very minimal, expects you store type tags) - duplicate
/* def isReturnValue(obj) {
    if (obj == null) {
        return false;
    }
    if (obj["type"] == "ReturnValue") {
        return true;
    }
    return false;
} */

// toJson, no escaping or .join: manual string assembly
def blockStatementToJson(self) {
    let stmts = self["statements"];
    let stmtsLen = len(stmts);
    let arr = [];
    let idx = 0;
    while (idx < stmtsLen) {
        let statement = stmts[idx];
        if (statement["toJson"] != null) {
            let jsonVal = statement["toJson"](statement);
            push(arr, jsonVal);
        }
        idx = idx + 1;
    }
    // Manual join with comma and newline. (No .join. No escapes. You may only use real line breaks in code.)
    let elementsJson = "";
    idx = 0;
    let arrLen = len(arr);
    while (idx < arrLen) {
        // elementsJson = elementsJson + arr[idx]; // No longer needed
        // if (idx < arrLen - 1) { // No longer needed
        //     elementsJson = elementsJson + "," + chr(10); // No longer needed
        // } // No longer needed
        idx = idx + 1;
    }
    // return '{ "type": "BlockStatement", "position": "' + self["position"] + '", "statements": [ ' + elementsJson + ' ] }';
    let result = {};
    result["type"] = "BlockStatement";
    result["position"] = self["position"];
    result["statements"] = arr; // arr directly contains the maps from child toJson calls
    return result;
}

def blockStatementToGo(self) {
    // Phase 2.5: project hasLocals so evalBlock can skip its per-block
    // NewContext() allocation when the resolver tagged this block as
    // introducing zero bindings (resolvedLocals is empty). This is the
    // dominant alloc inside while/for bodies that don't declare any `let`.
    let stmts = self["statements"];
    let n = len(stmts);
    let locals = self["resolvedLocals"];
    let emitHasLocals = false;
    if (locals != null) {
        if (len(locals) > 0) {
            emitHasLocals = true;
        }
    }

    print('&Node{kind: nkBlock');
    if (emitHasLocals) {
        print(', hasLocals: true');
    }
    print(', list: []*Node{');

    let i = 0;
    while (i < n) {
        let stmt = stmts[i];
        if (stmt["toGo"] != null) {
            stmt["toGo"](stmt);
        }
        if (i < n - 1) {
            print(',');
        }
        i = i + 1;
    }

    print('}}');
}



// InterpreterJ: FunctionDeclaration node representation

// Create a FunctionDeclaration node map
def makeFunctionDeclaration(name, parameters, body, position) {
    let node = {
        "type": "FunctionDeclaration",
        "name": name,
        "parameters": parameters,
        "body": body,
        "position": position
    };
    node["evaluate"] = evaluateFunctionDeclaration;
    node["toJson"] = functionDeclarationToJson;
    node["toGo"] = functionDeclarationToGo;
    return node;
}

// Evaluate function for the FunctionDeclaration node
def evaluateFunctionDeclaration(node, context) { // FIXME really?
    // Create the function definition as a map
    def functionValue(args) {
        // P-VM.4: if the IJ-side bytecode compiler attached a chunk to this
        // node (ijvmAttachChunks; only when the IJ VM gate is on), run the
        // body as bytecode on a slot frame instead of tree-walking it. The
        // function VALUE stays this ordinary closure either way, so values
        // flow safely between VM-compiled and tree-walked code. defCtx =
        // the captured declaration context -- non-slot names chain into it
        // exactly like the tree-walk's functionContext parent chain.
        let ijvmCh = node["ijvmChunk"];
        if (ijvmCh != null) {
            return ijvmCallChunk(ijvmCh, context, args);
        }
        // Create a new context extended from the parent
        let functionContext = extendContext(context);

        // Bind each parameter to its argument (or null if absent)
        let params = node["parameters"];
        let paramCount = len(params);
        let argCount = len(args);
        let i = 0;
        while (i < paramCount) {
            let param = params[i];
            let arg = null;
            if (i < argCount) {
                arg = args[i];
            }
            functionContext["define"](functionContext, param, arg);
            i = i + 1;
        }

        // Evaluate the body in the new function context
        let result = node["body"]["evaluate"](node["body"], functionContext);

        // Unwrap ReturnValue if present (assuming ReturnValue is a map with "value" field)
        if (isReturnValue(result)) {
            return result["value"];
        } else {
            return result;
        }
    }

    // P-VM.5d: stamp the chunk + captured ctx + this layer's stack onto the
    // native FunctionCommand beneath functionValue, so the op-5 native fast
    // path can call the chunk directly (no Execute round trip, no arg
    // wrapping). Gated: under IJ_VM_NATEXEC=0 the stamp is never read and
    // the fallback path stays byte-for-byte identical to P-VM.4 behavior.
    if (ijvmUseNativeExec) {
        let tagCh = node["ijvmChunk"];
        if (tagCh != null) {
            ijvmTagFn(functionValue, tagCh, context, ijvmStack);
        }
    }

    // Place the function definition as a callable in context, under the function's name
    context["define"](context, node["name"], functionValue);

    // Return nothing or null as this is a declaration statement
    return null;
}

// Helper: isReturnValue(result)
// Checks if result is a map with key "isReturnValue" set to true.
// MUST type-check before indexing: under Phase-2 emit, scalar[key] returns
// tInvalid, which evalInfix/evalProgram propagate as a fatal abort. The
// IJ tree-walker frequently calls this with non-map results (e.g. a puts
// callee returning Value{tag:tInt,i:0}) — without the isMap guard, every
// non-map statement result terminates the surrounding evaluate-loop.
def isReturnValue(result) {
    if (result == null) {
        return false;
    }
    if (!isMap(result)) {
        return false;
    }
    return result[returnValueIndicatorMagicValue] == true;
}

// toJson for FunctionDeclaration
def functionDeclarationToJson(node) {
    // Build parameters as JSON array of quoted strings
    let elementsArr = [];
    let i = 0;
    while (i < len(node["parameters"])) {
        let quoted = '"' + node["parameters"][i] + '"';
        push(elementsArr, quoted);
        i = i + 1;
    }
    let parametersJson = "";
    if (len(elementsArr) > 0) {
        parametersJson = elementsArr[0];
        i = 1;
        while (i < len(elementsArr)) {
            parametersJson = parametersJson + ", " + elementsArr[i];
            i = i + 1;
        }
    }

    // Handle body toJson
    let bodyJson = null; 
    if (node["body"] != null) {
        // Assume body is a map with a "toJson" function
        bodyJson = node["body"]["toJson"](node["body"]);
    }

    // Build and return the JSON string according to specification
    // let s = '{ "type": "FunctionDeclaration", "position": "' + node["position"] + '", "name": "' + node["name"] + '", "parameters": [ ' + parametersJson + ' ], "body": ' + bodyJson + ' }';
    // return s;
    let result = {};
    result["type"] = "FunctionDeclaration";
    result["position"] = node["position"];
    result["name"] = node["name"];
    // node["parameters"] is already an array of strings e.g. ["a", "b"]
    result["parameters"] = node["parameters"]; 
    result["body"] = bodyJson; // bodyJson is already a map or null
    return result;
}

def intString(i) { // HACK to compensate Java-based Interpreter error :-)
    let i = "" + i;
    if (endsWith(i,".0")) {
        i = substr(i, 0, len(i) - 2);
    }
    return i;
}

// Mangle an IJ identifier into a safe Go identifier (prefix "ij_").
// The IJ parser already restricts identifiers to [A-Za-z_][A-Za-z0-9_]*,
// so a simple prefix suffices and avoids collisions with Go builtins/keywords.
def mangle(name) {
    return "ij_" + name;
}

// Map the resolver's string-tagged annotation to the numeric rk* constant
// emitted at runtime. Used by *ToGo emitters to project resolvedKind onto
// Node literals so evalIdent/evalAssign/evalVarDecl can switch on it.
def resolverKindCode(kind, origin) {
    if (kind == "global") {
        if (origin == "lib") { return "rkLib"; }
        if (origin == "let") { return "rkGlobalLet"; }
        return "rkGlobal";
    }
    if (kind == "local") {
        if (origin == "param") { return "rkParam"; }
        return "rkLocal";
    }
    if (kind == "captured") { return "rkUpvalue"; }
    return "rkGlobal";
}

// ============================================================================
// Resolver pass: annotates the AST with scope/resolution info before toGo.
//
// For every Identifier / VariableDeclaration / AssignmentStatement /
// FunctionDeclaration node, adds:
//   node["resolvedKind"] = "local" | "captured" | "global"
//   node["resolvedName"] = mangle(node["name"])   (unused for "global")
//
// For every BlockStatement / FunctionDeclaration, adds:
//   node["resolvedLocals"] = [names of `let` and `def` declared in this scope]
//
// "local"    -> declared in the same function as the reference.
// "captured" -> declared in an enclosing function (Go closure capture will
//               make it work automatically).
// "global"   -> declared at the top-level (root) scope, OR not declared
//               anywhere that the resolver could see (fall back to ctx).
//
// The resolver uses hoisting semantics: all `let` and `def` in a block are
// visible throughout that block, matching IJ's runtime behaviour where
// mutual recursion at the same scope works regardless of textual order.
// ============================================================================

let resolverScopeIdCounter = 0;

def makeResolverScope(parent, isFunctionScope) {
    let s = {};
    s["parent"] = parent;
    s["isFunctionScope"] = isFunctionScope;
    s["locals"] = {};
    resolverScopeIdCounter = resolverScopeIdCounter + 1;
    s["id"] = resolverScopeIdCounter;
    return s;
}

// origin is one of: "param" | "let" | "def" | "lib"
def resolverScopeDeclare(scope, name, origin) {
    let localsMap = scope["locals"];
    localsMap[name] = origin;
}

// Names of built-in library functions registered by registerLibraryFunctions().
// Keep in sync with the emissions in goLibPrefix.
def libraryFunctionNames() {
    return [
        "puts", "gets", "assert", "push", "pop", "join", "keys", "values",
        "char", "len", "chr", "ord", "substr", "int", "string", "random",
        "typeof", "isArray", "isMap", "isNumber", "isString", "double",
        "echo", "print", "delete", "startsWith", "endsWith", "trim",
        "match", "findAll", "replace", "split", "getenv", "eputs", "hasKey",
        "ijvmCallNative", "ijvmTagFn"
    ];
}

def resolverScopeLookup(scope, name) {
    let s = scope;
    let crossedFunction = false;
    while (s != null) {
        let sLocals = s["locals"];
        let originHere = sLocals[name];
        if (originHere != null) {
            let r = {};
            r["origin"] = originHere;
            if (s["parent"] == null) {
                r["kind"] = "global";
            } else {
                if (crossedFunction) {
                    r["kind"] = "captured";
                } else {
                    r["kind"] = "local";
                }
            }
            return r;
        }
        if (s["isFunctionScope"]) {
            crossedFunction = true;
        }
        s = s["parent"];
    }
    let r = {};
    r["kind"] = "global";
    r["origin"] = null;
    return r;
}

def resolveNode(node, scope) {
    if (node == null) { return null; }
    if (!isMap(node)) { return null; }
    let t = node["type"];
    if (t == null) { return null; }

    if (t == "BlockStatement") { resolveBlockStatement(node, scope); return null; }
    if (t == "FunctionDeclaration") { resolveFunctionDeclaration(node, scope); return null; }
    if (t == "VariableDeclaration") { resolveVariableDeclaration(node, scope); return null; }
    if (t == "AssignmentStatement") { resolveAssignmentStatement(node, scope); return null; }
    if (t == "Identifier") { resolveIdentifier(node, scope); return null; }

    resolveGeneric(node, scope);
    return null;
}

def resolveBlockStatement(node, parentScope) {
    let s = makeResolverScope(parentScope, false);
    node["resolvedScope"] = s;
    let locals = [];
    node["resolvedLocals"] = locals;

    let stmts = node["statements"];
    if (stmts == null) { return null; }
    let n = len(stmts);

    // Sequential resolution: declarations become visible AFTER their
    // statement has been processed, so `let x = f(x)` resolves the RHS `x`
    // against the enclosing scope (matching IJ runtime semantics where
    // shadowing `let i = "" + i` is a common idiom).
    let i = 0;
    while (i < n) {
        let stmt = stmts[i];
        if (stmt != null) {
            resolveNode(stmt, s);
            let st = stmt["type"];
            if (st == "VariableDeclaration") {
                resolverScopeDeclare(s, stmt["name"], "let");
                push(locals, stmt["name"]);
            }
            if (st == "FunctionDeclaration") {
                resolverScopeDeclare(s, stmt["name"], "def");
                push(locals, stmt["name"]);
            }
        }
        i = i + 1;
    }
    return null;
}

def resolveFunctionDeclaration(node, parentScope) {
    let info = resolverScopeLookup(parentScope, node["name"]);
    node["resolvedKind"] = info["kind"];
    node["resolvedOrigin"] = info["origin"];
    node["resolvedName"] = mangle(node["name"]);
    // A `def` is at root only when its enclosing scope is the program root.
    // A nested `def` that happens to share a name with a top-level `def`
    // (e.g. mcp.s `def skipWhitespace(s,index)` inside `def mcp()` vs the
    // top-level lexer `def skipWhitespace(lexer)`) must NOT be emitted as a
    // package-level ij_<name> assignment or it would clobber the outer one
    // at runtime. Use resolvedAtRoot instead of resolvedKind/resolvedOrigin
    // to gate the C6 root-def emission.
    node["resolvedAtRoot"] = (parentScope["parent"] == null);

    let fnScope = makeResolverScope(parentScope, true);
    node["resolvedScope"] = fnScope;

    let params = node["parameters"];
    if (params != null) {
        let paramLocals = [];
        let pn = len(params);
        let i = 0;
        while (i < pn) {
            resolverScopeDeclare(fnScope, params[i], "param");
            push(paramLocals, params[i]);
            i = i + 1;
        }
        node["resolvedParamLocals"] = paramLocals;
    }

    resolveNode(node["body"], fnScope);

    // D1: decide whether this function's body can skip the per-call
    // NewContext() that FunctionCommand.Execute normally allocates. The
    // predicate is conservative: the body must NOT emit any ctx.Get /
    // ctx.Update / ctx.Create so that reusing the caller's ctx is
    // observationally identical. See analyzeIsStatic below.
    node["resolvedIsStatic"] = analyzeIsStatic(node["body"]);

    return null;
}

// Walk a function body and return true iff the emitted Go for every
// descendant matches identifierToGo / assignmentStatementToGo's static
// code path (no ctx.Get, no ctx.Update, no ctx.Create). Nested
// FunctionDeclaration short-circuits to false because a nested def emits
// ctx.Create("name", ...) into the block-level Go ctx. Only descends into
// the current function's body; nested functions compute their own
// resolvedIsStatic independently.
def analyzeIsStatic(node) {
    if (node == null) { return true; }
    if (!isMap(node)) { return true; }
    let t = node["type"];
    if (t == null) { return true; }

    if (t == "FunctionDeclaration") { return false; }

    if (t == "Identifier") {
        let origin = node["resolvedOrigin"];
        let kind = node["resolvedKind"];
        let usesGoVar = false;
        if (origin == "param") { usesGoVar = true; }
        if (origin == "let") {
            if (kind == "local" || kind == "captured") { usesGoVar = true; }
        }
        if (kind == "global") {
            if (origin == "lib" || origin == "def" || origin == "let") { usesGoVar = true; }
        }
        if (!usesGoVar) { return false; }
    }

    if (t == "AssignmentStatement") {
        let origin = node["resolvedOrigin"];
        let kind = node["resolvedKind"];
        let useGoVar = false;
        let isGlobal = false;
        let isTopLetWrite = false;
        if (origin == "param") { useGoVar = true; }
        if (origin == "let") {
            if (kind == "local" || kind == "captured") { useGoVar = true; }
        }
        if (kind == "global") {
            if (origin == "lib" || origin == "def" || origin == "let") {
                useGoVar = true;
                isGlobal = true;
                if (origin == "let") { isTopLetWrite = true; }
            }
        }
        if (!useGoVar) { return false; }
        // D1-reborn Run N+3: kind=global,origin=let writes are direct-emit-safe
        // because assignmentStatementToGoDirect dual-writes (Go var + ctx.Update)
        // and evalAssign's rkGlobalLet case mirrors that for eval-body callers,
        // so both paths stay coherent. Writes to lib/def globals remain
        // disallowed -- those have no plumbing path.
        if (isGlobal) {
            if (!isTopLetWrite) { return false; }
        }
    }

    let scalarKeys = ["condition","consequence","alternative","body","left","right","collection","index","value","callee","expression","initializer"];
    let i = 0;
    while (i < len(scalarKeys)) {
        let k = scalarKeys[i];
        let child = node[k];
        if (child != null) {
            if (isMap(child)) {
                if (!analyzeIsStatic(child)) { return false; }
            }
        }
        i = i + 1;
    }
    let arrKeys = ["statements","elements","arguments"];
    let j = 0;
    while (j < len(arrKeys)) {
        let k = arrKeys[j];
        let arr = node[k];
        if (arr != null) {
            if (isArray(arr)) {
                let m = 0;
                while (m < len(arr)) {
                    if (arr[m] != null) {
                        if (isMap(arr[m])) {
                            if (!analyzeIsStatic(arr[m])) { return false; }
                        }
                    }
                    m = m + 1;
                }
            }
        }
        j = j + 1;
    }
    let pairs = node["pairs"];
    if (pairs != null) {
        if (isArray(pairs)) {
            let p = 0;
            while (p < len(pairs)) {
                let pair = pairs[p];
                if (pair != null) {
                    if (isMap(pair)) {
                        let pk = pair["key"];
                        if (pk != null) { if (isMap(pk)) { if (!analyzeIsStatic(pk)) { return false; } } }
                        let pv = pair["value"];
                        if (pv != null) { if (isMap(pv)) { if (!analyzeIsStatic(pv)) { return false; } } }
                    }
                }
                p = p + 1;
            }
        }
    }

    return true;
}

def resolveVariableDeclaration(node, scope) {
    // The VarDecl node's own annotation describes the binding the declaration
    // CREATES -- root-scope lets are global/let (rkGlobalLet), everything else
    // is local/let (rkLocal). It must NOT be the enclosing-scope resolution of
    // the name: with sequential block resolution the lookup runs before the
    // local declare, so a function-local `let result` inside a tree-walked
    // body would resolve up the chain to a same-named TOP-LEVEL let and get
    // stamped rkGlobalLet -- and the emitted evalVarDecl treats rkGlobalLet
    // as "this IS a top-level let" and calls setTopLetGoVar, clobbering the
    // package-level Go var of the genuine global. That was the 2026-06-12 MCP
    // regression (eval.s's global `result` zeroed by inner-interpreter
    // locals; latent in interpreter.s itself via makeInterpreter's
    // `let interpreter = {}`). Identifier/Assignment nodes keep the
    // enclosing-scope lookup -- assignment semantics genuinely write the
    // resolved binding; only declarations create a fresh one.
    if (scope["parent"] == null) {
        node["resolvedKind"] = "global";
    } else {
        node["resolvedKind"] = "local";
    }
    node["resolvedOrigin"] = "let";
    node["resolvedName"] = mangle(node["name"]);
    // The enclosing scope matters for emission: root-scope lets stay dynamic
    // (ctx.Create) until a later phase, function-local lets become Go vars.
    node["resolvedAtRoot"] = (scope["parent"] == null);

    if (node["initializer"] != null) {
        resolveNode(node["initializer"], scope);
    }
    return null;
}

def resolveAssignmentStatement(node, scope) {
    let info = resolverScopeLookup(scope, node["name"]);
    node["resolvedKind"] = info["kind"];
    node["resolvedOrigin"] = info["origin"];
    node["resolvedName"] = mangle(node["name"]);

    if (node["value"] != null) {
        resolveNode(node["value"], scope);
    }
    return null;
}

def resolveIdentifier(node, scope) {
    let info = resolverScopeLookup(scope, node["name"]);
    node["resolvedKind"] = info["kind"];
    node["resolvedOrigin"] = info["origin"];
    node["resolvedName"] = mangle(node["name"]);
    return null;
}

def resolveGeneric(node, scope) {
    // Walk known scalar AST child fields.
    let scalarKeys = ["condition","consequence","alternative","body","left","right","collection","index","value","callee","expression","initializer"];
    let i = 0;
    while (i < len(scalarKeys)) {
        let k = scalarKeys[i];
        let child = node[k];
        if (child != null) {
            if (isMap(child)) {
                resolveNode(child, scope);
            }
        }
        i = i + 1;
    }
    // Walk known array-valued AST child fields.
    let arrKeys = ["statements","elements","arguments"];
    let j = 0;
    while (j < len(arrKeys)) {
        let k = arrKeys[j];
        let arr = node[k];
        if (arr != null) {
            if (isArray(arr)) {
                let m = 0;
                while (m < len(arr)) {
                    if (arr[m] != null) {
                        if (isMap(arr[m])) {
                            resolveNode(arr[m], scope);
                        }
                    }
                    m = m + 1;
                }
            }
        }
        j = j + 1;
    }
    // Special: MapLiteral "pairs" is an array of {"key":Node,"value":Node}.
    let pairs = node["pairs"];
    if (pairs != null) {
        if (isArray(pairs)) {
            let p = 0;
            while (p < len(pairs)) {
                let pair = pairs[p];
                if (pair != null) {
                    if (isMap(pair)) {
                        let pk = pair["key"];
                        if (pk != null) { if (isMap(pk)) { resolveNode(pk, scope); } }
                        let pv = pair["value"];
                        if (pv != null) { if (isMap(pv)) { resolveNode(pv, scope); } }
                    }
                }
                p = p + 1;
            }
        }
    }
    return null;
}

def resolveScopes(ast) {
    if (ast == null) { return null; }
    // If the AST root is a Program, treat it as the root scope directly so
    // top-level `let`/`def` end up in the scope whose parent is null, which is
    // how lookup classifies them as "global".
    if (ast["type"] == "Program") {
        let rootScope = makeResolverScope(null, true);
        ast["resolvedScope"] = rootScope;
        let locals = [];
        ast["resolvedLocals"] = locals;

        // Static resolution requires that every identifier (even ones that
        // textually precede their top-level declaration) can resolve to a
        // root-level name. We therefore pre-declare (hoist):
        //   - built-in library functions (origin="lib")
        //   - top-level `def` (origin="def")
        //   - top-level `let` (origin="let")
        // This is safe for correctness because the root scope has no
        // enclosing scope, so there is nothing for a later `let` to shadow.
        let libNames = libraryFunctionNames();
        let libGlobals = [];
        let li = 0;
        while (li < len(libNames)) {
            resolverScopeDeclare(rootScope, libNames[li], "lib");
            push(libGlobals, libNames[li]);
            li = li + 1;
        }
        ast["resolvedLibraryGlobals"] = libGlobals;

        let rootGlobals = [];
        // D1-reborn Run N+3: top-level `let` names tracked separately so the
        // emitter can plumb each as a package-level `var ij_<name> Value`
        // backed by ctx via setTopLetGoVar. Lets direct-emit'd code skip
        // ctx.Get/Update for top-level mutable globals (currentToken,
        // peekToken, lexer, tokens, ...).
        let rootLets = [];
        let stmts = ast["statements"];
        if (stmts == null) {
            ast["resolvedRootGlobals"] = rootGlobals;
            ast["resolvedRootLets"] = rootLets;
            return rootScope;
        }
        let n = len(stmts);

        let h = 0;
        while (h < n) {
            let stmt = stmts[h];
            if (stmt != null) {
                let st = stmt["type"];
                if (st == "VariableDeclaration") {
                    resolverScopeDeclare(rootScope, stmt["name"], "let");
                    push(rootGlobals, stmt["name"]);
                    push(rootLets, stmt["name"]);
                }
                if (st == "FunctionDeclaration") {
                    resolverScopeDeclare(rootScope, stmt["name"], "def");
                    push(rootGlobals, stmt["name"]);
                }
            }
            h = h + 1;
        }
        ast["resolvedRootGlobals"] = rootGlobals;
        ast["resolvedRootLets"] = rootLets;

        let i = 0;
        while (i < n) {
            let stmt = stmts[i];
            if (stmt != null) {
                resolveNode(stmt, rootScope);
                let st = stmt["type"];
                if (st == "VariableDeclaration") {
                    push(locals, stmt["name"]);
                }
                if (st == "FunctionDeclaration") {
                    push(locals, stmt["name"]);
                }
            }
            i = i + 1;
        }
        return rootScope;
    }
    let rootScope = makeResolverScope(null, true);
    resolveNode(ast, rootScope);
    return rootScope;
}

def functionDeclarationToGo(self) {
    // Phase 2: emit Node tree; evalFuncDecl creates Go closure dynamically.
    // D2-reborn: when this decl was promoted to a sibling ij_<name>_impl Go fn
    // (collectStaticDefs in programToGoPhase2), the body literal was emitted
    // once at the top of main() into ij_<name>_body. Reference it by name
    // here to avoid doubling the emit size; nkFuncDecl still runs so the
    // ctx[name] = Value{tag:tFunc} binding exists for any indirect-by-value
    // callers (e.g. `let g = foo; g(42)`).
    //
    // Run N+6: when this decl is direct-emit'd (useDirectEmit==true), also
    // attach staticImpl: ij_<name>_impl_wrapper to the FuncDecl Node so the
    // evalFuncDecl runtime closure dispatches to the direct-Go-statement impl
    // instead of walking the Node-tree body via eval(bodyN, local). This
    // closes the dominant cost path under selfhost: indirect calls like
    // node["evaluate"](node, ctx) (Execute -> evalFuncDecl closure -> eval).
    // staticImpl on a FuncDecl Node = closure body shortcut (NOT a direct
    // call site -- nkStaticCall already covers the direct-by-name path).
    print('&Node{kind: nkFuncDecl, name: "' + self["name"] + '", params: []string{');

    let params = self["parameters"];
    let pn = len(params);
    let pi = 0;
    while (pi < pn) {
        if (pi > 0) {
            print(',');
        }
        print('"' + params[pi] + '"');
        pi = pi + 1;
    }

    print('}, body: ');

    if (self["isStaticPromoted"] == true) {
        print(mangle(self["name"]) + "_body");
    } else {
        let body = self["body"];
        if (body != null) {
            if (body["toGo"] != null) {
                body["toGo"](body);
            }
        }
    }

    if (self["useDirectEmit"] == true) {
        print(", staticImpl: " + mangle(self["name"]) + "_impl_wrapper");
    }

    print('}');
}

// NumberLiteral node constructor
def makeNumberLiteral(value, position) {
    let node = {
        "type": "NumberLiteral",
        "position": position,
        "value": value
    };
    // Attach evaluate function
    node["evaluate"] = numberLiteralEvaluate;
    // Attach toJson function
    node["toJson"] = numberLiteralToJson;
    node["toGo"] = numberLiteralToGo;
    
    return node;
}

// Evaluate function for NumberLiteral node
def numberLiteralEvaluate(self, context) {
    return self["value"];
}

// toJson function for NumberLiteral node
def numberLiteralToJson(node) {
    // let typePart = '{ "type": "NumberLiteral", "position": "';
    // let posPart = node["position"];
    // let valuePart = '", "value": ';
    // let valVal = node["value"];
    // let endPart = " }";
    // return typePart + posPart + valuePart + valVal + endPart;
    let result = {};
    result["type"] = "NumberLiteral";
    result["position"] = node["position"];
    result["value"] = node["value"];
    return result;
}

def numberLiteralToGo(self) {
    let str = string(self["value"]);
    let i = 0;
    let isDouble = false;
    while (i < len(str)) {
        if (char(str, i) == ".") {
            isDouble = true;
        }
        i = i + 1;
    }
    if (isDouble) {
        print('&Node{kind: nkDoubleLit, dVal: ' + str + '}');
    } else {
        print('&Node{kind: nkIntLit, iVal: ' + str + '}');
    }
}



// StringLiteral: a literal string AST node

// Construct a StringLiteral node
def makeStringLiteral(value, position) {
    // Create a map (object) to represent the node
    let node = { 
        "type": "StringLiteral",
        "value": value,
        "position": position
    };
    // Manually attach functions
    node["getValue"] = getStringLiteralValue;
    node["evaluate"] = evaluateStringLiteral;
    node["toJson"] = stringLiteralToJson;
    node["toGo"] = stringLiteralToGo;
    return node;
}

// Get value field
def getStringLiteralValue(thisNode) {
    return thisNode["value"];
}

// Evaluate the node (returns the literal value)
def evaluateStringLiteral(thisNode, context) {
    return thisNode["value"];
}

// Generate JSON representation of this StringLiteral node
def stringLiteralToJson(thisNode) {
    let typeString = 'StringLiteral';
    let positionString = thisNode["position"];
    let valueString = thisNode["value"];
    // No string escaping allowed, so produce only correct non-escaped JSON
    // Only single-line, simple, explicit building
    // return '{ "type": "' + typeString + '", "position": "' + positionString + '", "value": "' + valueString + '" }';
    let result = {};
    result["type"] = typeString;
    result["position"] = positionString;
    result["value"] = valueString;
    return result;
}

def stringLiteralToGo(self) {
    print('&Node{kind: nkStringLit, name: "' + escapeGoStringLiteral(self["value"]) + '"}');
}

def escapeGoStringLiteral(s) {
    let r = "";
    let i = 0;
    while (i < len(s)) {
        let c = char(s, i);
        if (ord(c) == 34) {
            r = r + chr(92); // FIXME "\" issue with lexer?
        }
        r = r + c
        i = i + 1;
    }
    return r;
}



// ===============================
// BooleanLiteral Node (InterpreterJ)
// ===============================

// Constructor for BooleanLiteral Node
def makeBooleanLiteral(value, position) {
    let node = {
        "type": "BooleanLiteral",
        "value": value,
        "position": position
    };
    node["getValue"] = getBooleanLiteralValue;
    node["evaluate"] = evaluateBooleanLiteral;
    node["toJson"] = toJsonBooleanLiteral;
    node["toGo"] = toGoBooleanLiteral;
    return node;
}

// Accessor for value
def getBooleanLiteralValue(self) {
    return self["value"];
}

// Evaluator - returns the value
def evaluateBooleanLiteral(self, context) {
    return self["value"];
}

// toJson - returns JSON string
def toJsonBooleanLiteral(self) {
    // if (self["value"]) {
    //     return '{ "type": "BooleanLiteral", "position": "' + self["position"] + '", "value": true }';
    // } else {
    //     return '{ "type": "BooleanLiteral", "position": "' + self["position"] + '", "value": false }';
    // }
    let result = {};
    result["type"] = "BooleanLiteral";
    result["position"] = self["position"];
    result["value"] = self["value"];
    return result;
}

def toGoBooleanLiteral(self) {
    if (self["value"]) {
        print('&Node{kind: nkBoolLit, bVal: true}');
    }
    else {
        print('&Node{kind: nkBoolLit, bVal: false}');
    }
}



def makeIdentifier(name, position) {
    let obj = {
        "type": "Identifier",
        "name": name,
        "position": position
    };
    // Attach evaluator function
    obj["evaluate"] = identifierEvaluate;
    obj["toJson"] = identifierToJson;
    obj["toGo"] = identifierToGo;
    return obj;
}

// Evaluator function for Identifier nodes
def identifierEvaluate(self, context) {
    // Direct variable lookup - position is stored in self if needed for error
    return context["get"](context, self["name"], self["position"]);
}

// toJson function for Identifier nodes
def identifierToJson(self) {
    let position = self["position"];
    let name = self["name"];
    // return '{ "type": "Identifier", "position": "' + position + '", "name": "' + name + '" }';
    let result = {};
    result["type"] = "Identifier";
    result["position"] = position;
    result["name"] = name;
    return result;
}

def identifierToGo(self) {
    // Phase 2.5: project resolver annotations onto Node so evalIdent can
    // dispatch on resolvedKind. Only the rkLib fast path is actually wired
    // through to a fast lookup today (rootCtx.GetLocal); the other
    // resolvedKind values still fall through evalIdent's default ctx.Get
    // chain walk because rkParam / rkLocal cannot use GetLocal until
    // P2.5.6 collapses the per-block *Context allocation.
    print('&Node{kind: nkIdent, name: "' + self["name"] + '"');
    if (self["resolvedKind"] != null) {
        print(", resolvedKind: ");
        print(resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
    }
    print('}');
}



// --- TokenType constants ---
let DEF = "DEF";
let LET = "LET";
let IF = "IF";
let ELSE = "ELSE";
let WHILE = "WHILE";
let RETURN = "RETURN";
let TRUE = "TRUE";
let FALSE = "FALSE";
let NULL = "NULL";
let IDENTIFIER = "IDENTIFIER";

// --- Keywords map ---
let keywords = {};
keywords["def"] = DEF;
keywords["let"] = LET;
keywords["if"] = IF;
keywords["else"] = ELSE;
keywords["while"] = WHILE;
keywords["return"] = RETURN;
keywords["true"] = TRUE;
keywords["false"] = FALSE;
keywords["null"] = NULL;

// --- Keyword lookup function ---
def lookupKeyword(identifier) {
  if (keywords[identifier] != null) {
    return keywords[identifier];
  } else {
    return IDENTIFIER;
  }
}



// Parser.s: LL(1) Predictive Recursive Descent Parser for InterpreterJ

// TokenType constants expected available:
// LET, DEF, IF, ELSE, WHILE, RETURN,
// TRUE, FALSE, NULL, IDENTIFIER,
// NUMBER, STRING,
// PLUS, MINUS, ASTERISK, SLASH, PERCENT,
// EQ, NOT_EQ, LT, GT, LT_EQ, GT_EQ,
// AND, OR, NOT,
// ASSIGN,
// COMMA, SEMICOLON, LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, COLON, EOF

// Assumes lexer object with method nextToken() returning Token map with keys:
// type, literal, line, column

// Parser state variables global inside this file:

let lexer = null;          // Lexer instance (map)
let tokens = [];           // Array of tokens buffered (map with keys as above)
let currentPosition = 0;   // Index in tokens array

let currentToken = null;   // Current token map
let peekToken = null;      // Next token map

// Errors array stores parsing errors as maps with keys: message, line, column
let errors = [];

// prefixParseFns: map from tokenType -> parser function returning Node (map)
let prefixParseFns = {};

// infixParseFns: map from tokenType -> function taking (Node) returning Node
let infixParseFns = {};

// Precedence numeric values for operators:
// a map from tokenType to precedence integer
let precedences = {};

// Precedence constants for clarity (use integers)
let PREC_LOWEST = 1;
let PREC_OR = 2;
let PREC_AND = 3;
let PREC_EQUALS = 4;
let PREC_COMPARE = 5;
let PREC_SUM = 6;
let PREC_PRODUCT = 7;
let PREC_PREFIX = 8;
let PREC_CALL = 9;

// --- Functions ---

def initPrecedences() {
    precedences["OR"] = PREC_OR;
    precedences["AND"] = PREC_AND;
    precedences["EQ"] = PREC_EQUALS;
    precedences["NOT_EQ"] = PREC_EQUALS;
    precedences["LT"] = PREC_COMPARE;
    precedences["GT"] = PREC_COMPARE;
    precedences["LT_EQ"] = PREC_COMPARE;
    precedences["GT_EQ"] = PREC_COMPARE;
    precedences["PLUS"] = PREC_SUM;
    precedences["MINUS"] = PREC_SUM;
    precedences["ASTERISK"] = PREC_PRODUCT;
    precedences["SLASH"] = PREC_PRODUCT;
    precedences["PERCENT"] = PREC_PRODUCT;
    precedences["LPAREN"] = PREC_CALL;
    precedences["LBRACKET"] = PREC_CALL;
}

// Advance tokens: move currentToken and peekToken forward
def nextToken() {
    currentToken = peekToken;
    if (currentPosition < len(tokens)) {
        peekToken = tokens[currentPosition];
        currentPosition = currentPosition + 1;
    } else {
        let t = lexer["nextToken"](lexer);
        push(tokens, t);
        peekToken = t;
        currentPosition = currentPosition + 1;
    }
}

// Check if current token is of given type string
def currentTokenIs(tokenType) {
    if (currentToken == null) {
        return false;
    }
    if (currentToken["type"] == tokenType) {
        return true;
    }
    return false;
}

// Check if peek token is of given type string
def peekTokenIs(tokenType) {
    if (peekToken == null) {
        return false;
    }
    if (peekToken["type"] == tokenType) {
        return true;
    }
    return false;
}

// Expect peek token to be tokenType, if so advance, else record error and return false
def expectPeek(tokenType) {
    if (peekTokenIs(tokenType)) {
        nextToken();
        return true;
    } else {
        peekError(tokenType);
        return false;
    }
}

// Add error for expected peek token type mismatch
def peekError(tokenType) {
    let message = "Expected next token to be " + tokenType + ", got ";
    if (peekToken != null) {
        message = message + peekToken["type"];
    } else {
        message = message + "null";
    }
    let line = 0;
    let column = 0;
    if (peekToken != null) {
        line = peekToken["line"];
        column = peekToken["column"];
    }
    let err = { "message": message, "line": line, "column": column };
    push(errors, err);
}

// Get the precedence integer of current token's type or default
def currentPrecedence() {
    if (currentToken == null) {
        return PREC_LOWEST;
    }
    let p = precedences[currentToken["type"]];
    if (p == null) {
        return PREC_LOWEST;
    }
    return p;
}

// Get the precedence integer of peek token's type or default
def peekPrecedence() {
    if (peekToken == null) {
        return PREC_LOWEST;
    }
    let p = precedences[peekToken["type"]];
    if (p == null) {
        return PREC_LOWEST;
    }
    return p;
}

// Register prefix parse function for token type string tokType
def registerPrefix(tokType, fn) {
    prefixParseFns[tokType] = fn;
}

// Register infix parse function for token type string tokType
def registerInfix(tokType, fn) {
    infixParseFns[tokType] = fn;
}

// Parse entire program producing a Program node map
def parseProgram() {
    let program = makeProgram();

    while (!currentTokenIs("EOF")) {
        let stmt = parseStatement();
        if (stmt != null) {
            program["addStatement"](program, stmt);
        }
        nextToken();
    }
    return program;
}

// Parse one statement node
def parseStatement() {
    if (currentToken == null) {
        return null;
    }
    let typ = currentToken["type"];

    if (typ == "LET") {
        return parseVariableDeclaration();
    }
    if (typ == "DEF") {
        return parseFunctionDeclaration();
    }
    if (typ == "IF") {
        return parseIfStatement();
    }
    if (typ == "WHILE") {
        return parseWhileStatement();
    }
    if (typ == "RETURN") {
        return parseReturnStatement();
    }
    if (typ == "LBRACE") {
        return parseBlockStatement();
    }
    if (typ == "IDENTIFIER") {
        // Look ahead for `[`, or `=` after identifier to decide special statement
        if (peekToken != null) {
            if (peekToken["type"] == "LBRACKET") {
                let savedPosition = currentPosition;
                // We try parse index assignment statement
                // Move tokens ahead to check
                nextToken(); // move to '['
                if (!currentTokenIs("LBRACKET")) {
                    // Not `[`, rollback and parse expression statement
                    currentPosition = savedPosition;
                    peekToken = tokens[currentPosition-1];
                    currentToken = tokens[currentPosition-2];
                    return parseExpressionStatement();
                }
                nextToken(); // inside '[' expect index expression
                // parse expression (not stored now)
                let idxExpr = parseExpression(PREC_LOWEST);
                if (!expectPeek("RBRACKET")) {
                    currentPosition = savedPosition;
                    peekToken = tokens[currentPosition-1];
                    currentToken = tokens[currentPosition-2];
                    return parseExpressionStatement();
                }
                // Check if next is ASSIGN for index assignment
                if (peekTokenIs("ASSIGN")) {
                    // Reset tokens position and call parseIndexAssignmentStatement
                    currentPosition = savedPosition;
                    peekToken = tokens[currentPosition-1];
                    currentToken = tokens[currentPosition-2];
                    return parseIndexAssignmentStatement();
                } else {
                    // Reset tokens & parse expression statement
                    currentPosition = savedPosition;
                    peekToken = tokens[currentPosition-1];
                    currentToken = tokens[currentPosition-2];
                    return parseExpressionStatement();
                }
            }
            if (peekToken["type"] == "ASSIGN") {
                // assignment statement
                return parseAssignmentStatement();
            }
        }
        return parseExpressionStatement();
    }
    // Default fallback parse expression statement
    return parseExpressionStatement();
}

// Parse variable declaration: "let IDENTIFIER = expression;"
def parseVariableDeclaration() {
    let tok = currentToken;

    if (!expectPeek("IDENTIFIER")) {
        return null;
    }
    let name = currentToken["literal"];

    if (!expectPeek("ASSIGN")) {
        return null;
    }

    nextToken(); // move to expression start

    let initializer = parseExpression(PREC_LOWEST);

    if (peekTokenIs("SEMICOLON")) {
        nextToken();
    }

    let pos = tok["line"] + ":" + tok["column"];

    let node = makeVariableDeclaration(name, initializer, pos);
    return node;
}

// Parse function declaration: "def IDENTIFIER (params) { body }"
def parseFunctionDeclaration() {
    let tok = currentToken;

    if (!expectPeek("IDENTIFIER")) {
        return null;
    }
    let name = currentToken["literal"];

    if (!expectPeek("LPAREN")) {
        return null;
    }

    let parameters = parseFunctionParameters();

    if (!expectPeek("LBRACE")) {
        return null;
    }

    let body = parseBlockStatement();

    let pos = tok["line"] + ":" + tok["column"];

    let node = makeFunctionDeclaration(name, parameters, body, pos);

    return node;
}

// Parse function formal parameters inside parentheses
def parseFunctionParameters() {
    let params = [];

    if (peekTokenIs("RPAREN")) {
        nextToken();
        return params;
    }

    nextToken();
    push(params, currentToken["literal"]);

    while (peekTokenIs("COMMA")) {
        nextToken(); // consume comma
        nextToken(); // advance to next param
        push(params, currentToken["literal"]);
    }
    if (!expectPeek("RPAREN")) {
        return null;
    }
    return params;
}

// Parse if statement: if (condition) { consequence } [else { alternative }]
def parseIfStatement() {
    let tok = currentToken;

    if (!expectPeek("LPAREN")) {
        return null;
    }

    nextToken();
    let condition = parseExpression(PREC_LOWEST);

    if (!expectPeek("RPAREN")) {
        return null;
    }

    if (!expectPeek("LBRACE")) {
        return null;
    }

    let consequence = parseBlockStatement();

    let alternative = null;
    if (peekTokenIs("ELSE")) {
        nextToken();
        if (!expectPeek("LBRACE")) {
            return null;
        }
        alternative = parseBlockStatement();
    }
    let pos = tok["line"] + ":" + tok["column"];

    let node = makeIfStatement(condition, consequence, alternative, pos);
    return node;
}

// Parse return statement: return expression?;
def parseReturnStatement() {
    let tok = currentToken;

    nextToken(); // move after return

    let val = null;
    if (!currentTokenIs("SEMICOLON")) {
        val = parseExpression(PREC_LOWEST);
    }

    if (peekTokenIs("SEMICOLON")) {
        nextToken();
    }

    let pos = tok["line"] + ":" + tok["column"];

    let node = ReturnStatement_create(val, pos);
    return node;
}

// parse while statement: while (condition) { body }
def parseWhileStatement() {
    let tok = currentToken;

    if (!expectPeek("LPAREN")) {
        return null;
    }

    nextToken();
    let condition = parseExpression(PREC_LOWEST);

    if (!expectPeek("RPAREN")) {
        return null;
    }

    if (!expectPeek("LBRACE")) {
        return null;
    }

    let body = parseBlockStatement();

    let pos = tok["line"] + ":" + tok["column"];

    let node = makeWhileStatement(condition, body, pos);
    return node;
}

// parse block statement: { statements* }
def parseBlockStatement() {
    let tok = currentToken;

    let block = makeBlockStatement([], tok["line"] + ":" + tok["column"]);

    nextToken();

    while (!currentTokenIs("RBRACE") && !currentTokenIs("EOF")) {
        let stmt = parseStatement();
        if (stmt != null) {
            block["addStatement"](block, stmt);
        }
        nextToken();
    }

    if (!currentTokenIs("RBRACE")) {
        let err = { "message": "Expected '}' at end of block statement", "line": currentToken["line"], "column": currentToken["column"] };
        push(errors, err);
        return null;
    }

    return block;
}

// parse expression statement: expression;
def parseExpressionStatement() {
    let tok = currentToken;

    let expr = parseExpression(PREC_LOWEST);

    if (peekTokenIs("SEMICOLON")) {
        nextToken();
    }

    let pos = tok["line"] + ":" + tok["column"];

    let node = makeExpressionStatement(expr, pos);

    return node;
}

// parse expression with given precedence
def parseExpression(precedence) {
    if (currentToken == null) {
        return null;
    }
    let prefix = prefixParseFns[currentToken["type"]];
    if (prefix == null) {
        let message = "No prefix parse function for " + currentToken["type"] + " (" + currentToken["literal"] + ")";
        let err = { "message": message, "line": currentToken["line"], "column": currentToken["column"] };
        push(errors, err);
        return null;
    }

    let leftExp = prefix();

    while (!peekTokenIs("SEMICOLON") && precedence < peekPrecedence()) {
        let infix = infixParseFns[peekToken["type"]];
        if (infix == null) {
            return leftExp;
        }
        nextToken();
        leftExp = infix(leftExp);
    }
    return leftExp;
}

// parse identifier token
def parseIdentifier() {
    let pos = currentToken["line"] + ":" + currentToken["column"];
    return makeIdentifier(currentToken["literal"], pos);
}

// parse number literal token
def parseNumberLiteral() {
    let pos = currentToken["line"] + ":" + currentToken["column"];
    let value = 0.0;
    let strVal = currentToken["literal"];
    value = parseDouble(strVal);
    return makeNumberLiteral(value, pos);
}

// dummy parseDouble returns default 0 for now (you may implement)
def parseDouble(str) {
    let i = 0;
    while (i < len(str)) {
        if (char(str, i) == ".") {
            return double(str);        
        }
        i = i + 1;
    }
    return int(str); // FIXME PARSER DOUBLE //GOFIX
}

// parse string literal token
def parseStringLiteral() {
    let pos = currentToken["line"] + ":" + currentToken["column"];
    return makeStringLiteral(currentToken["literal"], pos);
}

// parse boolean literal token: true or false
def parseBooleanLiteral() {
    let pos = currentToken["line"] + ":" + currentToken["column"];
    let val = false;
    if (currentToken["type"] == "TRUE") {
        val = true;
    } else {
        val = false;
    }
    return makeBooleanLiteral(val, pos);
}

// parse null literal token
def parseNullLiteral() {
    let pos = currentToken["line"] + ":" + currentToken["column"];
    return makeNullLiteral(pos);
}

// parse grouped expression: ( expression )
def parseGroupedExpression() {
    nextToken();
    let expr = parseExpression(PREC_LOWEST);
    if (!expectPeek("RPAREN")) {
        return null;
    }
    return expr;
}

// parse prefix expressions: -expr or !expr
def parsePrefixExpression() {
    let tok = currentToken;
    let operator = currentToken["literal"];
    nextToken();
    let right = parseExpression(PREC_PREFIX);
    let pos = tok["line"] + ":" + tok["column"];
    return makePrefixExpression(operator, right, pos);
}

// parse infix expressions with left Node given
def parseInfixExpression(left) {
    let tok = currentToken;
    let operator = currentToken["literal"];
    let precedence = currentPrecedence();
    nextToken();
    let right = parseExpression(precedence);
    let pos = tok["line"] + ":" + tok["column"];
    return makeInfixExpression(left, operator, right, pos);
}

// parse call expressions: fn(args...)
def parseCallExpression(functionNode) {
    let tok = currentToken;
    let args = parseCallArguments();
    let pos = tok["line"] + ":" + tok["column"];
    return CallExpression_create(functionNode, args, pos);
}

// parse call arguments list inside parentheses
def parseCallArguments() {
    let args = [];
    if (peekTokenIs("RPAREN")) {
        nextToken();
        return args;
    }
    nextToken();
    push(args, parseExpression(PREC_LOWEST));
    while (peekTokenIs("COMMA")) {
        nextToken(); // consume comma
        nextToken();
        push(args,parseExpression(PREC_LOWEST));
    }
    if (!expectPeek("RPAREN")) {
        return null;
    }
    return args;
}

// parse assignment statement: IDENTIFIER = expression;
def parseAssignmentStatement() {
    let tok = currentToken;
    let name = currentToken["literal"];

    if (!expectPeek("ASSIGN")) {
        return null;
    }
    nextToken();

    let value = parseExpression(PREC_LOWEST);

    if (peekTokenIs("SEMICOLON")) {
        nextToken();
    }

    let pos = tok["line"] + ":" + tok["column"];

    let node = makeAssignmentStatement(name, value, pos);

    return node;
}

// parse array literal: [elements]
def parseArrayLiteral() {
    let tok = currentToken;
    let elements = parseArrayElements();
    let pos = tok["line"] + ":" + tok["column"];
    return makeArrayLiteral(elements, pos);
}

// parse array elements (comma-separated expressions)
def parseArrayElements() {
    let elements = [];
    if (peekTokenIs("RBRACKET")) {
        nextToken();
        return elements;
    }
    nextToken();
    push(elements,parseExpression(PREC_LOWEST));
    while (peekTokenIs("COMMA")) {
        nextToken(); // consume comma
        nextToken();
        push(elements,parseExpression(PREC_LOWEST));
    }
    if (!expectPeek("RBRACKET")) {
        return null;
    }
    return elements;
}

// parse index expression: collection[index]
def parseIndexExpression(collectionNode) {
    let tok = currentToken;
    nextToken(); // skip '['
    let index = parseExpression(PREC_LOWEST);
    if (!expectPeek("RBRACKET")) {
        return null;
    }
    let pos = tok["line"] + ":" + tok["column"];
    return makeIndexExpression(collectionNode, index, pos);
}

// parse index assignment statement: collection[index] = value;
def parseIndexAssignmentStatement() {
    let tok = currentToken;
    let identifier = currentToken["literal"];
    let pos = tok["line"] + ":" + tok["column"];
    let collection = makeIdentifier(identifier, pos);
    nextToken();

    if (!currentTokenIs("LBRACKET")) {
        let err = { "message": "Expected '[' in index expression", "line": currentToken["line"], "column": currentToken["column"] };
        push(errors, err);
        return null;
    }
    nextToken(); // skip '['
    let index = parseExpression(PREC_LOWEST);

    if (!expectPeek("RBRACKET")) {
        return null;
    }

    if (!expectPeek("ASSIGN")) {
        return null;
    }
    nextToken();

    let value = parseExpression(PREC_LOWEST);

    if (peekTokenIs("SEMICOLON")) {
        nextToken();
    }
    return makeIndexAssignmentStatement(collection, index, value, pos);
}

// parse map literal: { pairs }
def parseMapLiteral() {
    let tok = currentToken;

    //puts("parseMapListeral: tok=" + tok["toString"](tok)); //DEBUG

    let pairs = parseMapPairs();
    let pos = tok["line"] + ":" + tok["column"];

    //puts("parseMapListeral: pairs=" + pairs); //DEBUG

    return makeMapLiteral(pairs, pos);
}

// parse map key-value pairs
def parseMapPairs() {
    let pairs = [];
    if (peekTokenIs("RBRACE")) {
        nextToken();

        //puts("parseMapPairs: No pairs!"); //DEBUG

        return pairs;
    }
    nextToken();

    //puts("parseMapPairs: currentToken=" + currentToken["toString"](currentToken)); //DEBUG

    let key = parseExpression(PREC_LOWEST);

    //puts("Key=" + key); //DEBUG

    if (!expectPeek("COLON")) {
        return null;
    }
    nextToken();
    let value = parseExpression(PREC_LOWEST);
    push(pairs, { "key": key, "value": value });

    while (peekTokenIs("COMMA")) {
        nextToken();
        nextToken();
        key = parseExpression(PREC_LOWEST);
        if (!expectPeek("COLON")) {
            return null;
        }
        nextToken();
        value = parseExpression(PREC_LOWEST);
        push(pairs, { "key": key, "value": value });
    }
    if (!expectPeek("RBRACE")) {
        return null;
    }
    return pairs;
}

// --- Initialization ---

def initParser(givenLexer) {
    lexer = givenLexer;
    tokens = [];
    currentPosition = 0;
    errors = [];

    prefixParseFns = {};
    infixParseFns = {};
    precedences = {};

    initPrecedences();

    nextToken();
    nextToken();

    registerPrefix("IDENTIFIER", parseIdentifier);
    registerPrefix("NUMBER", parseNumberLiteral);
    registerPrefix("STRING", parseStringLiteral);
    registerPrefix("TRUE", parseBooleanLiteral);
    registerPrefix("FALSE", parseBooleanLiteral);
    registerPrefix("NULL", parseNullLiteral);
    registerPrefix("LPAREN", parseGroupedExpression);
    registerPrefix("MINUS", parsePrefixExpression);
    registerPrefix("NOT", parsePrefixExpression);
    registerPrefix("LBRACKET", parseArrayLiteral);
    registerPrefix("LBRACE", parseMapLiteral);

    registerInfix("PLUS", parseInfixExpression);
    registerInfix("MINUS", parseInfixExpression);
    registerInfix("ASTERISK", parseInfixExpression);
    registerInfix("SLASH", parseInfixExpression);
    registerInfix("PERCENT", parseInfixExpression);
    registerInfix("EQ", parseInfixExpression);
    registerInfix("NOT_EQ", parseInfixExpression);
    registerInfix("LT", parseInfixExpression);
    registerInfix("GT", parseInfixExpression);
    registerInfix("LT_EQ", parseInfixExpression);
    registerInfix("GT_EQ", parseInfixExpression);
    registerInfix("AND", parseInfixExpression);
    registerInfix("OR", parseInfixExpression);
    registerInfix("LPAREN", parseCallExpression);
    registerInfix("LBRACKET", parseIndexExpression);
}

// --- Provide exported functions ---

// parse given Lexer instance to Program node
def parse(lexerInstance) {
    initParser(lexerInstance);
    return parseProgram();
}

// Errors getter
def getErrors() {
    return errors;
}

// --- End of Parser.s ---

// The parser uses externally defined node constructors and auxiliary functions:
// makeProgram, makeVariableDeclaration, makeFunctionDeclaration, makeIfStatement,
// makeWhileStatement, makeBlockStatement, makeExpressionStatement,
// ReturnStatement_create, makeAssignmentStatement, makeIndexAssignmentStatement,
// makeArrayLiteral, makeMapLiteral, makeIdentifier, makeNumberLiteral, makeStringLiteral,
// makeBooleanLiteral, makeNullLiteral,
// makePrefixExpression, makeInfixExpression, CallExpression_create, makeIndexExpression.

// All these must be defined as in given references.

// --- end ---



// Token "struct" factory and helpers for InterpreterJ

// Factory function to create a Token map
def createToken(type, literal, line, column) {
  let token = {}; // new map
  token["type"] = type;
  token["literal"] = literal;
  token["line"] = line;
  token["column"] = column;
  token["toString"] = tokenToString; // attach method manually
  return token;
}

// Accessor: get token type
def getTokenType(token) {
  return token["type"];
}

// Accessor: get token literal
def getTokenLiteral(token) {
  return token["literal"];
}

// Accessor: get token line
def getTokenLine(token) {
  return token["line"];
}

// Accessor: get token column
def getTokenColumn(token) {
  return token["column"];
}

// toString function for token (returns as string)
def tokenToString(token) {
  return "Token(" + token["type"] + ", '" + token["literal"] + "', " + token["line"] + ":" + token["column"] + ")";
}



// FIXME not sure CallExpression and FunctionDeclaration are properly designed to work together

// CallExpression "class" as a map (NOT a class!)
let CallExpression = {};

// Constructor: def CallExpression_create(callee, arguments, position)
def CallExpression_create(callee, arguments, position) {
    let node = {};
    node["type"] = "CallExpression";
    node["callee"] = callee;
    if (arguments == null) {
        node["arguments"] = [];
    } else {
        node["arguments"] = arguments;
    }
    node["position"] = position;

    // Attach functions to the node map
    node["evaluate"] = CallExpression_evaluate;
    node["toJson"] = CallExpression_toJson;
    node["toGo"] = CallExpression_toGo;

    return node;
}

// Evaluate (call expression) function. Called as node["evaluate"](node, context).
def CallExpression_evaluate(self, context) {
    // Self = this CallExpression node instance (map)



    // Use try-finally pattern
    let result = null;
    let errorCaught = false;
    let errorObj = null;

    // Try block simulation
    {
        // Evaluate the function (callee)
        let functionValue = null;
        if (self["callee"] != null) {
            functionValue = self["callee"]["evaluate"](self["callee"], context);
            //puts("DEBUG: functionValue=" + functionValue);
        }
        if (functionValue == null) {
            errorCaught = true;
            errorObj = RuntimeError_create(
                "Cannot call null as a function",
                //self["position"]["line"],
                //self["position"]["column"]
                self["position"]
            );
        }

        // Only continue if no error so far
        if (!errorCaught) {
            // Evaluate arguments - optimized
            let argumentNodes = self["arguments"];
            let argLen = len(argumentNodes);
            let args = [];
            let idx = 0;
            while (idx < argLen) {
                let argNode = argumentNodes[idx];
                let argValue = argNode["evaluate"](argNode, context);
                push(args, argValue);
                idx = idx + 1;
            }
            result = functionValue(args);

            /* FIXME review required ;-)
            // Call if it's CallableFunction:  Assume our CallableFunction is identified by checking map field "apply"
            if (functionValue != null && functionValue["apply"] != null) {
                puts("DEBUG: Function has apply...");

                // Try/catch function application
                let success = false;
                let caughtErr = null;
                let applyResult = null;
                {
                    // Try applying
                    let didThrow = false;
                    let thrown = null;
                    // Simulating try-catch for apply
                    let applyRet = null;
                    // The "apply" field of functionValue must be a function taking (self, args)
                    let caughtApplyError = false;
                    let caughtApplyObj = null;
                    {
                        // Try block
                        applyRet = functionValue["apply"](functionValue, args);
                    }
                    applyResult = applyRet;
                    // success
                    success = true;
                }
                // If apply succeeded
                if (success) {
                    result = applyResult;
                }
            } else {
                // Not a callable function
                errorCaught = true;
                errorObj = RuntimeError_create(
                    "Not a function: " + valueToString(functionValue),
                    //self["position"]["line"],
                    //self["position"]["column"]
                    self["position"]
                );
            }
            */

        }
    }



    // Rethrow error if there was one
    if (errorCaught) {
        // Throwing in InterpreterJ: call the throwRuntimeError function
        throwRuntimeError(errorObj);
        // To please the static analyzer
        return null;
    }

    return result;
}

// toJson function for CallExpression. Called as node["toJson"](node)
def CallExpression_toJson(self) {
    let argsJson = "";
    let argsLen = len(self["arguments"]);
    let i = 0;
    while (i < argsLen) {
        let argNode = self["arguments"][i];
        let itemJson = "null";
        if (argNode != null && argNode["toJson"] != null) {
            itemJson = argNode["toJson"](argNode);
        }
        if (i > 0) {
            argsJson = argsJson + ", ";
        }
        argsJson = argsJson + itemJson;
        i = i + 1;
    }

    let calleeJson = "null";
    if (self["callee"] != null && self["callee"]["toJson"] != null) {
        calleeJson = self["callee"]["toJson"](self["callee"]);
    }

    // No string escaping or newlines!
    // return '{ "type": "CallExpression", "position": "' +
    //     self["position"] + '", "callee": ' + calleeJson +
    //     ', "arguments": [' + argsJson + '] }';
    // argsJson is a string of comma-separated JSONs, need to convert to list of maps
    let argsList = [];
    let k = 0;
    let argNodes = self["arguments"];
    while (k < len(argNodes)) {
        let argNode = argNodes[k];
        let itemMap = null;
        if (argNode != null && argNode["toJson"] != null) {
            itemMap = argNode["toJson"](argNode);
        }
        push(argsList, itemMap);
        k = k + 1;
    }

    let result = {};
    result["type"] = "CallExpression";
    result["position"] = self["position"];
    result["callee"] = calleeJson; // calleeJson is already map or null
    result["arguments"] = argsList;
    return result;
}

def CallExpression_toGo(self) {
    // Phase 2: emit Node tree; evalCall handles Execute
    let callee = self["callee"];
    let args = self["arguments"];
    let argsLen = len(args);

    // D2-reborn: if the callee is a name resolving to a top-level static def
    // that we promoted in collectStaticDefs (resolvedKind=global, origin=def),
    // emit nkStaticCall with the impl func pointer baked into the Node literal.
    // This bypasses evalIdent + ctx.Get + FunctionCommand.Execute + ArrayValue
    // allocation at runtime. resolvedOrigin == "def" is the key gate: it
    // distinguishes the real top-level def from a let/param/upvalue with the
    // same name (sequential resolver lookup would have returned origin="let"
    // or kind="local"/"captured" in that case).
    let isStaticCall = false;
    if (callee != null) {
        if (callee["type"] == "Identifier") {
            if (callee["resolvedKind"] == "global") {
                if (callee["resolvedOrigin"] == "def") {
                    if (staticDefByName[callee["name"]] != null) {
                        isStaticCall = true;
                    }
                }
            }
        }
    }

    if (isStaticCall) {
        print('&Node{kind: nkStaticCall, staticImpl: ' + mangle(callee["name"]) + '_impl_wrapper, list: []*Node{');
    } else {
        print('&Node{kind: nkCall, left: ');
        callee["toGo"](callee);
        print(', list: []*Node{');
    }

    let i = 0;
    while (i < argsLen) {
        if (i > 0) {
            print(',');
        }
        let argNode = args[i];
        if (argNode["toGo"] != null) {
            argNode["toGo"](argNode);
        }
        i = i + 1;
    }

    print('}}');
}

// Helper: value to string for non-function error message
def valueToString(val) {
    // Only handle primitive values and arrays/maps simply, for debugging
    if (val == null) {
        return "null";
    }
    if (val == true) {
        return "true";
    }
    if (val == false) {
        return "false";
    }
    // If it's a number or string
    // InterpreterJ cannot distinguish types easily; fallback to string concat
    return "" + val;
}

// RuntimeError "constructor"
def RuntimeError_create(msg, pos /* line, column */) {
    let err = {};
    err["message"] = msg;
    //err["line"] = line;
    //err["column"] = column;
    err["pos"] = pos;
    return err;
}

// Simulate "throw new RuntimeError" by calling throwRuntimeError
def throwRuntimeError(error) {
    // No real throw, just call the system error function or stop execution.
    // In InterpreterJ, you'll need to either call your interpreter's panic function,
    // or, if not possible, simply cause an invalid operation:
    panic(error); // FIXME not supported, and dummy implementation below is a bad idea
}

// Dummy panic handler for demo (replace in your engine)
def panic(error) {
    // This will forcefully stop the interpreter if used.
    // For demo purposes, print to output (remove this if not allowed):
    //puts("PANIC: " + error["message"] + " at " + error["line"] + ":" + error["column"]);
    //puts("panic(" + error + ")");
    //assert(false, "PANIC: " + error["message"] + " at " + error["pos"]);
    assert(false, "panic: " + error);
    // Infinite loop to simulate halt (remove if your engine provides built-in error/throw)
    //FIXME bad idea: while (true) {}
    
}



// IfStatement "class" - represented as a map with functions/properties manually set

// Create an IfStatement node as a map
def makeIfStatement(condition, consequence, alternative, position) {
    let node = {
        "type": "IfStatement",
        "condition": condition,
        "consequence": consequence,
        "alternative": alternative,
        "position": position
    };

    // Attach evaluate function
    node["evaluate"] = ifStatementEvaluate;
    // Attach toJson function
    node["toJson"] = ifStatementToJson;
    node["toGo"] = ifStatementToGo;

    return node;
}

// Evaluate the IfStatement: procedural, explicit, no OO
def ifStatementEvaluate(self, context) {
    let conditionResult = self["condition"]["evaluate"](self["condition"], context);

    if (EvaluatorIsTruthy(conditionResult)) {
        return self["consequence"]["evaluate"](self["consequence"], context);
    } else {
        if (self["alternative"] != null) {
            return self["alternative"]["evaluate"](self["alternative"], context);
        } else {
            return null;
        }
    }
}

// Serialize the IfStatement to json (NO escaping, strict format! No newlines in strings!)
def ifStatementToJson(self) {
    let condPart = null; 
    if (self["condition"] != null) {
        condPart = self["condition"]["toJson"](self["condition"]);
    } else {
        condPart = null; 
    }

    let consPart = null;
    if (self["consequence"] != null) {
        consPart = self["consequence"]["toJson"](self["consequence"]);
    } else {
        consPart = null; 
    }

    let altPart = null;
    if (self["alternative"] != null) {
        altPart = self["alternative"]["toJson"](self["alternative"]);
    } else {
        altPart = null; 
    }

    // return '{ "type": "IfStatement", "position": "' + self["position"] + '", "condition": ' + condPart + ', "consequence": ' + consPart + ', "alternative": ' + altPart + ' }';
    let result = {};
    result["type"] = "IfStatement";
    result["position"] = self["position"];
    result["condition"] = condPart; // condPart is already a map or null
    result["consequence"] = consPart; // consPart is already a map or null
    result["alternative"] = altPart; // altPart is already a map or null
    return result;
}

// D3: emit a Go boolean expression for a condition slot. When the condition
// is an InfixExpression with a comparison operator or a PrefixExpression `!`,
// use a direct bool-returning helper to skip the intermediate BoolValue.
// Fall back to `<value>.IsTruthy()` for anything else.
def conditionToGoBool(condNode) {
    // Phase 2: condition is a child Node in if/while; evalIf/evalWhile evaluate and check IsTruthy
    if (condNode != null) {
        if (condNode["toGo"] != null) {
            condNode["toGo"](condNode);
        }
    }
}

def ifStatementToGo(self) {
    // Phase 2: emit Node tree; evalIf handles condition + branching
    print('&Node{kind: nkIfStmt, left: ');
    conditionToGoBool(self["condition"]);
    print(', body: ');
    if (self["consequence"]["toGo"] != null) {
        self["consequence"]["toGo"](self["consequence"]);
    }
    if (self["alternative"] != null) {
        print(', right: ');
        if (self["alternative"]["toGo"] != null) {
            self["alternative"]["toGo"](self["alternative"]);
        }
    }
    print('}');
}



// === Lexer for InterpreterJ ===
// Usage: let lexer = createLexer(inputString); ... functions below

// Factory function: returns a new lexer "struct" (map)
def createLexer(input) {
  let lexer = {};
  lexer["input"] = input;
  lexer["position"] = 0;
  lexer["readPosition"] = 0;
  lexer["ch"] = "";
  lexer["line"] = 1;
  lexer["column"] = 0;
  lexer["readChar"] = readChar;
  lexer["peekChar"] = peekChar;
  lexer["skipWhitespace"] = skipWhitespace;
  lexer["isLetter"] = isLetter;
  lexer["isDigit"] = isDigit;
  lexer["readIdentifier"] = readIdentifier;
  lexer["readNumber"] = readNumber;
  lexer["readStringLiteral"] = readStringLiteral;
  lexer["skipComments"] = skipComments;
  lexer["nextToken"] = scnnnerNextToken;
  lexer["tokenize"] = tokenize;
  // Initialize first character
  readChar(lexer);
  return lexer;
}

// Reads next character and updates position, line, column
def readChar(lexer) {
  let input = lexer["input"];
  let readPosition = lexer["readPosition"];
  if (readPosition >= len(input)) {
    lexer["ch"] = ""; // Empty string means EOF
  } else {
    lexer["ch"] = char(input, readPosition);
  }
  lexer["position"] = lexer["readPosition"];
  lexer["readPosition"] = lexer["readPosition"] + 1;
  lexer["column"] = lexer["column"] + 1;
  // Handle newlines to track line numbers & column resets
  if (lexer["ch"] == chr(10)) { // chr(10) == "\n"
    lexer["line"] = lexer["line"] + 1;
    lexer["column"] = 0;
  }
}

// Looks at next char, does NOT move position
def peekChar(lexer) {
  let input = lexer["input"];
  let readPosition = lexer["readPosition"];
  if (readPosition >= len(input)) {
    return "";
  } else {
    return char(input, readPosition);
  }
}

// Skips whitespace (space, tab, newline, carriage return)
def skipWhitespace(lexer) {
  while (
    lexer["ch"] == " " ||
    lexer["ch"] == chr(9) ||             // "\t"
    lexer["ch"] == chr(10) ||            // "\n"
    lexer["ch"] == chr(13)               // "\r"
  ) {
    readChar(lexer);
  }
}

// Skips comments (//, /* */, or #) at the lexer position
def skipComments(lexer) {
  if (lexer["ch"] == "/") {
    if (peekChar(lexer) == "/") {
      // single-line comment: skip until end of line/EOF
      while (lexer["ch"] != "" && lexer["ch"] != chr(10)) {
        readChar(lexer);
      }
      if (lexer["ch"] != "") {
        readChar(lexer);
      }
    } else {
      if (peekChar(lexer) == "*") {
        // multi-line comment: skip until */
        readChar(lexer); // skip /
        readChar(lexer); // skip *
        let ended = false;
        while (!ended && lexer["ch"] != "") {
          if (lexer["ch"] == "*" && peekChar(lexer) == "/") {
            ended = true;
            readChar(lexer); // skip *
            readChar(lexer); // skip /
          } else {
            readChar(lexer);
          }
        }
      }
    }
  } else {
    if (lexer["ch"] == "#") {
      // python-style: skip to end of line or EOF
      while (lexer["ch"] != "" && lexer["ch"] != chr(10)) {
        readChar(lexer);
      }
      if (lexer["ch"] != "") {
        readChar(lexer);
      }
    }
  }
}

// Returns true if ch is a letter or underscore
def isLetter(ch) {
  let code = ord(ch);
  if (code >= ord("a") && code <= ord("z")) {
    return true;
  }
  if (code >= ord("A") && code <= ord("Z")) {
    return true;
  }
  if (ch == "_") {
    return true;
  }
  return false;
}

// Returns true if ch is a digit
def isDigit(ch) {
  let code = ord(ch);
  if (code >= ord("0") && code <= ord("9")) {
    return true;
  }
  return false;
}

// Reads a full identifier from the current position, returns as string
def readIdentifier(lexer) {
  let input = lexer["input"];
  let start = lexer["position"];
  while (isLetter(lexer["ch"]) || isDigit(lexer["ch"])) {
    readChar(lexer);
  }
  let end = lexer["position"];
  return substr(input, start, end - start);
}

// Reads a full number (integer or float) from the current position, returns as string
def readNumber(lexer) {
  let input = lexer["input"];
  let start = lexer["position"];
  let hasDot = false;
  while (
     isDigit(lexer["ch"]) ||
     (lexer["ch"] == "." && !hasDot)
  ) {
    if (lexer["ch"] == ".") {
      hasDot = true;
    }
    readChar(lexer);
  }
  let end = lexer["position"];
  return substr(input, start, end - start);
}

// Reads a quoted string (handles '' and "") including empty string, NO ESCAPES
def readStringLiteral(lexer, quote) {
  readChar(lexer); // skip opening
  let input = lexer["input"];
  let start = lexer["position"];
  while (lexer["ch"] != "" && lexer["ch"] != quote) {
    readChar(lexer);
  }
  let end = lexer["position"];
  let strVal = substr(input, start, end - start);
  // Unterminated strings: just return up to now
  if (lexer["ch"] != "") {
    readChar(lexer); // skip closing
  }
  return strVal;
}

// Returns the next token ("consumes") and advances/updates lexer
def scnnnerNextToken(lexer) {
  let token = null;

  // Skip whitespace/comments in loop (keep retrying if something changed)
  let skipped = true;
  while (skipped) {
    let posBefore = lexer["position"];
    skipWhitespace(lexer);
    skipComments(lexer);
    if (lexer["position"] > posBefore) {
      skipped = true;
    } else {
      skipped = false;
    }
  }

  // Scan single/double-char tokens
  let ch = lexer["ch"];
  if (ch == "=") {
    if (peekChar(lexer) == "=") {
      let startColumn = lexer["column"];
      let left = ch;
      readChar(lexer);
      token = createToken(TOKEN_EQ, left + lexer["ch"], lexer["line"], startColumn);
    } else {
      token = createToken(TOKEN_ASSIGN, ch, lexer["line"], lexer["column"]);
    }
  } else {
    if (ch == "+") {
      token = createToken(TOKEN_PLUS, ch, lexer["line"], lexer["column"]);
    } else {
      if (ch == "-") {
        token = createToken(TOKEN_MINUS, ch, lexer["line"], lexer["column"]);
      } else {
        if (ch == "*") {
          token = createToken(TOKEN_ASTERISK, ch, lexer["line"], lexer["column"]);
        } else {
          if (ch == "#") {
            skipComments(lexer);
            return scnnnerNextToken(lexer);
          } else {
            if (ch == "/") {
              if (peekChar(lexer) == "/" || peekChar(lexer) == "*") {
                skipComments(lexer);
                return scnnnerNextToken(lexer);
              } else {
                token = createToken(TOKEN_SLASH, ch, lexer["line"], lexer["column"]);
              }
            } else {
              if (ch == "%") {
                token = createToken(TOKEN_PERCENT, ch, lexer["line"], lexer["column"]);
              } else {
                if (ch == "!") {
                  if (peekChar(lexer) == "=") {
                    let startColumn = lexer["column"];
                    let left = ch;
                    readChar(lexer);
                    token = createToken(TOKEN_NOT_EQ, left + lexer["ch"], lexer["line"], startColumn);
                  } else {
                    token = createToken(TOKEN_NOT, ch, lexer["line"], lexer["column"]);
                  }
                } else {
                  if (ch == "<") {
                    if (peekChar(lexer) == "=") {
                      let startColumn = lexer["column"];
                      let left = ch;
                      readChar(lexer);
                      token = createToken(TOKEN_LT_EQ, left + lexer["ch"], lexer["line"], startColumn);
                    } else {
                      token = createToken(TOKEN_LT, ch, lexer["line"], lexer["column"]);
                    }
                  } else {
                    if (ch == ">") {
                      if (peekChar(lexer) == "=") {
                        let startColumn = lexer["column"];
                        let left = ch;
                        readChar(lexer);
                        token = createToken(TOKEN_GT_EQ, left + lexer["ch"], lexer["line"], startColumn);
                      } else {
                        token = createToken(TOKEN_GT, ch, lexer["line"], lexer["column"]);
                      }
                    } else {
                      if (ch == "&") {
                        if (peekChar(lexer) == "&") {
                          let startColumn = lexer["column"];
                          let left = ch;
                          readChar(lexer);
                          token = createToken(TOKEN_AND, left + lexer["ch"], lexer["line"], startColumn);
                        } else {
                          token = createToken(TOKEN_ILLEGAL, ch, lexer["line"], lexer["column"]);
                        }
                      } else {
                        if (ch == "|") {
                          if (peekChar(lexer) == "|") {
                            let startColumn = lexer["column"];
                            let left = ch;
                            readChar(lexer);
                            token = createToken(TOKEN_OR, left + lexer["ch"], lexer["line"], startColumn);
                          } else {
                            token = createToken(TOKEN_ILLEGAL, ch, lexer["line"], lexer["column"]);
                          }
                        } else {
                          if (ch == ",") {
                            token = createToken(TOKEN_COMMA, ch, lexer["line"], lexer["column"]);
                          } else {
                            if (ch == ";") {
                              token = createToken(TOKEN_SEMICOLON, ch, lexer["line"], lexer["column"]);
                            } else {
                              if (ch == "(") {
                                token = createToken(TOKEN_LPAREN, ch, lexer["line"], lexer["column"]);
                              } else {
                                if (ch == ")") {
                                  token = createToken(TOKEN_RPAREN, ch, lexer["line"], lexer["column"]);
                                } else {
                                  if (ch == "{") {
                                    token = createToken(TOKEN_LBRACE, ch, lexer["line"], lexer["column"]);
                                  } else {
                                    if (ch == "}") {
                                      token = createToken(TOKEN_RBRACE, ch, lexer["line"], lexer["column"]);
                                    } else {
                                      if (ch == "[") {
                                        token = createToken(TOKEN_LBRACKET, ch, lexer["line"], lexer["column"]);
                                      } else {
                                        if (ch == "]") {
                                          token = createToken(TOKEN_RBRACKET, ch, lexer["line"], lexer["column"]);
                                        } else {
                                          if (ch == ":") {
                                            token = createToken(TOKEN_COLON, ch, lexer["line"], lexer["column"]);
                                          } else {
                                            // FIXME if (ch == "\"" || ch == "'") {
                                            if (ch == chr(34) || ch == "'") {  
                                              let quote = ch;
                                              let startColumn = lexer["column"];
                                              let stringVal = readStringLiteral(lexer, quote);
                                              return createToken(TOKEN_STRING, stringVal, lexer["line"], startColumn);
                                            } else {
                                              if (ch == "") {
                                                token = createToken(TOKEN_EOF, "", lexer["line"], lexer["column"]);
                                              } else {
                                                if (isLetter(ch)) {
                                                  let startColumn = lexer["column"];
                                                  let ident = readIdentifier(lexer);
                                                  let typ = lookupKeyword(ident);
                                                  return createToken(typ, ident, lexer["line"], startColumn);
                                                } else {
                                                  if (isDigit(ch)) {
                                                    let startColumn = lexer["column"];
                                                    let num = readNumber(lexer);
                                                    return createToken(TOKEN_NUMBER, num, lexer["line"], startColumn);
                                                  } else {
                                                    token = createToken(TOKEN_ILLEGAL, ch, lexer["line"], lexer["column"]);
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Always move forward if not EOF
  readChar(lexer);
  return token;
}

// Tokenize the entire input and return an array of tokens (may be empty)
def tokenize(lexer) {
  let tokens = [];
  let t = scnnnerNextToken(lexer);
  push(tokens, t);
  while (getTokenType(t) != TOKEN_EOF) {
    t = scnnnerNextToken(lexer);
    push(tokens, t);
  }
  return tokens;
}

// === END Lexer ===



// ---------- PrefixExpression "constructor" ----------
def makePrefixExpression(operator, right, position) {
    let node = {
        "type": "PrefixExpression",
        "operator": operator,
        "right": right,
        "position": position
    };
    // Attach functions explicitly
    node["evaluate"] = PrefixExpression_evaluate;
    node["toJson"] = PrefixExpression_toJson;
    node["toGo"] = PrefixExpression_toGo;
    return node;
}

// ---------- Evaluate Function ----------
def PrefixExpression_evaluate(self, context) {
    // "self" is the PrefixExpression node/map
    let rightNode = self["right"];
    let rightValue = null;
    if (rightNode != null) {
        rightValue = rightNode["evaluate"](rightNode, context);
    }
    let result = Evaluator_applyPrefixOperator(self["operator"], rightValue);
    return result;
}

// ---------- toJson Function ----------
def PrefixExpression_toJson(self) {
    // Stringify child node
    let rightNode = self["right"];
    let rightJson = "null";
    if (rightNode != null) {
        rightJson = rightNode["toJson"](rightNode);
    }

    // return '{ "type": "PrefixExpression", "position": "' +
    //     self["position"] + '", "operator": "' +
    //     self["operator"] + '", "right": ' +
    //     rightJson + ' }';
    let result = {};
    result["type"] = "PrefixExpression";
    result["position"] = self["position"];
    result["operator"] = self["operator"];
    result["right"] = rightJson; // rightJson is already map or null
    return result;
}

def PrefixExpression_toGo(self) {
    // Phase 2: emit Node tree; evalPrefix handles ! and -
    let op = self["operator"];
    let opCode = "opNeg";
    if (op == "!") { opCode = "opNot"; }
    print('&Node{kind: nkPrefix, op: ' + opCode + ', right: ');
    if (self["right"]["toGo"] != null) {
        self["right"]["toGo"](self["right"]);
    }
    print('}');
}



// Token type names as string constants

let TOKEN_EOF = "EOF";
let TOKEN_ILLEGAL = "ILLEGAL";

let TOKEN_IDENTIFIER = "IDENTIFIER";
let TOKEN_NUMBER = "NUMBER";
let TOKEN_STRING = "STRING";

let TOKEN_DEF = "DEF";
let TOKEN_LET = "LET";
let TOKEN_IF = "IF";
let TOKEN_ELSE = "ELSE";
let TOKEN_WHILE = "WHILE";
let TOKEN_RETURN = "RETURN";
let TOKEN_TRUE = "TRUE";
let TOKEN_FALSE = "FALSE";
let TOKEN_NULL = "NULL";

let TOKEN_PLUS = "PLUS";
let TOKEN_MINUS = "MINUS";
let TOKEN_ASTERISK = "ASTERISK";
let TOKEN_SLASH = "SLASH";
let TOKEN_PERCENT = "PERCENT";

let TOKEN_EQ = "EQ";
let TOKEN_NOT_EQ = "NOT_EQ";
let TOKEN_LT = "LT";
let TOKEN_GT = "GT";
let TOKEN_LT_EQ = "LT_EQ";
let TOKEN_GT_EQ = "GT_EQ";

let TOKEN_AND = "AND";
let TOKEN_OR = "OR";
let TOKEN_NOT = "NOT";

let TOKEN_ASSIGN = "ASSIGN";

let TOKEN_COMMA = "COMMA";
let TOKEN_SEMICOLON = "SEMICOLON";
let TOKEN_LPAREN = "LPAREN";
let TOKEN_RPAREN = "RPAREN";
let TOKEN_LBRACE = "LBRACE";
let TOKEN_RBRACE = "RBRACE";
let TOKEN_LBRACKET = "LBRACKET";
let TOKEN_RBRACKET = "RBRACKET";
let TOKEN_COLON = "COLON";

// Map token type -> literal (string shown in source)
let TOKEN_LITERALS = {
  "EOF": "EOF",
  "ILLEGAL": "ILLEGAL",

  "IDENTIFIER": "IDENTIFIER",
  "NUMBER": "NUMBER",
  "STRING": "STRING",

  "DEF": "DEF",
  "LET": "LET",
  "IF": "IF",
  "ELSE": "ELSE",
  "WHILE": "WHILE",
  "RETURN": "RETURN",
  "TRUE": "TRUE",
  "FALSE": "FALSE",
  "NULL": "NULL",

  "PLUS": "+",
  "MINUS": "-",
  "ASTERISK": "*",
  "SLASH": "/",
  "PERCENT": "%",

  "EQ": "==",
  "NOT_EQ": "!=",
  "LT": "<",
  "GT": ">",
  "LT_EQ": "<=",
  "GT_EQ": ">=",

  "AND": "&&",
  "OR": "||",
  "NOT": "!",

  "ASSIGN": "=",

  "COMMA": ",",
  "SEMICOLON": ";",
  "LPAREN": "(",
  "RPAREN": ")",
  "LBRACE": "{",
  "RBRACE": "}",
  "LBRACKET": "[",
  "RBRACKET": "]",
  "COLON": ":"
};

// Function: get the literal for a given token type string
def getTokenLiteral(tokenType) {
  if (TOKEN_LITERALS[tokenType] != null) {
    return TOKEN_LITERALS[tokenType];
  } else {
    return tokenType;
  }
}



// InterpreterJ port of EvaluationContext Java class
// Procedural style, manual explicit map access only, no classes, no dot notation.



// RuntimeError generator - prints message and aborts execution via assert(false)
def raiseRuntimeError(message, line, column) {
    let fullMessage = "RuntimeError: " + message + " at " + line + ":" + column;
    //puts(fullMessage);
    assert(false, fullMessage);
}



// Helper to get line and column number from position map or default 0,0
def getLineCol(position) { // FIXME position mess (map vs. string)
    let line = -1;
    let col = -1;
    if (position != null) {
        if (isArray(position)) {
            // position can be map with getLine() and getColumn() functions or properties
            if (position["getLine"] != null) {
                line = position["getLine"](position);
            } else {
                if (position["line"] != null) {
                    line = position["line"];
                }
            }
            if (position["getColumn"] != null) {
                col = position["getColumn"](position);
            } else {
                if (position["column"] != null) {
                    col = position["column"];
                }
            }
        }
    }
    return [line, col];
}



// Helper function to check if map has key (no 'in' operator, no direct containsKey)
// P-VM.5a: O(1) via the native hasKey builtin (findPair/keyIndex), replacing
// the keys()-alloc + linear scan that was the #2 GC driver after the args-
// array shim. Sole callers are ctxGet/ctxAssign on context maps, whose keys
// are always strings, so the findPair String()-collision quirk (m[1] vs
// m["1"]) cannot bite here. At interpreted layers hasKey chains down to the
// native impl (MapLibraryFunctionsInitializer), so the inner interpreter's
// own ctxAssign no longer does an interpreted full-map scan either.
def mapHasKey(mapObj, key) {
    return hasKey(mapObj, key);
}

// Creates a new EvaluationContext map with initial values and attached functions
def makeEvaluationContext() {
    let ctx = {};

    ctx["parent"] = null;

    ctx["values"] = {};
    ctx["functions"] = {};

    // Attach methods explicitly
    ctx["define"] = ctxDefine;
    ctx["get"] = ctxGet;
    ctx["assign"] = ctxAssign;
    ctx["registerFunction"] = ctxRegisterFunction;
    ctx["extend"] = ctxExtend;

    return ctx;
}

// Define variable in current scope
def ctxDefine(ctx, name, value) {
    // Direct assignment
    let vls = ctx["values"];
    vls[name] = value;
    return value;
}

// Get variable or function from current or parent scopes, with errors on not found
def ctxGet(ctx, name, position) {
    // Hot path: a present, non-null binding. O(1), no scan.
    let val = ctx["values"][name];
    if (val != null) {
        return val;
    }

    // Functions are never registered as null, so a non-null read here is a hit.
    // Checking this BEFORE the values present-null scan is the load-bearing
    // reorder: looking up a builtin or top-level def used to fall through to
    // mapHasKey(values) first, which keys()-allocates and linear-scans the
    // entire (hundreds-deep) global values map on every such lookup. Under
    // selfhost that made ij_mapHasKey_impl the hottest leaf (10% flat / 34% cum
    // via ctxGet — see docs/research/2026-05-29-stage2-cpu.pprof). With the
    // functions probe first, the common builtin/global-fn path never scans.
    val = ctx["functions"][name];
    if (val != null) {
        return val;
    }

    // Both maps read null. The only way that is not a genuine miss is an
    // explicit null binding, and only the values map can hold one (functions
    // are never null), so the scan is restricted to values and skipped entirely
    // for the hot paths above.
    if (mapHasKey(ctx["values"], name)) {
        return null;
    }

    // Recurse to parent scope if any
    if (ctx["parent"] != null) {
        return ctx["parent"]["get"](ctx["parent"], name, position);
    }

    // Not found, raise runtime error
    let arr = getLineCol(position);
    raiseRuntimeError("Undefined variable '" + name + "'", arr[0], arr[1]);
    return null; // unreachable
}

// Assign a value to a variable in current or parent scopes, with errors on undefined
def ctxAssign(ctx, name, value, position) {
    // Try direct assignment first for performance
    let vls = ctx["values"];
    if (vls[name] != null || mapHasKey(vls, name)) {
        vls[name] = value;
        return value;
    }

    // Otherwise recurse into parent if present
    if (ctx["parent"] != null) {
        return ctx["parent"]["assign"](ctx["parent"], name, value, position);
    }

    // Variable not found; raise error
    let arr = getLineCol(position);
    raiseRuntimeError("Cannot assign to undefined variable '" + name + "'", arr[0], arr[1]);
    return null; // unreachable
}

// Register a library function by name in current scope
def ctxRegisterFunction(ctx, name, functionObject) {
    // BAD ctx["functions"][name] = functionObject;
    let fns = ctx["functions"];
    fns[name] = functionObject;
    return functionObject;
}

// Extend current context creating child context with new local scopes
def ctxExtend(ctx) {
    let child = {};

    child["parent"] = ctx;
    child["values"] = {};
    child["functions"] = {};

    // Attach all methods to child context same as parent
    child["define"] = ctxDefine;
    child["get"] = ctxGet;
    child["assign"] = ctxAssign;
    child["registerFunction"] = ctxRegisterFunction;
    child["extend"] = ctxExtend;

    return child;
}

def extendContext(context) { //INTEGRATION
    return ctxExtend(context);
}



// -- TEST --



// Represents an assignment to array or map via [ ] = 
// Fields: "collection", "index", "value", "position"
// All functions are attached to node map by string key.

def makeIndexAssignmentStatement(collection, index, value, position) {
    let node = {
        "type": "IndexAssignmentStatement",
        "collection": collection,
        "index": index,
        "value": value,
        "position": position
    };
    node["evaluate"] = indexAssignmentStatement_evaluate;
    node["toJson"] = indexAssignmentStatement_toJson;
    node["toGo"] = indexAssignmentStatement_toGo;
    return node;
}

// Evaluate (executes assignment) for IndexAssignmentStatement node
def indexAssignmentStatement_evaluate(self, context) {
    let collectionObject = self["collection"]["evaluate"](self["collection"], context);
    let indexValue = self["index"]["evaluate"](self["index"], context);
    let valueToAssign = self["value"]["evaluate"](self["value"], context);

    // Check array
    if (isArray(collectionObject)) {
        return assignToArray(collectionObject, indexValue, valueToAssign, self["position"]);
    } else {
        if (isMap(collectionObject)) {
            return assignToMap(collectionObject, indexValue, valueToAssign, self["position"]);
        } else {
            // Not an array or map: runtime error
            throwRuntimeError("Cannot use index operator on non-collection value, got:"+collectionObject, self["position"]);
            return null;
        }
    }
}

// Assigns value to array at given index
def assignToArray(array, indexValue, valueToAssign, position) {
    if (!isNumber(indexValue)) {
        throwRuntimeError("Array index must be a number", position);
        return null;
    }
    let idx = int(indexValue);
    let length = len(array);
    if (idx < 0 || idx >= length) {
        throwRuntimeError("Array index out of bounds: " + idx + "", position);
        return null;
    }
    array[idx] = valueToAssign;
    return valueToAssign;
}

// Assigns value to map at given key
def assignToMap(mapObj, key, valueToAssign, position) {
    if (!(isString(key) || isNumber(key))) {
        throwRuntimeError("Map key must be a string or number", position);
        return null;
    }
    mapObj[key] = valueToAssign;
    return valueToAssign;
}

// JSON serialization for the node
def indexAssignmentStatement_toJson(self) {
    let collectionJson = null; 
    if (self["collection"] != null) {
        collectionJson = self["collection"]["toJson"](self["collection"]);
    }
    let indexJson = null; 
    if (self["index"] != null) {
        indexJson = self["index"]["toJson"](self["index"]);
    }
    let valueJson = null; 
    if (self["value"] != null) {
        valueJson = self["value"]["toJson"](self["value"]);
    }
    // return '{ "type": "IndexAssignmentStatement", "position": "' + self["position"] + '", "collection": ' + collectionJson + ', "index": ' + indexJson + ', "value": ' + valueJson + ' }';
    let result = {};
    result["type"] = "IndexAssignmentStatement";
    result["position"] = self["position"];
    result["collection"] = collectionJson; // collectionJson is already map or null
    result["index"] = indexJson; // indexJson is already map or null
    result["value"] = valueJson; // valueJson is already map or null
    return result;
}

def indexAssignmentStatement_toGo(self) {
    // Phase 2: emit Node tree; evalIndexAssign handles Put
    print('&Node{kind: nkIndexAssign, left: ');
    if (self["collection"]["toGo"] != null) {
        self["collection"]["toGo"](self["collection"]);
    }
    print(', right: ');
    if (self["index"]["toGo"] != null) {
        self["index"]["toGo"](self["index"]);
    }
    print(', body: ');
    if (self["value"]["toGo"] != null) {
        self["value"]["toGo"](self["value"]);
    }
    print('}');
}



// InterpreterJ translation of MapLiteral Node from Java

// Assumed context: 
// - "let" always needs initializer. 
// - No OOP: everything passes around explicit maps and arrays, never 'this' or dot notation.
// - "position" is assumed to be a field inside the node maps (e.g., node["position"])
// - No function expressions, only def name() { ... }
// - attach functions to node maps with explicit assignment: node["evaluate"] = ...; etc.

// Create a MapLiteral node with explicit "pairs" and "position"
def makeMapLiteral(pairs, position) {
  let node = {};
  node["type"] = "MapLiteral";
  node["pairs"] = pairs;      // pairs: array of {"key": Node, "value": Node} pairs, see below
  node["position"] = position;

  // Attach evaluate function
  def evaluate(self,context) {
    // mapValues will be built as a map with string/number keys only
    let mapValues = {};

    let pairsArr = node["pairs"];
    let i = 0;
    while (i < len(pairsArr)) {
      let pair = pairsArr[i];
      // pair must have {"key": Node, "value": Node}
      let keyNode = pair["key"];
      let valueNode = pair["value"];

      // Evaluate the key
      let key = keyNode["evaluate"](keyNode, context);

      // Validate key type: only string or number allowed
      let keyIsString = false;
      let keyIsNumber = false;
      // Basic runtime type check; assuming typeofString() and typeofNumber() provided by stdlib, or use custom logic
      if (typeof(key) == "string") {
        keyIsString = true;
      } else {
        if (typeof(key) == "number") {
          keyIsNumber = true;
        }
      }
      if (!(keyIsString || keyIsNumber)) {
        // Error: Map keys must be string or number
        // Raise a runtime error (assume RuntimeError constructor: def RuntimeError(msg, line, col))
        let msg = "Map keys must be strings or numbers, got: ";
        if (key == null) {
          msg = msg + "null";
        } else {
          msg = msg + typeof(key);
        }
        // Error expects source position; use node["position"]["line"], node["position"]["column"]
        throw(RuntimeError(msg, node["position"]["line"], node["position"]["column"]));
      }

      // Evaluate the value
      let value = valueNode["evaluate"](valueNode,context);

      mapValues[key] = value;

      i = i + 1;
    }

    return mapValues;
  }
  node["evaluate"] = evaluate;

  // Attach toJson function
  def toJson(self) {
    // Produce a string representation of the map literal including all pairs as JSON-like output
    let pairsArr = node["pairs"];
    
    //puts("MapLiteral.toJson: pairsArr=" + pairsArr); //DEBUG
    
    let pairsJsonArray = [];
    let i = 0;
    while (i < len(pairsArr)) {
      let pair = pairsArr[i];
      let keyNode = pair["key"];
      let valueNode = pair["value"];

      // Convert key/value nodes to JSON
      let keyJson = "null";
      if (keyNode != null) {
        keyJson = keyNode["toJson"](keyNode);
      }
      let valueJson = null; // Changed from "null" string to actual null
      if (valueNode != null) {
        valueJson = valueNode["toJson"](valueNode);
      }

      // Append as map: { "key": <keyJson>, "value": <valueJson> }
      let pairMap = {};
      pairMap["key"] = keyJson;
      pairMap["value"] = valueJson;
      push(pairsJsonArray, pairMap);
      i = i + 1;
    }

    // // Join comma-separated // No longer needed
    // let pairsJson = "";
    // i = 0;
    // while (i < len(pairsJsonArray)) {
    //   if (i > 0) {
    //     pairsJson = pairsJson + ", ";
    //   }
    //   pairsJson = pairsJson + pairsJsonArray[i];
    //   i = i + 1;
    // }

    // Build main object
    // let resultString = '{ "type": "MapLiteral", "position": "' + node["position"] + '", "pairs": [ ' + pairsJson + ' ] }';
    // return resultString;
    let resultMap = {};
    resultMap["type"] = "MapLiteral";
    resultMap["position"] = node["position"];
    resultMap["pairs"] = pairsJsonArray;
    return resultMap;
  }
  node["toJson"] = toJson;

  def toGo(self) {
    // Phase 2: emit Node tree; evalMapLit handles construction
    print('&Node{kind: nkMapLit, list: []*Node{');

    let pairsArr = node["pairs"];
    let i = 0;
    while (i < len(pairsArr)) {
      let pair = pairsArr[i];
      let keyNode = pair["key"];
      let valueNode = pair["value"];

      if (i > 0) {
        print(",");
      }

      if (keyNode["toGo"] != null) {
        keyNode["toGo"](keyNode);
      }

      print(',');

      if (valueNode["toGo"] != null) {
        valueNode["toGo"](valueNode);
      }

      i = i + 1;
    }

    print('}}');
  }
  node["toGo"] = toGo;

  return node;
}



// Program node - the root of every AST

// Create Program node as a map literal with methods attached manually

def makeProgram() {
    let program = {
        "type": "Program",
        "statements": []
    };

    def addStatement(self, statement) {
        if (statement != null) {
            push(program["statements"], statement);
        }
    }
    program["addStatement"] = addStatement;

    //FIXME not supported: program["getStatements"] = def() {
    def getStatements() {
        return program["statements"];
    }
    program["getStatements"] = getStatements;

    // context must be a map holding runtime state
    def evaluate(self, context) {
        let result = null;
        let stmts = program["statements"];
        let n = len(stmts);
        let i = 0;
        while (i < n) {
            let statement = stmts[i];
            result = statement["evaluate"](statement,context);
            
            // Early return if we hit a ReturnValue (represented as a map with type "ReturnValue")
            //if (result != null) {
            //    //if (isArray(result)) { if (result["type"] == "ReturnValue") { // FIXME we need to agree whether eval returns a map with a key value or directly a value
            //    //    return result["value"]; // FIXME return support
            //    //} }
            //}

            if (isReturnValue(result)) {
                return result["value"];
            }

            i = i + 1;
        }
        return result;
    }
    program["evaluate"] = evaluate;

    // toJson method
    def toJson(self) {
        let stmts = program["statements"];
        let parts = []; // This will now collect maps
        let n = len(stmts);
        let i = 0;
        while (i < n) {
            // Assuming stmts[i]["toJson"] now returns a map
            push(parts, stmts[i]["toJson"](stmts[i]));
            i = i + 1;
        }
        // // Join with ",\n" (not a real newline inside the string, just comma and backslash-n as two characters)
        // let sep = ","; // FIXME ",\n"; // No longer needed
        // let out = ""; // No longer needed
        // let j = 0; // No longer needed
        // while (j < len(parts)) { // No longer needed
        //     if (j == 0) { // No longer needed
        //         out = parts[j]; // No longer needed
        //     } else { // No longer needed
        //         out = out + sep + parts[j]; // No longer needed
        //     } // No longer needed
        //     j = j + 1; // No longer needed
        // } // No longer needed
        // return '{ "type": "Program", "statements": [ ' + out + ' ] }';
        let result = {};
        result["type"] = "Program";
        result["statements"] = parts; // 'parts' is now a list of maps
        return result;
    }
    program["toJson"] = toJson;

    def toGo(self) {
        // Populate the package-level Go vars that cache built-in library
        // functions so static references (C6) see the right Value. Done
        // once at program start, right after registerLibraryFunctions(ctx)
        // from goLibPrefix ran.
        let libs = self["resolvedLibraryGlobals"];
        if (libs != null) {
            let li = 0;
            while (li < len(libs)) {
                let lname = libs[li];
                puts(mangle(lname) + ' = ctx.Get("' + lname + '")');
                li = li + 1;
            }
        }

        let stmts = self["statements"];
        let n = len(stmts);

        let i = 0;
        while (i < n) {
            let stmt = stmts[i];
            if (stmt["toGo"] != null) {
                stmt["toGo"](stmt);
                puts("");
            }
            i = i + 1;
        }
    }
    if (useNodeTree) {
        program["toGo"] = programToGoPhase2;
    } else {
        program["toGo"] = toGo;
    }

    return program;
}



// Utility: create VariableDeclaration AST node as a map
def makeVariableDeclaration(name, initializer, position) {
    let node = {
        "type": "VariableDeclaration",
        "position": position,
        "name": name,
        "initializer": initializer
    }
    node["evaluate"] = evaluateVariableDeclaration
    node["toJson"] = variableDeclarationToJson
    node["toGo"] = variableDeclarationToGo;

    return node
}

// Actual evaluation logic
def evaluateVariableDeclaration(self, context) {
    // Check if initializer exists, otherwise use null
    let init = self["initializer"]
    let value = null
    if (init != null) {
        value = init["evaluate"](init, context)
    } else {
        value = null
    }
    // context["define"](name, value)
    return context["define"](context, self["name"], value)
}

// JSON representation
def variableDeclarationToJson(self) {
    // let result = '{ "type": "VariableDeclaration", "position": "' + self["position"] + '", "name": "' + self["name"] + '", "initializer": '
    let init = self["initializer"];
    let initJson = null; 
    if (init != null) {
        initJson = init["toJson"](init); // initJson is already a map or null
    }
    // result = result + ' }' // No longer needed
    // return result
    let mapResult = {};
    mapResult["type"] = "VariableDeclaration";
    mapResult["position"] = self["position"];
    mapResult["name"] = self["name"];
    mapResult["initializer"] = initJson;
    return mapResult;
}

def variableDeclarationToGo(self) {
    // Phase 2.5: project resolver annotation. evalVarDecl currently ignores
    // it (every binding goes into the current ctx regardless), so this is
    // documentation-only until P4 slot-indexed contexts care about it.
    print('&Node{kind: nkVarDecl, name: "' + self["name"] + '"');
    if (self["resolvedKind"] != null) {
        print(", resolvedKind: ");
        print(resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
    }
    let init = self["initializer"];
    if (init != null) {
        print(', right: ');
        if (init["toGo"] != null) {
            init["toGo"](init);
        }
    }
    print('}');
}



def goLibPrefix() {
puts("");
puts("package main");
puts("import (");
puts("" + chr(34) + "bufio" + chr(34) + "");
puts("" + chr(34) + "crypto/rand" + chr(34) + "");
puts("" + chr(34) + "encoding/hex" + chr(34) + "");
puts("" + chr(34) + "fmt" + chr(34) + "");
puts("" + chr(34) + "io" + chr(34) + "");
puts("" + chr(34) + "math" + chr(34) + "");
puts("" + chr(34) + "os" + chr(34) + "");
puts("" + chr(34) + "regexp" + chr(34) + "");
puts("" + chr(34) + "runtime/pprof" + chr(34) + "");
puts("" + chr(34) + "strconv" + chr(34) + "");
puts("" + chr(34) + "strings" + chr(34) + "");
puts("" + chr(34) + "unsafe" + chr(34) + "");
puts(")");
puts("var stdinReader *bufio.Reader = bufio.NewReader(os.Stdin)");
puts("var regexCache = make(map[string]*regexp.Regexp)");
puts("func Foo() {");
puts("fmt.Println(" + chr(34) + "foo" + chr(34) + ")");
puts("}");
puts("func GenerateSecureID() (string, error) {");
puts("const byteLen = 16");
puts("bytes := make([]byte, byteLen)");
puts("_, err := rand.Read(bytes)");
puts("if err != nil {");
puts("return " + chr(34) + "" + chr(34) + ", fmt.Errorf(" + chr(34) + "failed to generate random bytes: %w" + chr(34) + ", err)");
puts("}");
puts("hexStr := hex.EncodeToString(bytes)");
puts("return " + chr(34) + "r" + chr(34) + " + hexStr, nil");
puts("}");
puts("var ijCountNewContext uint64");
puts("var ijCountCreate uint64");
puts("var ijCountGet uint64");
puts("var ijCountMapGet uint64");
puts("var ijCountMapPut uint64");
puts("var ijCountFuncExec uint64");
puts("var ijCountNewMap uint64");
puts("var ijCountNewArr uint64");
puts("var ijCountUpdate uint64");
puts("var ijCountCtxPromote uint64");
// P-VM.5a: ijb_* fixed-arity builtin impls. Single source of truth for the
// hot builtins: the registerLibraryFunctions closures delegate here, and
// CallExpression_toGoDirect emits direct ijb_* calls for pristine-lib
// callees (resolvedOrigin=="lib" guarantees no top-level def/let shadows
// the name anywhere in the program, because the resolver hoists all root
// declarations before resolving bodies). This kills the per-call
// Execute(ctx, NewArrayValue(...)) shim -- the top allocation source in
// the P-VM.4 selfhost profile (NewArrayValue 5.2% + closure dispatch).
puts("func ijb_len(x Value) Value { return Value{tag: tInt, i: int64(x.Length())} }");
puts("func ijb_typeof(v Value) Value { return v.Type() }");
puts("func ijb_string(v Value) Value { return Value{tag: tString, s: v.ValueString()} }");
puts("func ijb_isArray(v Value) Value { return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "array" + chr(34) + "} }");
puts("func ijb_isMap(v Value) Value { return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "map" + chr(34) + "} }");
puts("func ijb_isNumber(v Value) Value { return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "number" + chr(34) + "} }");
puts("func ijb_isString(v Value) Value { return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "string" + chr(34) + "} }");
puts("func ijb_push(arr Value, ele Value) Value {");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "push: expected array" + chr(34) + ")");
puts("}");
puts("arr.arrp().values = append(arr.arrp().values, ele)");
puts("return arr");
puts("}");
puts("func ijb_keys(arr Value) Value {");
puts("if arr.tag != tMap {");
puts("return vInvalid(" + chr(34) + "keys: expected map" + chr(34) + ")");
puts("}");
puts("keys := make([]Value, len(arr.mp().pairs))");
puts("i := 0");
puts("for _, pair := range arr.mp().pairs {");
puts("keys[i] = pair.Key");
puts("i++");
puts("}");
puts("return vArray(NewArrayValue(keys...))");
puts("}");
puts("func ijb_char(str Value, pos Value) Value {");
puts("if str.tag != tString {");
puts("return vInvalid(" + chr(34) + "char: expected key" + chr(34) + ")");
puts("}");
puts("posVal := pos.IntValue()");
puts("if posVal >= 0 && posVal < len(str.s) {");
puts("return Value{tag: tString, s: string(str.s[posVal])}");
puts("} else {");
puts("return vNull()");
puts("}");
puts("}");
puts("func ijb_chr(asciiCode Value) Value { return Value{tag: tString, s: string(rune(asciiCode.IntValue()))} }");
puts("func ijb_ord(c Value) Value { return Value{tag: tInt, i: int64(c.String()[0])} }");
puts("func ijb_substr(str Value, start Value, length Value) Value { return Value{tag: tString, s: str.ValueString()[start.IntValue() : start.IntValue()+length.IntValue()]} }");
// hasKey: O(1) key-presence via the same findPair the language's own map
// index reads use (keyIndex on Key.String()). Non-map receivers are false,
// matching the old IJ-level mapHasKey scan (keys(nonmap) -> invalid ->
// len==0 -> false).
puts("func ijb_hasKey(m Value, k Value) Value {");
puts("if m.tag != tMap {");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("_, found := m.mp().findPair(k)");
puts("return Value{tag: tBool, b: found}");
puts("}");
// P-VM.5c/5d: native dispatch loop for the IJ-side bytecode VM. The IJ-side
// ijvmCallChunk/ijvmRunTopChunk are thin gates into the native CALL
// protocol (ijb_ijvmCallNative -> natCallChunk -> natExec), so chunk-op
// dispatch AND the call frame protocol run at native speed at EVERY
// interpretation depth: the binary's entry points call it directly
// (positional hooks = the binary's own ij_* functions), and each
// interpreted layer reaches it through a chained registration
// (DefaultLibraryFunctionsInitializer), with hooks = that layer's own
// function VALUES (1-arg args-array closures -- the meta-level encoding
// evaluateFunctionDeclaration gives every interpreted function). The depth
// parameter selects the call encoding.
// Semantic work (infix/prefix operators, ctx get/assign/define, index
// load/store, truthiness, runtime errors) still goes through the hooks, so
// per-layer semantics and overlay overrides behave exactly like the old
// interpreted loop (which resolved the same names at its own layer).
puts("type natChunk struct {");
puts("ops []int32");
puts("aa []int32");
puts("bb []int32");
puts("consts []Value");
puts("names []Value");
puts("poss []Value");
puts("nodes []Value");
puts("numSlots int");
puts("numParams int");
puts("maxDepth int");
puts("}");
puts("var natChunkCache = map[*MapValue]*natChunk{}");
puts('func natChunkArr(ch *MapValue, key string) []Value {');
puts("v := ch.Get(Value{tag: tString, s: key})");
puts("if v.tag != tArray { return nil }");
puts("return v.arrp().values");
puts("}");
puts("func natChunkInts(ch *MapValue, key string) []int32 {");
puts("vs := natChunkArr(ch, key)");
puts("out := make([]int32, len(vs))");
puts("for i := 0; i < len(vs); i++ { out[i] = int32(vs[i].IntValue()) }");
puts("return out");
puts("}");
// Chunks are immutable once compiled (ijvmPatchA runs during compile only),
// so the decoded int arrays + Value slice headers are safe to cache by map
// identity. The size bound keeps long-running MCP sessions from leaking.
puts("func natDecodeChunk(ch *MapValue) *natChunk {");
puts("if c, ok := natChunkCache[ch]; ok { return c }");
puts("if len(natChunkCache) > 16384 { natChunkCache = map[*MapValue]*natChunk{} }");
puts("nc := &natChunk{}");
puts('nc.ops = natChunkInts(ch, "ops")');
puts('nc.aa = natChunkInts(ch, "a")');
puts('nc.bb = natChunkInts(ch, "b")');
puts('nc.consts = natChunkArr(ch, "consts")');
puts('nc.names = natChunkArr(ch, "names")');
puts('nc.poss = natChunkArr(ch, "poss")');
puts('nc.nodes = natChunkArr(ch, "nodes")');
puts('nc.numSlots = ch.Get(Value{tag: tString, s: "numSlots"}).IntValue()');
puts('nc.numParams = ch.Get(Value{tag: tString, s: "numParams"}).IntValue()');
puts('nc.maxDepth = ch.Get(Value{tag: tString, s: "maxDepth"}).IntValue()');
puts("natChunkCache[ch] = nc");
puts("return nc");
puts("}");
// Native fast paths for the hot hook operations. Each mirrors its IJ def in
// this file EXACTLY (applyInfixOperator, isTruthy, applyPrefixOperator,
// ctxGet/ctxAssign/ctxDefine, ijvmIndexLoad/ijvmIndexPut); any case whose
// fidelity is uncertain (error paths, the _isArray quirk, mixed-type "+",
// float array indexes) reports ok=false and the op falls back to the layer's
// hook. This removes the per-op hook Execute + depth-wrapping allocations
// that made GC the wall-clock bottleneck when the native loop landed
// (gctrace showed 22-24% GC under GOMAXPROCS=1), and it works at every
// depth because contexts/collections are plain MapValue/ArrayValue data at
// the native level no matter how many interpretation layers built them.
// natTruthy = IJ isTruthy: arrays/maps/functions/invalid are ALWAYS truthy
// (Value.IsTruthy is length-based for collections -- do not substitute it).
puts("func natTruthy(v Value) bool {");
puts("switch v.tag {");
puts("case tNull: return false");
puts("case tBool: return v.b");
puts("case tInt: return v.i != 0");
puts("case tDouble: return v.f() != 0");
puts("case tString: return len(v.s) > 0");
puts("}");
puts("return true");
puts("}");
// Non-numeric "==" mirror (numeric pairs are handled before this is
// consulted): null only equals null; same-typeof scalars compare; arrays,
// maps, functions and invalids are never equal (leftEquals).
puts("func natEq(l Value, r Value) bool {");
puts("if l.tag == tNull { return r.tag == tNull }");
puts("if l.tag == tString && r.tag == tString { return l.s == r.s }");
puts("if l.tag == tBool && r.tag == tBool { return l.b == r.b }");
puts("return false");
puts("}");
puts("func natInfix(l Value, op string, r Value) (Value, bool) {");
puts("ln := l.tag == tInt || l.tag == tDouble");
puts("rn := r.tag == tInt || r.tag == tDouble");
puts("if ln && rn {");
puts("switch op {");
puts('case "+": return l.Add(r), true');
puts('case "-": return l.Subtract(r), true');
puts('case "*": return l.Multiply(r), true');
puts('case "/": return l.Divide(r), true');
puts('case "%": return l.Modulo(r), true');
puts('case "<": return l.LessThan(r), true');
puts('case ">": return l.BiggerThan(r), true');
puts('case "<=": return l.LessThanEqual(r), true');
puts('case ">=": return l.BiggerThanEqual(r), true');
puts('case "==": return l.Equals(r), true');
puts('case "!=": return l.Equals(r).Not(), true');
puts("}");
puts("return vNull(), false");
puts("}");
puts("switch op {");
puts('case "+":');
puts("if l.tag == tString && r.tag == tString { return Value{tag: tString, s: l.s + r.s}, true }");
puts("if l.tag == tArray && r.tag == tArray { return l.Add(r), true }");
puts('case "&&": return vBool(natTruthy(l) && natTruthy(r)), true');
puts('case "||": return vBool(natTruthy(l) || natTruthy(r)), true');
puts('case "==": return vBool(natEq(l, r)), true');
puts('case "!=": return vBool(!natEq(l, r)), true');
puts("}");
puts("return vNull(), false");
puts("}");
// "-" on a number compiles to vInt(0).Subtract(v) everywhere (see
// prefixExpressionToGoDirect); reusing it keeps -0.0 formatting identical.
puts("func natPrefix(op string, v Value) (Value, bool) {");
puts('if op == "!" { return vBool(!natTruthy(v)), true }');
puts('if op == "-" {');
puts("if v.tag == tInt || v.tag == tDouble { return vInt(0).Subtract(v), true }");
puts("return vNull(), true");
puts("}");
puts("return vNull(), false");
puts("}");
puts('var natKeyValues = Value{tag: tString, s: "values"}');
puts('var natKeyFunctions = Value{tag: tString, s: "functions"}');
puts('var natKeyParent = Value{tag: tString, s: "parent"}');
// ctxGet probe order is load-bearing: values non-null hit, then functions
// non-null hit, then values present-but-null (explicit null binding), then
// parent. A miss at the chain root is the undefined-variable error path ->
// bail so the layer's hook raises it.
puts("func natCtxGet(ctx Value, name Value) (Value, bool) {");
puts("cur := ctx");
puts("for cur.tag == tMap {");
puts("cm := cur.mp()");
puts("vv := cm.Get(natKeyValues)");
puts("if vv.tag != tMap { return vNull(), false }");
puts("vm := vv.mp()");
puts("vFound := false");
puts("if idx, ok := vm.findPair(name); ok {");
puts("vFound = true");
puts("if val := vm.pairs[idx].Value; val.tag != tNull { return val, true }");
puts("}");
puts("fv := cm.Get(natKeyFunctions)");
puts("if fv.tag != tMap { return vNull(), false }");
puts("if idx, ok := fv.mp().findPair(name); ok {");
puts("if val := fv.mp().pairs[idx].Value; val.tag != tNull { return val, true }");
puts("}");
puts("if vFound { return vNull(), true }");
puts("cur = cm.Get(natKeyParent)");
puts("}");
puts("return vNull(), false");
puts("}");
puts("func natCtxAssign(ctx Value, name Value, val Value) (Value, bool) {");
puts("cur := ctx");
puts("for cur.tag == tMap {");
puts("cm := cur.mp()");
puts("vv := cm.Get(natKeyValues)");
puts("if vv.tag != tMap { return vNull(), false }");
puts("vm := vv.mp()");
puts("if idx, ok := vm.findPair(name); ok { vm.pairs[idx].Value = val; return val, true }");
puts("cur = cm.Get(natKeyParent)");
puts("}");
puts("return vNull(), false");
puts("}");
puts("func natCtxDefine(ctx Value, name Value, val Value) (Value, bool) {");
puts("if ctx.tag != tMap { return vNull(), false }");
puts("vv := ctx.mp().Get(natKeyValues)");
puts("if vv.tag != tMap { return vNull(), false }");
puts("vv.mp().Put(name, val)");
puts("return val, true");
puts("}");
// Index load: scalars route through Value.Get so the meta-level poison flow
// (invalid values) matches ijvmIndexLoad's map-read of a scalar. Maps with a
// "_isArray" key and out-of-bounds/non-int array reads bail to the hook.
puts("func natIndexLoad(coll Value, idx Value) (Value, bool) {");
puts("switch coll.tag {");
puts("case tArray:");
puts("if idx.tag != tInt { return vNull(), false }");
puts("a := coll.arrp()");
puts("i := int(idx.i)");
puts("if i < 0 || i >= len(a.values) { return vNull(), false }");
puts("return a.values[i], true");
puts("case tMap:");
puts("m := coll.mp()");
puts('if _, ok := m.keyIndex["_isArray"]; ok { return vNull(), false }');
puts("if idx.tag == tString || idx.tag == tInt || idx.tag == tDouble { return m.Get(idx), true }");
puts("return vNull(), false");
puts("case tNull:");
puts("return vNull(), false");
puts("}");
puts("if idx.tag == tString || idx.tag == tInt || idx.tag == tDouble { return coll.Get(idx), true }");
puts("return vNull(), false");
puts("}");
puts("func natIndexPut(coll Value, idx Value, v Value) (Value, bool) {");
puts("if coll.tag == tArray {");
puts("if idx.tag != tInt { return vNull(), false }");
puts("a := coll.arrp()");
puts("i := int(idx.i)");
puts("if i < 0 || i >= len(a.values) { return vNull(), false }");
puts("a.values[i] = v");
puts("return v, true");
puts("}");
puts("if coll.tag == tMap {");
puts("if idx.tag == tString || idx.tag == tInt || idx.tag == tDouble { coll.mp().Put(idx, v); return v, true }");
puts("return vNull(), false");
puts("}");
puts("return vNull(), false");
puts("}");
// The loop mirrors ijvmExecFallback (src IJ def) op for op.
//
// DEPTH = the host layer's interpretation depth (0 = the binary executing
// its guest's chunks; 1 = a depth-1 interpreted interpreter executing ITS
// guest; ...). It determines the meta-level call encoding: a function value
// created by machinery at depth d is a closure tower that unwraps
// params.values[0] once per level, so calling it with logical args L needs
// wrap-by-one applied d times ([L] at d=1, [[L]] at d=2, ...). Hooks are
// the host's own machinery functions (depth wraps; depth 0 = the binary's
// compiled defs, which take positional params). op-5 callees are guest
// values (depth+1 wraps). The chain registration in
// DefaultLibraryFunctionsInitializer increments depth one hop per layer.
//
// Hook calls at depth 0 use a per-frame reusable buffer: every callee
// (impl wrappers, interpreted closure param binding, ijvmCallChunk slot
// copies) COPIES values out of the args array during its prologue and
// never retains the array itself, and re-entrancy is safe because nested
// exec frames own their own buffers while this frame is suspended.
// op-5/15/16 build fresh collections (those escape into program data).
// The stack is accessed through the *ArrayValue on every op because
// nested calls grow it via append (ijvmEnsureStack).
// P-VM.5d: the native side OWNS the per-layer stack pointer (keyed by the
// stack's *ArrayValue identity -- one ijvmStack per layer, pointer-stable
// across growth). Every chunk-frame entry goes through natCallChunk: the
// IJ-side ijvmCallChunk/ijvmRunTopChunk gate straight into it (via the
// ijvmCallNative builtin), and the op-5 same-layer fast path below calls
// it directly. The IJ-side ijvmSP is only live on the IJ_VM_NATEXEC=0
// fallback path; the two never interleave (the gate is a per-layer
// startup constant).
puts("var natSP = map[*ArrayValue]int{}");
puts("func natEnsureStack(stk *ArrayValue, need int) {");
puts("for len(stk.values) < need { stk.values = append(stk.values, vNull()) }");
puts("}");
// P-VM.5d: per-layer call environment, recorded on the first chunk frame a
// layer runs (every layer enters natCallChunk through its own gate before
// any of its guest functions can be called). A layer's hook values and
// depth are startup constants (top-level lets; one ijvm state per layer),
// so the first-entry snapshot is always valid. FunctionCommand.Execute
// uses this to run a stamped callee's chunk directly even when the call
// arrives from a DIFFERENT layer or from tree-walked code -- the cases the
// op-5 same-layer fast path cannot see.
puts("type natLayerInfo struct {");
puts("h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11 Value");
puts("depth int");
puts("}");
puts("var natLayer = map[*ArrayValue]*natLayerInfo{}");
// Mirrors the IJ ijvmCallChunk EXACTLY: bind params (null-pad missing,
// drop extras), reserve the frame window, run, restore SP. frameCtx for
// function chunks = the captured defCtx; top-level chunks pass the program
// ctx and have numParams 0 (so a nil av is fine).
puts("func natCallChunk(nc *natChunk, stk *ArrayValue, defCtx Value, av []Value, hInfix Value, hPrefix Value, hCtxGet Value, hCtxAssign Value, hCtxDefine Value, hTruthy Value, hIdxLoad Value, hIdxPut Value, hErrNew Value, hThrow Value, hBadKey Value, depth int) Value {");
puts("if _, ok := natLayer[stk]; !ok {");
puts("natLayer[stk] = &natLayerInfo{hInfix, hPrefix, hCtxGet, hCtxAssign, hCtxDefine, hTruthy, hIdxLoad, hIdxPut, hErrNew, hThrow, hBadKey, depth}");
puts("}");
puts("base := natSP[stk]");
puts("top := base + nc.numSlots + nc.maxDepth");
puts("natEnsureStack(stk, top)");
puts("np := nc.numParams");
puts("na := len(av)");
puts("for i := 0; i < np; i++ {");
puts("if i < na { stk.values[base+i] = av[i] } else { stk.values[base+i] = vNull() }");
puts("}");
puts("natSP[stk] = top");
puts("r := natExec(nc, stk, base, defCtx, hInfix, hPrefix, hCtxGet, hCtxAssign, hCtxDefine, hTruthy, hIdxLoad, hIdxPut, hErrNew, hThrow, hBadKey, depth)");
puts("natSP[stk] = base");
puts("return r");
puts("}");
puts("func natExec(nc *natChunk, stk *ArrayValue, base int, frameCtx Value, hInfix Value, hPrefix Value, hCtxGet Value, hCtxAssign Value, hCtxDefine Value, hTruthy Value, hIdxLoad Value, hIdxPut Value, hErrNew Value, hThrow Value, hBadKey Value, depth int) Value {");
puts("sp := base + nc.numSlots");
puts("pc := 0");
puts("n := len(nc.ops)");
puts("var hb [4]Value");
puts("hargs := ArrayValue{}");
puts("callHook := func(h Value, cnt int) Value {");
puts("if depth == 0 {");
puts("hargs.values = hb[:cnt]");
puts("return h.Execute(nil, &hargs)");
puts("}");
puts("cur := NewArrayValue(hb[:cnt]...)");
puts("for i := 0; i < depth; i++ { cur = NewArrayValue(vArray(cur)) }");
puts("return h.Execute(nil, cur)");
puts("}");
// STALE-SLICE HAZARD: `stk.values[i] = <call>` evaluates the slice header
// BEFORE the call; a hook can re-enter ijvmEnsureStack whose append
// reallocates the backing array, so the store would land in the dead one.
// Every call result is therefore staged in a temp and stored afterwards
// (re-reading stk.values through the *ArrayValue pointer).
puts("for pc < n {");
puts("op := nc.ops[pc]");
puts("switch op {");
puts("case 1:");
puts("stk.values[sp] = stk.values[base+int(nc.aa[pc])]");
puts("sp++");
puts("pc++");
puts("case 2:");
puts("stk.values[sp] = nc.consts[nc.aa[pc]]");
puts("sp++");
puts("pc++");
puts("case 3:");
puts("r := stk.values[sp-1]");
puts("sp--");
puts("opv := nc.consts[nc.aa[pc]]");
puts("rv, ok := natInfix(stk.values[sp-1], opv.s, r)");
puts("if !ok {");
puts("hb[0] = stk.values[sp-1]");
puts("hb[1] = opv");
puts("hb[2] = r");
puts("rv = callHook(hInfix, 3)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
// natTruthy IS the layer's isTruthy (total over all tags), so op 4 never
// calls hTruthy; the hook stays in the signature for the chain protocol.
puts("case 4:");
puts("c := stk.values[sp-1]");
puts("sp--");
puts("if natTruthy(c) { pc++ } else { pc = int(nc.aa[pc]) }");
// op 5 mirrors the source loop's `fv(args)`: guest function values need
// depth+1 wraps (one more than hooks -- guest values carry one more
// closure level than the host's own machinery functions).
// P-VM.5d fast path: a callee that ijvmTagFn stamped with a chunk AND
// whose stack is THIS layer's stack runs natCallChunk directly -- no args
// copy, no depth-wrap tower, no Execute -> functionValue tree-walk ->
// ijvmCallChunk round trip. Same stack <=> same layer <=> same hooks +
// depth (hooks are top-level lets, one ijvm state per layer). The arg
// window [sp-argc, sp) is disjoint from the callee's slot window (which
// starts at this frame's top), and natCallChunk re-reads stk.values after
// any growth, so passing the live sub-slice is safe.
puts("case 5:");
puts("argc := int(nc.aa[pc])");
puts("fnv := stk.values[sp-argc-1]");
puts("if fnv.tag == tFunc {");
puts("fc := fnv.cmdp()");
puts("if fc.ijChunk != nil && fc.ijStack == stk {");
puts("rv := natCallChunk(fc.ijChunk, stk, fc.ijDefCtx, stk.values[sp-argc:sp], hInfix, hPrefix, hCtxGet, hCtxAssign, hCtxDefine, hTruthy, hIdxLoad, hIdxPut, hErrNew, hThrow, hBadKey, depth)");
puts("sp -= argc");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("break");
puts("}");
puts("}");
puts("av := make([]Value, argc)");
puts("copy(av, stk.values[sp-argc:sp])");
puts("sp -= argc");
puts("fv := stk.values[sp-1]");
puts("cur := NewArrayValue(av...)");
puts("for i := 0; i <= depth; i++ { cur = NewArrayValue(vArray(cur)) }");
puts("rv := fv.Execute(nil, cur)");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("case 6:");
puts("si := nc.aa[pc]");
puts("rv, ok := natCtxGet(frameCtx, nc.names[si])");
puts("if !ok {");
puts("hb[0] = frameCtx");
puts("hb[1] = nc.names[si]");
puts("hb[2] = nc.poss[si]");
puts("rv = callHook(hCtxGet, 3)");
puts("}");
puts("stk.values[sp] = rv");
puts("sp++");
puts("pc++");
puts("case 7:");
puts("stk.values[base+int(nc.aa[pc])] = stk.values[sp-1]");
puts("pc++");
puts("case 8:");
puts("pc = int(nc.aa[pc])");
puts("case 9:");
puts("sp--");
puts("pc++");
puts("case 10:");
puts("idxv := stk.values[sp-1]");
puts("sp--");
puts("rv, ok := natIndexLoad(stk.values[sp-1], idxv)");
puts("if !ok {");
puts("hb[0] = stk.values[sp-1]");
puts("hb[1] = idxv");
puts("hb[2] = nc.nodes[nc.aa[pc]]");
puts("rv = callHook(hIdxLoad, 3)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("case 11:");
puts("if stk.values[sp-1].tag == tNull {");
puts("nd := nc.nodes[nc.bb[pc]]");
puts('hb[0] = Value{tag: tString, s: "Cannot call null as a function"}');
puts('hb[1] = nd.Get(Value{tag: tString, s: "position"})');
puts("errv := callHook(hErrNew, 2)");
puts("hb[0] = errv");
puts("callHook(hThrow, 1)");
puts("stk.values[sp-1] = vNull()");
puts("pc = int(nc.aa[pc])");
puts("} else {");
puts("pc++");
puts("}");
puts("case 12:");
puts("si := nc.aa[pc]");
puts("rv, ok := natCtxAssign(frameCtx, nc.names[si], stk.values[sp-1])");
puts("if !ok {");
puts("hb[0] = frameCtx");
puts("hb[1] = nc.names[si]");
puts("hb[2] = stk.values[sp-1]");
puts("hb[3] = nc.poss[si]");
puts("rv = callHook(hCtxAssign, 4)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("case 13:");
puts("return stk.values[sp-1]");
puts("case 14:");
puts("opv := nc.consts[nc.aa[pc]]");
puts("rv, ok := natPrefix(opv.s, stk.values[sp-1])");
puts("if !ok {");
puts("hb[0] = opv");
puts("hb[1] = stk.values[sp-1]");
puts("rv = callHook(hPrefix, 2)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("case 15:");
puts("cnt := int(nc.aa[pc])");
puts("av := make([]Value, cnt)");
puts("copy(av, stk.values[sp-cnt:sp])");
puts("sp -= cnt");
puts("stk.values[sp] = vArray(NewArrayValue(av...))");
puts("sp++");
puts("pc++");
puts("case 16:");
puts("take := int(nc.aa[pc]) * 2");
puts("m2 := NewEmptyMapValue()");
puts("j := sp - take");
puts("for j < sp {");
puts("k := stk.values[j]");
puts("if k.tag != tString && k.tag != tInt && k.tag != tDouble {");
puts("hb[0] = nc.nodes[nc.bb[pc]]");
puts("hb[1] = frameCtx");
puts("callHook(hBadKey, 2)");
puts("}");
puts("m2.Put(k, stk.values[j+1])");
puts("j += 2");
puts("}");
puts("sp -= take");
puts("stk.values[sp] = vMap(m2)");
puts("sp++");
puts("pc++");
puts("case 17:");
puts("v3 := stk.values[sp-1]");
puts("i3 := stk.values[sp-2]");
puts("sp -= 2");
puts("rv, ok := natIndexPut(stk.values[sp-1], i3, v3)");
puts("if !ok {");
puts("hb[0] = stk.values[sp-1]");
puts("hb[1] = i3");
puts("hb[2] = v3");
puts("hb[3] = nc.nodes[nc.aa[pc]]");
puts("rv = callHook(hIdxPut, 4)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("default:");
puts("si := nc.aa[pc]");
puts("rv, ok := natCtxDefine(frameCtx, nc.names[si], stk.values[sp-1])");
puts("if !ok {");
puts("hb[0] = frameCtx");
puts("hb[1] = nc.names[si]");
puts("hb[2] = stk.values[sp-1]");
puts("rv = callHook(hCtxDefine, 3)");
puts("}");
puts("stk.values[sp-1] = rv");
puts("pc++");
puts("}");
puts("}");
puts("return vNull()");
puts("}");
// P-VM.5d: the IJ-visible native entry is now the CALL protocol (bind +
// frame + exec), replacing the old exec-only entry: SP lives in natSP so
// the op-5 fast path and the IJ-side entry points cannot desync.
puts("func ijb_ijvmCallNative(chunkV Value, stackV Value, defCtxV Value, argsV Value, h1 Value, h2 Value, h3 Value, h4 Value, h5 Value, h6 Value, h7 Value, h8 Value, h9 Value, h10 Value, h11 Value, depthV Value) Value {");
puts('if chunkV.tag != tMap || stackV.tag != tArray { return vInvalid("ijvmCallNative: bad chunk or stack") }');
puts("var av []Value");
puts("if argsV.tag == tArray { av = argsV.arrp().values }");
puts("return natCallChunk(natDecodeChunk(chunkV.mp()), stackV.arrp(), defCtxV, av, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, depthV.IntValue())");
puts("}");
// P-VM.5d: stamp a guest function value with its compiled chunk, captured
// def context and the creating layer's stack. evaluateFunctionDeclaration
// calls this once per chunk-backed closure; the op-5 fast path reads the
// stamp. Values are native FunctionCommands at the bottom of every
// interpretation tower, so the builtin works at any depth (args pass
// through each layer's chain registration unchanged).
puts("func ijb_ijvmTagFn(fnV Value, chunkV Value, defCtxV Value, stackV Value) Value {");
puts("if fnV.tag == tFunc && chunkV.tag == tMap && stackV.tag == tArray {");
puts("fc := fnV.cmdp()");
puts("fc.ijChunk = natDecodeChunk(chunkV.mp())");
puts("fc.ijDefCtx = defCtxV");
puts("fc.ijStack = stackV.arrp()");
puts("}");
puts("return fnV");
puts("}");
puts("func registerLibraryFunctions(ctx *Context) {");
puts("ctx.Create(" + chr(34) + "puts" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("val := params.Get(Value{tag: tInt, i: 0})");
puts("fmt.Println(val.String())");
puts("return Value{tag: tInt, i: 0}");
puts("})))");
puts("ctx.Create(" + chr(34) + "gets" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("s, err := stdinReader.ReadString('" + chr(92) + "n')");
puts("if err != nil {");
puts("if err == io.EOF {");
puts("return vNull()");
puts("} else {");
puts("return vInvalid(" + chr(34) + "gets error: " + chr(34) + " + err.Error())");
puts("}");
puts("}");
puts("s = strings.TrimSuffix(s, " + chr(34) + "" + chr(92) + "n" + chr(34) + ")");
puts("s = strings.TrimSuffix(s, " + chr(34) + "" + chr(92) + "r" + chr(34) + ")");
puts("return Value{tag: tString, s: s}");
puts("})))");
puts("ctx.Create(" + chr(34) + "assert" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("if !params.Get(Value{tag: tInt, i: 0}).IsTruthy() {");
puts("fmt.Println(" + chr(34) + "=> FAILED " + chr(34) + ", params.Get(Value{tag: tInt, i: 1}).ValueString())");
puts("}");
puts("return vNull()");
puts("})))");
puts("ctx.Create(" + chr(34) + "push" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_push(params.Get(Value{tag: tInt, i: 0}), params.Get(Value{tag: tInt, i: 1}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "pop" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "pop: expected array" + chr(34) + ")");
puts("}");
puts("if len(arr.arrp().values) == 0 {");
puts("return vInvalid(" + chr(34) + "pop: array is empty" + chr(34) + ")");
puts("}");
puts("lastElement := arr.arrp().values[len(arr.arrp().values)-1]");
puts("arr.arrp().values = arr.arrp().values[:len(arr.arrp().values)-1]");
puts("return lastElement");
puts("})))");
puts("ctx.Create(" + chr(34) + "join" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "join: expected array" + chr(34) + ")");
puts("}");
puts("delim := params.Get(Value{tag: tInt, i: 1}).ValueString()");
puts("strValues := make([]string, len(arr.arrp().values))");
puts("for i, v := range arr.arrp().values {");
puts("strValues[i] = v.ValueString()");
puts("}");
puts("joined := strings.Join(strValues, delim)");
puts("return Value{tag: tString, s: joined}");
puts("})))");
puts("ctx.Create(" + chr(34) + "keys" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_keys(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "values" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tMap {");
puts("return vInvalid(" + chr(34) + "values: expected map" + chr(34) + ")");
puts("}");
puts("values := make([]Value, len(arr.mp().pairs))");
puts("i := 0");
puts("for _, pair := range arr.mp().pairs {");
puts("values[i] = pair.Value");
puts("i++");
puts("}");
puts("return vArray(NewArrayValue(values...))");
puts("})))");
puts("ctx.Create(" + chr(34) + "char" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_char(params.Get(Value{tag: tInt, i: 0}), params.Get(Value{tag: tInt, i: 1}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "len" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_len(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "chr" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_chr(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "ord" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_ord(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "substr" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_substr(params.Get(Value{tag: tInt, i: 0}), params.Get(Value{tag: tInt, i: 1}), params.Get(Value{tag: tInt, i: 2}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "int" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("num, err := strconv.Atoi(v.ValueString())");
puts("if err == nil {");
puts("return Value{tag: tInt, i: int64(num)}");
puts("} else {");
puts("return vInvalid(" + chr(34) + "int: " + chr(34) + " + err.Error())");
puts("}");
puts("})))");
puts("ctx.Create(" + chr(34) + "string" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_string(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "random" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("secId, err := GenerateSecureID()");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "random: " + chr(34) + " + err.Error())");
puts("}");
puts("return Value{tag: tString, s: secId}");
puts("})))");
puts("ctx.Create(" + chr(34) + "typeof" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_typeof(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "isArray" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_isArray(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "isMap" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_isMap(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "isNumber" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_isNumber(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "isString" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_isString(params.Get(Value{tag: tInt, i: 0}))");
puts("})))");
puts("ctx.Create(" + chr(34) + "assert" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("t := params.Get(Value{tag: tInt, i: 0})");
puts("m := params.Get(Value{tag: tInt, i: 1})");
puts("if !t.IsTruthy() {");
puts("panic(" + chr(34) + "assertion failed: " + chr(34) + " + m.ValueString())");
puts("return vInvalid(" + chr(34) + "assert: " + chr(34) + " + m.ValueString())");
puts("}");
puts("return vNull()");
puts("})))");
puts("ctx.Create(" + chr(34) + "double" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("num, err := strconv.ParseFloat(v.ValueString(), 64)");
puts("if err == nil {");
puts("return vDouble(num)");
puts("} else {");
puts("return vNull()");
puts("}");
puts("})))");
puts("ctx.Create(" + chr(34) + "echo" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return params.Get(Value{tag: tInt, i: 0})");
puts("})))");
puts("ctx.Create(" + chr(34) + "print" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("val := params.Get(Value{tag: tInt, i: 0})");
puts("fmt.Print(val.String())");
puts("return Value{tag: tInt, i: 0}");
puts("})))");
puts("ctx.Create(" + chr(34) + "delete" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("collection := params.Get(Value{tag: tInt, i: 0})");
puts("keyOrIndex := params.Get(Value{tag: tInt, i: 1})");
puts("if collection.tag == tArray {");
puts("if keyOrIndex.tag != tInt {");
puts("return vInvalid(" + chr(34) + "delete: array index must be a number" + chr(34) + ")");
puts("}");
puts("idx := int(keyOrIndex.i)");
puts("if idx < 0 || idx >= len(collection.arrp().values) {");
puts("return vInvalid(" + chr(34) + "delete: array index out of bounds" + chr(34) + ")");
puts("}");
puts("removed := collection.arrp().values[idx]");
puts("collection.arrp().values = append(collection.arrp().values[:idx], collection.arrp().values[idx+1:]...)");
puts("return removed");
puts("} else if collection.tag == tMap {");
puts("if idx, found := collection.mp().findPair(keyOrIndex); found {");
puts("removed := collection.mp().pairs[idx].Value");
puts("collection.mp().pairs = append(collection.mp().pairs[:idx], collection.mp().pairs[idx+1:]...)");
puts("if collection.mp().keyIndex == nil {");
puts("collection.mp().keyIndex = make(map[string]int)");
puts("} else {");
puts("for k := range collection.mp().keyIndex {");
puts("delete(collection.mp().keyIndex, k)");
puts("}");
puts("}");
puts("for i, pair := range collection.mp().pairs {");
puts("collection.mp().keyIndex[pair.Key.String()] = i");
puts("}");
puts("return removed");
puts("}");
puts("return vNull()");
puts("} else {");
puts("return vInvalid(" + chr(34) + "delete: first argument must be an array or map" + chr(34) + ")");
puts("}");
puts("})))");
puts("ctx.Create(" + chr(34) + "startsWith" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("prefix := params.Get(Value{tag: tInt, i: 1})");
puts("return Value{tag: tBool, b: strings.HasPrefix(str.ValueString(), prefix.ValueString())}");
puts("})))");
puts("ctx.Create(" + chr(34) + "endsWith" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("suffix := params.Get(Value{tag: tInt, i: 1})");
puts("return Value{tag: tBool, b: strings.HasSuffix(str.ValueString(), suffix.ValueString())}");
puts("})))");
puts("ctx.Create(" + chr(34) + "trim" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tString, s: strings.TrimSpace(str.ValueString())}");
puts("})))");
puts("ctx.Create(" + chr(34) + "match" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("pattern := params.Get(Value{tag: tInt, i: 1})");
puts("patternStr := strings.ReplaceAll(pattern.ValueString(), " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ", " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ")");
puts("matched, err := regexp.MatchString(patternStr, str.ValueString())");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "match: invalid regex pattern: " + chr(34) + " + err.Error())");
puts("}");
puts("return Value{tag: tBool, b: matched}");
puts("})))");
puts("ctx.Create(" + chr(34) + "findAll" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("pattern := params.Get(Value{tag: tInt, i: 1})");
puts("patternStr := strings.ReplaceAll(pattern.ValueString(), " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ", " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ")");
puts("re, exists := regexCache[patternStr]");
puts("if !exists {");
puts("var err error");
puts("re, err = regexp.Compile(patternStr)");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "findAll: invalid regex pattern: " + chr(34) + " + err.Error())");
puts("}");
puts("regexCache[patternStr] = re");
puts("}");
puts("matches := re.FindAllString(str.ValueString(), -1)");
puts("values := make([]Value, len(matches))");
puts("for i, match := range matches {");
puts("values[i] = Value{tag: tString, s: match}");
puts("}");
puts("return vArray(NewArrayValue(values...))");
puts("})))");
puts("ctx.Create(" + chr(34) + "replace" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("pattern := params.Get(Value{tag: tInt, i: 1})");
puts("replacement := params.Get(Value{tag: tInt, i: 2})");
puts("patternStr := strings.ReplaceAll(pattern.ValueString(), " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ", " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ")");
puts("re, exists := regexCache[patternStr]");
puts("if !exists {");
puts("var err error");
puts("re, err = regexp.Compile(patternStr)");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "replace: invalid regex pattern: " + chr(34) + " + err.Error())");
puts("}");
puts("regexCache[patternStr] = re");
puts("}");
puts("result := re.ReplaceAllString(str.ValueString(), replacement.ValueString())");
puts("return Value{tag: tString, s: result}");
puts("})))");
puts("ctx.Create(" + chr(34) + "split" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("pattern := params.Get(Value{tag: tInt, i: 1})");
puts("patternStr := strings.ReplaceAll(pattern.ValueString(), " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ", " + chr(34) + "" + chr(92) + "" + chr(92) + "" + chr(34) + ")");
puts("re, exists := regexCache[patternStr]");
puts("if !exists {");
puts("var err error");
puts("re, err = regexp.Compile(patternStr)");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "split: invalid regex pattern: " + chr(34) + " + err.Error())");
puts("}");
puts("regexCache[patternStr] = re");
puts("}");
puts("parts := re.Split(str.ValueString(), -1)");
puts("values := make([]Value, len(parts))");
puts("for i, part := range parts {");
puts("values[i] = Value{tag: tString, s: part}");
puts("}");
puts("return vArray(NewArrayValue(values...))");
puts("})))");
// P-VM.4: getenv lets IJ-level code read env vars (the IJ-side VM gate).
// Each interpreted layer re-registers getenv as a wrapper over the layer
// above (DefaultLibraryFunctionsInitializer), so the value chains down to
// this native os.Getenv at any nesting depth.
puts("ctx.Create(" + chr(34) + "getenv" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tString, s: os.Getenv(v.ValueString())}");
puts("})))");
// P-VM.4: eputs writes to stderr (debug/diagnostics that must not corrupt
// program stdout -- differential tests diff stdout). Chains like getenv.
puts("ctx.Create(" + chr(34) + "eputs" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("val := params.Get(Value{tag: tInt, i: 0})");
puts("fmt.Fprintln(os.Stderr, val.String())");
puts("return Value{tag: tInt, i: 0}");
puts("})))");
// P-VM.5a: hasKey(map, key) -- O(1) presence check (see ijb_hasKey).
// Chains down to this native impl at every interpreted layer via
// MapLibraryFunctionsInitializer's twoWrapper(hasKey), like getenv.
// Unblocks the O(1) mapHasKey that the 2026-05-29 sentinel dead-end
// could not have: the committed binary is no longer a frozen bridge, so
// new builtins land by replacing the binary in the same commit.
puts("ctx.Create(" + chr(34) + "hasKey" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("return ijb_hasKey(params.Get(Value{tag: tInt, i: 0}), params.Get(Value{tag: tInt, i: 1}))");
puts("})))");
// P-VM.5d: native ijvm call entry (replaces the P-VM.5c exec entry). 16
// args: chunk, stack, defCtx, args, 11 hooks, depth. The binary's
// ijvmCallChunk/ijvmRunTopChunk direct-emit ijb_ijvmCallNative with depth
// 0; interpreted layers reach this binding through the ijvmCallChain
// registration, which adds 1 per layer hop.
puts("ctx.Create(" + chr(34) + "ijvmCallNative" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("p := params.values");
puts('if len(p) < 16 { return vInvalid("ijvmCallNative: expected 16 args") }');
puts("return ijb_ijvmCallNative(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15])");
puts("})))");
// P-VM.5d: chunk stamp for the op-5 native fast path (see ijb_ijvmTagFn).
puts("ctx.Create(" + chr(34) + "ijvmTagFn" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("p := params.values");
puts('if len(p) < 4 { return vInvalid("ijvmTagFn: expected 4 args") }');
puts("return ijb_ijvmTagFn(p[0], p[1], p[2], p[3])");
puts("})))");
puts("}");
puts("// --- Value tagged-union (Phase 1) ---");
puts("const (");
puts("tNull uint8 = iota");
puts("tInt");
puts("tDouble");
puts("tString");
puts("tBool");
puts("tArray");
puts("tMap");
puts("tFunc");
puts("tNamed");
puts("tInvalid");
puts(")");
// P-VM.5 lean Value: 88 -> 40 bytes, 6 -> 2 pointer words. The selfhost
// profile is dominated by Value copies (memclr/memmove) + GC scans of the
// 6-pointer-word layout. Field merges: `d` lives in `i` as Float64bits
// (tag tDouble); the tInvalid message lives in `s`; `arr`/`m`/`cmd` share
// one unsafe.Pointer `p` (tag disambiguates; *FunctionCommand is the only
// Command impl so the interface header is dropped too). The accessor
// methods keep every consumer one-token away from the old field reads.
puts("type Value struct {");
puts("tag   uint8");
puts("b     bool");
puts("i     int64");
puts("s     string");
puts("p     unsafe.Pointer");
puts("}");
puts("func (v Value) f() float64 { return math.Float64frombits(uint64(v.i)) }");
puts("func (v Value) arrp() *ArrayValue { return (*ArrayValue)(v.p) }");
puts("func (v Value) mp() *MapValue { return (*MapValue)(v.p) }");
puts("func (v Value) cmdp() *FunctionCommand { return (*FunctionCommand)(v.p) }");
puts("func (v Value) IsTruthy() bool {");
puts("switch v.tag {");
puts("case tNull: return false");
puts("case tInt: return v.i != 0");
puts("case tDouble: return v.f() != 0");
puts("case tString: return len(v.s) > 0");
puts("case tBool: return v.b");
puts("case tArray: return v.arrp() != nil && v.arrp().Length() > 0");
puts("case tMap: return v.mp() != nil && v.mp().Length() > 0");
puts("case tFunc: return true");
puts("case tInvalid: return false");
puts("}");
puts("return false");
puts("}");
puts("func (v Value) IsInvalid() bool { return v.tag == tInvalid }");
puts("func (v Value) Length() int {");
puts("switch v.tag {");
puts("case tString: return len(v.s)");
puts("case tArray: return v.arrp().Length()");
puts("case tMap: return v.mp().Length()");
puts("}");
puts("return 0");
puts("}");
puts("func (v Value) IntValue() int {");
puts("switch v.tag {");
puts("case tInt: return int(v.i)");
puts("case tDouble: return int(v.f())");
puts("case tBool: if v.b { return 1 }; return 0");
puts("}");
puts("return 0");
puts("}");
puts("func (v Value) String() string {");
puts("switch v.tag {");
puts("case tNull: return " + chr(34) + "null" + chr(34) + "");
puts("case tInt: return strconv.FormatInt(v.i, 10)");
puts("case tDouble: return strconv.FormatFloat(v.f(), 'f', -1, 64)");
puts("case tString: return v.s");
puts("case tBool: if v.b { return " + chr(34) + "true" + chr(34) + " }; return " + chr(34) + "false" + chr(34) + "");
puts("case tArray: return v.arrp().String()");
puts("case tMap: return v.mp().String()");
puts("case tFunc: return " + chr(34) + "function" + chr(34) + "");
puts("case tInvalid: return " + chr(34) + "invalid: " + chr(34) + " + v.s");
puts("}");
puts("return " + chr(34) + chr(34) + "");
puts("}");
puts("func (v Value) ValueString() string { return v.String() }");
puts("func (v Value) Add(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tInt, i: v.i + other.i}");
puts("case tDouble: return vDouble(float64(v.i) + other.f())");
puts("case tString: return Value{tag: tString, s: strconv.FormatInt(v.i, 10) + other.s}");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return vDouble(v.f() + float64(other.i))");
puts("case tDouble: return vDouble(v.f() + other.f())");
puts("case tString: return Value{tag: tString, s: strconv.FormatFloat(v.f(), 'f', -1, 64) + other.s}");
puts("}");
puts("case tString:");
puts("var sb2 strings.Builder");
puts("sb2.Grow(len(v.s) + len(other.String()))");
puts("sb2.WriteString(v.s)");
puts("sb2.WriteString(other.String())");
puts("return Value{tag: tString, s: sb2.String()}");
puts("case tArray:");
puts("if other.tag == tArray {");
puts("result := &ArrayValue{values: make([]Value, len(v.arrp().values)+len(other.arrp().values))}");
puts("copy(result.values, v.arrp().values)");
puts("copy(result.values[len(v.arrp().values):], other.arrp().values)");
puts("return vArray(result)");
puts("}");
puts("case tMap:");
puts("if other.tag == tMap {");
puts("result := &MapValue{pairs: make([]KeyValuePair, len(v.mp().pairs)), keyIndex: make(map[string]int)}");
puts("copy(result.pairs, v.mp().pairs)");
puts("for i, pair := range result.pairs { result.keyIndex[pair.Key.String()] = i }");
puts("for _, pair := range other.mp().pairs {");
puts("if idx, found := result.keyIndex[pair.Key.String()]; found { result.pairs[idx].Value = pair.Value } else {");
puts("newIdx := len(result.pairs); result.pairs = append(result.pairs, KeyValuePair{Key: pair.Key, Value: pair.Value})");
puts("result.keyIndex[pair.Key.String()] = newIdx");
puts("}");
puts("}");
puts("return vMap(result)");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "type mismatch in Add" + chr(34) + "}");
puts("}");
puts("func (v Value) Subtract(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tInt, i: v.i - other.i}");
puts("case tDouble: return vDouble(float64(v.i) - other.f())");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return vDouble(v.f() - float64(other.i))");
puts("case tDouble: return vDouble(v.f() - other.f())");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "type mismatch in Subtract" + chr(34) + "}");
puts("}");
puts("func (v Value) Multiply(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tInt, i: v.i * other.i}");
puts("case tDouble: return vDouble(float64(v.i) * other.f())");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return vDouble(v.f() * float64(other.i))");
puts("case tDouble: return vDouble(v.f() * other.f())");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "type mismatch in Multiply" + chr(34) + "}");
puts("}");
puts("func (v Value) Divide(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, s: " + chr(34) + "division by zero" + chr(34) + "} }; return Value{tag: tInt, i: v.i / other.i}");
puts("case tDouble: if other.f() == 0 { return Value{tag: tInvalid, s: " + chr(34) + "division by zero" + chr(34) + "} }; return vDouble(float64(v.i) / other.f())");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, s: " + chr(34) + "division by zero" + chr(34) + "} }; return vDouble(v.f() / float64(other.i))");
puts("case tDouble: if other.f() == 0 { return Value{tag: tInvalid, s: " + chr(34) + "division by zero" + chr(34) + "} }; return vDouble(v.f() / other.f())");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "type mismatch in Divide" + chr(34) + "}");
puts("}");
puts("func (v Value) Modulo(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, s: " + chr(34) + "modulo by zero" + chr(34) + "} }; return Value{tag: tInt, i: v.i % other.i}");
puts("case tDouble: if other.f() == 0 { return Value{tag: tInvalid, s: " + chr(34) + "modulo by zero" + chr(34) + "} }; return Value{tag: tInvalid, s: " + chr(34) + "modulo not defined for floating point" + chr(34) + "}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "type mismatch in Modulo" + chr(34) + "}");
puts("}");
puts("func (v Value) Equals(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("if v.tag != other.tag { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: true}");
puts("case tInt: return Value{tag: tBool, b: v.i == other.i}");
puts("case tDouble: return Value{tag: tBool, b: v.f() == other.f()}");
puts("case tString: return Value{tag: tBool, b: v.s == other.s}");
puts("case tBool: return Value{tag: tBool, b: v.b == other.b}");
puts("case tFunc: return Value{tag: tBool, b: v.p == other.p}");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) LessThan(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i < other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) < other.f()} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.f() < float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.f() < other.f()} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) LessThanEqual(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: other.tag == tNull}");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i <= other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) <= other.f()} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.f() <= float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.f() <= other.f()} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) BiggerThan(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i > other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) > other.f()} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.f() > float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.f() > other.f()} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) BiggerThanEqual(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: other.tag == tNull}");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i >= other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) >= other.f()} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.f() >= float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.f() >= other.f()} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) And(other Value) Value {");
puts("if v.IsTruthy() { return other }");
puts("return v");
puts("}");
puts("func (v Value) Or(other Value) Value {");
puts("if v.IsTruthy() { return v }");
puts("return other");
puts("}");
puts("func (v Value) Not() Value {");
puts("return Value{tag: tBool, b: !v.IsTruthy()}");
puts("}");
puts("func (v Value) Get(index Value) Value {");
puts("switch v.tag {");
puts("case tString:");
puts("if index.tag != tInt { return Value{tag: tInvalid, s: " + chr(34) + "string index must be number" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx >= 0 && idx < len(v.s) { return Value{tag: tString, s: string(v.s[idx])} }");
puts("return Value{tag: tInvalid, s: " + chr(34) + "string index out of bounds" + chr(34) + "}");
puts("case tArray:");
puts("if index.tag != tInt { return Value{tag: tInvalid, s: " + chr(34) + "array index must be number" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx >= 0 && idx < len(v.arrp().values) { return v.arrp().values[idx] }");
puts("return Value{tag: tInvalid, s: " + chr(34) + "array index out of bounds" + chr(34) + "}");
puts("case tMap:");
puts("return v.mp().Get(index)");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "Get not supported for type" + chr(34) + "}");
puts("}");
puts("func (v Value) Put(index Value, value Value) Value {");
puts("switch v.tag {");
puts("case tArray:");
puts("if index.tag != tInt { return Value{tag: tInvalid, s: " + chr(34) + "array index must be number for Put" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx < 0 || idx >= len(v.arrp().values) { return Value{tag: tInvalid, s: " + chr(34) + "array index out of bounds" + chr(34) + "} }");
puts("v.arrp().values[idx] = value");
puts("return value");
puts("case tMap:");
puts("return v.mp().Put(index, value)");
puts("}");
puts("return Value{tag: tInvalid, s: " + chr(34) + "Put not supported for type" + chr(34) + "}");
puts("}");
puts("func (v Value) Keys() Value {");
puts("if v.tag == tMap { return v.mp().Keys() }");
puts("return Value{tag: tInvalid, s: " + chr(34) + "Keys not supported" + chr(34) + "}");
puts("}");
puts("func (v Value) Values() Value {");
puts("if v.tag == tMap { return v.mp().Values() }");
puts("return Value{tag: tInvalid, s: " + chr(34) + "Values not supported" + chr(34) + "}");
puts("}");
puts("func (v Value) Execute(ctx *Context, params *ArrayValue) Value {");
puts("if v.tag == tFunc { return v.cmdp().Execute(ctx, params) }");
puts("return v");
puts("}");
puts("func (v Value) Type() Value {");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tString, s: " + chr(34) + "null" + chr(34) + "}");
puts("case tInt: return Value{tag: tString, s: " + chr(34) + "number" + chr(34) + "}");
puts("case tDouble: return Value{tag: tString, s: " + chr(34) + "number" + chr(34) + "}");
puts("case tString: return Value{tag: tString, s: " + chr(34) + "string" + chr(34) + "}");
puts("case tBool: return Value{tag: tString, s: " + chr(34) + "boolean" + chr(34) + "}");
puts("case tArray: return Value{tag: tString, s: " + chr(34) + "array" + chr(34) + "}");
puts("case tMap: return Value{tag: tString, s: " + chr(34) + "map" + chr(34) + "}");
puts("case tFunc: return Value{tag: tString, s: " + chr(34) + "function" + chr(34) + "}");
puts("case tInvalid: return Value{tag: tString, s: " + chr(34) + "invalid" + chr(34) + "}");
puts("}");
puts("return Value{tag: tString, s: " + chr(34) + "unknown" + chr(34) + "}");
puts("}");
puts("func (v Value) Append(value Value) Value {");
puts("if v.tag == tArray { v.arrp().values = append(v.arrp().values, value); return value }");
puts("return Value{tag: tInvalid, s: " + chr(34) + "Append only supported for arrays" + chr(34) + "}");
puts("}");
puts("func vNull() Value { return Value{tag: tNull} }");
puts("func vBool(b bool) Value { return Value{tag: tBool, b: b} }");
puts("func vInt(i int64) Value { return Value{tag: tInt, i: i} }");
puts("func vDouble(d float64) Value { return Value{tag: tDouble, i: int64(math.Float64bits(d))} }");
puts("func vString(s string) Value { return Value{tag: tString, s: s} }");
puts("func vArray(a *ArrayValue) Value { return Value{tag: tArray, p: unsafe.Pointer(a)} }");
puts("func vMap(m *MapValue) Value { return Value{tag: tMap, p: unsafe.Pointer(m)} }");
puts("func vFunc(c *FunctionCommand) Value { return Value{tag: tFunc, p: unsafe.Pointer(c)} }");
puts("func vInvalid(reason string) Value { return Value{tag: tInvalid, s: reason} }");
puts("func ValueToOld(v Value) Value { return nil } // stub — unused during transition");
// P-VM.5: the raw-bool comparison helpers + AsValue wrappers used to be
// injected by fix_app_go.py (STEP 4/5). The lean Value made the injected
// text stale (it read the removed `d` field), so the prelude is now their
// single source of truth -- fix_app_go.py's guards see them and skip the
// injection. Keep the exact signature strings: the guards match on
// "func EqualsBool(a, b Value) bool" / "func NewArrayValueAsValue".
puts("func EqualsBool(a, b Value) bool {");
puts("if a.tag != b.tag { return false }");
puts("switch a.tag {");
puts("case tInt: return a.i == b.i");
puts("case tDouble: return a.f() == b.f()");
puts("case tString: return a.s == b.s");
puts("case tBool: return a.b == b.b");
puts("case tNull: return true");
puts("}");
puts("return false");
puts("}");
puts("func NotEqualsBool(a, b Value) bool { return !EqualsBool(a, b) }");
puts("func LessThanBool(a, b Value) bool {");
puts("if a.tag == tInt && b.tag == tInt { return a.i < b.i }");
puts("if a.tag == tDouble && b.tag == tDouble { return a.f() < b.f() }");
puts("return a.LessThan(b).b");
puts("}");
puts("func LessThanEqualBool(a, b Value) bool {");
puts("if a.tag == tInt && b.tag == tInt { return a.i <= b.i }");
puts("if a.tag == tDouble && b.tag == tDouble { return a.f() <= b.f() }");
puts("return a.LessThanEqual(b).b");
puts("}");
puts("func BiggerThanBool(a, b Value) bool {");
puts("if a.tag == tInt && b.tag == tInt { return a.i > b.i }");
puts("if a.tag == tDouble && b.tag == tDouble { return a.f() > b.f() }");
puts("return a.BiggerThan(b).b");
puts("}");
puts("func BiggerThanEqualBool(a, b Value) bool {");
puts("if a.tag == tInt && b.tag == tInt { return a.i >= b.i }");
puts("if a.tag == tDouble && b.tag == tDouble { return a.f() >= b.f() }");
puts("return a.BiggerThanEqual(b).b");
puts("}");
puts("func NewMapValueAsValue(pairs ...KeyValuePair) Value { return vMap(NewMapValue(pairs...)) }");
puts("func NewArrayValueAsValue(elements ...Value) Value { return vArray(NewArrayValue(elements...)) }");
puts("// --- ArrayValue (Value-based array) ---");
puts("type ArrayValue struct {");
puts("values []Value");
puts("}");
puts("func NewArrayValue(elements ...Value) *ArrayValue {");
puts("if elements == nil { return &ArrayValue{values: []Value{}} }");
puts("return &ArrayValue{values: elements}");
puts("}");
puts("func (a *ArrayValue) Get(index Value) Value {");
puts("if index.tag != tInt { return vInvalid(" + chr(34) + "ArrayValue requires int index" + chr(34) + ") }");
puts("idx := int(index.i)");
puts("if idx >= 0 && idx < len(a.values) { return a.values[idx] }");
puts("return vInvalid(" + chr(34) + "index out of bounds" + chr(34) + ")");
puts("}");
puts("func (a *ArrayValue) Put(index Value, value Value) Value {");
puts("if index.tag != tInt { return vInvalid(" + chr(34) + "ArrayValue requires int index" + chr(34) + ") }");
puts("idx := int(index.i)");
puts("if idx < 0 || idx >= len(a.values) { return vInvalid(" + chr(34) + "index out of bounds" + chr(34) + ") }");
puts("a.values[idx] = value");
puts("return value");
puts("}");
puts("func (a *ArrayValue) Append(value Value) Value {");
puts("a.values = append(a.values, value)");
puts("return value");
puts("}");
puts("func (a *ArrayValue) Length() int { return len(a.values) }");
puts("func (a *ArrayValue) String() string {");
puts("if len(a.values) == 0 { return " + chr(34) + "[]" + chr(34) + " }");
puts("var sb2 strings.Builder");
puts("sb2.WriteString(" + chr(34) + "[" + chr(34) + ")");
puts("for i, v := range a.values { if i > 0 { sb2.WriteByte(',') }; sb2.WriteString(v.String()) }");
puts("sb2.WriteString(" + chr(34) + "]" + chr(34) + ")");
puts("return sb2.String()");
puts("}");
puts("// --- MapValue (Value-based map) ---");
puts("type KeyValuePair struct {");
puts("Key   Value");
puts("Value Value");
puts("}");
puts("type MapValue struct {");
puts("pairs    []KeyValuePair");
puts("keyIndex map[string]int");
puts("}");
puts("func NewMapValue(pairs ...KeyValuePair) *MapValue {");
puts("m := &MapValue{pairs: pairs, keyIndex: make(map[string]int)}");
puts("for i, pair := range pairs { m.keyIndex[pair.Key.String()] = i }");
puts("return m");
puts("}");
puts("func NewEmptyMapValue() *MapValue {");
puts("return &MapValue{keyIndex: make(map[string]int)}");
puts("}");
puts("func (m *MapValue) findPair(key Value) (int, bool) {");
puts("idx, found := m.keyIndex[key.String()]");
puts("return idx, found");
puts("}");
puts("func (m *MapValue) Get(index Value) Value {");
puts("if idx, found := m.findPair(index); found { return m.pairs[idx].Value }");
puts("return vNull()");
puts("}");
puts("func (m *MapValue) Put(index Value, value Value) Value {");
puts("keyStr := index.String()");
puts("if idx, found := m.keyIndex[keyStr]; found { m.pairs[idx].Value = value } else {");
puts("newIdx := len(m.pairs); m.pairs = append(m.pairs, KeyValuePair{Key: index, Value: value})");
puts("m.keyIndex[keyStr] = newIdx");
puts("}");
puts("return value");
puts("}");
puts("func (m *MapValue) Length() int { return len(m.pairs) }");
puts("func (m *MapValue) Keys() Value {");
puts("keys := make([]Value, len(m.pairs))");
puts("for i, pair := range m.pairs { keys[i] = pair.Key }");
puts("return vArray(NewArrayValue(keys...))");
puts("}");
puts("func (m *MapValue) Values() Value {");
puts("values := make([]Value, len(m.pairs))");
puts("for i, pair := range m.pairs { values[i] = pair.Value }");
puts("return vArray(NewArrayValue(values...))");
puts("}");
puts("func (m *MapValue) String() string {");
puts("if len(m.pairs) == 0 { return " + chr(34) + "{}" + chr(34) + " }");
puts("var sb2 strings.Builder");
puts("sb2.WriteString(" + chr(34) + "{" + chr(34) + ")");
puts("for i, pair := range m.pairs { if i > 0 { sb2.WriteByte(',') }; sb2.WriteString(pair.Key.String()); sb2.WriteByte(':'); sb2.WriteString(pair.Value.String()) }");
puts("sb2.WriteString(" + chr(34) + "}" + chr(34) + ")");
puts("return sb2.String()");
puts("}");
puts("// --- Context (Value-based context) ---");
// P-VM.5e: inline storage for the first 4 bindings. Per-call function
// contexts and per-block contexts hold 1-4 entries almost always; the
// Go map they used to allocate (header + first-insert group ~600B in 2
// allocs per call) was the top malloc site in the selfhost profile
// (mapassign growToSmall under evalFuncDecl.func2). Linear scan over
// <=4 keys also beats map hashing on the read side. Spill (>4 bindings,
// e.g. rootCtx) goes to the lazily-created map; a name lives in EITHER
// the inline slots or the map, never both (localPut checks both before
// appending), so shadowing/update semantics are unchanged.
puts("type Context struct {");
puts("parent    *Context");
puts("variables map[string]Value");
puts("inN       int");
puts("inKeys    [4]string");
puts("inVals    [4]Value");
puts("}");
puts("func NewContext(parent *Context) *Context {");
puts("return &Context{parent: parent}");
puts("}");
puts("func (c *Context) localGet(name string) (Value, bool) {");
puts("for i := 0; i < c.inN; i++ {");
puts("if c.inKeys[i] == name { return c.inVals[i], true }");
puts("}");
puts("if c.variables != nil {");
puts("v, ok := c.variables[name]");
puts("return v, ok");
puts("}");
puts("return Value{}, false");
puts("}");
puts("func (c *Context) localPut(name string, value Value) {");
puts("for i := 0; i < c.inN; i++ {");
puts("if c.inKeys[i] == name { c.inVals[i] = value; return }");
puts("}");
puts("if c.variables != nil {");
puts("if _, ok := c.variables[name]; ok { c.variables[name] = value; return }");
puts("}");
puts("if c.inN < 4 {");
puts("c.inKeys[c.inN] = name");
puts("c.inVals[c.inN] = value");
puts("c.inN++");
puts("return");
puts("}");
puts("if c.variables == nil { c.variables = make(map[string]Value) }");
puts("c.variables[name] = value");
puts("}");
puts("func (c *Context) localUpdate(name string, value Value) bool {");
puts("for i := 0; i < c.inN; i++ {");
puts("if c.inKeys[i] == name { c.inVals[i] = value; return true }");
puts("}");
puts("if c.variables != nil {");
puts("if _, ok := c.variables[name]; ok { c.variables[name] = value; return true }");
puts("}");
puts("return false");
puts("}");
puts("func (c *Context) Get(name string) Value {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if v, ok := ctx.localGet(name); ok { return v }");
puts("}");
puts("return vInvalid(" + chr(34) + "variable not found: " + chr(34) + " + name)");
puts("}");
puts("func (c *Context) Exists(name string) bool {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if _, ok := ctx.localGet(name); ok { return true }");
puts("}");
puts("return false");
puts("}");
puts("func (c *Context) Create(name string, value Value) Value {");
puts("c.localPut(name, value)");
puts("return value");
puts("}");
puts("func (c *Context) Update(name string, value Value) Value {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if ctx.localUpdate(name, value) { return value }");
puts("}");
puts("return c.Create(name, value)");
puts("}");
puts("func (c *Context) GetLocal(name string) Value {");
puts("if v, ok := c.localGet(name); ok { return v }");
puts("return vInvalid(" + chr(34) + "variable not found: " + chr(34) + " + name)");
puts("}");
puts("func (c *Context) UpdateLocal(name string, value Value) Value {");
puts("c.localPut(name, value)");
puts("return value");
puts("}");
puts("var rootCtx *Context");
puts("// --- Command + FunctionCommand (Value-based) ---");
puts("type Command interface {");
puts("Execute(ctx *Context, params *ArrayValue) Value");
puts("String() string");
puts("IsTruthy() bool");
puts("IsInvalid() bool");
puts("}");
puts("type FunctionCommand struct {");
puts("definitionCtx *Context");
puts("executeFunc   func(*Context, *ArrayValue) Value");
// P-VM.5d: ijvmTagFn stamp -- set for chunk-backed guest closures so the
// op-5 native fast path can run the callee chunk without the Execute ->
// functionValue tree-walk -> ijvmCallChunk round trip. ijStack doubles as
// the layer-identity check (one ijvmStack per layer, pointer-stable).
puts("ijChunk *natChunk");
puts("ijDefCtx Value");
puts("ijStack *ArrayValue");
puts("}");
puts("func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {");
puts("// P-VM.5d: a chunk-stamped guest closure can run its chunk natively no");
puts("// matter who calls it (tree-walked bodies, other layers, hooks): every");
puts("// caller uses the canonical tower encoding -- callee(args) wraps once");
puts("// per interpretation hop, so params.values[0] unwrapped layer-depth");
puts("// times is the logical args array. The layer env comes from natLayer");
puts("// (recorded before any guest closure of that layer can be invoked).");
puts("// Any shape surprise bails to the original tree-walk closure, which");
puts("// reaches the same chunk through ijvmCallChunk -- semantics identical.");
puts("if c.ijChunk != nil {");
puts("if li, ok := natLayer[c.ijStack]; ok && len(params.values) > 0 {");
puts("x := params.values[0]");
puts("good := true");
puts("for i := 0; i < li.depth; i++ {");
puts("if x.tag == tArray && len(x.arrp().values) > 0 { x = x.arrp().values[0] } else { good = false; break }");
puts("}");
puts("if good && x.tag == tArray {");
puts("return natCallChunk(c.ijChunk, c.ijStack, c.ijDefCtx, x.arrp().values, li.h1, li.h2, li.h3, li.h4, li.h5, li.h6, li.h7, li.h8, li.h9, li.h10, li.h11, li.depth)");
puts("}");
puts("}");
puts("}");
puts("// Phase 2.5: pass nil to executeFunc. The closure body already opens its own");
puts("// `local := NewContext(defCtx)` (evalFuncDecl emit), so any ctx we pass here");
puts("// is discarded. Skipping NewContext(c.definitionCtx) saves one *Context alloc");
puts("// per function invocation -- this is the inner-loop allocator in sample.s.");
puts("return c.executeFunc(nil, params)");
puts("}");
puts("func (c *FunctionCommand) String() string { return " + chr(34) + "function" + chr(34) + " }");
puts("func (c *FunctionCommand) IsTruthy() bool { return true }");
puts("func (c *FunctionCommand) IsInvalid() bool { return false }");
puts("func NewFunctionCommand(defCtx *Context, fn func(*Context, *ArrayValue) Value) *FunctionCommand {");
puts("return &FunctionCommand{definitionCtx: defCtx, executeFunc: fn}");
puts("}");
puts("func NewStaticFunctionCommand(defCtx *Context, fn func(*Context, *ArrayValue) Value) *FunctionCommand {");
puts("return &FunctionCommand{definitionCtx: defCtx, executeFunc: fn}");
puts("}");
puts("// --- end Value helpers ---");
puts("// --- Phase 2: Typed AST Node struct ---");
puts("const (");
puts("nkInfix uint8 = iota");
puts("nkPrefix");
puts("nkAssign");
puts("nkIndexAssign");
puts("nkExprStmt");
puts("nkBlock");
puts("nkVarDecl");
puts("nkFuncDecl");
puts("nkIfStmt");
puts("nkWhileStmt");
puts("nkReturn");
puts("nkIdent");
puts("nkIntLit");
puts("nkDoubleLit");
puts("nkStringLit");
puts("nkBoolLit");
puts("nkNullLit");
puts("nkArrayLit");
puts("nkMapLit");
puts("nkIndex");
puts("nkCall");
puts("nkStaticCall");
puts("nkProgram");
puts(")");
puts("const (");
puts("opAdd uint8 = iota");
puts("opSub");
puts("opMul");
puts("opDiv");
puts("opMod");
puts("opEq");
puts("opNeq");
puts("opLt");
puts("opLte");
puts("opGt");
puts("opGte");
puts("opAnd");
puts("opOr");
puts("opNot");
puts("opNeg");
puts(")");
puts("const (");
puts("rkGlobal  uint8 = iota");
puts("rkParam");
puts("rkLocal");
puts("rkUpvalue");
puts("rkLib");
puts("rkGlobalLet");
puts(")");
puts("type Node struct {");
puts("kind         uint8");
puts("op           uint8");
puts("pos          uint32");
puts("sIdx         uint32");
puts("iVal         int64");
puts("dVal         float64");
puts("bVal         bool");
puts("left         *Node");
puts("right        *Node");
puts("list         []*Node");
puts("body         *Node");
puts("params       []string");
puts("name         string");
puts("resolvedKind uint8");
puts("resolvedSlot int32");
puts("resolvedName string");
puts("isStatic     bool");
puts("hasLocals    bool");
puts("staticImpl   func(*Context, []Value) Value");
puts("}");
puts("// --- Phase 2: Tree-walking eval runtime ---");
puts("func eval(n *Node, ctx *Context) (Value, bool) {");
puts("switch n.kind {");
puts("case nkIntLit: return Value{tag: tInt, i: n.iVal}, false");
puts("case nkDoubleLit: return vDouble(n.dVal), false");
puts("case nkStringLit: return Value{tag: tString, s: n.name}, false");
puts("case nkBoolLit: return Value{tag: tBool, b: n.bVal}, false");
puts("case nkNullLit: return vNull(), false");
puts("case nkIdent: return evalIdent(n, ctx)");
puts("case nkInfix: return evalInfix(n, ctx)");
puts("case nkPrefix: return evalPrefix(n, ctx)");
puts("case nkAssign: return evalAssign(n, ctx)");
puts("case nkIndexAssign: return evalIndexAssign(n, ctx)");
puts("case nkExprStmt: return eval(n.left, ctx)");
puts("case nkBlock: return evalBlock(n, ctx)");
puts("case nkVarDecl: return evalVarDecl(n, ctx)");
puts("case nkFuncDecl: return evalFuncDecl(n, ctx)");
puts("case nkIfStmt: return evalIf(n, ctx)");
puts("case nkWhileStmt: return evalWhile(n, ctx)");
puts("case nkReturn: return evalReturn(n, ctx)");
puts("case nkArrayLit: return evalArrayLit(n, ctx)");
puts("case nkMapLit: return evalMapLit(n, ctx)");
puts("case nkIndex: return evalIndex(n, ctx)");
puts("case nkCall: return evalCall(n, ctx)");
puts("case nkStaticCall: return evalStaticCall(n, ctx)");
puts("case nkProgram: return evalProgram(n, ctx)");
puts("}");
puts("return vInvalid(" + chr(34) + "unknown node kind" + chr(34) + "), false");
puts("}");
puts("func evalIdent(n *Node, ctx *Context) (Value, bool) {");
puts("// Phase 2.5: only rkLib gets the GetLocal fast-path. rkParam/rkLocal");
puts("// look correct on paper but evalBlock/evalFuncDecl create per-block");
puts("// *Context children, so a function-scope `let` lives in the function's");
puts("// local ctx while a nested-block ident resolves with the inner block's");
puts("// ctx -- GetLocal would miss the binding. Wait for P2.5.6's evalBlock");
puts("// hasLocals gate (which collapses block ctxs into the function ctx)");
puts("// before fast-pathing rkParam/rkLocal.");
puts("if n.resolvedKind == rkLib { return rootCtx.GetLocal(n.name), false }");
puts("return ctx.Get(n.name), false");
puts("}");
puts("func evalInfix(n *Node, ctx *Context) (Value, bool) {");
puts("l, ret := eval(n.left, ctx)");
puts("if ret { return l, true }");
puts("if l.tag == tInvalid { return l, false }");
puts("if n.op == opAnd { if !l.IsTruthy() { return l, false }; r, r2 := eval(n.right, ctx); return r, r2 }");
puts("if n.op == opOr  { if l.IsTruthy() { return l, false }; r, r2 := eval(n.right, ctx); return r, r2 }");
puts("r, ret2 := eval(n.right, ctx)");
puts("if ret2 { return r, true }");
puts("if r.tag == tInvalid { return r, false }");
puts("switch n.op {");
puts("case opAdd: return l.Add(r), false");
puts("case opSub: return l.Subtract(r), false");
puts("case opMul: return l.Multiply(r), false");
puts("case opDiv: return l.Divide(r), false");
puts("case opMod: return l.Modulo(r), false");
puts("case opEq:  return l.Equals(r), false");
puts("case opNeq: return l.Equals(r).Not(), false");
puts("case opLt:  return l.LessThan(r), false");
puts("case opLte: return l.LessThanEqual(r), false");
puts("case opGt:  return l.BiggerThan(r), false");
puts("case opGte: return l.BiggerThanEqual(r), false");
puts("}");
puts("return vInvalid(" + chr(34) + "unknown infix op" + chr(34) + "), false");
puts("}");
puts("func evalPrefix(n *Node, ctx *Context) (Value, bool) {");
puts("v, ret := eval(n.right, ctx)");
puts("if ret { return v, true }");
puts("if v.tag == tInvalid { return v, false }");
puts("switch n.op {");
puts("case opNeg: return Value{tag: tInt, i: -1}.Multiply(v), false");
puts("case opNot: return v.Not(), false");
puts("}");
puts("return vInvalid(" + chr(34) + "unknown prefix op" + chr(34) + "), false");
puts("}");
puts("func evalAssign(n *Node, ctx *Context) (Value, bool) {");
puts("v, ret := eval(n.right, ctx)");
puts("if ret { return v, true }");
puts("// Phase 2.5: only the EXPLICITLY-annotated non-default kinds get fast");
puts("// paths. rkGlobal is the Go-zero default (0) so it would catch every");
puts("// unannotated nkAssign (any node still emitted by an older bootstrap");
puts("// emitter) -- those must continue through the chain-walk fallback to");
puts("// preserve `x = ...; <undeclared>` -> create-in-current-ctx semantics.");
puts("switch n.resolvedKind {");
puts("case rkParam, rkLocal:");
puts("ctx.Update(n.name, v)");
puts("return v, false");
puts("case rkLib:");
puts("rootCtx.UpdateLocal(n.name, v)");
puts("return v, false");
puts("case rkGlobalLet:");
puts("// D1-reborn Run N+3: top-level user `let` writes from the eval-body");
puts("// path must also update the package-scope Go var so direct-emit'd code");
puts("// (which reads ij_<name> directly) stays in sync. ctx.Update first so");
puts("// any non-direct-emit reader sees the new value before setTopLetGoVar");
puts("// (which is a single Go assignment) updates the Go-var cache.");
puts("rootCtx.UpdateLocal(n.name, v)");
puts("setTopLetGoVar(n.name, v)");
puts("return v, false");
puts("}");
puts("if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }");
puts("return v, false");
puts("}");
puts("func evalIndexAssign(n *Node, ctx *Context) (Value, bool) {");
puts("coll, ret := eval(n.left, ctx)");
puts("if ret { return coll, true }");
puts("if coll.tag == tInvalid { return coll, false }");
puts("idx, ret2 := eval(n.right, ctx)");
puts("if ret2 { return idx, true }");
puts("rhs, ret3 := eval(n.body, ctx)");
puts("if ret3 { return rhs, true }");
puts("coll.Put(idx, rhs)");
puts("return rhs, false");
puts("}");
puts("func evalBlock(n *Node, ctx *Context) (Value, bool) {");
puts("// Phase 2.5: skip the per-block *Context allocation when the resolver");
puts("// tagged this block as introducing zero bindings (hasLocals == false).");
puts("// while/for bodies with no `let` are the dominant case in sample.s.");
puts("// Reusing the caller's ctx is safe because evalAssign/evalVarDecl");
puts("// already route to the right ctx via their own dispatch; identifier");
puts("// reads walk the chain via ctx.Get which is identical to walking from");
puts("// a fresh blockCtx whose only entry would be the (absent) locals.");
puts("blockCtx := ctx");
puts("if n.hasLocals {");
puts("blockCtx = NewContext(ctx)");
puts("}");
puts("var last Value = vNull()");
puts("for _, s := range n.list {");
puts("v, returned := eval(s, blockCtx)");
puts("if returned { return v, true }");
puts("if v.tag == tInvalid { return v, false }");
puts("last = v");
puts("}");
puts("return last, false");
puts("}");
puts("func evalVarDecl(n *Node, ctx *Context) (Value, bool) {");
puts("var v Value = vNull()");
puts("if n.right != nil {");
puts("var ret bool; v, ret = eval(n.right, ctx)");
puts("if ret { return v, true }");
puts("}");
puts("// A new `let` ALWAYS binds in the current ctx, regardless of how the");
puts("// resolver classifies the pre-existing name. UpdateLocal is just");
puts("// Create without the function-call overhead of going through Create.");
puts("ctx.UpdateLocal(n.name, v)");
puts("// D1-reborn Run N+3: top-level `let X = ...` runs once at programNode");
puts("// startup; sync the package-scope Go var so direct-emit'd code observes");
puts("// the initialised value rather than vNull() (Go zero).");
puts("if n.resolvedKind == rkGlobalLet { setTopLetGoVar(n.name, v) }");
puts("return v, false");
puts("}");
puts("func evalIf(n *Node, ctx *Context) (Value, bool) {");
puts("c, ret := eval(n.left, ctx)");
puts("if ret { return c, true }");
puts("if c.tag == tInvalid { return c, false }");
puts("if c.IsTruthy() {");
puts("v, r := eval(n.body, ctx)");
puts("return v, r");
puts("}");
puts("if n.right != nil {");
puts("v, r := eval(n.right, ctx)");
puts("return v, r");
puts("}");
puts("return vNull(), false");
puts("}");
puts("func evalWhile(n *Node, ctx *Context) (Value, bool) {");
puts("var last Value = vNull()");
puts("for {");
puts("c, ret := eval(n.left, ctx)");
puts("if ret { return c, true }");
puts("if c.tag == tInvalid { return c, false }");
puts("if !c.IsTruthy() { return last, false }");
puts("v, returned := eval(n.body, ctx)");
puts("if returned { return v, true }");
puts("if v.tag == tInvalid { return v, false }");
puts("last = v");
puts("}");
puts("}");
puts("func evalReturn(n *Node, ctx *Context) (Value, bool) {");
puts("var v Value = vNull()");
puts("if n.right != nil { var ret bool; v, ret = eval(n.right, ctx); if ret { return v, true } }");
puts("return v, true");
puts("}");
puts("func evalFuncDecl(n *Node, ctx *Context) (Value, bool) {");
puts("defCtx := ctx");
// Run N+6: if the FuncDecl was direct-emit'd, dispatch the closure body
// straight into ij_<name>_impl_wrapper(defCtx, args.values). Skips the
// per-call &Context literal + params-map alloc + eval(bodyN, local) tree
// walk for every indirect call (the hot path under selfhost). For non-
// direct-emit'd defs (~12 holdouts + user-level IJ defs in parsed input)
// fall through to the original eval-body path.
//
// We pass defCtx (the ctx at evalFuncDecl-time = rootCtx for top-level
// promoted defs) instead of callerCtx because FunctionCommand.Execute
// discards callerCtx (Phase 2.5 alloc opt: `executeFunc(nil, params)`).
// The direct-emit'd impl's `ctx := callerCtx; ctx.Get(\"<name>\")` walks
// the parent chain to find top-level bindings; rootCtx is at the chain's
// root, so handing the impl rootCtx directly preserves semantics AND
// skips the chain-walk. ctx.Update for rkGlobalLet writes also resolve
// at rootCtx (where the binding lives), so dual-write semantics hold.
puts("if n.staticImpl != nil {");
puts("impl := n.staticImpl");
puts("fn := NewFunctionCommand(defCtx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("return impl(defCtx, args.values)");
puts("})");
puts("ctx.Create(n.name, vFunc(fn))");
puts("return vFunc(fn), false");
puts("}");
puts("pNames := n.params");
puts("bodyN := n.body");
// Closure body allocates a fresh *Context per call. P-VM.5e: params go
// into the Context's INLINE slots (first 4) -- no map alloc at all for
// the overwhelmingly common <=4-param case (the old sized-map emit was
// the top malloc site: mapassign growToSmall under this closure).
// Params 5+ spill through localPut. Missing args stay UNBOUND (reads
// chain-walk to defCtx at read time) -- the i < nv guard is load-bearing.
puts("fn := NewFunctionCommand(defCtx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("local := &Context{parent: defCtx}");
puts("nv := len(args.values)");
puts("for i, p := range pNames {");
puts("if i >= nv { break }");
puts("if i < 4 {");
puts("local.inKeys[i] = p");
puts("local.inVals[i] = args.values[i]");
puts("local.inN = i + 1");
puts("} else {");
puts("local.localPut(p, args.values[i])");
puts("}");
puts("}");
puts("result, _ := eval(bodyN, local)");
puts("return result");
puts("})");
puts("ctx.Create(n.name, vFunc(fn))");
puts("return vFunc(fn), false");
puts("}");
puts("func evalCall(n *Node, ctx *Context) (Value, bool) {");
puts("callee, ret := eval(n.left, ctx)");
puts("if ret { return callee, true }");
puts("if callee.tag == tInvalid { return callee, false }");
puts("if callee.tag != tFunc { return vInvalid(" + chr(34) + "call target not a function" + chr(34) + "), false }");
// Preallocate the args wrapper + backing slice to the exact arg count.
// Previous emit (`NewArrayValue()` + per-arg `append`) cost one alloc
// for the empty ArrayValue, one growth alloc for the backing slice on
// the first append, and potentially more on growth. Single &ArrayValue
// literal with a pre-sized slice cuts this to one alloc for the slice
// + one for the wrapper (lib fns still need the wrapper for Get/Length).
puts("nargs := len(n.list)");
puts("av := &ArrayValue{values: make([]Value, nargs)}");
puts("for i, a := range n.list { v, r2 := eval(a, ctx); if r2 { return v, true }; av.values[i] = v }");
puts("result := callee.cmdp().Execute(ctx, av)");
puts("return result, false");
puts("}");
puts("func evalStaticCall(n *Node, ctx *Context) (Value, bool) {");
puts("// D2-reborn: callee is a top-level static def known at emit time. Skip");
puts("// evalIdent + ctx.Get + FunctionCommand.Execute + ArrayValue alloc; jump");
puts("// directly into the body's evaluator via the baked-in func pointer.");
puts("args := make([]Value, len(n.list))");
puts("for i, a := range n.list {");
puts("v, r := eval(a, ctx)");
puts("if r { return v, true }");
puts("if v.tag == tInvalid { return v, false }");
puts("args[i] = v");
puts("}");
puts("return n.staticImpl(ctx, args), false");
puts("}");
puts("func evalArrayLit(n *Node, ctx *Context) (Value, bool) {");
puts("a := NewArrayValue()");
puts("for _, e := range n.list { v, ret := eval(e, ctx); if ret { return v, true }; a.values = append(a.values, v) }");
puts("return vArray(a), false");
puts("}");
puts("func evalMapLit(n *Node, ctx *Context) (Value, bool) {");
puts("m := NewEmptyMapValue()");
puts("for i := 0; i+1 < len(n.list); i += 2 {");
puts("k, r1 := eval(n.list[i], ctx); if r1 { return k, true }");
puts("v, r2 := eval(n.list[i+1], ctx); if r2 { return v, true }");
puts("m.Put(k, v)");
puts("}");
puts("return vMap(m), false");
puts("}");
puts("func evalIndex(n *Node, ctx *Context) (Value, bool) {");
puts("coll, ret := eval(n.left, ctx)");
puts("if ret { return coll, true }");
puts("if coll.tag == tInvalid { return coll, false }");
puts("idx, ret2 := eval(n.right, ctx)");
puts("if ret2 { return idx, true }");
puts("return coll.Get(idx), false");
puts("}");
puts("func evalProgram(n *Node, ctx *Context) (Value, bool) {");
puts("var last Value = vNull()");
puts("for _, s := range n.list {");
puts("v, ret := eval(s, ctx)");
puts("if ret { return v, true }");
puts("if v.tag == tInvalid { return v, false }");
puts("last = v");
puts("}");
puts("return last, false");
puts("}");
puts("");
goVMPrefix();
puts("");

}

// P-VM.1/3: Go-side bytecode VM. Since P-VM.3 (2026-06-12) it is the DEFAULT
// engine; IJ_VM=0 opts back into the tree-walking eval (escape hatch until
// P-VM.4 retires the dead walker). Emitted as constant text into every
// app.go prelude, so the fixed point is unaffected by construction. The
// compiler (vmCompileProgram/vmCompileFunc) runs at binary startup on the
// emitted programNode:
//   - top-level statements compile per-statement; any unsupported statement
//     rolls back and becomes a vmOpEvalNode escape into eval(stmt, ctx), so
//     semantics are preserved at statement granularity.
//   - top-level FuncDecls WITHOUT staticImpl get all-or-nothing body chunks
//     with slot-indexed frame locals (params + function-scope lets; P-VM.2
//     adds block-scoped lets via compile-time shadow records that restore
//     the symtab mapping at block end -- exact NewContext(blockCtx)
//     semantics, fresh slot per shadowed name). Remaining bail rules keep
//     tree-walk semantics exact: no nested defs, no upvalues, no unannotated
//     writes inside funcs (dynamic Exists/Update/Create can target a
//     function-local ctx that slots cannot model).
//   - P-VM.2 node-kind coverage: nkArrayLit/nkMapLit (vmOpArray/vmOpMap,
//     no per-element invalid checks -- evalArrayLit/evalMapLit have none),
//     nkIndex/nkIndexAssign (invalid COLLECTION short-circuits keeping the
//     invalid as the result; idx/rhs are NOT invalid-checked, mirroring
//     evalIndex/evalIndexAssign), nkStaticCall (per-arg invalid check
//     aborts the call keeping the invalid -- evalStaticCall semantics; args
//     copied to a fresh []Value because the impl may re-enter the VM which
//     would clobber an in-stack window).
//   - promoted defs (staticImpl != nil) declare via vmOpMakeStaticFn, an
//     exact mirror of the evalFuncDecl staticImpl branch; their CALLS go
//     through vmOpStaticCall/the closure fast branch -- direct Go bodies
//     are already faster than the VM, so bodies are never VM-compiled.
// Invalid-value propagation mirrors the tree-walker exactly: vmOpChkInv is
// emitted at the same points eval* check tag==tInvalid (infix left/right,
// prefix operand, call callee, if/while condition), and vmOpStep replicates
// the per-statement invalid abort of evalBlock/evalProgram/evalWhile.
// Arity tolerance (extras dropped, missing vNull-padded) lives in
// vmCallChunk, matching the closure convention in evalFuncDecl.
def goVMPrefix() {
puts("// --- P-VM: bytecode VM (runtime compile; default engine since P-VM.3, IJ_VM=0 opts out) ---");
puts("const (");
puts("vmOpConst uint8 = iota");
puts("vmOpNull");
puts("vmOpTrue");
puts("vmOpFalse");
puts("vmOpLoadSlot");
puts("vmOpStoreSlot");
puts("vmOpLoadName");
puts("vmOpLoadLib");
puts("vmOpStoreNameUpdate");
puts("vmOpStoreLib");
puts("vmOpStoreGlobalLet");
puts("vmOpStoreNameDyn");
puts("vmOpDeclName");
puts("vmOpInfix");
puts("vmOpPrefix");
puts("vmOpJump");
puts("vmOpJumpIfFalse");
puts("vmOpJumpIfFalsyKeep");
puts("vmOpJumpIfTruthyKeep");
puts("vmOpJumpIfNotFunc");
puts("vmOpJumpIfInvKeep");
puts("vmOpJumpIfInvDropN");
puts("vmOpCall");
puts("vmOpMakeFn");
puts("vmOpReturn");
puts("vmOpStep");
puts("vmOpEvalNode");
puts("vmOpArray");
puts("vmOpMap");
puts("vmOpIndex");
puts("vmOpIndexStore");
puts("vmOpStaticCall");
puts("vmOpMakeStaticFn");
puts(")");
puts("type VMInstr struct {");
puts("op uint8");
puts("a int32");
puts("b int32");
puts("}");
puts("type VMChunk struct {");
puts("code []VMInstr");
puts("consts []Value");
puts("names []string");
puts("nodes []*Node");
puts("fns []*VMChunk");
puts("params []string");
puts("bodyNode *Node");
puts("numParams int");
puts("numSlots int");
puts("name string");
puts("}");
puts("var vmStack []Value");
puts("var vmSP int");
puts('var vmDebug = os.Getenv("IJ_VM_DEBUG") != ""');
puts("func vmEnsureStack(n int) {");
puts("if n <= len(vmStack) { return }");
puts("ns := len(vmStack) * 2");
puts("if ns < 1024 { ns = 1024 }");
puts("if ns < n { ns = n + 1024 }");
puts("newStack := make([]Value, ns)");
puts("copy(newStack, vmStack)");
puts("vmStack = newStack");
puts("}");
puts("// P-VM.2: block-scoped `let` support. A let inside a nested block gets a");
puts("// FRESH slot and a shadow record; at block end the symtab mapping is");
puts("// restored, so reads after the block see the outer binding (which kept");
puts("// its value -- writes inside the block hit the shadow slot). This is");
puts("// exactly the tree-walker's NewContext(blockCtx) create/destroy, modeled");
puts("// at compile time. Re-let of a name already declared in the SAME block");
puts("// reuses its slot (UpdateLocal overwrite semantics).");
puts("type vmShadowRec struct {");
puts("name string");
puts("slot int32");
puts("had bool");
puts("}");
puts("type vmCompiler struct {");
puts("chunk *VMChunk");
puts("ok bool");
puts("topLevel bool");
puts("blockDepth int");
puts("symtab map[string]int32");
puts("shadows []vmShadowRec");
puts("scopeMarks []int");
puts("}");
puts("func (c *vmCompiler) emit(op uint8, a int32, b int32) int {");
puts("c.chunk.code = append(c.chunk.code, VMInstr{op: op, a: a, b: b})");
puts("return len(c.chunk.code) - 1");
puts("}");
puts("func (c *vmCompiler) here() int32 { return int32(len(c.chunk.code)) }");
puts("func (c *vmCompiler) patch(at int) { c.chunk.code[at].a = int32(len(c.chunk.code)) }");
puts("func (c *vmCompiler) nameIdx(s string) int32 {");
puts("for i := 0; i < len(c.chunk.names); i++ {");
puts("if c.chunk.names[i] == s { return int32(i) }");
puts("}");
puts("c.chunk.names = append(c.chunk.names, s)");
puts("return int32(len(c.chunk.names) - 1)");
puts("}");
puts("func (c *vmCompiler) constIdx(v Value) int32 {");
puts("c.chunk.consts = append(c.chunk.consts, v)");
puts("return int32(len(c.chunk.consts) - 1)");
puts("}");
puts("func (c *vmCompiler) compileIdent(n *Node) {");
puts("if !c.topLevel {");
puts("if slot, found := c.symtab[n.name]; found {");
puts("c.emit(vmOpLoadSlot, slot, 0)");
puts("return");
puts("}");
puts("}");
puts("if n.resolvedKind == rkUpvalue { c.ok = false; return }");
puts("if n.resolvedKind == rkLib {");
puts("c.emit(vmOpLoadLib, c.nameIdx(n.name), 0)");
puts("return");
puts("}");
puts("c.emit(vmOpLoadName, c.nameIdx(n.name), 0)");
puts("}");
puts("// Invalid values are POISON VALUES, not exceptions: evalInfix returns the");
puts("// invalid operand as the expression result (skipping the rest of the");
puts("// expression) and only the per-STATEMENT checks (vmOpStep) abort frames.");
puts("// vmOpJumpIfInvKeep jumps to the expression end keeping the invalid on top.");
puts("func (c *vmCompiler) compileInfix(n *Node) {");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("if n.op == opAnd {");
puts("j := c.emit(vmOpJumpIfFalsyKeep, 0, 0)");
puts("c.compileExpr(n.right)");
puts("c.patch(j)");
puts("c.patch(ji)");
puts("return");
puts("}");
puts("if n.op == opOr {");
puts("j := c.emit(vmOpJumpIfTruthyKeep, 0, 0)");
puts("c.compileExpr(n.right)");
puts("c.patch(j)");
puts("c.patch(ji)");
puts("return");
puts("}");
puts("c.compileExpr(n.right)");
puts("if !c.ok { return }");
puts("// r invalid: result is r and l is DISCARDED (evalInfix returns r) --");
puts("// must drop l beneath or the stack misaligns. Drop-variant jump.");
puts("ji2 := c.emit(vmOpJumpIfInvDropN, 0, 1)");
puts("c.emit(vmOpInfix, int32(n.op), 0)");
puts("c.patch(ji)");
puts("c.patch(ji2)");
puts("}");
puts("func (c *vmCompiler) compileExpr(n *Node) {");
puts("if !c.ok { return }");
puts("if n == nil { c.ok = false; return }");
puts("switch n.kind {");
puts("case nkIntLit:");
puts("c.emit(vmOpConst, c.constIdx(Value{tag: tInt, i: n.iVal}), 0)");
puts("case nkDoubleLit:");
puts("c.emit(vmOpConst, c.constIdx(vDouble(n.dVal)), 0)");
puts("case nkStringLit:");
puts("c.emit(vmOpConst, c.constIdx(Value{tag: tString, s: n.name}), 0)");
puts("case nkBoolLit:");
puts("if n.bVal { c.emit(vmOpTrue, 0, 0) } else { c.emit(vmOpFalse, 0, 0) }");
puts("case nkNullLit:");
puts("c.emit(vmOpNull, 0, 0)");
puts("case nkIdent:");
puts("c.compileIdent(n)");
puts("case nkInfix:");
puts("c.compileInfix(n)");
puts("case nkPrefix:");
puts("c.compileExpr(n.right)");
puts("if !c.ok { return }");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("c.emit(vmOpPrefix, int32(n.op), 0)");
puts("c.patch(ji)");
puts("case nkCall:");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("j := c.emit(vmOpJumpIfNotFunc, 0, 0)");
puts("for i := 0; i < len(n.list); i++ {");
puts("c.compileExpr(n.list[i])");
puts("if !c.ok { return }");
puts("}");
puts("c.emit(vmOpCall, 0, int32(len(n.list)))");
puts("c.patch(ji)");
puts("c.patch(j)");
puts("case nkArrayLit:");
puts("// evalArrayLit: elements appended verbatim, NO invalid checks");
puts("for i := 0; i < len(n.list); i++ {");
puts("c.compileExpr(n.list[i])");
puts("if !c.ok { return }");
puts("}");
puts("c.emit(vmOpArray, int32(len(n.list)), 0)");
puts("case nkMapLit:");
puts("// evalMapLit: k/v pairs Put in order, NO invalid checks; an odd");
puts("// trailing expr is never evaluated (i+1 < len guard) -- mirror that");
puts("np := 0");
puts("for i := 0; i+1 < len(n.list); i += 2 {");
puts("c.compileExpr(n.list[i])");
puts("c.compileExpr(n.list[i+1])");
puts("if !c.ok { return }");
puts("np++");
puts("}");
puts("c.emit(vmOpMap, int32(np), 0)");
puts("case nkIndex:");
puts("// evalIndex: invalid COLLECTION is the result (idx never evaluated);");
puts("// the idx itself is NOT invalid-checked (coll.Get(invalid) runs)");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("c.compileExpr(n.right)");
puts("if !c.ok { return }");
puts("c.emit(vmOpIndex, 0, 0)");
puts("c.patch(ji)");
puts("case nkStaticCall:");
puts("c.compileStaticCall(n)");
puts("default:");
puts("c.ok = false");
puts("}");
puts("}");
puts("// evalStaticCall semantics: each ARG is invalid-checked (unlike nkCall");
puts("// where invalids flow into the callee) -- an invalid arg aborts the call");
puts("// and becomes the expression result, dropping the args already pushed.");
puts("func (c *vmCompiler) compileStaticCall(n *Node) {");
puts("jumps := []int{}");
puts("for i := 0; i < len(n.list); i++ {");
puts("c.compileExpr(n.list[i])");
puts("if !c.ok { return }");
puts("jumps = append(jumps, c.emit(vmOpJumpIfInvDropN, 0, int32(i)))");
puts("}");
puts("c.chunk.nodes = append(c.chunk.nodes, n)");
puts("c.emit(vmOpStaticCall, int32(len(c.chunk.nodes)-1), int32(len(n.list)))");
puts("for i := 0; i < len(jumps); i++ { c.patch(jumps[i]) }");
puts("}");
puts("// evalIndexAssign: invalid COLLECTION short-circuits (no Put, invalid is");
puts("// the statement result); idx and rhs are NOT invalid-checked. Result=rhs.");
puts("func (c *vmCompiler) compileIndexAssign(n *Node) {");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("c.compileExpr(n.right)");
puts("if !c.ok { return }");
puts("c.compileExpr(n.body)");
puts("if !c.ok { return }");
puts("c.emit(vmOpIndexStore, 0, 0)");
puts("c.patch(ji)");
puts("}");
puts("func (c *vmCompiler) compileVarDecl(n *Node) {");
puts("// init expr compiles BEFORE the symtab update: `let x = x + 1` reads");
puts("// the OUTER x, matching eval(n.right) before UpdateLocal binds.");
puts("if n.right != nil { c.compileExpr(n.right) } else { c.emit(vmOpNull, 0, 0) }");
puts("if !c.ok { return }");
puts("if c.topLevel {");
puts("if c.blockDepth > 0 { c.ok = false; return }");
puts("flag := int32(0)");
puts("if n.resolvedKind == rkGlobalLet { flag = 1 }");
puts("c.emit(vmOpDeclName, c.nameIdx(n.name), flag)");
puts("return");
puts("}");
puts("if c.blockDepth > 0 {");
puts("// block-scoped let (P-VM.2): re-let in the SAME block overwrites its");
puts("// slot; first let shadows the outer mapping via a fresh slot + a");
puts("// shadow record that compileBlock restores at block end.");
puts("mark := c.scopeMarks[len(c.scopeMarks)-1]");
puts("for i := mark; i < len(c.shadows); i++ {");
puts("if c.shadows[i].name == n.name {");
puts("c.emit(vmOpStoreSlot, c.symtab[n.name], 0)");
puts("return");
puts("}");
puts("}");
puts("old, had := c.symtab[n.name]");
puts("c.shadows = append(c.shadows, vmShadowRec{name: n.name, slot: old, had: had})");
puts("slot := int32(c.chunk.numSlots)");
puts("c.chunk.numSlots = c.chunk.numSlots + 1");
puts("c.symtab[n.name] = slot");
puts("c.emit(vmOpStoreSlot, slot, 0)");
puts("return");
puts("}");
puts("slot, found := c.symtab[n.name]");
puts("if !found {");
puts("slot = int32(c.chunk.numSlots)");
puts("c.chunk.numSlots = c.chunk.numSlots + 1");
puts("c.symtab[n.name] = slot");
puts("}");
puts("c.emit(vmOpStoreSlot, slot, 0)");
puts("}");
puts("func (c *vmCompiler) compileAssign(n *Node) {");
puts("c.compileExpr(n.right)");
puts("if !c.ok { return }");
puts("if !c.topLevel {");
puts("if slot, found := c.symtab[n.name]; found {");
puts("c.emit(vmOpStoreSlot, slot, 0)");
puts("return");
puts("}");
puts("switch n.resolvedKind {");
puts("case rkLib:");
puts("c.emit(vmOpStoreLib, c.nameIdx(n.name), 0)");
puts("case rkGlobalLet:");
puts("c.emit(vmOpStoreGlobalLet, c.nameIdx(n.name), 0)");
puts("default:");
puts("c.ok = false");
puts("}");
puts("return");
puts("}");
puts("switch n.resolvedKind {");
puts("case rkParam, rkLocal:");
puts("c.emit(vmOpStoreNameUpdate, c.nameIdx(n.name), 0)");
puts("case rkLib:");
puts("c.emit(vmOpStoreLib, c.nameIdx(n.name), 0)");
puts("case rkGlobalLet:");
puts("c.emit(vmOpStoreGlobalLet, c.nameIdx(n.name), 0)");
puts("default:");
puts("c.emit(vmOpStoreNameDyn, c.nameIdx(n.name), 0)");
puts("}");
puts("}");
puts("func (c *vmCompiler) compileBlock(n *Node) {");
puts("if c.topLevel && n.hasLocals { c.ok = false; return }");
puts("c.emit(vmOpNull, 0, 0)");
puts("c.blockDepth = c.blockDepth + 1");
puts("c.scopeMarks = append(c.scopeMarks, len(c.shadows))");
puts("for i := 0; i < len(n.list); i++ {");
puts("c.compileStmt(n.list[i])");
puts("if !c.ok { return }");
puts("c.emit(vmOpStep, 0, 0)");
puts("}");
puts("// restore shadowed mappings (reverse order: innermost-last wins back)");
puts("mark := c.scopeMarks[len(c.scopeMarks)-1]");
puts("for i := len(c.shadows) - 1; i >= mark; i-- {");
puts("if c.shadows[i].had {");
puts("c.symtab[c.shadows[i].name] = c.shadows[i].slot");
puts("} else {");
puts("delete(c.symtab, c.shadows[i].name)");
puts("}");
puts("}");
puts("c.shadows = c.shadows[:mark]");
puts("c.scopeMarks = c.scopeMarks[:len(c.scopeMarks)-1]");
puts("c.blockDepth = c.blockDepth - 1");
puts("}");
puts("func (c *vmCompiler) compileIf(n *Node) {");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("// invalid condition: the if-statement RESULT is the invalid (evalIf)");
puts("ji := c.emit(vmOpJumpIfInvKeep, 0, 0)");
puts("jf := c.emit(vmOpJumpIfFalse, 0, 0)");
puts("c.compileStmt(n.body)");
puts("if !c.ok { return }");
puts("jend := c.emit(vmOpJump, 0, 0)");
puts("c.patch(jf)");
puts("if n.right != nil {");
puts("c.compileStmt(n.right)");
puts("if !c.ok { return }");
puts("} else {");
puts("c.emit(vmOpNull, 0, 0)");
puts("}");
puts("c.patch(jend)");
puts("c.patch(ji)");
puts("}");
puts("func (c *vmCompiler) compileWhile(n *Node) {");
puts("c.emit(vmOpNull, 0, 0)");
puts("top := c.here()");
puts("c.compileExpr(n.left)");
puts("if !c.ok { return }");
puts("// invalid condition: drop the loop-last beneath, keep the invalid as");
puts("// the while-statement result (evalWhile returns c on invalid cond)");
puts("ji := c.emit(vmOpJumpIfInvDropN, 0, 1)");
puts("jf := c.emit(vmOpJumpIfFalse, 0, 0)");
puts("c.compileStmt(n.body)");
puts("if !c.ok { return }");
puts("c.emit(vmOpStep, 0, 0)");
puts("c.emit(vmOpJump, top, 0)");
puts("c.patch(jf)");
puts("c.patch(ji)");
puts("}");
puts("func (c *vmCompiler) compileFuncDecl(n *Node) {");
puts("if !c.topLevel { c.ok = false; return }");
puts("if n.staticImpl != nil {");
puts("// promoted def: declaration compiles to vmOpMakeStaticFn (exact mirror");
puts("// of the evalFuncDecl staticImpl fast branch); the body stays direct Go");
puts("c.chunk.nodes = append(c.chunk.nodes, n)");
puts("c.emit(vmOpMakeStaticFn, int32(len(c.chunk.nodes)-1), 0)");
puts("return");
puts("}");
puts("fc, found := vmCompileFunc(n)");
puts("if !found { c.ok = false; return }");
puts('if vmDebug { fmt.Fprintln(os.Stderr, "[vm] compiled func chunk: " + n.name) }');
puts("c.chunk.fns = append(c.chunk.fns, fc)");
puts("c.emit(vmOpMakeFn, int32(len(c.chunk.fns)-1), c.nameIdx(n.name))");
puts("}");
puts("func (c *vmCompiler) compileStmt(n *Node) {");
puts("if !c.ok { return }");
puts("if n == nil { c.ok = false; return }");
puts("switch n.kind {");
puts("case nkExprStmt:");
puts("c.compileExpr(n.left)");
puts("case nkVarDecl:");
puts("c.compileVarDecl(n)");
puts("case nkAssign:");
puts("c.compileAssign(n)");
puts("case nkIndexAssign:");
puts("c.compileIndexAssign(n)");
puts("case nkBlock:");
puts("c.compileBlock(n)");
puts("case nkIfStmt:");
puts("c.compileIf(n)");
puts("case nkWhileStmt:");
puts("c.compileWhile(n)");
puts("case nkReturn:");
puts("if n.right != nil { c.compileExpr(n.right) } else { c.emit(vmOpNull, 0, 0) }");
puts("if c.ok { c.emit(vmOpReturn, 0, 0) }");
puts("case nkFuncDecl:");
puts("c.compileFuncDecl(n)");
puts("default:");
puts("c.compileExpr(n)");
puts("}");
puts("}");
puts("func vmCompileFunc(n *Node) (*VMChunk, bool) {");
puts("if n.body == nil { return nil, false }");
puts("if n.body.kind != nkBlock { return nil, false }");
puts("fc := &VMChunk{name: n.name, numParams: len(n.params), params: n.params, bodyNode: n.body}");
puts("c := &vmCompiler{chunk: fc, ok: true, topLevel: false, symtab: make(map[string]int32)}");
puts("for i := 0; i < len(n.params); i++ {");
puts("c.symtab[n.params[i]] = int32(i)");
puts("}");
puts("fc.numSlots = len(n.params)");
puts("c.emit(vmOpNull, 0, 0)");
puts("for i := 0; i < len(n.body.list); i++ {");
puts("c.compileStmt(n.body.list[i])");
puts("if !c.ok { return nil, false }");
puts("c.emit(vmOpStep, 0, 0)");
puts("}");
puts("c.emit(vmOpReturn, 0, 0)");
puts("return fc, true");
puts("}");
puts("func vmCompileProgram(n *Node) *VMChunk {");
puts('ch := &VMChunk{name: "__program__"}');
puts("c := &vmCompiler{chunk: ch, ok: true, topLevel: true}");
puts("c.emit(vmOpNull, 0, 0)");
puts("nEsc := 0");
puts("for i := 0; i < len(n.list); i++ {");
puts("s := n.list[i]");
puts("mark := len(ch.code)");
puts("fnsMark := len(ch.fns)");
puts("nodesMark := len(ch.nodes)");
puts("c.ok = true");
puts("c.blockDepth = 0");
puts("c.shadows = c.shadows[:0]");
puts("c.scopeMarks = c.scopeMarks[:0]");
puts("c.compileStmt(s)");
puts("if !c.ok {");
puts("ch.code = ch.code[:mark]");
puts("ch.fns = ch.fns[:fnsMark]");
puts("ch.nodes = ch.nodes[:nodesMark]");
puts("ch.nodes = append(ch.nodes, s)");
puts("nEsc++");
puts("c.ok = true");
puts("c.emit(vmOpEvalNode, int32(len(ch.nodes)-1), 0)");
puts("}");
puts("c.emit(vmOpStep, 0, 0)");
puts("}");
puts('if vmDebug { fmt.Fprintln(os.Stderr, "[vm] program stmts:", len(n.list), "escaped:", nEsc, "funcChunks:", len(ch.fns)) }');
puts("return ch");
puts("}");
puts("func vmExec(ch *VMChunk, ctx *Context, base int) Value {");
puts("code := ch.code");
puts("pc := 0");
puts("for pc < len(code) {");
puts("in := code[pc]");
puts("pc++");
puts("switch in.op {");
puts("case vmOpConst:");
puts("vmStack[vmSP] = ch.consts[in.a]");
puts("vmSP++");
puts("case vmOpNull:");
puts("vmStack[vmSP] = vNull()");
puts("vmSP++");
puts("case vmOpTrue:");
puts("vmStack[vmSP] = Value{tag: tBool, b: true}");
puts("vmSP++");
puts("case vmOpFalse:");
puts("vmStack[vmSP] = Value{tag: tBool, b: false}");
puts("vmSP++");
puts("case vmOpLoadSlot:");
puts("vmStack[vmSP] = vmStack[base+int(in.a)]");
puts("vmSP++");
puts("case vmOpStoreSlot:");
puts("vmStack[base+int(in.a)] = vmStack[vmSP-1]");
puts("case vmOpLoadName:");
puts("vmStack[vmSP] = ctx.Get(ch.names[in.a])");
puts("vmSP++");
puts("case vmOpLoadLib:");
puts("vmStack[vmSP] = rootCtx.GetLocal(ch.names[in.a])");
puts("vmSP++");
puts("case vmOpStoreNameUpdate:");
puts("ctx.Update(ch.names[in.a], vmStack[vmSP-1])");
puts("case vmOpStoreLib:");
puts("rootCtx.UpdateLocal(ch.names[in.a], vmStack[vmSP-1])");
puts("case vmOpStoreGlobalLet:");
puts("rootCtx.UpdateLocal(ch.names[in.a], vmStack[vmSP-1])");
puts("setTopLetGoVar(ch.names[in.a], vmStack[vmSP-1])");
puts("case vmOpStoreNameDyn:");
puts("if ctx.Exists(ch.names[in.a]) {");
puts("ctx.Update(ch.names[in.a], vmStack[vmSP-1])");
puts("} else {");
puts("ctx.Create(ch.names[in.a], vmStack[vmSP-1])");
puts("}");
puts("case vmOpDeclName:");
puts("ctx.UpdateLocal(ch.names[in.a], vmStack[vmSP-1])");
puts("if in.b == 1 { setTopLetGoVar(ch.names[in.a], vmStack[vmSP-1]) }");
puts("case vmOpInfix:");
puts("r := vmStack[vmSP-1]");
puts("l := vmStack[vmSP-2]");
puts("vmSP = vmSP - 2");
puts("var res Value");
puts("switch uint8(in.a) {");
puts("case opAdd:");
puts("res = l.Add(r)");
puts("case opSub:");
puts("res = l.Subtract(r)");
puts("case opMul:");
puts("res = l.Multiply(r)");
puts("case opDiv:");
puts("res = l.Divide(r)");
puts("case opMod:");
puts("res = l.Modulo(r)");
puts("case opEq:");
puts("res = l.Equals(r)");
puts("case opNeq:");
puts("res = l.Equals(r).Not()");
puts("case opLt:");
puts("res = l.LessThan(r)");
puts("case opLte:");
puts("res = l.LessThanEqual(r)");
puts("case opGt:");
puts("res = l.BiggerThan(r)");
puts("case opGte:");
puts("res = l.BiggerThanEqual(r)");
puts("default:");
puts('res = vInvalid("unknown infix op")');
puts("}");
puts("vmStack[vmSP] = res");
puts("vmSP++");
puts("case vmOpPrefix:");
puts("v := vmStack[vmSP-1]");
puts("vmSP--");
puts("var res Value");
puts("if uint8(in.a) == opNeg {");
puts("res = Value{tag: tInt, i: -1}.Multiply(v)");
puts("} else if uint8(in.a) == opNot {");
puts("res = v.Not()");
puts("} else {");
puts('res = vInvalid("unknown prefix op")');
puts("}");
puts("vmStack[vmSP] = res");
puts("vmSP++");
puts("case vmOpJump:");
puts("pc = int(in.a)");
puts("case vmOpJumpIfFalse:");
puts("v := vmStack[vmSP-1]");
puts("vmSP--");
puts("if !v.IsTruthy() { pc = int(in.a) }");
puts("case vmOpJumpIfFalsyKeep:");
puts("if !vmStack[vmSP-1].IsTruthy() { pc = int(in.a) } else { vmSP-- }");
puts("case vmOpJumpIfTruthyKeep:");
puts("if vmStack[vmSP-1].IsTruthy() { pc = int(in.a) } else { vmSP-- }");
puts("case vmOpJumpIfNotFunc:");
puts("if vmStack[vmSP-1].tag != tFunc {");
puts('vmStack[vmSP-1] = vInvalid("call target not a function")');
puts("pc = int(in.a)");
puts("}");
puts("case vmOpCall:");
puts("argc := int(in.b)");
puts("av := &ArrayValue{values: make([]Value, argc)}");
puts("copy(av.values, vmStack[vmSP-argc:vmSP])");
puts("callee := vmStack[vmSP-argc-1]");
puts("vmSP = vmSP - argc - 1");
puts("res := callee.cmdp().Execute(ctx, av)");
puts("vmStack[vmSP] = res");
puts("vmSP++");
puts("case vmOpMakeFn:");
puts("fc := ch.fns[in.a]");
puts("fn := NewFunctionCommand(ctx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("return vmCallChunk(fc, args.values)");
puts("})");
puts("fv := vFunc(fn)");
puts("ctx.Create(ch.names[in.b], fv)");
puts("vmStack[vmSP] = fv");
puts("vmSP++");
puts("case vmOpReturn:");
puts("return vmStack[vmSP-1]");
puts("case vmOpStep:");
puts("v := vmStack[vmSP-1]");
puts("vmSP--");
puts("if v.tag == tInvalid { return v }");
puts("vmStack[vmSP-1] = v");
puts("case vmOpJumpIfInvKeep:");
puts("if vmStack[vmSP-1].tag == tInvalid { pc = int(in.a) }");
puts("case vmOpJumpIfInvDropN:");
puts("// keep top, drop b values beneath it (infix-l/while-last: b=1;");
puts("// static-call args already pushed: b=i)");
puts("if vmStack[vmSP-1].tag == tInvalid {");
puts("v := vmStack[vmSP-1]");
puts("vmSP = vmSP - 1 - int(in.b)");
puts("vmStack[vmSP] = v");
puts("vmSP++");
puts("pc = int(in.a)");
puts("}");
puts("case vmOpArray:");
puts("cnt := int(in.a)");
puts("av := NewArrayValue()");
puts("av.values = append(av.values, vmStack[vmSP-cnt:vmSP]...)");
puts("vmSP = vmSP - cnt");
puts("vmStack[vmSP] = vArray(av)");
puts("vmSP++");
puts("case vmOpMap:");
puts("np := int(in.a)");
puts("m := NewEmptyMapValue()");
puts("basei := vmSP - 2*np");
puts("for i := 0; i < np; i++ {");
puts("m.Put(vmStack[basei+2*i], vmStack[basei+2*i+1])");
puts("}");
puts("vmSP = basei");
puts("vmStack[vmSP] = vMap(m)");
puts("vmSP++");
puts("case vmOpIndex:");
puts("idx := vmStack[vmSP-1]");
puts("coll := vmStack[vmSP-2]");
puts("vmSP = vmSP - 2");
puts("vmStack[vmSP] = coll.Get(idx)");
puts("vmSP++");
puts("case vmOpIndexStore:");
puts("rhs := vmStack[vmSP-1]");
puts("idx := vmStack[vmSP-2]");
puts("coll := vmStack[vmSP-3]");
puts("vmSP = vmSP - 3");
puts("coll.Put(idx, rhs)");
puts("vmStack[vmSP] = rhs");
puts("vmSP++");
puts("case vmOpStaticCall:");
puts("// args COPIED out of the stack window: the impl may re-enter the VM");
puts("// (vmCallChunk bases at the current vmSP) and clobber the window");
puts("argc := int(in.b)");
puts("sn := ch.nodes[in.a]");
puts("args := make([]Value, argc)");
puts("copy(args, vmStack[vmSP-argc:vmSP])");
puts("vmSP = vmSP - argc");
puts("vmStack[vmSP] = sn.staticImpl(ctx, args)");
puts("vmSP++");
puts("case vmOpMakeStaticFn:");
puts("sn := ch.nodes[in.a]");
puts("impl := sn.staticImpl");
puts("fn := NewFunctionCommand(ctx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("return impl(ctx, args.values)");
puts("})");
puts("fv := vFunc(fn)");
puts("ctx.Create(sn.name, fv)");
puts("vmStack[vmSP] = fv");
puts("vmSP++");
puts("case vmOpEvalNode:");
puts("v, ret := eval(ch.nodes[in.a], ctx)");
puts("if ret { return v }");
puts("vmStack[vmSP] = v");
puts("vmSP++");
puts("}");
puts("}");
puts("return vmStack[vmSP-1]");
puts("}");
puts("func vmCallChunk(ch *VMChunk, args []Value) Value {");
puts("// Arity underflow: the tree-walk closure leaves missing params UNBOUND");
puts("// (reads chain-walk to defCtx at read time -- usually vInvalid). Slots");
puts("// cannot model unbound, so fall back to the exact evalFuncDecl closure");
puts("// path for this rare case. Extras-dropped (overflow) stays on slots.");
puts("if len(args) < ch.numParams {");
puts("vars := make(map[string]Value, ch.numParams)");
puts("for i := 0; i < len(args); i++ {");
puts("vars[ch.params[i]] = args[i]");
puts("}");
puts("local := &Context{parent: rootCtx, variables: vars}");
puts("res, _ := eval(ch.bodyNode, local)");
puts("return res");
puts("}");
puts("base := vmSP");
puts("vmEnsureStack(base + ch.numSlots + len(ch.code) + 8)");
puts("for i := 0; i < ch.numSlots; i++ {");
puts("if i < ch.numParams && i < len(args) {");
puts("vmStack[base+i] = args[i]");
puts("} else {");
puts("vmStack[base+i] = vNull()");
puts("}");
puts("}");
puts("vmSP = base + ch.numSlots");
puts("res := vmExec(ch, rootCtx, base)");
puts("vmSP = base");
puts("return res");
puts("}");
puts("func vmRunProgram(n *Node, ctx *Context) {");
puts("ch := vmCompileProgram(n)");
puts("vmEnsureStack(vmSP + len(ch.code) + 8)");
puts("vmExec(ch, ctx, 0)");
puts("}");
}


// Phase 2: Node tree program emitter — top-level def, captured AST closures stay live
let useNodeTree = true;

// D2-reborn: top-level static defs eligible for direct-call dispatch.
// Populated by collectStaticDefs(). staticDefNames is an in-source-order list
// (required for deterministic emit -- bit-identical fixed-point). staticDefByName
// is the name->FunctionDeclaration map consulted by CallExpression_toGo to decide
// whether to emit nkStaticCall (direct fn pointer) vs nkCall (Value{tag:tFunc}).
let staticDefNames = [];
let staticDefByName = {};

// D1-reborn Run N+3: top-level user `let` name set, populated by
// programToGoPhase2 from ast["resolvedRootLets"] BEFORE collectStaticDefs.
// canDirectEmit consults it to gate kind=global+origin=let identifier reads /
// call callees / assignment targets. Membership means "we have package-scope
// Go-var plumbing for this name" -- absence forces canDirectEmit to reject
// the def (no Go var to read/write, dual-write would emit invalid Go).
let topLetSet = {};

// Walk a Program's top-level statements; mark each FunctionDeclaration that is
//   - resolvedIsStatic   (body has no nested def, no dynamic lookup, no global write)
//   - resolvedAtRoot     (parent scope is the program root -- closure capture is rootCtx)
//   - single binding     (no other top-level def/let/assign rebinds the same name --
//                         excludes the `let oldX = X; def X(...) { oldX(...) }` override
//                         idiom and any future redefinition shape)
// Eligible defs get isStaticPromoted=true on the AST node, get a top-level Go
// `func ij_<name>_impl(...) Value` emitted alongside the AST, and get all
// direct-by-name call sites rewritten to nkStaticCall in the Node tree.
def collectStaticDefs(stmts) {
    staticDefNames = [];
    staticDefByName = {};
    let n = len(stmts);

    let counts = {};
    let i = 0;
    while (i < n) {
        let s = stmts[i];
        if (s != null) {
            let t = s["type"];
            if (t == "FunctionDeclaration" || t == "VariableDeclaration" || t == "AssignmentStatement") {
                let nm = s["name"];
                if (nm != null) {
                    if (counts[nm] == null) { counts[nm] = 0; }
                    counts[nm] = counts[nm] + 1;
                }
            }
        }
        i = i + 1;
    }

    // Pass 2: mark promoted defs + populate staticDefByName.
    // D2-reborn requires only: top-level (resolvedAtRoot) + single binding.
    // resolvedIsStatic was the D1-inlining predicate (no global writes, no
    // dynamic lookups so identifiers could be hoisted to Go vars); D2 keeps
    // the eval(body, local) call path so global writes via ctx.Update and
    // dynamic lookups via ctx.Get continue to work. Promoting non-static
    // defs (e.g. parser helpers like nextToken that write top-level state
    // currentToken/peekToken/currentPosition) is observationally identical
    // to the closure path while skipping FunctionCommand.Execute indirection.
    i = 0;
    while (i < n) {
        let s = stmts[i];
        if (s != null) {
            if (s["type"] == "FunctionDeclaration") {
                if (s["resolvedAtRoot"] == true) {
                    if (counts[s["name"]] == 1) {
                        s["isStaticPromoted"] = true;
                        push(staticDefNames, s["name"]);
                        staticDefByName[s["name"]] = s;
                    }
                }
            }
        }
        i = i + 1;
    }

    // Pass 3: opt promoted defs into direct-Go-statement body emit.
    // Run separately so staticDefByName is fully populated before
    // canDirectEmit walks bodies and reasons about CallExpression callees.
    // The opt-in trigger is either:
    //   (a) explicit allowlist (manual override, mostly for legacy
    //       Run-N+1 names that the body-coverage check ALSO accepts),
    //   (b) body-coverage check (canDirectEmit) AND resolvedIsStatic
    //       (no nested defs, no global writes, no dynamic lookups).
    // resolvedIsStatic is the safety belt against silent miscompiles:
    // direct-emit lowers identifier reads to Go vars, so any IJ
    // statement that depends on per-call ctx semantics (assignment
    // fall-through, captured-by-inner-def, ctx.Exists-style dynamic
    // lookup) would silently emit wrong code without it. The body
    // coverage check is necessary too: even a fully static body can
    // reference top-level lets / defs as bare values, which we do not
    // emit Go vars for (lib globals plumbing only covers library names).
    i = 0;
    while (i < n) {
        let s = stmts[i];
        if (s != null) {
            if (s["isStaticPromoted"] == true) {
                if (s["resolvedIsStatic"] == true) {
                    if (directEmitAllowlist[s["name"]] == true) {
                        s["useDirectEmit"] = true;
                    } else {
                        if (canDirectEmit(s["body"])) {
                            s["useDirectEmit"] = true;
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    return null;
}

// Body-coverage check used by collectStaticDefs Pass 3. Walks the body and
// returns true iff every node kind is supported by nodeToGoDirect AND every
// identifier / call-callee resolves to a name we can emit as a Go variable.
//
// The strict identifier rule reflects what programToGoPhase2 actually emits
// at package scope:
//   - kind=local            -> Go param / block-let / let-captured. Always OK.
//   - kind=global,origin=lib -> var ij_<n> Value (lib globals plumbing). OK.
//   - kind=global,origin=def -> as call callee in staticDefByName: OK
//                                (CallExpression_toGoDirect emits ij_<n>_impl);
//                                as bare value: NOT OK (no Go var named
//                                ij_<n>; only ij_<n>_impl and ij_<n>_body).
//   - kind=global,origin=let -> NOT OK (Phase 2 does not emit Go vars for
//                                top-level lets).
// The CallExpression branch checks the callee under a relaxed rule, then
// recurses into args under the normal rule.
def canDirectEmit(node) {
    if (node == null) { return true; }
    if (!isMap(node)) { return true; }
    let t = node["type"];
    if (t == null) { return true; }

    let supported = false;
    if (t == "NullLiteral") { supported = true; }
    if (t == "BooleanLiteral") { supported = true; }
    if (t == "NumberLiteral") { supported = true; }
    if (t == "StringLiteral") { supported = true; }
    if (t == "Identifier") { supported = true; }
    if (t == "BlockStatement") { supported = true; }
    if (t == "ReturnStatement") { supported = true; }
    if (t == "InfixExpression") { supported = true; }
    if (t == "PrefixExpression") { supported = true; }
    if (t == "CallExpression") { supported = true; }
    if (t == "IndexExpression") { supported = true; }
    if (t == "ExpressionStatement") { supported = true; }
    if (t == "VariableDeclaration") { supported = true; }
    if (t == "AssignmentStatement") { supported = true; }
    if (t == "IfStatement") { supported = true; }
    if (t == "WhileStatement") { supported = true; }
    if (t == "IndexAssignmentStatement") { supported = true; }
    if (t == "ArrayLiteral") { supported = true; }
    if (t == "MapLiteral") { supported = true; }
    if (!supported) { return false; }

    if (t == "Identifier") {
        let kind = node["resolvedKind"];
        let origin = node["resolvedOrigin"];
        if (kind == "local") { return true; }
        if (kind == "global") {
            if (origin == "lib") { return true; }
            // D1-reborn Run N+3: top-level `let` reads emit `ij_<name>`
            // (Go var) when name has plumbing; otherwise reject so the
            // generated Go does not reference a missing global.
            if (origin == "let") {
                if (topLetSet[node["name"]] == true) { return true; }
                return false;
            }
            // D1-reborn Run N+3: bare reference to a top-level def (e.g.
            // `node["evaluate"] = nullLiteralEvaluate`) emits `ctx.Get("<n>")`
            // as a safe value-lookup fallback. No package-scope Go var
            // required -- this slow path costs one map lookup, which is
            // negligible for AST-construction sites that run once per node.
            if (origin == "def") { return true; }
            return false;
        }
        return false;
    }

    if (t == "CallExpression") {
        let callee = node["callee"];
        if (callee != null) {
            if (isMap(callee)) {
                if (callee["type"] == "Identifier") {
                    let ckind = callee["resolvedKind"];
                    let corigin = callee["resolvedOrigin"];
                    let ok = false;
                    if (ckind == "local") { ok = true; }
                    if (ckind == "global") {
                        if (corigin == "lib") { ok = true; }
                        if (corigin == "def") {
                            if (staticDefByName[callee["name"]] != null) { ok = true; }
                        }
                        // D1-reborn Run N+3: indirect call through a top-level
                        // let-bound value (e.g. `lexer["nextToken"](lexer)` --
                        // here the lexer index is the callee, but a bare
                        // let-bound callable also reaches this branch). Emit
                        // through Value.Execute -- still skips an evalIdent +
                        // ctx.Get on the receiver.
                        if (corigin == "let") {
                            if (topLetSet[callee["name"]] == true) { ok = true; }
                        }
                    }
                    if (!ok) { return false; }
                } else {
                    if (!canDirectEmit(callee)) { return false; }
                }
            }
        }
        let args = node["arguments"];
        if (args != null) {
            if (isArray(args)) {
                let ai = 0;
                while (ai < len(args)) {
                    if (!canDirectEmit(args[ai])) { return false; }
                    ai = ai + 1;
                }
            }
        }
        return true;
    }

    let scalarKeys = ["condition","consequence","alternative","body","left","right","collection","index","value","callee","expression","initializer"];
    let si = 0;
    while (si < len(scalarKeys)) {
        let k = scalarKeys[si];
        let child = node[k];
        if (child != null) {
            if (isMap(child)) {
                if (!canDirectEmit(child)) { return false; }
            }
        }
        si = si + 1;
    }
    let arrKeys = ["statements","elements","arguments"];
    let aj = 0;
    while (aj < len(arrKeys)) {
        let k = arrKeys[aj];
        let arr = node[k];
        if (arr != null) {
            if (isArray(arr)) {
                let m = 0;
                while (m < len(arr)) {
                    if (arr[m] != null) {
                        if (isMap(arr[m])) {
                            if (!canDirectEmit(arr[m])) { return false; }
                        }
                    }
                    m = m + 1;
                }
            }
        }
        aj = aj + 1;
    }
    let pairs = node["pairs"];
    if (pairs != null) {
        if (isArray(pairs)) {
            let p = 0;
            while (p < len(pairs)) {
                let pair = pairs[p];
                if (pair != null) {
                    if (isMap(pair)) {
                        let pk = pair["key"];
                        if (pk != null) { if (isMap(pk)) { if (!canDirectEmit(pk)) { return false; } } }
                        let pv = pair["value"];
                        if (pv != null) { if (isMap(pv)) { if (!canDirectEmit(pv)) { return false; } } }
                    }
                }
                p = p + 1;
            }
        }
    }

    return true;
}

// D1-reborn allowlist. MVP scope: one leaf def (`nullLiteralEvaluate`) whose
// body is `return null;` -- exercises the impl prologue + epilogue, block,
// return, and null-literal direct emitters end-to-end. Subsequent runs grow
// this list as more `*ToGoDirect` emitters land.
let directEmitAllowlist = {};
directEmitAllowlist["nullLiteralEvaluate"] = true;
// Run N+1 additions: expression-only defs whose bodies use only the node
// kinds supported by the dispatcher today (NullLit/BoolLit/NumLit/StrLit,
// Identifier, Block, Return, Infix, Prefix, Call, Index). All callees and
// identifiers are either parameters (kind=local/origin=param) or static defs
// in staticDefByName, never library names — library identifier references
// expand to `ij_<libname>` which is NOT declared at package scope under the
// Phase-2 emit, and the closest follow-up loop will add that plumbing
// alongside statement-level emitters.
directEmitAllowlist["mangle"] = true;
directEmitAllowlist["positionGetLine"] = true;
directEmitAllowlist["positionGetColumn"] = true;
directEmitAllowlist["positionToString"] = true;
directEmitAllowlist["numberLiteralEvaluate"] = true;
directEmitAllowlist["getStringLiteralValue"] = true;
directEmitAllowlist["evaluateStringLiteral"] = true;
directEmitAllowlist["getBooleanLiteralValue"] = true;
directEmitAllowlist["evaluateBooleanLiteral"] = true;

// D1-reborn per-node-kind direct emitters. Each prints raw Go statement or
// expression text (no `&Node{...}` literals). Call sites are reached through
// the central `nodeToGoDirect` dispatcher; opt-in is per-def via the
// `useDirectEmit` flag set in `collectStaticDefs`. See
// `docs/research/2026-05-18-d1-reborn-emit-template.md` for the per-statement
// mapping these emitters mirror.

def nullLiteralToGoDirect(self) {
    print("vNull()");
}

def toGoBooleanLiteralDirect(self) {
    if (self["value"]) {
        print("Value{tag: tBool, b: true}");
    } else {
        print("Value{tag: tBool, b: false}");
    }
}

def numberLiteralToGoDirect(self) {
    let str = string(self["value"]);
    let i = 0;
    let isDouble = false;
    while (i < len(str)) {
        if (char(str, i) == ".") {
            isDouble = true;
        }
        i = i + 1;
    }
    if (isDouble) {
        // Lean Value: the double payload lives in `i` as Float64bits, so a
        // struct literal can no longer carry a float -- emit the constructor.
        print("vDouble(" + str + ")");
    } else {
        print("Value{tag: tInt, i: " + str + "}");
    }
}

def stringLiteralToGoDirect(self) {
    print("Value{tag: tString, s: " + chr(34) + escapeGoStringLiteral(self["value"]) + chr(34) + "}");
}

def identifierToGoDirect(self) {
    // Direct-emit identifiers resolve to Go variables with the `ij_` prefix:
    // - Parameters (resolvedKind=local, resolvedOrigin=param) -> ij_<name> Go
    //   function-scope locals materialised from `args[i]` in the impl prologue.
    // - Library names (resolvedKind=global, resolvedOrigin=lib) -> ij_<name>
    //   Go package-scope vars populated in main() after registerLibraryFunctions.
    // - Top-level user lets (resolvedKind=global, resolvedOrigin=let) -> ij_<name>
    //   Go package-scope vars populated by evalVarDecl (rkGlobalLet) when the
    //   programNode runs the let init AND kept in sync by evalAssign on writes
    //   from the eval-body path; direct-emit'd assignments dual-write to keep
    //   the eval-body view (ctx.Get) coherent.
    // - Bare ref to a top-level def (kind=global, origin=def) -> ctx.Get(<n>)
    //   slow path. AST-construction code (e.g. `node["evaluate"] = fooEvaluate`)
    //   stores the value once per node, so the map lookup is negligible.
    // - Block-scope `let`s (resolvedKind=local, resolvedOrigin=let) -> ij_<name>
    //   Go locals declared by `variableDeclarationToGoDirect` in the body.
    // No annotation: fall back to ctx.Get(<name>) so unannotated bootstrap-era
    // AST nodes (or any node the resolver did not visit) still compile.
    let kind = self["resolvedKind"];
    let origin = self["resolvedOrigin"];
    let nm = self["name"];
    if (kind == "local") {
        print(mangle(nm));
        return null;
    }
    if (kind == "global") {
        if (origin == "lib") {
            print(mangle(nm));
            return null;
        }
        if (origin == "let") {
            print(mangle(nm));
            return null;
        }
        if (origin == "def") {
            print("ctx.Get(" + chr(34) + nm + chr(34) + ")");
            return null;
        }
        print(mangle(nm));
        return null;
    }
    print("ctx.Get(" + chr(34) + nm + chr(34) + ")");
}

def ReturnStatement_toGoDirect(self) {
    if (self["value"] != null) {
        print("return ");
        nodeToGoDirect(self["value"]);
        puts("");
    } else {
        puts("return vNull()");
    }
}

def blockStatementToGoDirect(self) {
    puts("{");
    puts("_ = ctx");
    let stmts = self["statements"];
    let n = len(stmts);
    let i = 0;
    while (i < n) {
        nodeToGoDirect(stmts[i]);
        i = i + 1;
    }
    puts("}");
}

// Run N+1 expression-level emitters.
//
// Direct-emit produces Go expressions whose value type is `Value` (the tagged
// union). Every operator lowers onto a `Value` method. Receivers are wrapped
// in parens so nested expressions (e.g. `a + b + c` -> chained `Add`) stay
// unambiguous regardless of what the recursive emit produced.

def infixExpressionToGoDirect(self) {
    let op = self["operator"];
    // != is a.Equals(b).Not() — Equals returns Value, .Not() flips the bool tag.
    if (op == "!=") {
        print("(");
        nodeToGoDirect(self["left"]);
        print(").Equals(");
        nodeToGoDirect(self["right"]);
        print(").Not()");
        return null;
    }
    let method = "Add";
    if (op == "+") { method = "Add"; }
    if (op == "-") { method = "Subtract"; }
    if (op == "*") { method = "Multiply"; }
    if (op == "/") { method = "Divide"; }
    if (op == "%") { method = "Modulo"; }
    if (op == "==") { method = "Equals"; }
    if (op == "<") { method = "LessThan"; }
    if (op == "<=") { method = "LessThanEqual"; }
    if (op == ">") { method = "BiggerThan"; }
    if (op == ">=") { method = "BiggerThanEqual"; }
    if (op == "&&") { method = "And"; }
    if (op == "||") { method = "Or"; }
    print("(");
    nodeToGoDirect(self["left"]);
    print(").");
    print(method);
    print("(");
    nodeToGoDirect(self["right"]);
    print(")");
}

def prefixExpressionToGoDirect(self) {
    let op = self["operator"];
    if (op == "!") {
        print("(");
        nodeToGoDirect(self["right"]);
        print(").Not()");
        return null;
    }
    if (op == "-") {
        // No Value.Negate helper in goLibPrefix; subtract from vInt(0).
        print("vInt(0).Subtract(");
        nodeToGoDirect(self["right"]);
        print(")");
        return null;
    }
    puts("D1R_UNSUPPORTED_PREFIX_OP_" + op);
}

// P-VM.5a: fixed-arity fast-path table for pristine builtins. Returns the
// ijb_* Go helper name when (name, argc) has one, else null. Only consulted
// for callees the resolver stamped resolvedOrigin=="lib", which guarantees
// no top-level def/let anywhere in the program shadows the name (root
// declarations are hoisted before bodies are resolved), so the binding can
// never change at runtime -- exactly the same guarantee the existing
// ij_<name> package-var emit relies on. Names outside this table (or with
// a different arg count) keep the generic Execute(ctx, NewArrayValue(...))
// emit, whose pad/truncate arity behavior must be preserved.
def libFastEmitName(name, argc) {
    if (argc == 1) {
        if (name == "len") { return "ijb_len"; }
        if (name == "typeof") { return "ijb_typeof"; }
        if (name == "keys") { return "ijb_keys"; }
        if (name == "chr") { return "ijb_chr"; }
        if (name == "ord") { return "ijb_ord"; }
        if (name == "string") { return "ijb_string"; }
        if (name == "isArray") { return "ijb_isArray"; }
        if (name == "isMap") { return "ijb_isMap"; }
        if (name == "isNumber") { return "ijb_isNumber"; }
        if (name == "isString") { return "ijb_isString"; }
    }
    if (argc == 2) {
        if (name == "push") { return "ijb_push"; }
        if (name == "char") { return "ijb_char"; }
        if (name == "hasKey") { return "ijb_hasKey"; }
    }
    if (argc == 3) {
        if (name == "substr") { return "ijb_substr"; }
    }
    if (argc == 4) {
        if (name == "ijvmTagFn") { return "ijb_ijvmTagFn"; }
    }
    if (argc == 16) {
        if (name == "ijvmCallNative") { return "ijb_ijvmCallNative"; }
    }
    return null;
}

// CallExpression dispatch mirrors CallExpression_toGo's static-vs-indirect
// gate (kind=global && origin=def && staticDefByName[name]). Static-def
// callees skip the Value->FunctionCommand.Execute indirection by calling the
// impl directly (still through the []Value calling convention so the impl
// signature does not change between nkStaticCall and direct-emit dispatch).
// Indirect callees fall back to Value.Execute(ctx, *ArrayValue); fix_app_go.py
// keeps `.Execute(ctx, NewArrayValue(...))` untouched while rewriting bare
// NewArrayValue -> NewArrayValueAsValue elsewhere, so the *ArrayValue arg is
// preserved as the post-processor expects.
def CallExpression_toGoDirect(self) {
    let callee = self["callee"];
    let args = self["arguments"];
    let argsLen = len(args);

    let isStaticCall = false;
    if (callee != null) {
        if (callee["type"] == "Identifier") {
            if (callee["resolvedKind"] == "global") {
                if (callee["resolvedOrigin"] == "def") {
                    if (staticDefByName[callee["name"]] != null) {
                        isStaticCall = true;
                    }
                }
            }
        }
    }

    if (isStaticCall) {
        // Use positional-arg call when callee is a direct-emit def (no []Value alloc).
        // Eval-body promoted defs keep the []Value convention.
        //
        // ARITY: IJ tolerates extra/missing args at call sites (the
        // closure-path Execute drops extras and defaults missing to vNull).
        // Positional-arg Go calls cannot — Go enforces arity. Fall back to
        // the _impl_wrapper []Value path when caller-arg-count != callee-
        // param-count so semantic parity holds (wrapper does pad/truncate).
        let calleeData = staticDefByName[callee["name"]];
        let calleeIsDirectEmit = false;
        let calleeArity = 0;
        if (calleeData != null) {
            if (calleeData["useDirectEmit"] == true) {
                calleeIsDirectEmit = true;
            }
            let cps = calleeData["parameters"];
            if (cps != null) {
                calleeArity = len(cps);
            }
        }
        if (calleeIsDirectEmit && argsLen == calleeArity) {
            print(mangle(callee["name"]) + "_impl(ctx");
            let i = 0;
            while (i < argsLen) {
                print(", ");
                nodeToGoDirect(args[i]);
                i = i + 1;
            }
            print(")");
        } else {
            if (calleeIsDirectEmit) {
                print(mangle(callee["name"]) + "_impl_wrapper(ctx, []Value{");
            } else {
                print(mangle(callee["name"]) + "_impl(ctx, []Value{");
            }
            let i = 0;
            while (i < argsLen) {
                if (i > 0) { print(", "); }
                nodeToGoDirect(args[i]);
                i = i + 1;
            }
            print("})");
        }
    } else {
        // P-VM.5a: pristine-lib callees with a fixed-arity ijb_* impl skip
        // the Execute(ctx, NewArrayValue(...)) shim entirely (no *ArrayValue
        // alloc, no FunctionCommand dispatch, no params.Get unboxing).
        let fastName = null;
        if (callee != null) {
            if (callee["type"] == "Identifier") {
                if (callee["resolvedKind"] == "global") {
                    if (callee["resolvedOrigin"] == "lib") {
                        fastName = libFastEmitName(callee["name"], argsLen);
                    }
                }
            }
        }
        if (fastName != null) {
            print(fastName + "(");
            let i = 0;
            while (i < argsLen) {
                if (i > 0) { print(", "); }
                nodeToGoDirect(args[i]);
                i = i + 1;
            }
            print(")");
        } else {
            print("(");
            nodeToGoDirect(callee);
            print(").Execute(ctx, NewArrayValue(");
            let i = 0;
            while (i < argsLen) {
                if (i > 0) { print(", "); }
                nodeToGoDirect(args[i]);
                i = i + 1;
            }
            print("))");
        }
    }
}

def IndexExpression_toGoDirect(self) {
    print("(");
    nodeToGoDirect(self["collection"]);
    print(").Get(");
    nodeToGoDirect(self["index"]);
    print(")");
}

// Run N+2 statement-level emitters.
//
// Local Go let scoping mirrors IJ block scoping: a `var ij_<n> Value = ...`
// is visible only within the enclosing Go `{ ... }`, so inner-block lets
// shadow outer-block lets the same way IJ does. AssignmentStatement target
// is constrained to params + block-locals (resolvedIsStatic forbids
// global writes), so `ij_<n> = expr` is always re-assigning a Go var
// already in scope.
def variableDeclarationToGoDirect(self) {
    print("var " + mangle(self["name"]) + " Value = ");
    let init = self["initializer"];
    if (init != null) {
        nodeToGoDirect(init);
    } else {
        print("vNull()");
    }
    puts("");
    puts("_ = " + mangle(self["name"]));
}

def assignmentStatementToGoDirect(self) {
    let kind = self["resolvedKind"];
    let origin = self["resolvedOrigin"];
    // D1-reborn Run N+3: top-level `let` writes from direct-emit'd code
    // dual-write the package-scope Go var AND ctx, so eval-body readers
    // (which use ctx.Get) observe the new value. The Go-var write is the
    // fast read source for direct-emit'd code; ctx.Update keeps the
    // legacy path coherent. rootCtx is the canonical owner of top-level
    // lets, so the write goes through rootCtx.UpdateLocal (single map
    // write, no chain walk).
    if (kind == "global") {
        if (origin == "let") {
            print(mangle(self["name"]) + " = ");
            nodeToGoDirect(self["value"]);
            puts("");
            puts("rootCtx.UpdateLocal(" + chr(34) + self["name"] + chr(34) + ", " + mangle(self["name"]) + ")");
            return null;
        }
    }
    print(mangle(self["name"]) + " = ");
    nodeToGoDirect(self["value"]);
    puts("");
}

def expressionStatementToGoDirect(self) {
    // ExpressionStatement direct emit: `_ = <expr>` so Go is happy with any
    // Value-typed expression at statement position (including bare reads).
    // CallExpressions are valid statements in Go without the `_ =` wrap,
    // but the universal form keeps emit simple and lets the Go compiler
    // discard the result.
    let expr = self["expression"];
    if (expr == null) {
        return null;
    }
    print("_ = ");
    nodeToGoDirect(expr);
    puts("");
}

// Helper: emit the body of an if/while branch. If the body is a
// BlockStatement, emit its statements directly inside the outer Go braces
// the if/while emits -- avoids `{ { ... } }` nesting that would needlessly
// introduce an inner Go scope. Non-block bodies (single statement form,
// rare in IJ) just emit themselves.
def emitDirectBodyStatements(node) {
    if (node == null) { return null; }
    if (node["type"] == "BlockStatement") {
        let stmts = node["statements"];
        let n = len(stmts);
        let i = 0;
        while (i < n) {
            nodeToGoDirect(stmts[i]);
            i = i + 1;
        }
    } else {
        nodeToGoDirect(node);
    }
    return null;
}

def ifStatementToGoDirect(self) {
    print("if (");
    nodeToGoDirect(self["condition"]);
    puts(").IsTruthy() {");
    puts("_ = ctx");
    emitDirectBodyStatements(self["consequence"]);
    if (self["alternative"] != null) {
        puts("} else {");
        puts("_ = ctx");
        emitDirectBodyStatements(self["alternative"]);
    }
    puts("}");
}

def whileStatementToGoDirect(self) {
    print("for (");
    nodeToGoDirect(self["condition"]);
    puts(").IsTruthy() {");
    puts("_ = ctx");
    emitDirectBodyStatements(self["body"]);
    puts("}");
}

def indexAssignmentToGoDirect(self) {
    print("(");
    nodeToGoDirect(self["collection"]);
    print(").Put(");
    nodeToGoDirect(self["index"]);
    print(",");
    nodeToGoDirect(self["value"]);
    puts(")");
}

def arrayLiteralToGoDirect(self) {
    // Direct-emit impls live BEFORE main() in app.go and fix_app_go.py only
    // rewrites the body section (post-main). So we must emit the AsValue
    // form ourselves -- bare NewArrayValue(...) returns *ArrayValue and
    // breaks any "var X Value = ...", "return ...", call-arg, etc. context
    // where the surrounding Go expects Value. NewArrayValueAsValue is
    // unconditionally injected by fix_app_go.py STEP 5.
    print("NewArrayValueAsValue(");
    let elems = self["elements"];
    let n = len(elems);
    let i = 0;
    while (i < n) {
        if (i > 0) { print(","); }
        nodeToGoDirect(elems[i]);
        i = i + 1;
    }
    print(")");
}

def mapLiteralToGoDirect(self) {
    print("NewMapValueAsValue(");
    let pairs = self["pairs"];
    let n = len(pairs);
    let i = 0;
    while (i < n) {
        if (i > 0) { print(","); }
        let pair = pairs[i];
        print("KeyValuePair{Key: ");
        nodeToGoDirect(pair["key"]);
        print(", Value: ");
        nodeToGoDirect(pair["value"]);
        print("}");
        i = i + 1;
    }
    print(")");
}

// Dispatcher: route by AST node type. Unknown / unsupported kinds emit a
// sentinel that fails the Go build loudly so a mistakenly-opt'd-in def is
// caught at `compile-local.sh` time rather than silently miscompiling.
def nodeToGoDirect(node) {
    if (node == null) { return null; }
    let t = node["type"];
    if (t == "NullLiteral") { nullLiteralToGoDirect(node); return null; }
    if (t == "BooleanLiteral") { toGoBooleanLiteralDirect(node); return null; }
    if (t == "NumberLiteral") { numberLiteralToGoDirect(node); return null; }
    if (t == "StringLiteral") { stringLiteralToGoDirect(node); return null; }
    if (t == "Identifier") { identifierToGoDirect(node); return null; }
    if (t == "BlockStatement") { blockStatementToGoDirect(node); return null; }
    if (t == "ReturnStatement") { ReturnStatement_toGoDirect(node); return null; }
    if (t == "InfixExpression") { infixExpressionToGoDirect(node); return null; }
    if (t == "PrefixExpression") { prefixExpressionToGoDirect(node); return null; }
    if (t == "CallExpression") { CallExpression_toGoDirect(node); return null; }
    if (t == "IndexExpression") { IndexExpression_toGoDirect(node); return null; }
    if (t == "ExpressionStatement") { expressionStatementToGoDirect(node); return null; }
    if (t == "VariableDeclaration") { variableDeclarationToGoDirect(node); return null; }
    if (t == "AssignmentStatement") { assignmentStatementToGoDirect(node); return null; }
    if (t == "IfStatement") { ifStatementToGoDirect(node); return null; }
    if (t == "WhileStatement") { whileStatementToGoDirect(node); return null; }
    if (t == "IndexAssignmentStatement") { indexAssignmentToGoDirect(node); return null; }
    if (t == "ArrayLiteral") { arrayLiteralToGoDirect(node); return null; }
    if (t == "MapLiteral") { mapLiteralToGoDirect(node); return null; }
    puts("D1R_UNSUPPORTED_NODE_KIND_" + t + " // direct-emit fallback -- forces build failure");
    return null;
}

def programToGoPhase2(self) {
    let stmts = self["statements"];
    let n = len(stmts);

    // D1-reborn Run N+3: populate topLetSet from resolved top-level lets so
    // canDirectEmit (called transitively from collectStaticDefs) can accept
    // identifier reads / call callees / assignment targets that bind a
    // top-level user `let`. Done BEFORE collectStaticDefs so the body-coverage
    // walk sees a complete set.
    topLetSet = {};
    let rootLets = self["resolvedRootLets"];
    if (rootLets != null) {
        let rli = 0;
        while (rli < len(rootLets)) {
            topLetSet[rootLets[rli]] = true;
            rli = rli + 1;
        }
    }

    // D2-reborn pre-pass: mark eligible top-level static defs and emit a sibling
    // package-level Go function for each. Direct call-site dispatch
    // (CallExpression_toGo -> nkStaticCall) reads staticDefByName during the
    // Node-tree emit below; impls are package-level so order between impl emit
    // and Node-tree emit does not matter, but the body refs they read
    // (ij_<name>_body) are populated in main() before programNode is built.
    collectStaticDefs(stmts);

    // D1-reborn Run N+2: library globals plumbing. Direct-emit bodies refer to
    // library functions by bare `ij_<libname>` Go identifier (via identifier
    // and call-expression direct emitters). Declare those as package-scope
    // vars here so the references compile; populate them from ctx inside main()
    // immediately after registerLibraryFunctions(ctx). Without this, any
    // direct-emit'd def that calls puts/len/chr/... would compile-error.
    let libs = self["resolvedLibraryGlobals"];
    if (libs != null) {
        let li = 0;
        while (li < len(libs)) {
            puts("var " + mangle(libs[li]) + " Value");
            li = li + 1;
        }
    }

    // D1-reborn Run N+3: package-scope Go vars for top-level user lets +
    // setTopLetGoVar switch. Populated by evalVarDecl (rkGlobalLet) when the
    // programNode runs the top-level `let X = ...` init expressions, and
    // updated by evalAssign (rkGlobalLet) on subsequent eval-body writes.
    // Direct-emit'd code reads `ij_<name>` directly (skipping ctx.Get's chain
    // walk) and writes via dual-write (ij_<name> = v; ctx.Update(n, v)).
    if (rootLets != null) {
        let rli2 = 0;
        while (rli2 < len(rootLets)) {
            puts("var " + mangle(rootLets[rli2]) + " Value");
            rli2 = rli2 + 1;
        }
    }
    puts("func setTopLetGoVar(name string, v Value) {");
    if (rootLets != null) {
        if (len(rootLets) > 0) {
            puts("switch name {");
            let rli3 = 0;
            while (rli3 < len(rootLets)) {
                puts("case " + chr(34) + rootLets[rli3] + chr(34) + ": " + mangle(rootLets[rli3]) + " = v");
                rli3 = rli3 + 1;
            }
            puts("}");
        }
    }
    puts("}");

    let sdi = 0;
    while (sdi < len(staticDefNames)) {
        let nm = staticDefNames[sdi];
        puts("var " + mangle(nm) + "_body *Node");
        sdi = sdi + 1;
    }
    sdi = 0;
    while (sdi < len(staticDefNames)) {
        let nm = staticDefNames[sdi];
        let sdef = staticDefByName[nm];
        let sparams = sdef["parameters"];
        let spn = len(sparams);
        if (sdef["useDirectEmit"] == true) {
            // D1-reborn positional-arg direct-Go-statement impl.
            // Signature: func ij_<n>_impl(callerCtx *Context, ij_p1 Value, ...) Value
            // Skips the eval(body, local) tree-walker entirely and the []Value
            // args-slice alloc at direct call sites. A companion _impl_wrapper
            // with the uniform (ctx, args []Value) signature is emitted below for
            // nkStaticCall and other indirect paths.
            print("func " + mangle(nm) + "_impl(callerCtx *Context");
            let k = 0;
            while (k < spn) {
                print(", " + mangle(sparams[k]) + " Value");
                k = k + 1;
            }
            puts(") Value {");
            puts("ctx := callerCtx");
            puts("_ = ctx");
            k = 0;
            while (k < spn) {
                puts("_ = " + mangle(sparams[k]));
                k = k + 1;
            }
            puts("var result Value = vNull()");
            puts("_ = result");
            let sbody = sdef["body"];
            if (sbody != null) {
                if (sbody["type"] == "BlockStatement") {
                    puts("{");
                    puts("_ = ctx");
                    let bodyStmts = sbody["statements"];
                    let bn = len(bodyStmts);
                    let bi = 0;
                    while (bi < bn) {
                        if (bi == bn - 1) {
                            let lastStmt = bodyStmts[bi];
                            if (lastStmt["type"] == "ExpressionStatement") {
                                let expr = lastStmt["expression"];
                                if (expr != null) {
                                    print("result = ");
                                    nodeToGoDirect(expr);
                                    puts("");
                                }
                            } else {
                                nodeToGoDirect(lastStmt);
                            }
                        } else {
                            nodeToGoDirect(bodyStmts[bi]);
                        }
                        bi = bi + 1;
                    }
                    puts("}");
                } else {
                    nodeToGoDirect(sbody);
                }
            }
            puts("return result");
            puts("}");
            // Wrapper: uniform (ctx, args []Value) interface for nkStaticCall.
            // Unpacks the slice into positional args before calling _impl.
            puts("func " + mangle(nm) + "_impl_wrapper(callerCtx *Context, args []Value) Value {");
            k = 0;
            while (k < spn) {
                puts("var _wa" + string(k) + " Value; if " + string(k) + " < len(args) { _wa" + string(k) + " = args[" + string(k) + "] }");
                k = k + 1;
            }
            print("return " + mangle(nm) + "_impl(callerCtx");
            k = 0;
            while (k < spn) {
                print(", _wa" + string(k));
                k = k + 1;
            }
            puts(")");
            puts("}");
        } else {
            // Eval-body impl: uniform (ctx, args []Value) slice convention.
            puts("func " + mangle(nm) + "_impl(callerCtx *Context, args []Value) Value {");
            puts("local := NewContext(rootCtx)");
            let k = 0;
            while (k < spn) {
                puts("if " + string(k) + " < len(args) { local.Create(" + chr(34) + sparams[k] + chr(34) + ", args[" + string(k) + "]) }");
                k = k + 1;
            }
            puts("result, _ := eval(" + mangle(nm) + "_body, local)");
            puts("return result");
            puts("}");
            // Wrapper just forwards the slice (Go inliner likely eliminates the call).
            puts("func " + mangle(nm) + "_impl_wrapper(callerCtx *Context, args []Value) Value {");
            puts("return " + mangle(nm) + "_impl(callerCtx, args)");
            puts("}");
        }
        sdi = sdi + 1;
    }

    puts("func main() {");
    puts("if pf := os.Getenv(" + chr(34) + "IJ_CPUPROFILE" + chr(34) + "); pf != " + chr(34) + chr(34) + " {");
    puts("f, err := os.Create(pf)");
    puts("if err == nil {");
    puts("if err := pprof.StartCPUProfile(f); err == nil {");
    // Defer order matters: defers run LIFO. f.Close() must be queued FIRST
    // so it runs LAST -- i.e. pprof.StopCPUProfile() flushes the buffered
    // profile to f BEFORE f is closed. Previous order (StopCPUProfile then
    // f.Close pushed) ran f.Close FIRST → flush wrote to a closed fd →
    // every IJ_CPUPROFILE invocation produced a 0-byte profile.
    puts("defer f.Close()");
    puts("defer pprof.StopCPUProfile()");
    puts("}");
    puts("}");
    puts("}");
    puts("ctx := NewContext(nil)");
    puts("rootCtx = ctx");
    puts("registerLibraryFunctions(ctx)");

    // Populate the package-scope ij_<libname> Go vars declared at file scope
    // above. Done here -- right after registerLibraryFunctions(ctx) -- so the
    // first direct-emit'd impl call site that runs (somewhere inside the
    // programNode eval below) sees the cached library Values, no ctx.Get
    // chain walk required.
    if (libs != null) {
        let li2 = 0;
        while (li2 < len(libs)) {
            puts(mangle(libs[li2]) + " = ctx.Get(" + chr(34) + libs[li2] + chr(34) + ")");
            li2 = li2 + 1;
        }
    }

    puts("defer func() {");
    puts("if os.Getenv(" + chr(34) + "IJ_COUNTERS" + chr(34) + ") != " + chr(34) + chr(34) + " {");
    puts("fmt.Fprintf(os.Stderr, " + chr(34) + "[IJ counters] NewContext=%d Create=%d Get=%d Update=%d MapGet=%d MapPut=%d FuncExec=%d NewMap=%d NewArr=%d Promote=%d" + chr(92) + "n" + chr(34) + ", ijCountNewContext, ijCountCreate, ijCountGet, ijCountUpdate, ijCountMapGet, ijCountMapPut, ijCountFuncExec, ijCountNewMap, ijCountNewArr, ijCountCtxPromote)");
    puts("}");
    puts("}()");

    // Populate each promoted static def's body ref BEFORE the programNode
    // literal: functionDeclarationToGo emits `body: ij_<name>_body` (a Go var
    // reference) instead of inline body for promoted defs, so the var must be
    // set first. The literals are still emitted into ij_<name>_body so eval()
    // walks them at function-call time -- D2-reborn is a calling-convention
    // optimisation, not a body-codegen optimisation.
    sdi = 0;
    while (sdi < len(staticDefNames)) {
        let nm = staticDefNames[sdi];
        let sdef = staticDefByName[nm];
        print(mangle(nm) + "_body = ");
        let sbody = sdef["body"];
        if (sbody != null) {
            if (sbody["toGo"] != null) {
                sbody["toGo"](sbody);
            }
        }
        puts("");
        sdi = sdi + 1;
    }

    print("programNode := &Node{kind: nkProgram, list: []*Node{");

    let i = 0;
    while (i < n) {
        let stmt = stmts[i];
        if (stmt["toGo"] != null) {
            stmt["toGo"](stmt);
        }
        if (i < n - 1) {
            print(",");
        }
        i = i + 1;
    }

    print("}}");
    puts("");
    // P-VM.3 (2026-06-12): the bytecode VM is the DEFAULT engine. IJ_VM=0
    // opts back into the tree-walking eval (kept as an escape hatch until
    // P-VM.4 retires the dead walker). Same env-gate pattern as
    // IJ_CPUPROFILE / IJ_COUNTERS above; see goVMPrefix for the VM itself.
    puts("if os.Getenv(" + chr(34) + "IJ_VM" + chr(34) + ") == " + chr(34) + "0" + chr(34) + " {");
    puts("eval(programNode, ctx)");
    puts("} else {");
    puts("vmRunProgram(programNode, ctx)");
    puts("}");
    puts("}");
}




// Interpreter.s - InterpreterJ port of the Interpreter Java class

// Helper function to convert an InterpreterJ map/array/primitive to a JSON string
def mapToJsonString(obj) { // FIXME
    return ijToJson(obj);
}

// ============================================================================
// P-VM.4: IJ-side bytecode VM -- the interpreted-layer mirror of the Go-side
// VM in goVMPrefix. Replaces the node["evaluate"] MapValue tree-walk (the
// selfhost-dominant cost) with compile-to-flat-arrays + a dispatch loop.
//
// Semantics target: the IJ tree-walk evaluator in THIS file (NOT the Go-side
// runtime -- they differ!). Mirrored exactly:
//   - && and || evaluate BOTH operands (no short-circuit at the IJ level).
//   - missing call args bind the params to null; extra args are dropped.
//   - every block is a fresh scope (modeled as compile-time shadow slots).
//   - statement value = last statement's value (implicit function return).
//   - errors reuse the same helpers (throwRuntimeError / raiseRuntimeError /
//     ctxGet) so abort/continue behavior matches under both the native
//     assert (panics) and the MCP overlay assert (collects + continues).
// Known accepted divergences (pathological abort paths only, documented in
// IMPLEMENTATION_PLAN.md): map-literal bad-key error positions, and value
// side-effect order after a bad-key abort.
//
// Function bodies compile to chunks attached on the FuncDecl node as
// node["ijvmChunk"]; evaluateFunctionDeclaration's closure checks it first,
// so function VALUES stay ordinary closures and mix safely with tree-walked
// code (escaped statements, bailed parents). The ONLY chunk bail is a nested
// FunctionDeclaration statement (its closure must capture a live block ctx,
// which slot frames cannot model). Upvalue reads/writes work through the
// ctxGet/ctxAssign chain on the captured defCtx.
//
// Opcodes (numeric literals -- vmExec dispatch must not pay global reads):
//    1 loadSlot    a=slot          push frame slot
//    2 const       a=constIdx      push constant (consts are append-only,
//                                  NEVER interned: int 5 vs double 5.0 would
//                                  collide on a string key and corrupt math)
//    3 infix       a=constIdx      pop r, pop l, push applyInfixOperator
//    4 jumpIfFalse a=target        pop cond, jump when falsy
//    5 call        a=argc          stack [fn,a1..aN] -> fn([args]); push res
//    6 loadName    a=symIdx        push ctxGet(frameCtx, name, pos)
//    7 storeSlot   a=slot          slot = top (top KEPT: statement value)
//    8 jump        a=target
//    9 pop                         drop top (between block statements)
//   10 index       a=nodeIdx       pop idx, pop coll, push indexed read
//   11 checkCallee a=target b=nodeIdx  if top==null: throw "Cannot call
//                                  null", replace with null result, jump past
//                                  the call (args must NOT be evaluated)
//   12 storeName   a=symIdx        top = ctxAssign(frameCtx, name, top, pos)
//   13 return                      pop and return from chunk
//   14 prefix      a=constIdx      top = applyPrefixOperator(op, top)
//   15 array       a=count         build array literal from stack
//   16 map         a=pairCount b=nodeIdx  build map literal (key checks)
//   17 indexStore  a=nodeIdx       pop v, idx, coll; push assign result
//   18 defineName  a=symIdx        top = ctxDefine(frameCtx, name, top)
//                                  (top-level `let` only)
// ============================================================================

let ijvmStack = [];
let ijvmSP = 0;
let ijvmStatChunks = 0;
let ijvmStatBails = 0;

def ijvmEnsureStack(need) {
    let stack = ijvmStack;
    let n = len(stack);
    while (n < need) {
        push(stack, null);
        n = n + 1;
    }
    return null;
}

def ijvmNewChunk(name) {
    let ch = {};
    ch["name"] = name;
    ch["ops"] = [];
    ch["a"] = [];
    ch["b"] = [];
    ch["consts"] = [];
    ch["names"] = [];
    ch["poss"] = [];
    ch["nodes"] = [];
    ch["numParams"] = 0;
    ch["numSlots"] = 0;
    ch["maxDepth"] = 8;
    return ch;
}

def ijvmEmit(chunk, op, a, b) {
    push(chunk["ops"], op);
    push(chunk["a"], a);
    push(chunk["b"], b);
    return len(chunk["ops"]) - 1;
}

def ijvmHere(chunk) {
    return len(chunk["ops"]);
}

def ijvmPatchA(chunk, at, target) {
    let arr = chunk["a"];
    arr[at] = target;
    return null;
}

def ijvmConst(chunk, v) {
    push(chunk["consts"], v);
    return len(chunk["consts"]) - 1;
}

def ijvmSym(chunk, name, pos) {
    push(chunk["names"], name);
    push(chunk["poss"], pos);
    return len(chunk["names"]) - 1;
}

def ijvmNodeRef(chunk, nd) {
    push(chunk["nodes"], nd);
    return len(chunk["nodes"]) - 1;
}

// Mirror of makeIndexExpression's evaluate (read path). The _isArray quirk
// is reproduced without the per-read keys() alloc: the keys() scan only
// runs when the map actually has a non-null "_isArray" entry (never true in
// practice). Scalars route to the map-read so the meta-level poison flow
// matches the tree-walker's keys(scalar) behavior.
def ijvmIndexLoad(coll, idx, node) {
    if (isArray(coll)) {
        let arrayLength = len(coll);
        if (idx < 0 || idx >= arrayLength) {
            throwRuntimeError(
                "Array index out of bounds: " + idx + ", array size: " + arrayLength,
                node["position"]["line"],
                node["position"]["column"]
            );
        }
        return coll[idx];
    }
    let mapType = false;
    if (coll != null) {
        if (isMap(coll)) {
            mapType = true;
            if (coll["_isArray"] != null) {
                let keyList = keys(coll);
                if (len(keyList) == 1) {
                    if (keyList[0] == "_isArray") {
                        mapType = false;
                    }
                }
            }
        } else {
            mapType = true;
        }
    }
    if (mapType) {
        let isStr = isString(idx);
        let isNum = isNumber(idx);
        if (!(isStr || isNum)) {
            throwRuntimeError("Map key must be a string or number, got: " + idx, 0 - 1, 0 - 1);
        }
        return coll[idx];
    }
    throwRuntimeError(
        "Cannot use index operator on non-collection value, got: " + coll,
        node["position"]["line"],
        node["position"]["column"]
    );
    return null;
}

// Mirror of indexAssignmentStatement_evaluate (write path); reuses the very
// same assignToArray/assignToMap helpers so error text/behavior is identical.
def ijvmIndexPut(coll, idx, v, node) {
    if (isArray(coll)) {
        return assignToArray(coll, idx, v, node["position"]);
    } else {
        if (isMap(coll)) {
            return assignToMap(coll, idx, v, node["position"]);
        } else {
            throwRuntimeError("Cannot use index operator on non-collection value, got:" + coll, node["position"]);
            return null;
        }
    }
}

// Mirror of makeMapLiteral's broken bad-key path: it calls
// throw(RuntimeError(...)) where neither name exists, so the tree-walker
// aborts via ctxGet "Undefined variable 'throw'" then "Cannot call null".
// Positions cite the map literal node here (tree-walk cites interpreter-
// internal source) -- accepted divergence on this pathological abort path.
def ijvmBadMapKey(node, ctx) {
    ctxGet(ctx, "throw", node["position"]);
    throwRuntimeError(RuntimeError_create("Cannot call null as a function", node["position"]));
    return null;
}

// The dispatch loop. frameCtx = captured defCtx for function chunks, the
// program context for top-level statement chunks. Slot window lives on the
// shared ijvmStack at [base, base+numSlots); the expression stack works the
// region above it. Reentrancy: our caller parked ijvmSP at the top of this
// frame's reserved window, so closures invoked by op 5 base their frames
// above ours and cannot clobber it.
// P-VM.5c: this IJ loop is now the FALLBACK (IJ_VM_NATEXEC=0); the default
// path is the native Go loop -- see the ijvmExec wrapper below. Keep the two
// loops semantically identical: vm_difftest exercises the fallback.
def ijvmExecFallback(chunk, base, frameCtx) {
    let ops = chunk["ops"];
    let aArr = chunk["a"];
    let bArr = chunk["b"];
    let consts = chunk["consts"];
    let names = chunk["names"];
    let poss = chunk["poss"];
    let nodes = chunk["nodes"];
    let stack = ijvmStack;
    let sp = base + chunk["numSlots"];
    let pc = 0;
    let n = len(ops);
    while (pc < n) {
        let op = ops[pc];
        if (op < 7) {
            if (op == 1) { // loadSlot
                stack[sp] = stack[base + aArr[pc]];
                sp = sp + 1;
                pc = pc + 1;
            } else { if (op == 2) { // const
                stack[sp] = consts[aArr[pc]];
                sp = sp + 1;
                pc = pc + 1;
            } else { if (op == 3) { // infix
                let r = stack[sp - 1];
                sp = sp - 1;
                stack[sp - 1] = applyInfixOperator(stack[sp - 1], consts[aArr[pc]], r);
                pc = pc + 1;
            } else { if (op == 4) { // jumpIfFalse (pop)
                let c = stack[sp - 1];
                sp = sp - 1;
                let t = false;
                if (c == true) {
                    t = true;
                } else {
                    if (c != false) {
                        t = EvaluatorIsTruthy(c);
                    }
                }
                if (t) {
                    pc = pc + 1;
                } else {
                    pc = aArr[pc];
                }
            } else { if (op == 5) { // call
                let argc = aArr[pc];
                let args = [];
                let j = sp - argc;
                while (j < sp) {
                    push(args, stack[j]);
                    j = j + 1;
                }
                sp = sp - argc;
                let fv = stack[sp - 1];
                stack[sp - 1] = fv(args);
                pc = pc + 1;
            } else { // op == 6: loadName
                stack[sp] = ctxGet(frameCtx, names[aArr[pc]], poss[aArr[pc]]);
                sp = sp + 1;
                pc = pc + 1;
            } } } } }
        } else { if (op < 13) {
            if (op == 7) { // storeSlot (keep top)
                stack[base + aArr[pc]] = stack[sp - 1];
                pc = pc + 1;
            } else { if (op == 8) { // jump
                pc = aArr[pc];
            } else { if (op == 9) { // pop
                sp = sp - 1;
                pc = pc + 1;
            } else { if (op == 10) { // index read
                let idxv = stack[sp - 1];
                sp = sp - 1;
                stack[sp - 1] = ijvmIndexLoad(stack[sp - 1], idxv, nodes[aArr[pc]]);
                pc = pc + 1;
            } else { if (op == 11) { // checkCallee
                if (stack[sp - 1] == null) {
                    let nd = nodes[bArr[pc]];
                    throwRuntimeError(RuntimeError_create("Cannot call null as a function", nd["position"]));
                    stack[sp - 1] = null;
                    pc = aArr[pc];
                } else {
                    pc = pc + 1;
                }
            } else { // op == 12: storeName (keep result)
                stack[sp - 1] = ctxAssign(frameCtx, names[aArr[pc]], stack[sp - 1], poss[aArr[pc]]);
                pc = pc + 1;
            } } } } }
        } else {
            if (op == 13) { // return
                return stack[sp - 1];
            } else { if (op == 14) { // prefix
                stack[sp - 1] = applyPrefixOperator(consts[aArr[pc]], stack[sp - 1]);
                pc = pc + 1;
            } else { if (op == 15) { // array literal
                let cnt = aArr[pc];
                let arr2 = [];
                let j2 = sp - cnt;
                while (j2 < sp) {
                    push(arr2, stack[j2]);
                    j2 = j2 + 1;
                }
                sp = sp - cnt;
                stack[sp] = arr2;
                sp = sp + 1;
                pc = pc + 1;
            } else { if (op == 16) { // map literal
                let take = aArr[pc] * 2;
                let m2 = {};
                let j3 = sp - take;
                while (j3 < sp) {
                    let k2 = stack[j3];
                    let keyOk = false;
                    if (isString(k2)) { keyOk = true; }
                    if (isNumber(k2)) { keyOk = true; }
                    if (!keyOk) {
                        ijvmBadMapKey(nodes[bArr[pc]], frameCtx);
                    }
                    m2[k2] = stack[j3 + 1];
                    j3 = j3 + 2;
                }
                sp = sp - take;
                stack[sp] = m2;
                sp = sp + 1;
                pc = pc + 1;
            } else { if (op == 17) { // indexStore
                let v3 = stack[sp - 1];
                let i3 = stack[sp - 2];
                sp = sp - 2;
                stack[sp - 1] = ijvmIndexPut(stack[sp - 1], i3, v3, nodes[aArr[pc]]);
                pc = pc + 1;
            } else { // op == 18: defineName (keep result)
                stack[sp - 1] = ctxDefine(frameCtx, names[aArr[pc]], stack[sp - 1]);
                pc = pc + 1;
            } } } } }
        }
        }
    }
    return null; // unreachable: every chunk ends with op 13
}

// P-VM.5c/5d: default dispatch is the native Go loop, entered through the
// CALL protocol (ijb_ijvmCallNative via the lib fast path): the native
// side binds params, reserves the frame window, and owns the per-layer
// stack pointer (natSP keyed by stack identity), so the op-5 same-layer
// fast path inside natExec and these entry points can never desync. The
// hooks are passed as VALUES so the native loop calls back into THIS
// layer's semantics -- each layer's overrides keep working while chunk-op
// dispatch runs at native speed at every depth.
// At the binary, "ijvmCallNative" direct-emits the Go builtin and depth 0
// means "hooks are compiled defs, positional". At an interpreted layer the
// same name resolves to the chained ijvmCallChain registration (see
// DefaultLibraryFunctionsInitializer), which adds 1 to depth per layer hop
// so the native loop knows how many closure-tower levels its hook /
// callee values carry (see natExec in goLibPrefix).
// The hooks are hoisted into top-level lets because a bare def-as-value
// reference direct-emits as ctx.Get(name) -- 11 root-map lookups per call
// on the hottest path. Top-level lets emit as Go package vars.
let ijvmUseNativeExec = getenv("IJ_VM_NATEXEC") != "0";
let ijvmHookInfix = applyInfixOperator;
let ijvmHookPrefix = applyPrefixOperator;
let ijvmHookCtxGet = ctxGet;
let ijvmHookCtxAssign = ctxAssign;
let ijvmHookCtxDefine = ctxDefine;
let ijvmHookTruthy = EvaluatorIsTruthy;
let ijvmHookIndexLoad = ijvmIndexLoad;
let ijvmHookIndexPut = ijvmIndexPut;
let ijvmHookErrNew = RuntimeError_create;
let ijvmHookThrow = throwRuntimeError;
let ijvmHookBadKey = ijvmBadMapKey;

// One chain hop per interpretation layer: registered as the NEXT layer's
// "ijvmCallNative" binding, it forwards to THIS layer's binding with
// depth+1, so by the time the call bottoms out at the Go builtin, depth
// equals the calling layer's interpretation depth.
def ijvmCallChain(chunk, stack, defCtx, args, hInfix, hPrefix, hCtxGet,
        hCtxAssign, hCtxDefine, hTruthy, hIdxLoad, hIdxPut, hErrNew, hThrow,
        hBadKey, depth) {
    return ijvmCallNative(chunk, stack, defCtx, args,
        hInfix, hPrefix, hCtxGet, hCtxAssign, hCtxDefine, hTruthy,
        hIdxLoad, hIdxPut, hErrNew, hThrow, hBadKey, depth + 1);
}

// Invoke a function chunk: bind params (null-pad missing, drop extras --
// the IJ tree-walk closure's exact arity behavior), reserve the frame
// window, run. Non-param slots need no init: compile order guarantees every
// slot is stored (its `let` runs) before any read at the same pc range.
// Default path: the native call protocol does all of that in Go (and the
// op-5 fast path bypasses even this entry for same-layer calls). The IJ
// body below is the IJ_VM_NATEXEC=0 fallback only.
def ijvmCallChunk(chunk, defCtx, args) {
    if (ijvmUseNativeExec) {
        return ijvmCallNative(chunk, ijvmStack, defCtx, args,
            ijvmHookInfix, ijvmHookPrefix, ijvmHookCtxGet, ijvmHookCtxAssign,
            ijvmHookCtxDefine, ijvmHookTruthy, ijvmHookIndexLoad, ijvmHookIndexPut,
            ijvmHookErrNew, ijvmHookThrow, ijvmHookBadKey, 0);
    }
    let base = ijvmSP;
    let numSlots = chunk["numSlots"];
    let top = base + numSlots + chunk["maxDepth"];
    ijvmEnsureStack(top);
    let stack = ijvmStack;
    let np = chunk["numParams"];
    let na = len(args);
    let i = 0;
    while (i < np) {
        if (i < na) {
            stack[base + i] = args[i];
        } else {
            stack[base + i] = null;
        }
        i = i + 1;
    }
    ijvmSP = top;
    let r = ijvmExecFallback(chunk, base, defCtx);
    ijvmSP = base;
    return r;
}

// Run a compiled top-level statement chunk against the program context.
// Top chunks have numParams 0, so the native call protocol with null args
// is exactly "reserve window + exec".
def ijvmRunTopChunk(chunk, ctx) {
    if (ijvmUseNativeExec) {
        return ijvmCallNative(chunk, ijvmStack, ctx, null,
            ijvmHookInfix, ijvmHookPrefix, ijvmHookCtxGet, ijvmHookCtxAssign,
            ijvmHookCtxDefine, ijvmHookTruthy, ijvmHookIndexLoad, ijvmHookIndexPut,
            ijvmHookErrNew, ijvmHookThrow, ijvmHookBadKey, 0);
    }
    let base = ijvmSP;
    let top = base + chunk["numSlots"] + chunk["maxDepth"];
    ijvmEnsureStack(top);
    ijvmSP = top;
    let r = ijvmExecFallback(chunk, base, ctx);
    ijvmSP = base;
    return r;
}

// ---------------------------------------------------------------------------
// Compiler: AST (MapValue nodes) -> chunk. st fields:
//   "symtab"   name -> slot for the CURRENT compile position (block-scoped
//              shadows handled by ijvmCompileBlock's local record list)
//   "numSlots" frame slot high-water
//   "topLevel" true for per-statement program chunks: depth-0 `let` becomes
//              defineName (must bind in the real program ctx); block-nested
//              `let`s still use slots (they are transient, exactly like the
//              tree-walker's per-block contexts)
//   "blockDepth" 0 at statement root
//   "ok"       bail flag -- false aborts the whole chunk (caller discards)
// ---------------------------------------------------------------------------

def ijvmCompileExpr(chunk, node, st) {
    if (st["ok"] != true) { return null; }
    if (node == null) {
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        return null;
    }
    let t = node["type"];
    if (t == "NumberLiteral") {
        ijvmEmit(chunk, 2, ijvmConst(chunk, node["value"]), 0);
        return null;
    }
    if (t == "StringLiteral") {
        ijvmEmit(chunk, 2, ijvmConst(chunk, node["value"]), 0);
        return null;
    }
    if (t == "BooleanLiteral") {
        ijvmEmit(chunk, 2, ijvmConst(chunk, node["value"]), 0);
        return null;
    }
    if (t == "NullLiteral") {
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        return null;
    }
    if (t == "Identifier") {
        let symtab = st["symtab"];
        let slot = symtab[node["name"]];
        if (slot != null) {
            ijvmEmit(chunk, 1, slot, 0);
        } else {
            ijvmEmit(chunk, 6, ijvmSym(chunk, node["name"], node["position"]), 0);
        }
        return null;
    }
    if (t == "InfixExpression") {
        ijvmCompileExpr(chunk, node["left"], st);
        ijvmCompileExpr(chunk, node["right"], st);
        ijvmEmit(chunk, 3, ijvmConst(chunk, node["operator"]), 0);
        return null;
    }
    if (t == "PrefixExpression") {
        ijvmCompileExpr(chunk, node["right"], st);
        ijvmEmit(chunk, 14, ijvmConst(chunk, node["operator"]), 0);
        return null;
    }
    if (t == "CallExpression") {
        ijvmCompileExpr(chunk, node["callee"], st);
        let ckAt = ijvmEmit(chunk, 11, 0, ijvmNodeRef(chunk, node));
        let argNodes = node["arguments"];
        let argc = 0;
        if (argNodes != null) {
            argc = len(argNodes);
            let ai = 0;
            while (ai < argc) {
                ijvmCompileExpr(chunk, argNodes[ai], st);
                ai = ai + 1;
            }
        }
        ijvmEmit(chunk, 5, argc, 0);
        ijvmPatchA(chunk, ckAt, ijvmHere(chunk));
        return null;
    }
    if (t == "IndexExpression") {
        ijvmCompileExpr(chunk, node["collection"], st);
        ijvmCompileExpr(chunk, node["index"], st);
        ijvmEmit(chunk, 10, ijvmNodeRef(chunk, node), 0);
        return null;
    }
    if (t == "ArrayLiteral") {
        let elems = node["elements"];
        let cnt = 0;
        if (elems != null) {
            cnt = len(elems);
            let ei = 0;
            while (ei < cnt) {
                ijvmCompileExpr(chunk, elems[ei], st);
                ei = ei + 1;
            }
        }
        ijvmEmit(chunk, 15, cnt, 0);
        return null;
    }
    if (t == "MapLiteral") {
        let pairs = node["pairs"];
        let pcnt = 0;
        if (pairs != null) {
            pcnt = len(pairs);
            let pi = 0;
            while (pi < pcnt) {
                let pair = pairs[pi];
                ijvmCompileExpr(chunk, pair["key"], st);
                ijvmCompileExpr(chunk, pair["value"], st);
                pi = pi + 1;
            }
        }
        ijvmEmit(chunk, 16, pcnt, ijvmNodeRef(chunk, node));
        return null;
    }
    st["ok"] = false;
    return null;
}

def ijvmCompileStmt(chunk, node, st, declared, shadows) {
    if (st["ok"] != true) { return null; }
    if (node == null) {
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        return null;
    }
    let t = node["type"];
    if (t == "VariableDeclaration") {
        // Initializer FIRST (let x = x + 1 reads the OUTER x), then declare.
        if (node["initializer"] != null) {
            ijvmCompileExpr(chunk, node["initializer"], st);
        } else {
            ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        }
        let atRoot = false;
        if (st["topLevel"] == true) {
            if (st["blockDepth"] == 0) { atRoot = true; }
        }
        if (atRoot) {
            ijvmEmit(chunk, 18, ijvmSym(chunk, node["name"], node["position"]), 0);
        } else {
            let name = node["name"];
            let slot = declared[name];
            if (slot == null) {
                slot = st["numSlots"];
                st["numSlots"] = slot + 1;
                declared[name] = slot;
                let symtab = st["symtab"];
                let rec = {};
                rec["name"] = name;
                let old = symtab[name];
                if (old == null) {
                    rec["had"] = false;
                    rec["old"] = 0;
                } else {
                    rec["had"] = true;
                    rec["old"] = old;
                }
                push(shadows, rec);
                symtab[name] = slot;
            }
            ijvmEmit(chunk, 7, slot, 0);
        }
        return null;
    }
    if (t == "AssignmentStatement") {
        ijvmCompileExpr(chunk, node["value"], st);
        let symtab = st["symtab"];
        let slot = symtab[node["name"]];
        if (slot != null) {
            ijvmEmit(chunk, 7, slot, 0);
        } else {
            ijvmEmit(chunk, 12, ijvmSym(chunk, node["name"], node["position"]), 0);
        }
        return null;
    }
    if (t == "ExpressionStatement") {
        if (node["expression"] != null) {
            ijvmCompileExpr(chunk, node["expression"], st);
        } else {
            ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        }
        return null;
    }
    if (t == "IndexAssignmentStatement") {
        ijvmCompileExpr(chunk, node["collection"], st);
        ijvmCompileExpr(chunk, node["index"], st);
        ijvmCompileExpr(chunk, node["value"], st);
        ijvmEmit(chunk, 17, ijvmNodeRef(chunk, node), 0);
        return null;
    }
    if (t == "IfStatement") {
        ijvmCompileExpr(chunk, node["condition"], st);
        let jf = ijvmEmit(chunk, 4, 0, 0);
        ijvmCompileBlock(chunk, node["consequence"], st);
        let jend = ijvmEmit(chunk, 8, 0, 0);
        ijvmPatchA(chunk, jf, ijvmHere(chunk));
        if (node["alternative"] != null) {
            ijvmCompileBlock(chunk, node["alternative"], st);
        } else {
            ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        }
        ijvmPatchA(chunk, jend, ijvmHere(chunk));
        return null;
    }
    if (t == "WhileStatement") {
        // Statement value = last completed body value (null if 0 iterations).
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        let ltop = ijvmHere(chunk);
        ijvmCompileExpr(chunk, node["condition"], st);
        let jf = ijvmEmit(chunk, 4, 0, 0);
        ijvmEmit(chunk, 9, 0, 0);
        ijvmCompileBlock(chunk, node["body"], st);
        ijvmEmit(chunk, 8, ltop, 0);
        ijvmPatchA(chunk, jf, ijvmHere(chunk));
        return null;
    }
    if (t == "BlockStatement") {
        ijvmCompileBlock(chunk, node, st);
        return null;
    }
    if (t == "ReturnStatement") {
        if (st["topLevel"] == true) {
            // A top-level return must stop the whole program loop; the
            // escape path's ReturnValue wrapper handles that. Bail.
            st["ok"] = false;
            return null;
        }
        if (node["value"] != null) {
            ijvmCompileExpr(chunk, node["value"], st);
        } else {
            ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        }
        ijvmEmit(chunk, 13, 0, 0);
        return null;
    }
    // FunctionDeclaration (closure must capture a live ctx) or unknown.
    st["ok"] = false;
    return null;
}

def ijvmCompileBlock(chunk, blockNode, st) {
    if (st["ok"] != true) { return null; }
    if (blockNode == null) {
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
        return null;
    }
    if (blockNode["type"] != "BlockStatement") {
        // if/while consequence/body is always a block in this parser, but
        // stay defensive: compile as a single statement.
        ijvmCompileStmt(chunk, blockNode, st, {}, []);
        return null;
    }
    st["blockDepth"] = st["blockDepth"] + 1;
    let declared = {};
    let shadows = [];
    let stmts = blockNode["statements"];
    let n = len(stmts);
    if (n == 0) {
        ijvmEmit(chunk, 2, ijvmConst(chunk, null), 0);
    }
    let i = 0;
    while (i < n) {
        if (i > 0) {
            ijvmEmit(chunk, 9, 0, 0);
        }
        ijvmCompileStmt(chunk, stmts[i], st, declared, shadows);
        i = i + 1;
    }
    // Block exit: restore the symtab view (the tree-walker's block ctx dies).
    let symtab = st["symtab"];
    let k = len(shadows) - 1;
    while (k >= 0) {
        let rec = shadows[k];
        if (rec["had"]) {
            symtab[rec["name"]] = rec["old"];
        } else {
            symtab[rec["name"]] = null;
        }
        k = k - 1;
    }
    st["blockDepth"] = st["blockDepth"] - 1;
    return null;
}

// Compile a FunctionDeclaration body into a chunk. Returns null on bail
// (nested def / unknown node) -- the closure then tree-walks the body.
def ijvmCompileFunc(funcNode) {
    let body = funcNode["body"];
    if (body == null) { return null; }
    let chunk = ijvmNewChunk(funcNode["name"]);
    let st = {};
    st["symtab"] = {};
    st["numSlots"] = 0;
    st["topLevel"] = false;
    st["blockDepth"] = 0;
    st["ok"] = true;
    let params = funcNode["parameters"];
    let np = 0;
    if (params != null) {
        np = len(params);
        let symtab = st["symtab"];
        let i = 0;
        while (i < np) {
            symtab[params[i]] = i;
            i = i + 1;
        }
    }
    chunk["numParams"] = np;
    st["numSlots"] = np;
    ijvmCompileBlock(chunk, body, st);
    ijvmEmit(chunk, 13, 0, 0);
    if (st["ok"] != true) { return null; }
    chunk["numSlots"] = st["numSlots"];
    chunk["maxDepth"] = len(chunk["ops"]) + 8;
    return chunk;
}

// Compile one top-level program statement. Returns null -> escape to the
// tree-walk (FuncDecl declarations, statements containing returns/defs).
def ijvmCompileTopStmt(stmt) {
    let chunk = ijvmNewChunk("top");
    let st = {};
    st["symtab"] = {};
    st["numSlots"] = 0;
    st["topLevel"] = true;
    st["blockDepth"] = 0;
    st["ok"] = true;
    ijvmCompileStmt(chunk, stmt, st, {}, []);
    ijvmEmit(chunk, 13, 0, 0);
    if (st["ok"] != true) { return null; }
    chunk["numSlots"] = st["numSlots"];
    chunk["maxDepth"] = len(chunk["ops"]) + 8;
    return chunk;
}

// Deep-walk the whole AST and attach a chunk to EVERY compilable FuncDecl
// node (any nesting depth). Closures created later -- even by tree-walked
// escapes or bailed parent functions -- pick the chunk up through
// evaluateFunctionDeclaration, with their captured ctx as the chain root.
def ijvmAttachChunks(node) {
    if (node == null) { return null; }
    if (!isMap(node)) { return null; }
    let t = node["type"];
    if (t == null) { return null; }
    if (t == "FunctionDeclaration") {
        let ch = ijvmCompileFunc(node);
        if (ch != null) {
            node["ijvmChunk"] = ch;
            ijvmStatChunks = ijvmStatChunks + 1;
        } else {
            ijvmStatBails = ijvmStatBails + 1;
        }
    }
    let scalarKeys = ["condition","consequence","alternative","body","left","right","collection","index","value","callee","expression","initializer"];
    let si = 0;
    while (si < len(scalarKeys)) {
        let child = node[scalarKeys[si]];
        if (child != null) {
            if (isMap(child)) {
                ijvmAttachChunks(child);
            }
        }
        si = si + 1;
    }
    let arrKeys = ["statements","elements","arguments"];
    let aj = 0;
    while (aj < len(arrKeys)) {
        let arr = node[arrKeys[aj]];
        if (arr != null) {
            if (isArray(arr)) {
                let m = 0;
                while (m < len(arr)) {
                    ijvmAttachChunks(arr[m]);
                    m = m + 1;
                }
            }
        }
        aj = aj + 1;
    }
    let pairs = node["pairs"];
    if (pairs != null) {
        if (isArray(pairs)) {
            let p = 0;
            while (p < len(pairs)) {
                let pair = pairs[p];
                if (pair != null) {
                    if (isMap(pair)) {
                        ijvmAttachChunks(pair["key"]);
                        ijvmAttachChunks(pair["value"]);
                    }
                }
                p = p + 1;
            }
        }
    }
    return null;
}

// VM entry: mirror of makeProgram's evaluate. Per-statement chunks with
// tree-walk escapes interleaved; FuncDecl statements always escape (their
// evaluateFunctionDeclaration must bind the closure in the REAL program
// ctx), but their bodies got chunks via ijvmAttachChunks above.
def ijvmRunProgram(ast, ctx) {
    ijvmStatChunks = 0;
    ijvmStatBails = 0;
    ijvmAttachChunks(ast);
    let stmts = ast["statements"];
    let n = len(stmts);
    let plans = [];
    let nEsc = 0;
    let i = 0;
    while (i < n) {
        let stmt = stmts[i];
        let ch = null;
        if (stmt != null) {
            if (stmt["type"] != "FunctionDeclaration") {
                ch = ijvmCompileTopStmt(stmt);
            }
        }
        if (ch == null) { nEsc = nEsc + 1; }
        push(plans, ch);
        i = i + 1;
    }
    if (getenv("IJ_VM_DEBUG") == "1") {
        eputs("[ijvm] stmts: " + n + " escaped: " + nEsc + " funcChunks: " + ijvmStatChunks + " funcBails: " + ijvmStatBails);
    }
    let result = null;
    i = 0;
    while (i < n) {
        let ch = plans[i];
        if (ch != null) {
            result = ijvmRunTopChunk(ch, ctx);
        } else {
            let stmt = stmts[i];
            result = stmt["evaluate"](stmt, ctx);
            if (isReturnValue(result)) {
                return result["value"];
            }
        }
        i = i + 1;
    }
    return result;
}


// Interpreter map holding state and library initializers
def makeInterpreter() {
    let interpreter = {};
    interpreter["ast"] = null;
    interpreter["libraryFunctionInitializers"] = [];

    // Constructor with all default library function initializers
    def initWithDefaultLibraries(self) {
        self["libraryFunctionInitializers"] = [
            DefaultLibraryFunctionsInitializer,
            StdIOLibraryFunctionsInitializer,
            MapLibraryFunctionsInitializer,
            ArrayLibraryFunctionsInitializer,
            StringLibraryFunctionsInitializer,
            RegexLibraryFunctionsInitializer,
            TypeLibraryFunctionsInitializer
        ];
    }

    // Init with library initializers
    def initWithLibraries(self, initializers) {
        if (initializers != null) {
            self["libraryFunctionInitializers"] = initializers;
        } else {
            self["libraryFunctionInitializers"] = [];
        }
    }

    // Register built-in library functions into the context
    def registerBuiltInFunctions(self, context) {
        let i = 0;
        while (i < len(self["libraryFunctionInitializers"])) {
            let initFn = self["libraryFunctionInitializers"][i];
            // Call the initializer function with context argument
            initFn(context);
            i = i + 1;
        }
    }
    interpreter["registerBuiltInFunctions"] = registerBuiltInFunctions;

    // Parse source code string and produce ParseResult map
    def parse(self, sourceCode) {
        // Error list for catching errors
        let errors = [];

        let resultAst = null;
        let hasError = false;

        let lexer = null;
        let parser = null;

        {
            // Simulated try block
            lexer = createLexer(sourceCode);
            parser = initParser(lexer);

            resultAst = parseProgram();

            // Collect errors from parser
            let parseErrors = getErrors();
            let i = 0;
            while (i < len(parseErrors)) {
                let err = parseErrors[i];
                // Create Error map: { message, line, column }
                let errMap = {};
                errMap["message"] = err["message"];
                errMap["line"] = err["line"];
                errMap["column"] = err["column"];
                push(errors, errMap);
                i = i + 1;
            }
        }

        // If parseAst is null or errors present, mark fail
        if (resultAst == null || len(errors) > 0) {
            hasError = true;
        }

        // Update interpreter AST state
        self["ast"] = resultAst;

        // Prepare ParseResult map
        let parseResult = {};
        parseResult["success"] = !hasError;
        parseResult["ast"] = resultAst;
        parseResult["errors"] = errors;
        return parseResult;
    }
    interpreter["parse"] = parse;

    // Evaluate stored AST and produce EvaluationResult map
    def evaluate(self) {
        let errors = [];

        // Check if ast is null
        if (self["ast"] == null) {
            // Create error: No AST to evaluate
            let err = {};
            err["message"] = "No AST to evaluate. Parse code first.";
            err["line"] = 0;
            err["column"] = 0;
            push(errors, err);
            let evalResultMap = {};
            evalResultMap["success"] = false;
            evalResultMap["result"] = null;
            evalResultMap["errors"] = errors;
            return evalResultMap;
        }

        // Step 1: Prepare context
        let context = makeEvaluationContext();

        // Step 2: Register built-in functions
        self["registerBuiltInFunctions"](self, context);

        // Step 3: Evaluate ast
        let success = true;
        let result = null;

        // Manual simulated try-catch not supported, assume evaluation either succeeds or aborts program
        // P-VM.4: the IJ-side bytecode VM is the default engine for the
        // interpreted layers. IJ_VM=0 disables every VM (Go-side gate in the
        // emitted main() plus this one, at all nesting depths -- getenv
        // chains down to the native os.Getenv). IJ_VM_IJ=0 disables only the
        // IJ-side VM, for differential isolation.
        {
            let ijvmOff = false;
            if (getenv("IJ_VM") == "0") { ijvmOff = true; }
            if (getenv("IJ_VM_IJ") == "0") { ijvmOff = true; }
            if (ijvmOff) {
                result = self["ast"]["evaluate"](self["ast"], context);
            } else {
                result = ijvmRunProgram(self["ast"], context);
            }
        }

        // Prepare evaluation result map
        let evalResultMap = {};
        evalResultMap["success"] = true;
        evalResultMap["result"] = result;
        evalResultMap["errors"] = [];

        return evalResultMap;
    }
    interpreter["evaluate"] = evaluate;

    // Return AST JSON string or null if no AST parsed
    def getAstJson(self) {
        if (self["ast"] == null) {
            return null;
        }
        // self["ast"]["toJson"](self["ast"]) now returns a map
        let astMap = self["ast"]["toJson"](self["ast"]);
        return mapToJsonString(astMap);
    }
    interpreter["getAstJson"] = getAstJson;

    // Phase 2 codegen path: every *toGo* emitter is a top-level def, so the
    // closures captured into AST nodes during parsing already point at the
    // current global value. The Phase 1 refreshToGoPointers helper is therefore
    // dead — and worse, when a fresh Phase-2 self-build runs interpreter.s on
    // itself the helper aborts the toGo eval somewhere mid-walk, leaving stage2
    // without a `func main()`. P2 deletes the helper to make stage1->stage2
    // bit-identical. Do not reintroduce without a Phase-2 use-case.
    def toGo(self) {
        if (self["ast"] == null) {
            return null;
        }
        resolveScopes(self["ast"]);
        return self["ast"]["toGo"](self["ast"]);
    }
    interpreter["toGo"] = toGo;

    // Format errors array as multiline string
    def formatErrors(errorsList) {
        if (len(errorsList) == 0) {
            return "No errors";
        }

        let result = "";
        let i = 0;
        while (i < len(errorsList)) {
            let err = errorsList[i];
            // Format: "Error at line:column: message"
            let s = "Error at " + err["line"] + ":" + err["column"] + ": " + err["message"];
            if (i == 0) {
                result = s;
            } else {
                result = result + chr(10) + s;
            }
            i = i + 1;
        }
        return result;
    }



    // Initialize interpreter with default library initializers on creation
    initWithDefaultLibraries(interpreter);

    return interpreter;
}

// DefaultLibraryFunctionsInitializer 

def zeroWrapper(f) {
    def wrapped(args) {
        return f();
    }
    return wrapped;
}

def oneWrapper(f) {
    def wrapped(args) {
        return f(args[0]);
    }
    return wrapped;
}

def twoWrapper(f) {
    def wrapped(args) {
        return f(args[0],args[1]);
    }
    return wrapped;
}

def threeWrapper(f) {
    def wrapped(args) {
        return f(args[0],args[1],args[2]);
    }
    return wrapped;
}

// P-VM.5d: arity adapter for the ijvmTagFn chain registration.
def fourWrapper(f) {
    def wrapped(args) {
        return f(args[0],args[1],args[2],args[3]);
    }
    return wrapped;
}

// P-VM.5c/5d: arity adapter for the ijvmCallChain registration (16 params:
// chunk, stack, defCtx, args, 11 hooks, depth).
def sixteenWrapper(f) {
    def wrapped(args) {
        return f(args[0],args[1],args[2],args[3],args[4],args[5],args[6],
            args[7],args[8],args[9],args[10],args[11],args[12],args[13],
            args[14],args[15]);
    }
    return wrapped;
}

def DefaultLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "random", zeroWrapper(random));
    context["registerFunction"](context, "assert", twoWrapper(assert));
    context["registerFunction"](context, "echo", oneWrapper(echo));
    context["registerFunction"](context, "int", oneWrapper(int));
    context["registerFunction"](context, "double", oneWrapper(double));
    context["registerFunction"](context, "string", oneWrapper(string));
    // P-VM.4: chain getenv/eputs down to the native builtins so every nested
    // interpretation layer can read the IJ_VM gate and emit debug to stderr.
    context["registerFunction"](context, "getenv", oneWrapper(getenv));
    context["registerFunction"](context, "eputs", oneWrapper(eputs));
    // P-VM.5c/5d: chain the native ijvm call protocol down to every nested
    // layer. The guest's "ijvmCallNative" binds THIS layer's ijvmCallChain,
    // which forwards to THIS layer's own "ijvmCallNative" binding with
    // depth+1 -- so the call bottoms out at the Go builtin carrying the
    // exact interpretation depth, which selects the closure-tower call
    // encoding for hooks and callees. The binary's own entry points never
    // consult this: they direct-emit ijb_ijvmCallNative with depth 0.
    // ijvmTagFn passes values through unchanged at every hop (like getenv).
    context["registerFunction"](context, "ijvmCallNative", sixteenWrapper(ijvmCallChain));
    context["registerFunction"](context, "ijvmTagFn", fourWrapper(ijvmTagFn));
}

// StdIOLibraryFunctionsInitializer implementation with puts and gets simulation

def StdIOLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "gets", zeroWrapper(gets));
    context["registerFunction"](context, "puts", oneWrapper(puts));
    context["registerFunction"](context, "print", oneWrapper(print));
}

// MapLibraryFunctionsInitializer stub

def MapLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "keys", oneWrapper(keys));
    context["registerFunction"](context, "values", oneWrapper(values));
    // P-VM.5a: chain hasKey down so every nested layer's mapHasKey bottoms
    // out at the native O(1) findPair instead of an interpreted keys() scan.
    context["registerFunction"](context, "hasKey", twoWrapper(hasKey));
}

// ArrayLibraryFunctionsInitializer stub

def ArrayLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "push", twoWrapper(push));
    context["registerFunction"](context, "pop", oneWrapper(pop));
    context["registerFunction"](context, "len", oneWrapper(len));
    context["registerFunction"](context, "delete", twoWrapper(delete));
}

// StringLibraryFunctionsInitializer stub

def StringLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "char", twoWrapper(char));
    context["registerFunction"](context, "ord", oneWrapper(ord));
    context["registerFunction"](context, "chr", oneWrapper(chr));
    context["registerFunction"](context, "substr", threeWrapper(substr));
    context["registerFunction"](context, "startsWith", twoWrapper(startsWith));
    context["registerFunction"](context, "endsWith", twoWrapper(endsWith));
    context["registerFunction"](context, "trim", oneWrapper(trim));
    context["registerFunction"](context, "join", twoWrapper(join));
}

// RegexLibraryFunctionsInitializer stub

def RegexLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "match", twoWrapper(match));
    context["registerFunction"](context, "findAll", twoWrapper(findAll));
    context["registerFunction"](context, "replace", threeWrapper(replace));
    context["registerFunction"](context, "split", twoWrapper(split));
}

// TypeLibraryFunctionsInitializer stub

def TypeLibraryFunctionsInitializer(context) {
    // Implementation of (), (), (), (), (), (), (), () can be added here if desired

    context["registerFunction"](context, "typeof", oneWrapper(typeof));
    context["registerFunction"](context, "isNumber", oneWrapper(isNumber));
    context["registerFunction"](context, "isString", oneWrapper(isString));
    //context["registerFunction"](context, "isBoolean", oneWrapper(isBoolean)); // FIXME fake news
    context["registerFunction"](context, "isArray", oneWrapper(isArray));
    context["registerFunction"](context, "isMap", oneWrapper(isMap));
    //context["registerFunction"](context, "isFunction", oneWrapper(isFunction)); // FIXME fake news
    //context["registerFunction"](context, "isNull", oneWrapper(isNull)); // FIXME fake news
}

//TEST

// Create an Interpreter instance, parse some code, evaluate, and output results

let interpreter = makeInterpreter();

def newlinehack(line) { // disabled for now, breaks 
    // let lines = split(line,"<NEWLINE/>"); // FIXME SUPERHACK ;-)
    // //puts("Split:" + line + " = " +lines);
    // let i = 0;
    // line = "";
    // while (i < len(lines)) {
    //     if (i > 0) {
    //         line = line + chr(10);
    //     }
    //     line = line + lines[i];
    //     i = i + 1;
    // }
    // return line;
    return line;
}

let printAst = false;
let runIt = true;
let transpileGo = false;
let transpileGoFull = false;
//let source = "let x = 1 + 2; let y = 10; x * y;";
def readSources() {
    let source = null;
    let line = gets();
    if (line != null) {
        source = newlinehack(line);
    }
    else {
        source = "puts('No sources found');";
    }
    if (source == "//multiline") {
        // P-VM.5e: collect lines and join ONCE. The old per-line
        // `source = source + chr(10) + line` rebuilt the whole string per
        // line -- O(n^2) bytes over a ~250KB source (~1GB of transient
        // allocations per layer reading interpreter.s; a top GC driver in
        // the selfhost profile at BOTH the native and interpreted layers).
        let parts = [source];
        let line = gets();
        while (line != null) {
            if (line == "//<EOF>") {
                return join(parts, chr(10));
            }
            if (line == "//<AST>") {
                printAst = true;
                runIt = false;
                return join(parts, chr(10));
            }
            if (line == "//<GO>") {
                transpileGo = true;
                runIt = false;
            }
            if (line == "//<GO2>") {
                transpileGo = true;
                transpileGoFull = true;
                runIt = false;
            }
            push(parts, newlinehack(line));
            line = gets();
        }
        return join(parts, chr(10));
    }
    //puts("Hack:" + source); //DEBUG
    return source;
}

//TO JSON support start (from mcp)
def buildToJson() {
// Helper function to convert a string to JSON string format with proper escaping
def stringToJsonString(s) {
    let result = chr(34); // Start with quote
    let i = 0;
    while (i < len(s)) {
        let ch = char(s, i);
        if (ch == chr(10)) {
            // Newline -> \n
            result = result + chr(92) + "n";
        } else {
            if (ch == chr(9)) {
                // Tab -> \t
                result = result + chr(92) + "t";
            } else {
                if (ch == chr(13)) {
                    // Carriage return -> \r
                    result = result + chr(92) + "r";
                } else {
                    if (ch == chr(92)) {
                        // Backslash -> \\
                        result = result + chr(92) + chr(92);
                    } else {
                        if (ch == chr(34)) {
                            // Quote -> \"
                            result = result + chr(92) + chr(34);
                        } else {
                            // Regular character
                            result = result + ch;
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    result = result + chr(34); // End with quote
    return result;
}

// Helper function to convert array to JSON string
def arrayToJsonString(arr) {
    let result = chr(91); // [
    let i = 0;
    while (i < len(arr)) {
        if (i > 0) {
            result = result + chr(44); // ,
        }
        result = result + jsonToString(arr[i]);
        i = i + 1;
    }
    result = result + chr(93); // ]
    return result;
}

// Helper function to convert map to JSON string
def mapToJsonString(map) {
    let result = chr(123); // {
    let mapKeys = keys(map);
    let i = 0;
    while (i < len(mapKeys)) {
        if (i > 0) {
            result = result + chr(44); // ,
        }
        let key = mapKeys[i];
        // Convert key to string and add colon
        result = result + stringToJsonString("" + key) + chr(58) + jsonToString(map[key]);
        i = i + 1;
    }
    result = result + chr(125); // }
    return result;
}

// Main function to convert any IJ value to JSON string
def jsonToString(value) {
    if (isString(value)) {
        return stringToJsonString(value);
    } else {
        if (isNumber(value)) {
            return "" + value;
        } else {
                if (value == null) {
                    return "null";
                } else {
                    if (isArray(value)) {
                        return arrayToJsonString(value);
                    } else {
                        if (isMap(value)) {
                            return mapToJsonString(value);
                        } else {
                           //if (isBoolean(value)) { // FIXME not supported
                           //     if (value) {
                           //         return "true";
                           //     } else {
                           //         return "false";
                           //     }
                           // }
                           return "" + value;
                        }
                    }
                }
            
        }
    }
}
return jsonToString;
}
let ijToJson = buildToJson();
//TO JSON support end

//puts("DEBUG: interpreter is ready"); //DEBUG

let source = readSources();

let parseResult = interpreter["parse"](interpreter, source);

if (!(parseResult["success"])) {
    puts("Parse failed with errors: " + parseResult["errors"]); //FIXME BACKPORT
} else {
    //puts("Parse succeeded.");
    if (runIt) {
        let evalResult = interpreter["evaluate"](interpreter);
        if (evalResult["success"]) {
            //puts("Evaluate succeeded. Result: " + "" + evalResult["result"]);
            let r = evalResult["result"];
            //if (r != null) {
            //    puts("" + r);
            //}
        } else {
            puts("Evaluation failed with errors: " + interpreter["formatErrors"](interpreter, evalResult["errors"]));
        }
    }
}

if (printAst) {
    let astJson = interpreter["getAstJson"](interpreter);
    if (astJson != null) {
        puts(astJson);
    } else {
        puts("No AST to show.");
    }

}

if (transpileGo) {
    if (transpileGoFull) {
        puts("#!/bin/bash");
        puts("cat <<'EOX' > app.go");
        goLibPrefix();
    }
    interpreter["toGo"](interpreter);
    if (transpileGoFull) {
        puts("EOX");
        puts("go build app.go");
    }
}

assert(interpreter != null, "Interpreter instance should not be null");

