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
---@field accessLevel "protected"|"public"
---@field defaultValue any
---@field nonOverwriteable boolean
---@field isReference boolean

---@class LassClassDefinition
---@field variables table<string, LassVariableDefinition>

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

local prefixValid = {
    [""] = true, -- for spacing if there's no modifiers
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
        local accessLevel = prefixes["protected"] and "protected" or "public"

        -- Check for nonsense
        if prefixes.protected and prefixes.public then
            error("Variable '" .. varName .. "' is attempting to be public and protected at the same time", 4)
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

        -- Make sure a variable's access level can't be changed
        if not noAccessModifier and classDefinition.variables[varName] then
            if classDefinition.variables[varName].accessLevel ~= accessLevel then
                error("Attempting to change access level of variable '" .. varName .. "' from " .. classDefinition.variables[varName].accessLevel .. " to " .. accessLevel, 4)
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
                    error("Trying to call method '" .. tostring(varName) .. "' as a non-method function (using . instead of :)\nTo define a non-method function, use the 'nonmethod' modifier in the variable definition.", 2)
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
        variables = {},
    }
    lass.definedClasses[className] = classDefinition

    -- Inherit variables
    for parentIndex = #parents, 1, -1 do
        local parentName = parents[parentIndex]
        local parentClassDefinition = lass.definedClasses[parentName]
        for varName, varValue in pairs(parentClassDefinition.variables) do
            local currentVariable = classDefinition.variables[varName]
            if currentVariable then
                if currentVariable.accessLevel ~= varValue.accessLevel then error("Variable access level clash in inheriting classes - variable '" .. varName .. "' is defined both as " .. currentVariable.accessLevel .. " and " .. varValue.accessLevel .. " in parents", 3) end
                if currentVariable.nonOverwriteable ~= varValue.nonOverwriteable then error("Variable '" .. varName .. "' is defined both as constant and as non-constant in parents.\nIn the case of functions, methods are considered constant, while nonmethods are not.", 3) end
            end

            local value = varValue.defaultValue
            if value == lass.softNil and currentVariable then
                value = currentVariable.defaultValue
            end

            classDefinition.variables[varName] = {accessLevel = varValue.accessLevel, defaultValue = value, nonOverwriteable = varValue.nonOverwriteable, isReference = varValue.isReference}
        end
    end

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
    local neededAccessLevel = varDefinition.accessLevel

    local accessLevel = instance.__currentAccessLevel
    local canAccessVariable = (accessLevel == neededAccessLevel) or (neededAccessLevel == "public") or (accessLevel ~= "public" and neededAccessLevel == "protected")

    if not varDefinition then
        error("Trying to access undefined variable '" .. tostring(varName) .. "'", 3)
    end
    if not canAccessVariable then
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

    return setmetatable(accessTable, instanceAccessMetatable)
end

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