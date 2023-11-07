local lass = {}
local lassMetatable = {}
setmetatable(lass, lassMetatable)

-- Some handy local functions to be used within the library ----------------------------------------

---@diagnostic disable-next-line: deprecated
local unpack = unpack or table.unpack -- 5.2 compat

local function assertWithLevel(condition, message, level)
    if not condition then
        error(message, 1 + (level or 2))
    end
end

local function assertType(value, desiredType, errorMessage, errorLevel)
    if type(value) ~= desiredType then
        error(errorMessage, 1 + (errorLevel or 2))
    end
end

local function deepCopy(t, _seenTables)
    _seenTables = _seenTables or {}
    if type(t) == "table" then
        local copiedTable = {}

        if _seenTables[t] then
            return _seenTables[t]
        else
            _seenTables[t] = copiedTable
        end

        for key, value in pairs(t) do
            copiedTable[key] = deepCopy(value, _seenTables)
        end
        return copiedTable
    end
    return t
end

-- Definitions -------------------------------------------------------------------------------------

---@class LassVariableDefinition
---@field accessLevel string
---@field defaultValue any
---@field nonOverwriteable boolean
---@field isReference boolean

---@class LassClassDefinition
---@field name string
---@field variables table<string, LassVariableDefinition>
---@field fullComposition table<string, boolean>

-- The stuff that makes Lass churn -----------------------------------------------------------------

---@type table<string, LassClassDefinition>
lass.definedClasses = {}
lass.nilValue = {} -- table for identification purposes
lass.softNil = {}
lass.hardNil = lass.nilValue

---@param parents string[]
local function verifyParentValidity(parents)
    for i = 1, #parents do
        local parentName = parents[i]
        if not lass.definedClasses[parentName] then
            error("Trying to inherit from a class that hasn't been defined ('" .. parentName .. "')", 4)
        end
    end
end

---@param varName string
---@return string varName
---@return table prefixesFound
local function extractPrefixesFromVariable(varName)
    local prefixesFound = {}
    local prefixes, remainder = string.match(varName, "^(.-)___*(.*)")
    if prefixes then
        prefixes = prefixes .. "_"
        varName = remainder
        for prefix in string.gmatch(prefixes, "(.-)_") do
            prefixesFound[prefix] = true
        end
    end
    return varName, prefixesFound
end

---@param classDefinition LassClassDefinition
---@param variableName string
---@return boolean
local function variableNameClashesWithInheritance(classDefinition, variableName)
    return classDefinition.fullComposition[variableName]
end

local prefixValid = {
    [""] = true, -- for spacing if there's no modifiers
    private = true,
    protected = true,
    public = true,
    nonmethod = true,
    reference = true,
    const = true
}

local function registerClassVariablesFromBody(className, classBody)
    local classDefinition = lass.definedClasses[className]

    local varNamesUsed = {}
    for varName, varValue in pairs(classBody) do
        local prefixes
        varName, prefixes = extractPrefixesFromVariable(varName)
        local noAccessModifier = not (prefixes["private"] or prefixes["protected"] or prefixes["public"])
        local accessLevel = (prefixes["private"] and "private_" .. className) or (prefixes["protected"] and "protected") or "public"

        -- Reserved variable names for inheriting classes
        if variableNameClashesWithInheritance(classDefinition, varName) then
            error("Cannot use variable name '" .. varName .. "' (reserved by parent class with the same name)", 4)
        end

        -- Constructor restrictions
        if varName == className then
            if type(varValue) ~= "function" then
                error("Constructor is not a function", 4)
            end
            if prefixes["nonmethod"] then
                error("Constructors may not be marked as nonmethod", 4)
            end
            if prefixes.private or prefixes.protected then
                error("Constructors must be public", 4)
            end
        end

        -- Check for nonsense
        local accessModifierCount = 0
        accessModifierCount = accessModifierCount + (prefixes.private and 1 or 0)
        accessModifierCount = accessModifierCount + (prefixes.protected and 1 or 0)
        accessModifierCount = accessModifierCount + (prefixes.public and 1 or 0)
        if accessModifierCount > 1 then
            error("Variable '" .. varName .. "' has more than one access level modifier", 4)
        end
        for prefix in pairs(prefixes) do
            if not prefixValid[prefix] then
                error("Unknown access modifier '" .. prefix .. "' in variable '" .. varName .. "'", 4)
            end
        end

        -- Make sure there's no duplicate variable names
        if varNamesUsed[varName] then
            error("Duplicate variable '" .. varName .. "'", 4)
        end
        varNamesUsed[varName] = true

        -- Extra edge-case for privates
        if classDefinition.variables[varName] then
            if string.sub(classDefinition.variables[varName].accessLevel, 1, 8) == "private_" then
                error("Variable '" .. varName .. "' already exists as a private variable within a parent (due to a limitation, private variable names have to be unique)", 4)
            end
        end

        -- Make sure a variable's access level can't be changed
        if not noAccessModifier and classDefinition.variables[varName] then
            if classDefinition.variables[varName].accessLevel ~= accessLevel then
                local newAccessLevel = accessLevel
                if string.sub(newAccessLevel, 1, 8) == "private_" then newAccessLevel = "private" end
                error("Attempting to change access level of variable '" .. varName .. "' from " .. classDefinition.variables[varName].accessLevel .. " to " .. newAccessLevel, 4)
            end
        end

        local nonOverwriteable = prefixes["const"] or false
        local isReference = prefixes["reference"] or false

        -- Modify functions' access levels
        if type(varValue) == "function" and not prefixes["nonmethod"] then
            nonOverwriteable = true
            local definedMethod = varValue
            ---@type unknown
            varValue = function (t, ...)
                if type(t) ~= "table" then
                    error("Syntax error: trying to call method '" .. tostring(varName) .. "' as a non-method function (using . instead of :)\nTo define a non-method function, use the 'nonmethod' modifier in the variable definition.", 2)
                elseif not t.__currentAccessLevel then
                    error("Method is being called on a non-class value (method is not stored inside class table)\nPlease pass in the method's selfness manually: sometable.thisMethod(self) instead of sometable:thisMethod()\n(This error may be a result of incorrect syntax in calling a parent's version of a method from the overriding method)", 2)
                end
                local previousAccessLevel = t.__currentAccessLevel
                t.__currentAccessLevel = "private_" .. className
                local returns = {definedMethod(t, ...)}
                t.__currentAccessLevel = previousAccessLevel
                return unpack(returns)
            end
        end

        -- Copy tables over
        if type(varValue) == "table" and not isReference and not varValue == lass.nilValue and not varValue == lass.softNil then
            varValue = deepCopy(varValue)
        end

        -- Make sure nonOverwriteable vars stay nonOverwriteable and vice versa
        if classDefinition.variables[varName] then
            local wasNonOverwriteable = classDefinition.variables[varName].nonOverwriteable
            if wasNonOverwriteable ~= nonOverwriteable then
                if wasNonOverwriteable then
                    error("Attempting to make constant variable '" .. varName .. "' non-constant. In the case of functions, methods are considered constant, and nonmethods are not.\nPlease mark the variable with the 'const' keyword.", 4)
                else
                    error("Attempting to make non-constant variable '" .. varName .. "' constant. In the case of functions, methods are considered constant, and nonmethods are not.\nTo make a function non-constant, mark it with the 'nonmethod' keyword.", 4)
                end
            end
        end

        -- Add to class
        if classDefinition.variables[varName] then
            classDefinition.variables[varName].defaultValue = varValue
        else
            classDefinition.variables[varName] = {accessLevel = accessLevel, defaultValue = varValue, nonOverwriteable = nonOverwriteable, isReference = isReference}
        end
    end
end

---@param className string
---@param parents string[]
---@param classBody table
local function defineClass(className, parents, classBody)
    verifyParentValidity(parents)

    ---@type LassClassDefinition
    local classDefinition = {
        name = className,
        variables = {},
        fullComposition = {}
    }
    lass.definedClasses[className] = classDefinition

    ---@type table<string, table<string, function>>
    local supers = {}

    for parentIndex = #parents, 1, -1 do
        local parentName = parents[parentIndex]
        local parentClassDefinition = lass.definedClasses[parentName]

        -- Track full class composition
        for key, value in pairs(parentClassDefinition.fullComposition) do
            classDefinition.fullComposition[key] = value
        end
        classDefinition.fullComposition[parentName] = true

        -- Prepare a super for this parent name
        supers[parentName] = {}

        -- Inherit variables
        for varName, varValue in pairs(parentClassDefinition.variables) do

            if varName == className then
                error("Cannot inherit from class '" .. parentName .. "' because it contains a variable with the same name as this class (" .. varName .. ")", 3)
            end

            local currentVariable = classDefinition.variables[varName]
            if currentVariable then
                if currentVariable.accessLevel ~= varValue.accessLevel then
                    local accessLevelCurrent = currentVariable.accessLevel
                    local accessLevelNext = varValue.accessLevel
                    if string.sub(accessLevelCurrent, 1, 8) == "private_" then accessLevelCurrent = "private" end
                    if string.sub(accessLevelNext, 1, 8) == "private_" then accessLevelNext = "private" end
                    if accessLevelCurrent == "private" and accessLevelNext == "private" then
                        error("Variable clash in inheriting classes - variable '" .. varName .. "' is private and defined in more than one parent (due to a limitation, private variables need to be unique in the whole inheritance tree)", 3)
                    end
                    error("Variable access level clash in inheriting classes - variable '" .. varName .. "' is defined both as " .. accessLevelCurrent .. " and " .. accessLevelNext .. " in parents", 3)
                end
                if currentVariable.nonOverwriteable ~= varValue.nonOverwriteable then error("Variable '" .. varName .. "' is defined both as constant and as non-constant in parents.\nIn the case of functions, methods are considered constant, while nonmethods are not.", 3) end
            end

            -- Parse nils
            local value = varValue.defaultValue
            if value == lass.softNil and currentVariable then
                value = currentVariable.defaultValue
            end

            -- Track the super
            if type(value) == "function" and varValue.nonOverwriteable then
                supers[parentName][varName] = value
            end

            -- Add the variable
            classDefinition.variables[varName] = {accessLevel = varValue.accessLevel, defaultValue = value, nonOverwriteable = varValue.nonOverwriteable, isReference = varValue.isReference}
        end
    end

    -- Finish making access to super and previous constructors
    for parentName, parentMethods in pairs(supers) do
        local constructorFound = false
        for key, value in pairs(parentMethods) do
            if key == parentName then
                setmetatable(supers[parentName], {__call = function (t, self, ...)
                    return value(self, ...)
                end})
                constructorFound = true
            end
        end
        if not constructorFound then
            setmetatable(supers[parentName], {__call = function (t, self, ...)
                error("Attempting to call constructor of class '" .. parentName .. "', which has no constructor", 2)
            end})
        end
    end

    -- Register the supers
    for parentName, parentMethods in pairs(supers) do
        classDefinition.variables[parentName] = {accessLevel = "protected", isReference = true, nonOverwriteable = true, defaultValue = parentMethods}
    end

    -- Add the defined variables for this class
    registerClassVariablesFromBody(className, classBody)
end

local function copyVariablesFromDefinition(classDefinitionVariables)
    local variableTable = {}
    for varName, varDefinition in pairs(classDefinitionVariables) do
        local varValue = varDefinition.defaultValue
        local copiedValue = varValue
        if varValue == lass.nilValue or varValue == lass.softNil then
            copiedValue = nil
        elseif type(varValue) == "table" and not varDefinition.isReference then
            copiedValue = deepCopy(varValue)
        end

        variableTable[varName] = copiedValue
    end
    return variableTable
end

local function verifyInstanceAccessLevel(instance, varName)
    local classDefinitionVariables = instance.__classDefinition.variables
    local varDefinition = classDefinitionVariables[varName]

    if not varDefinition then
        error("Trying to access undefined variable '" .. tostring(varName) .. "'", 3)
    end

    local neededAccessLevel = varDefinition.accessLevel
    local accessLevel = instance.__currentAccessLevel
    local canAccessVariable = (accessLevel == neededAccessLevel) or (neededAccessLevel == "public") or (accessLevel ~= "public" and neededAccessLevel == "protected")

    if not canAccessVariable then
        if string.sub(neededAccessLevel, 1, 8) == "private_" then neededAccessLevel = "private" end
        if string.sub(accessLevel, 1, 8) == "private_" then accessLevel = "private" end
        if neededAccessLevel == "private" and accessLevel == "private" then
            error("Trying to access private variable '" .. tostring(varName) .. "' outside of its class", 3)
        end
        error("Trying to access " .. neededAccessLevel .. " variable '" .. tostring(varName) .. "' in the " .. tostring(accessLevel) .. " scope", 3)
    end
end

local function verifyAllowedOverwrite(instance, varName)
    local classDefinitionVariables = instance.__classDefinition.variables
    local varDefinition = classDefinitionVariables[varName]
    local nonOverwriteable = varDefinition.nonOverwriteable
    if nonOverwriteable then
        if type(varDefinition.defaultValue) == "function" then
            error("Trying to overwrite a method or constant function\nMethods may not be overwritten. If you want an overwriteable function, mark it as nonmethod.", 3)
        end
        error("Trying to overwrite a constant value", 3)
    end
end

local instanceAccessMetatable = {}
function instanceAccessMetatable.__index(instance, varName)
    verifyInstanceAccessLevel(instance, varName)
    return instance.__variablesRaw[varName]
end
function instanceAccessMetatable.__newindex(instance, varName, newValue)
    verifyInstanceAccessLevel(instance, varName)
    verifyAllowedOverwrite(instance, varName)
    instance.__variablesRaw[varName] = newValue
end

local function generateClassInstance(className, ...)
    local classDefinition = lass.definedClasses[className]
    local classDefinitionVariables = classDefinition.variables

    local variableTable = copyVariablesFromDefinition(classDefinitionVariables)
    local accessTable = {
        __variablesRaw = variableTable,
        __classDefinition = classDefinition,
        __currentAccessLevel = "public"
    }
    setmetatable(accessTable, instanceAccessMetatable)

    -- Call the constructor
    if accessTable.__variablesRaw[className] then accessTable[className](accessTable, ...) end

    return accessTable
end

---Creates a new class instance
---@generic T
---@param className `T`
---@param ... unknown
---@return `T`
function lass.new(className, ...)
    if not lass.definedClasses[className] then
        error("Class '" .. tostring(className) .. "' has not been defined", 2)
    end

    return generateClassInstance(className, ...)
end

---@param childClassName string
---@param parentClassName string
---@return boolean
local function classIs(childClassName, parentClassName)
    local classDefinition = lass.definedClasses[childClassName]
    if not classDefinition then error("Unknown class '" .. childClassName .. "'", 3) end

    if childClassName == parentClassName then return true end
    return classDefinition.fullComposition[parentClassName] or false
end

---@param class any
---@return string
local function extractClassName(class)
    local classType = type(class)
    if classType == "string" then
        return class
    end

    if classType == "table" then
        if class.__classDefinition then
            return class.__classDefinition.name
        end
        error("Trying to compare a non-class table to a class", 3)
    end
    error("Invalid type (" .. classType .. "), please provide a class instance or class name", 3)
end

---Checks if the first argument is a subclass of or the same class as the second argument
---@param childClassInstanceOrName table|string
---@param parentClassInstanceOrName table|string
---@return boolean
function lass.is(childClassInstanceOrName, parentClassInstanceOrName)
    local childName = extractClassName(childClassInstanceOrName)
    local parentName = extractClassName(parentClassInstanceOrName)
    return classIs(childName, parentName)
end
lass.implements = lass.is

-- The meat of the syntax --------------------------------------------------------------------------

local classMakingTable = {}
local classMakingMetatable = {}
setmetatable(classMakingTable, classMakingMetatable)
function classMakingTable:from(parents)

    if self ~= classMakingTable then
        error("Incorrect syntax. Please use:\nlass 'ClassName' : from 'ParentName' { }\ninstead of:\nlass 'ClassName' . from 'ParentName' { }", 2)
    end

    -- Inherit 1 class
    if type(parents) == "string" then
        return setmetatable({parents}, classMakingMetatable)
    end

    -- Inherit from list of classes
    if type(parents) == "table" then
        if not parents[1] then
            error("Attempting to inherit from a table with no numerical entries. Please use:\nlass 'Class' : from {'ParentA', 'ParentB'} { }", 2)
        end

        for key, value in pairs(parents) do
            if type(key) ~= "number" then
                error("Attempting to inherit from a table with hash keys. Please use:\nlass 'Class' : from {'ParentA', 'ParentB'} { }", 2)
            end
            if type(value) ~= "string" then
                error("Trying to inherit from a non-string type (" .. tostring(type(parents)) .. ")", 2)
            end
        end

        return setmetatable(parents, classMakingMetatable)
    end

    error("Trying to inherit from a non-string type (" .. tostring(type(parents)) .. ")", 2)
end
classMakingTable.D = classMakingTable.from -- class 'Class' :D 'Parent' is valid syntax, you are welcome

function classMakingMetatable:__call(classBody)
    -- Adding many classes without table
    if type(classBody) == "string" then
        self[#self+1] = classBody
        return self
    end

    if type(classBody) ~= "table" then
        error("Class body isn't a table value (" .. tostring(type(classBody)) .. "). Please use:\nlass 'Class' : from {'ParentA', 'ParentB'} { }", 2)
    end

    if classBody[1] then
        local invalidEntries = {}
        for _, v in ipairs(classBody) do
            invalidEntries[#invalidEntries+1] = tostring(v)
        end
        error("Invalid syntax (Class body has numerical entries [" .. table.concat(invalidEntries, ", ") .. "]). This error may be a result of using multiple tables to define parent classes, which isn't possible.", 2)
    end

    -- Time to create the class

    local parents = self
    local className = classMakingTable.upcomingClassName
    assertWithLevel(className, "A class is being defined but no name for it was found. Are you using the library in weird ways? Unexpected behaviour might arise if you split class creation into multiple lines. Please use:\nlass 'Class' { }")

    classMakingTable.upcomingClassName = nil

    defineClass(className, parents, classBody)
end

-- Lass metatable metamethods and such go here -----------------------------------------------------

-- The initial class 'ClassName' call
lassMetatable.__call = function (callingTable, className)
    assertType(className, "string", "Class name is of type " .. tostring(type(className)) .. " instead of string \nTo create a class, use:\nlass 'ClassName' { }")
    assertWithLevel(not lass.definedClasses[className], "Class '" .. className .. "' is already defined")
    classMakingTable.upcomingClassName = className
    return classMakingTable
end

return lass