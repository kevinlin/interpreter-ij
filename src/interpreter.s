
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
        "match", "findAll", "replace", "split"
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
        if (origin == "param") { useGoVar = true; }
        if (origin == "let") {
            if (kind == "local" || kind == "captured") { useGoVar = true; }
        }
        if (kind == "global") {
            if (origin == "lib" || origin == "def" || origin == "let") {
                useGoVar = true;
                isGlobal = true;
            }
        }
        if (!useGoVar) { return false; }
        if (isGlobal) { return false; }
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
    let info = resolverScopeLookup(scope, node["name"]);
    node["resolvedKind"] = info["kind"];
    node["resolvedOrigin"] = info["origin"];
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
        let stmts = ast["statements"];
        if (stmts == null) {
            ast["resolvedRootGlobals"] = rootGlobals;
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
                }
                if (st == "FunctionDeclaration") {
                    resolverScopeDeclare(rootScope, stmt["name"], "def");
                    push(rootGlobals, stmt["name"]);
                }
            }
            h = h + 1;
        }
        ast["resolvedRootGlobals"] = rootGlobals;

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
        print('&Node{kind: nkStaticCall, staticImpl: ' + mangle(callee["name"]) + '_impl, list: []*Node{');
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
def mapHasKey(mapObj, key) {
    // Optimize: cache length
    let ks = keys(mapObj);
    let n = len(ks);
    let i = 0;
    while (i < n) {
        if (ks[i] == key) {
            return true;
        }
        i = i + 1;
    }
    return false;
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
    // Direct lookup is faster than mapHasKey for the common case
    let val = ctx["values"][name];
    if (val != null) {
        return val;
    }
    
    // Check if key exists but value is null
    if (mapHasKey(ctx["values"], name)) {
        return null;
    }

    // Check functions map
    val = ctx["functions"][name];
    if (val != null) {
        return val;
    }
    
    // Check if function exists but value is null
    if (mapHasKey(ctx["functions"], name)) {
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
puts("" + chr(34) + "os" + chr(34) + "");
puts("" + chr(34) + "regexp" + chr(34) + "");
puts("" + chr(34) + "runtime/pprof" + chr(34) + "");
puts("" + chr(34) + "strconv" + chr(34) + "");
puts("" + chr(34) + "strings" + chr(34) + "");
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
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "push: expected array" + chr(34) + ")");
puts("}");
puts("ele := params.Get(Value{tag: tInt, i: 1})");
puts("arr.arr.values = append(arr.arr.values, ele)");
puts("return arr");
puts("})))");
puts("ctx.Create(" + chr(34) + "pop" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "pop: expected array" + chr(34) + ")");
puts("}");
puts("if len(arr.arr.values) == 0 {");
puts("return vInvalid(" + chr(34) + "pop: array is empty" + chr(34) + ")");
puts("}");
puts("lastElement := arr.arr.values[len(arr.arr.values)-1]");
puts("arr.arr.values = arr.arr.values[:len(arr.arr.values)-1]");
puts("return lastElement");
puts("})))");
puts("ctx.Create(" + chr(34) + "join" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tArray {");
puts("return vInvalid(" + chr(34) + "join: expected array" + chr(34) + ")");
puts("}");
puts("delim := params.Get(Value{tag: tInt, i: 1}).ValueString()");
puts("strValues := make([]string, len(arr.arr.values))");
puts("for i, v := range arr.arr.values {");
puts("strValues[i] = v.ValueString()");
puts("}");
puts("joined := strings.Join(strValues, delim)");
puts("return Value{tag: tString, s: joined}");
puts("})))");
puts("ctx.Create(" + chr(34) + "keys" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tMap {");
puts("return vInvalid(" + chr(34) + "keys: expected map" + chr(34) + ")");
puts("}");
puts("keys := make([]Value, len(arr.m.pairs))");
puts("i := 0");
puts("for _, pair := range arr.m.pairs {");
puts("keys[i] = pair.Key");
puts("i++");
puts("}");
puts("return vArray(NewArrayValue(keys...))");
puts("})))");
puts("ctx.Create(" + chr(34) + "values" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("arr := params.Get(Value{tag: tInt, i: 0})");
puts("if arr.tag != tMap {");
puts("return vInvalid(" + chr(34) + "values: expected map" + chr(34) + ")");
puts("}");
puts("values := make([]Value, len(arr.m.pairs))");
puts("i := 0");
puts("for _, pair := range arr.m.pairs {");
puts("values[i] = pair.Value");
puts("i++");
puts("}");
puts("return vArray(NewArrayValue(values...))");
puts("})))");
puts("ctx.Create(" + chr(34) + "char" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("if str.tag != tString {");
puts("return vInvalid(" + chr(34) + "char: expected key" + chr(34) + ")");
puts("}");
puts("pos := params.Get(Value{tag: tInt, i: 1})");
puts("posVal := pos.IntValue()");
puts("if posVal >= 0 && posVal < len(str.s) {");
puts("return Value{tag: tString, s: string(str.s[posVal])}");
puts("} else {");
puts("return vNull()");
puts("}");
puts("})))");
puts("ctx.Create(" + chr(34) + "len" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("x := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tInt, i: int64(x.Length())}");
puts("})))");
puts("ctx.Create(" + chr(34) + "chr" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("asciiCode := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tString, s: string(rune(asciiCode.IntValue()))}");
puts("})))");
puts("ctx.Create(" + chr(34) + "ord" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("chr := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tInt, i: int64(chr.String()[0])}");
puts("})))");
puts("ctx.Create(" + chr(34) + "substr" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("str := params.Get(Value{tag: tInt, i: 0})");
puts("start := params.Get(Value{tag: tInt, i: 1})");
puts("len := params.Get(Value{tag: tInt, i: 2})");
puts("return Value{tag: tString, s: str.ValueString()[start.IntValue() : start.IntValue()+len.IntValue()]}");
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
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tString, s: v.ValueString()}");
puts("})))");
puts("ctx.Create(" + chr(34) + "random" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("secId, err := GenerateSecureID()");
puts("if err != nil {");
puts("return vInvalid(" + chr(34) + "random: " + chr(34) + " + err.Error())");
puts("}");
puts("return Value{tag: tString, s: secId}");
puts("})))");
puts("ctx.Create(" + chr(34) + "typeof" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return v.Type()");
puts("})))");
puts("ctx.Create(" + chr(34) + "isArray" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "array" + chr(34) + "}");
puts("})))");
puts("ctx.Create(" + chr(34) + "isMap" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "map" + chr(34) + "}");
puts("})))");
puts("ctx.Create(" + chr(34) + "isNumber" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "number" + chr(34) + "}");
puts("})))");
puts("ctx.Create(" + chr(34) + "isString" + chr(34) + ", vFunc(NewFunctionCommand(ctx, func(ctx *Context, params *ArrayValue) Value {");
puts("v := params.Get(Value{tag: tInt, i: 0})");
puts("return Value{tag: tBool, b: v.Type().ValueString() == " + chr(34) + "string" + chr(34) + "}");
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
puts("return Value{tag: tDouble, d: num}");
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
puts("if idx < 0 || idx >= len(collection.arr.values) {");
puts("return vInvalid(" + chr(34) + "delete: array index out of bounds" + chr(34) + ")");
puts("}");
puts("removed := collection.arr.values[idx]");
puts("collection.arr.values = append(collection.arr.values[:idx], collection.arr.values[idx+1:]...)");
puts("return removed");
puts("} else if collection.tag == tMap {");
puts("if idx, found := collection.m.findPair(keyOrIndex); found {");
puts("removed := collection.m.pairs[idx].Value");
puts("collection.m.pairs = append(collection.m.pairs[:idx], collection.m.pairs[idx+1:]...)");
puts("if collection.m.keyIndex == nil {");
puts("collection.m.keyIndex = make(map[string]int)");
puts("} else {");
puts("for k := range collection.m.keyIndex {");
puts("delete(collection.m.keyIndex, k)");
puts("}");
puts("}");
puts("for i, pair := range collection.m.pairs {");
puts("collection.m.keyIndex[pair.Key.String()] = i");
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
puts("type Value struct {");
puts("tag   uint8");
puts("b     bool");
puts("i     int64");
puts("d     float64");
puts("s     string");
puts("arr   *ArrayValue");
puts("m     *MapValue");
puts("cmd   Command");
puts("inv   string");
puts("}");
puts("func (v Value) IsTruthy() bool {");
puts("switch v.tag {");
puts("case tNull: return false");
puts("case tInt: return v.i != 0");
puts("case tDouble: return v.d != 0");
puts("case tString: return len(v.s) > 0");
puts("case tBool: return v.b");
puts("case tArray: return v.arr != nil && v.arr.Length() > 0");
puts("case tMap: return v.m != nil && v.m.Length() > 0");
puts("case tFunc: return true");
puts("case tInvalid: return false");
puts("}");
puts("return false");
puts("}");
puts("func (v Value) IsInvalid() bool { return v.tag == tInvalid }");
puts("func (v Value) Length() int {");
puts("switch v.tag {");
puts("case tString: return len(v.s)");
puts("case tArray: return v.arr.Length()");
puts("case tMap: return v.m.Length()");
puts("}");
puts("return 0");
puts("}");
puts("func (v Value) IntValue() int {");
puts("switch v.tag {");
puts("case tInt: return int(v.i)");
puts("case tDouble: return int(v.d)");
puts("case tBool: if v.b { return 1 }; return 0");
puts("}");
puts("return 0");
puts("}");
puts("func (v Value) String() string {");
puts("switch v.tag {");
puts("case tNull: return " + chr(34) + "null" + chr(34) + "");
puts("case tInt: return strconv.FormatInt(v.i, 10)");
puts("case tDouble: return strconv.FormatFloat(v.d, 'f', -1, 64)");
puts("case tString: return v.s");
puts("case tBool: if v.b { return " + chr(34) + "true" + chr(34) + " }; return " + chr(34) + "false" + chr(34) + "");
puts("case tArray: return v.arr.String()");
puts("case tMap: return v.m.String()");
puts("case tFunc: return " + chr(34) + "function" + chr(34) + "");
puts("case tInvalid: return " + chr(34) + "invalid: " + chr(34) + " + v.inv");
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
puts("case tDouble: return Value{tag: tDouble, d: float64(v.i) + other.d}");
puts("case tString: return Value{tag: tString, s: strconv.FormatInt(v.i, 10) + other.s}");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tDouble, d: v.d + float64(other.i)}");
puts("case tDouble: return Value{tag: tDouble, d: v.d + other.d}");
puts("case tString: return Value{tag: tString, s: strconv.FormatFloat(v.d, 'f', -1, 64) + other.s}");
puts("}");
puts("case tString:");
puts("var sb2 strings.Builder");
puts("sb2.Grow(len(v.s) + len(other.String()))");
puts("sb2.WriteString(v.s)");
puts("sb2.WriteString(other.String())");
puts("return Value{tag: tString, s: sb2.String()}");
puts("case tArray:");
puts("if other.tag == tArray {");
puts("result := &ArrayValue{values: make([]Value, len(v.arr.values)+len(other.arr.values))}");
puts("copy(result.values, v.arr.values)");
puts("copy(result.values[len(v.arr.values):], other.arr.values)");
puts("return Value{tag: tArray, arr: result}");
puts("}");
puts("case tMap:");
puts("if other.tag == tMap {");
puts("result := &MapValue{pairs: make([]KeyValuePair, len(v.m.pairs)), keyIndex: make(map[string]int)}");
puts("copy(result.pairs, v.m.pairs)");
puts("for i, pair := range result.pairs { result.keyIndex[pair.Key.String()] = i }");
puts("for _, pair := range other.m.pairs {");
puts("if idx, found := result.keyIndex[pair.Key.String()]; found { result.pairs[idx].Value = pair.Value } else {");
puts("newIdx := len(result.pairs); result.pairs = append(result.pairs, KeyValuePair{Key: pair.Key, Value: pair.Value})");
puts("result.keyIndex[pair.Key.String()] = newIdx");
puts("}");
puts("}");
puts("return Value{tag: tMap, m: result}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "type mismatch in Add" + chr(34) + "}");
puts("}");
puts("func (v Value) Subtract(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tInt, i: v.i - other.i}");
puts("case tDouble: return Value{tag: tDouble, d: float64(v.i) - other.d}");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tDouble, d: v.d - float64(other.i)}");
puts("case tDouble: return Value{tag: tDouble, d: v.d - other.d}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "type mismatch in Subtract" + chr(34) + "}");
puts("}");
puts("func (v Value) Multiply(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tInt, i: v.i * other.i}");
puts("case tDouble: return Value{tag: tDouble, d: float64(v.i) * other.d}");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: return Value{tag: tDouble, d: v.d * float64(other.i)}");
puts("case tDouble: return Value{tag: tDouble, d: v.d * other.d}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "type mismatch in Multiply" + chr(34) + "}");
puts("}");
puts("func (v Value) Divide(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "division by zero" + chr(34) + "} }; return Value{tag: tInt, i: v.i / other.i}");
puts("case tDouble: if other.d == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "division by zero" + chr(34) + "} }; return Value{tag: tDouble, d: float64(v.i) / other.d}");
puts("}");
puts("case tDouble:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "division by zero" + chr(34) + "} }; return Value{tag: tDouble, d: v.d / float64(other.i)}");
puts("case tDouble: if other.d == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "division by zero" + chr(34) + "} }; return Value{tag: tDouble, d: v.d / other.d}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "type mismatch in Divide" + chr(34) + "}");
puts("}");
puts("func (v Value) Modulo(other Value) Value {");
puts("if other.tag == tInvalid { return other }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch other.tag {");
puts("case tInt: if other.i == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "modulo by zero" + chr(34) + "} }; return Value{tag: tInt, i: v.i % other.i}");
puts("case tDouble: if other.d == 0 { return Value{tag: tInvalid, inv: " + chr(34) + "modulo by zero" + chr(34) + "} }; return Value{tag: tInvalid, inv: " + chr(34) + "modulo not defined for floating point" + chr(34) + "}");
puts("}");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "type mismatch in Modulo" + chr(34) + "}");
puts("}");
puts("func (v Value) Equals(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("if v.tag != other.tag { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: true}");
puts("case tInt: return Value{tag: tBool, b: v.i == other.i}");
puts("case tDouble: return Value{tag: tBool, b: v.d == other.d}");
puts("case tString: return Value{tag: tBool, b: v.s == other.s}");
puts("case tBool: return Value{tag: tBool, b: v.b == other.b}");
puts("case tFunc: return Value{tag: tBool, b: v.cmd == other.cmd}");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) LessThan(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i < other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) < other.d} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.d < float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.d < other.d} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) LessThanEqual(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: other.tag == tNull}");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i <= other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) <= other.d} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.d <= float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.d <= other.d} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) BiggerThan(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i > other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) > other.d} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.d > float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.d > other.d} }");
puts("}");
puts("return Value{tag: tBool, b: false}");
puts("}");
puts("func (v Value) BiggerThanEqual(other Value) Value {");
puts("if other.tag == tInvalid { return Value{tag: tBool, b: false} }");
puts("switch v.tag {");
puts("case tNull: return Value{tag: tBool, b: other.tag == tNull}");
puts("case tInt: if other.tag == tInt { return Value{tag: tBool, b: v.i >= other.i} }; if other.tag == tDouble { return Value{tag: tBool, b: float64(v.i) >= other.d} }");
puts("case tDouble: if other.tag == tInt { return Value{tag: tBool, b: v.d >= float64(other.i)} }; if other.tag == tDouble { return Value{tag: tBool, b: v.d >= other.d} }");
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
puts("if index.tag != tInt { return Value{tag: tInvalid, inv: " + chr(34) + "string index must be number" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx >= 0 && idx < len(v.s) { return Value{tag: tString, s: string(v.s[idx])} }");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "string index out of bounds" + chr(34) + "}");
puts("case tArray:");
puts("if index.tag != tInt { return Value{tag: tInvalid, inv: " + chr(34) + "array index must be number" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx >= 0 && idx < len(v.arr.values) { return v.arr.values[idx] }");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "array index out of bounds" + chr(34) + "}");
puts("case tMap:");
puts("return v.m.Get(index)");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "Get not supported for type" + chr(34) + "}");
puts("}");
puts("func (v Value) Put(index Value, value Value) Value {");
puts("switch v.tag {");
puts("case tArray:");
puts("if index.tag != tInt { return Value{tag: tInvalid, inv: " + chr(34) + "array index must be number for Put" + chr(34) + "} }");
puts("idx := int(index.i)");
puts("if idx < 0 || idx >= len(v.arr.values) { return Value{tag: tInvalid, inv: " + chr(34) + "array index out of bounds" + chr(34) + "} }");
puts("v.arr.values[idx] = value");
puts("return value");
puts("case tMap:");
puts("return v.m.Put(index, value)");
puts("}");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "Put not supported for type" + chr(34) + "}");
puts("}");
puts("func (v Value) Keys() Value {");
puts("if v.tag == tMap { return v.m.Keys() }");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "Keys not supported" + chr(34) + "}");
puts("}");
puts("func (v Value) Values() Value {");
puts("if v.tag == tMap { return v.m.Values() }");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "Values not supported" + chr(34) + "}");
puts("}");
puts("func (v Value) Execute(ctx *Context, params *ArrayValue) Value {");
puts("if v.tag == tFunc { return v.cmd.Execute(ctx, params) }");
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
puts("if v.tag == tArray { v.arr.values = append(v.arr.values, value); return value }");
puts("return Value{tag: tInvalid, inv: " + chr(34) + "Append only supported for arrays" + chr(34) + "}");
puts("}");
puts("func vNull() Value { return Value{tag: tNull} }");
puts("func vBool(b bool) Value { return Value{tag: tBool, b: b} }");
puts("func vInt(i int64) Value { return Value{tag: tInt, i: i} }");
puts("func vDouble(d float64) Value { return Value{tag: tDouble, d: d} }");
puts("func vString(s string) Value { return Value{tag: tString, s: s} }");
puts("func vArray(a *ArrayValue) Value { return Value{tag: tArray, arr: a} }");
puts("func vMap(m *MapValue) Value { return Value{tag: tMap, m: m} }");
puts("func vFunc(c Command) Value { return Value{tag: tFunc, cmd: c} }");
puts("func vInvalid(reason string) Value { return Value{tag: tInvalid, inv: reason} }");
puts("func ValueToOld(v Value) Value { return nil } // stub — unused during transition");
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
puts("type Context struct {");
puts("parent    *Context");
puts("variables map[string]Value");
puts("}");
puts("func NewContext(parent *Context) *Context {");
puts("return &Context{parent: parent}");
puts("}");
puts("func (c *Context) Get(name string) Value {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if v, ok := ctx.variables[name]; ok { return v }");
puts("}");
puts("return vInvalid(" + chr(34) + "variable not found: " + chr(34) + " + name)");
puts("}");
puts("func (c *Context) Exists(name string) bool {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if _, ok := ctx.variables[name]; ok { return true }");
puts("}");
puts("return false");
puts("}");
puts("func (c *Context) Create(name string, value Value) Value {");
puts("if c.variables == nil { c.variables = make(map[string]Value) }");
puts("c.variables[name] = value");
puts("return value");
puts("}");
puts("func (c *Context) Update(name string, value Value) Value {");
puts("for ctx := c; ctx != nil; ctx = ctx.parent {");
puts("if _, ok := ctx.variables[name]; ok { ctx.variables[name] = value; return value }");
puts("}");
puts("return c.Create(name, value)");
puts("}");
puts("func (c *Context) GetLocal(name string) Value {");
puts("if v, ok := c.variables[name]; ok { return v }");
puts("return vInvalid(" + chr(34) + "variable not found: " + chr(34) + " + name)");
puts("}");
puts("func (c *Context) UpdateLocal(name string, value Value) Value {");
puts("if c.variables == nil { c.variables = make(map[string]Value) }");
puts("c.variables[name] = value");
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
puts("}");
puts("func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {");
puts("// Phase 2.5: pass nil to executeFunc. The closure body already opens its own");
puts("// `local := NewContext(defCtx)` (evalFuncDecl emit), so any ctx we pass here");
puts("// is discarded. Skipping NewContext(c.definitionCtx) saves one *Context alloc");
puts("// per function invocation -- this is the inner-loop allocator in sample.s.");
puts("return c.executeFunc(nil, params)");
puts("}");
puts("func (c *FunctionCommand) String() string { return " + chr(34) + "function" + chr(34) + " }");
puts("func (c *FunctionCommand) IsTruthy() bool { return true }");
puts("func (c *FunctionCommand) IsInvalid() bool { return false }");
puts("func NewFunctionCommand(defCtx *Context, fn func(*Context, *ArrayValue) Value) Command {");
puts("return &FunctionCommand{definitionCtx: defCtx, executeFunc: fn}");
puts("}");
puts("func NewStaticFunctionCommand(defCtx *Context, fn func(*Context, *ArrayValue) Value) Command {");
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
puts("case nkDoubleLit: return Value{tag: tDouble, d: n.dVal}, false");
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
puts("pNames := n.params");
puts("bodyN := n.body");
puts("defCtx := ctx");
puts("npar := len(pNames)");
// Closure body allocates a fresh *Context per call. Combine the Context
// struct + the params map into ONE struct literal (single alloc + sized
// map) instead of NewContext(defCtx) → lazy `if c.variables == nil`
// guard → Create("p", v). Drops ~one allocation per call AND skips the
// nil-guard branch + per-Create function call overhead. Special-case
// 0-param defs so they skip the map alloc entirely.
puts("fn := NewFunctionCommand(defCtx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("var local *Context");
puts("if npar == 0 {");
puts("local = &Context{parent: defCtx}");
puts("} else {");
puts("vars := make(map[string]Value, npar)");
puts("nv := len(args.values)");
puts("for i, p := range pNames { if i < nv { vars[p] = args.values[i] } }");
puts("local = &Context{parent: defCtx, variables: vars}");
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
puts("result := callee.cmd.Execute(ctx, av)");
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
    return null;
}

def programToGoPhase2(self) {
    let stmts = self["statements"];
    let n = len(stmts);

    // D2-reborn pre-pass: mark eligible top-level static defs and emit a sibling
    // package-level Go function for each. Direct call-site dispatch
    // (CallExpression_toGo -> nkStaticCall) reads staticDefByName during the
    // Node-tree emit below; impls are package-level so order between impl emit
    // and Node-tree emit does not matter, but the body refs they read
    // (ij_<name>_body) are populated in main() before programNode is built.
    collectStaticDefs(stmts);

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
    puts("eval(programNode, ctx)");
    puts("}");
}




// Interpreter.s - InterpreterJ port of the Interpreter Java class

// Helper function to convert an InterpreterJ map/array/primitive to a JSON string
def mapToJsonString(obj) { // FIXME
    return ijToJson(obj);
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
        {
            result = self["ast"]["evaluate"](self["ast"], context);
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

def DefaultLibraryFunctionsInitializer(context) {
    context["registerFunction"](context, "random", zeroWrapper(random));
    context["registerFunction"](context, "assert", twoWrapper(assert));
    context["registerFunction"](context, "echo", oneWrapper(echo));
    context["registerFunction"](context, "int", oneWrapper(int));
    context["registerFunction"](context, "double", oneWrapper(double));
    context["registerFunction"](context, "string", oneWrapper(string));
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
        let line = gets();
        while (line != null) {
            if (line == "//<EOF>") {
                return source;
            }
            if (line == "//<AST>") {
                printAst = true;
                runIt = false;
                return source;
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
            line = newlinehack(line);
            source = source + chr(10) + line;
            line = gets();
        }
    }
    //puts("Hack:" + source); //DEBUG
    source;
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

