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

-- Definitions -------------------------------------------------------------------------------------

---@class LassVariableDefinition
---@field accessLevel "protected"|"public"
---@field defaultValue any

---@class LassClassDefinition
---@field variables table<string, LassVariableDefinition>

-- The stuff that makes Lass churn -----------------------------------------------------------------

---@type table<string, LassClassDefinition>
lass.definedClasses = {}
lass.nilValue = {} -- table for identification purposes

---@param parents string[]
local function checkParentValidity(parents)
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
    protected = true,
    public = true
}

local function registerClassVariablesFromBody(className, classBody)
    local classDefinition = lass.definedClasses[className]

    local varNamesUsed = {}
    for varName, varValue in pairs(classBody) do
        local prefixes
        varName, prefixes = extractPrefixesFromVariable(varName)
        local noModifier = not next(prefixes)
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
        if not noModifier and classDefinition.variables[varName] then
            if classDefinition.variables[varName].accessLevel ~= accessLevel then
                error("Attempting to change access level of variable '" .. varName .. "' from " .. classDefinition.variables[varName].accessLevel .. " to " .. accessLevel, 4)
            end
        end

        -- Add to class
        if classDefinition.variables[varName] then
            classDefinition.variables[varName].defaultValue = varValue
        else
            classDefinition.variables[varName] = {accessLevel = accessLevel, defaultValue = varValue}
        end
    end
end

---@param className string
---@param parents string[]
---@param classBody table
local function defineClass(className, parents, classBody)
    checkParentValidity(parents)

    ---@type LassClassDefinition
    local classDefinition = {
        variables = {},
    }
    lass.definedClasses[className] = classDefinition

    -- Inherit variables
    for parentIndex = 1, #parents do
        local parentName = parents[parentIndex]
        local parentClassDefinition = lass.definedClasses[parentName]
        for varName, varValue in pairs(parentClassDefinition.variables) do
            classDefinition.variables[varName] = {accessLevel = varValue.accessLevel, defaultValue = varValue.defaultValue}
        end
    end

    registerClassVariablesFromBody(className, classBody)
end

local function deepCopy(t)
    if type(t) == "table" then
        local copiedTable = {}
        for key, value in pairs(t) do
            copiedTable[key] = deepCopy(value)
        end
        return copiedTable
    end
    return t
end

local function copyVariablesFromDefinition(classDefinitionVariables)
    local variableTable = {}
    for varName, varDefinition in pairs(classDefinitionVariables) do
        local varValue = varDefinition.defaultValue
        local copiedValue = varValue
        if varValue == lass.nilValue then
            copiedValue = nil
        elseif type(varValue) == "table" then
            copiedValue = deepCopy(varValue)
        end

        variableTable[varName] = copiedValue
    end
    return variableTable
end

local publicAccessMetatable = {}
function publicAccessMetatable.__index(instance, varName)
    local classDefinitionVariables = instance.__classDefinition.variables
    local varDefinition = classDefinitionVariables[varName]

    if not varDefinition then
        error("Trying to access undefined variable '" .. tostring(varName) .. "'", 2)
    end
    if varDefinition.accessLevel ~= "public" then
        error("Trying to publicly access variable '" .. tostring(varName) .. "', which is " .. varDefinition.accessLevel, 2)
    end

    return instance.__variablesRaw[varName]
end
function publicAccessMetatable.__newindex(instance, varName, newValue)
    local classDefinitionVariables = instance.__classDefinition.variables
    local varDefinition = classDefinitionVariables[varName]

    if not varDefinition then
        error("Trying to set undefined variable '" .. tostring(varName) .. "'", 2)
    end
    if varDefinition.accessLevel ~= "public" then
        error("Trying to set " .. varDefinition.accessLevel .. " variable '" .. tostring(varName) .. "' in the public scope", 2)
    end

    instance.__variablesRaw[varName] = newValue
end

local function generateClassInstance(className, ...)
    local classDefinition = lass.definedClasses[className]
    local classDefinitionVariables = classDefinition.variables

    local variableTable = copyVariablesFromDefinition(classDefinitionVariables)
    local accessTable = {
        __variablesRaw = variableTable,
        __classDefinition = classDefinition
    }

    return setmetatable(accessTable, publicAccessMetatable)
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
classMakingTable._ = classMakingTable.from

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