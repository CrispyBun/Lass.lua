----------------------------------------------------------------------------------------------------
-- A sophistiated Lua class library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Lass.lua
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024 Ava "CrispyBun" Špráchalů

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
----------------------------------------------------------------------------------------------------

local lass = {}
local lassMetatable = {}
setmetatable(lass, lassMetatable)

local CONFIG = {}

-- If true, disables many features, but class instances run as fast as vanilla lua tables.
-- All code written in non-simple mode works in simple mode (unless youre accessing internal functionality variables),
-- so it is possible to write code in non-simple mode for better error messages, then switch to simple mode to ship the program
---@diagnostic disable-next-line: undefined-global
CONFIG.enableSimpleMode = LASSCONFIG_ENABLE_SIMPLE_MODE or false

-- If true, when reading an undefined field from a class, it will return nil instead of erroring
---@diagnostic disable-next-line: undefined-global
CONFIG.undefinedReturnsNil = LASSCONFIG_UNDEFINED_RETURNS_NIL or false

-- If true, allows assigning of variables that haven't been defined in the class,
-- as well as reading undefined variables, which will return nil
---@diagnostic disable-next-line: undefined-global
CONFIG.disableUndefined = LASSCONFIG_DISABLE_UNDEFINED or false

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
---@field isInstanced boolean

---@class LassClassDefinition
---@field name string
---@field variables table<string, LassVariableDefinition>
---@field fullComposition table<string, boolean>
---@field directParents string[]

-- The stuff that makes Lass churn -----------------------------------------------------------------

---@type table<string, LassClassDefinition>
lass.definedClasses = {}
lass.nilValue = {} -- table for identification purposes
lass.softNil = {}
lass.hardNil = lass.nilValue

---@type table<string, function>
lass.definedMimicClasses = {}

setmetatable(lass.softNil, {__tostring = function (t) return "LassSoftNil" end})
setmetatable(lass.hardNil, {__tostring = function (t) return "LassHardNil" end})

---@param className string
---@return LassClassDefinition|function|nil
function lass.classIsDefined(className)
    return lass.definedClasses[className] or lass.definedMimicClasses[className]
end
lass.exists = lass.classIsDefined

---@param parents string[]
local function verifyParentValidity(parents)
    for i = 1, #parents do
        local parentName = parents[i]
        if lass.definedMimicClasses[parentName] then
            error("Trying to inherit from a mimic class ('" .. parentName .. "'), which isn't possible", 4)
        end
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

local defaultConstructor = function (self, ...)
    local parents = self.__classDefinition.directParents
    for i = #parents, 1, -1 do
        local parentName = parents[i]
        if self.__variablesRaw[parentName][parentName] then self[parentName](self, ...) end
    end
end

local prefixValid = {
    [""] = true, -- for spacing if there's no modifiers
    private = true,
    protected = true,
    public = true,
    nonmethod = true,
    reference = true,
    const = true,
    instance = true,
    operator = true
}

local function registerClassVariablesFromBody(className, classBody)
    local classDefinition = lass.definedClasses[className]

    local varNamesUsed = {}
    for varName, varValue in pairs(classBody) do
        local unprocessedVarName = varName
        if not (type(unprocessedVarName) == "string" or type(unprocessedVarName) == "number") then
            error("Field '" .. tostring(unprocessedVarName) .. "' is a key of type " .. type(unprocessedVarName) .. ", which isn't supported", 4)
        end

        local prefixes
        varName, prefixes = extractPrefixesFromVariable(varName)
        local noAccessModifier = not (prefixes["private"] or prefixes["protected"] or prefixes["public"])
        local accessLevel = (prefixes["private"] and "private_" .. className) or (prefixes["protected"] and "protected") or "public"

        -- Operators are special
        if prefixes["operator"] then
            varName = "__" .. varName

            if accessLevel ~= "public" then
                error("Operator variable '" .. varName .. "' is not public (all operators must be public)", 4)
            end
        end

        -- Reserved variable names for inheriting classes
        if variableNameClashesWithInheritance(classDefinition, varName) then
            error("Cannot use variable name '" .. varName .. "' (reserved by parent class with the same name)", 4)
        end

        -- Constructor restrictions
        if varName == className then
            if varValue == "inherit" then
                varValue = defaultConstructor
            elseif type(varValue) ~= "function" then
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
        if prefixes["reference"] then
            if type(varValue) ~= "table" or varValue == lass.nilValue or varValue == lass.softNil then
                error("Variable '" .. varName .. "' is marked as reference, but isn't a table", 4)
            end
        end
        if prefixes["nonmethod"] and type(varValue) ~= "function" then
            error("Variable '" .. varName .. "' is marked as nonmethod, but isn't a function", 4)
        end
        if prefixes["instance"] then
            prefixes["nonmethod"] = true
            if type(varValue) == "string" then
                if not lass.classIsDefined(varValue) then
                    error("Variable '" .. varName .. "' is trying to instance class '" .. varValue .. "', which has not been defined", 4)
                end
                if varValue == className then
                    error("Variable '" .. varName .. "' is trying to instance the class it is in, which would cause a stack overflow", 4)
                end
            elseif type(varValue) ~= "function" then
                error("Variable '" .. varName .. "' is marked as instance but is of type " .. type(varValue) .. " ('instance' variables may only be class names or functions)", 4)
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
        local isReference = prefixes["reference"] or prefixes["operator"] or false -- __index operators must reference their tables

        -- Modify functions' access levels
        if type(varValue) == "function" and not prefixes["nonmethod"] then
            nonOverwriteable = true

            if not CONFIG.enableSimpleMode then
                local classMethod = varValue
                ---@type unknown
                varValue = function (t, ...)
                    -- Try to make sure the function is being called correctly
                    if type(t) ~= "table" then
                        error("Syntax error: trying to call method '" .. tostring(varName) .. "' as a non-method function (using . instead of :)\nTo define a non-method function, use the 'nonmethod' modifier in the variable definition.", 2)
                    elseif not (t.__currentAccessLevel) or (not t.__classDefinition) then
                        error("Method is being called on a non-class value (method is not stored inside class table)\nPlease pass in the method's selfness manually: sometable.thisMethod(self) instead of sometable:thisMethod()\n(This error may be a result of incorrect syntax in calling a parent's version of a method from the overriding method)", 2)
                    end

                    -- Prevent weird accessing of protected from other classes
                    if not lass.is(t.__classDefinition.name, className) then
                        error("Trying to call a method from class " .. className .. " on instance of class " .. t.__classDefinition.name .. ", which is not its subclass", 2)
                    end

                    -- Modify access level and run
                    local previousAccessLevel = t.__currentAccessLevel
                    t.__currentAccessLevel = "private_" .. className
                    local returns = {classMethod(t, ...)}
                    t.__currentAccessLevel = previousAccessLevel
                    return unpack(returns)
                end
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
            classDefinition.variables[varName] = {accessLevel = accessLevel, defaultValue = varValue, nonOverwriteable = nonOverwriteable, isReference = isReference, isInstanced = prefixes["instance"]}
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
        fullComposition = {},
        directParents = deepCopy(parents)
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
                        error("Variable clash in inheriting classes - variable '" .. varName .. "' is private and defined in more than one parent (due to a limitation, private variables need to have unique names in the whole inheritance tree)", 3)
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
            classDefinition.variables[varName] = {accessLevel = varValue.accessLevel, defaultValue = value, nonOverwriteable = varValue.nonOverwriteable, isReference = varValue.isReference, isInstanced = varValue.isInstanced}
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
        classDefinition.variables[parentName] = {accessLevel = "protected", isReference = true, nonOverwriteable = true, defaultValue = parentMethods, isInstanced = false}
    end

    -- Add the defined variables for this class
    registerClassVariablesFromBody(className, classBody)
end

local function copyVariablesFromDefinition(classDefinitionVariables, outputTable)
    local variableTable = outputTable or {}
    for varName, varDefinition in pairs(classDefinitionVariables) do
        local varValue = varDefinition.defaultValue
        local copiedValue = varValue
        if varValue == lass.nilValue or varValue == lass.softNil then
            copiedValue = nil
        elseif type(varValue) == "table" and not varDefinition.isReference then
            copiedValue = deepCopy(varValue)
        elseif varDefinition.isInstanced then
            if type(varValue) == "string" then
                copiedValue = lass.new(varValue)
            elseif type(varValue) == "function" then
                copiedValue = varValue()
            end
        end

        variableTable[varName] = copiedValue
    end
    return variableTable
end

local function verifyInstanceAccessLevel(instance, varName, writing)
    if type(varName) == "number" then return end

    local classDefinitionVariables = instance.__classDefinition.variables
    local varDefinition = classDefinitionVariables[varName]

    if not varDefinition then
        if CONFIG.disableUndefined then return end
        if CONFIG.undefinedReturnsNil and not writing then
            return
        end
        local accessWord = writing and "assign" or "read"
        error("Trying to " .. accessWord .. " undefined variable '" .. tostring(varName) .. "'", 3)
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
    if not varDefinition then return end

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
    verifyInstanceAccessLevel(instance, varName, true)
    verifyAllowedOverwrite(instance, varName)
    instance.__variablesRaw[varName] = newValue
end

local function generateClassInstance(className, ...)
    local classDefinition = lass.definedClasses[className]
    local classDefinitionVariables = classDefinition.variables

    local variableTable = copyVariablesFromDefinition(classDefinitionVariables)
    local accessTable = CONFIG.enableSimpleMode and variableTable or {} -- A wrapper in non-simple mode, simply the variable table in simple mode

    -- Instance access metamethods put alongside user defined operators (only applies to non simple mode)
    if not CONFIG.enableSimpleMode then
        local accessIndexMethod = instanceAccessMetatable.__index
        local accessNewIndexMethod = instanceAccessMetatable.__newindex
        local userIndexMethod = variableTable.__index
        local userNewIndexMethod = variableTable.__newindex

        local indexMethod = accessIndexMethod
        local newIndexMethod = accessNewIndexMethod

        -- In non-simple mode, user defined __index and __newindex need special closures

        if userIndexMethod then
            indexMethod = function (instance, varName)
                if instance.__variablesRaw[varName] ~= nil then
                    return accessIndexMethod(instance, varName)
                end

                if type(userIndexMethod) == "table" then return userIndexMethod[varName] end

                if type(userIndexMethod) == "function" then return userIndexMethod(instance, varName) end
            end
        end

        if userNewIndexMethod then
            newIndexMethod = function (instance, varName, newValue)
                if instance.__variablesRaw[varName] ~= nil then
                    return accessNewIndexMethod(instance, varName, newValue)
                end

                if type(userNewIndexMethod) == "table" then
                    userNewIndexMethod[varName] = newValue
                    return
                end

                if type(userNewIndexMethod) == "function" then
                    return userNewIndexMethod(instance, varName, newValue)
                end
            end
        end

        variableTable.__index = indexMethod
        variableTable.__newindex = newIndexMethod
        variableTable.__metatable = "Class metatable - editing is not recommended"
    end

    -- Instance access wrapper
    accessTable.__variablesRaw = variableTable
    accessTable.__classDefinition = classDefinition
    accessTable.__currentAccessLevel = "public"
    setmetatable(accessTable, variableTable)

    -- Call the constructor
    if rawget(accessTable.__variablesRaw, className) then accessTable[className](accessTable, ...) end

    return accessTable
end

---@param childClassName string
---@param parentClassName string
---@return boolean
local function classIs(childClassName, parentClassName)
    if childClassName == parentClassName then return true end

    local class = lass.definedClasses[childClassName]
    if not class then return false end

    return class.fullComposition[parentClassName] or false
end

---@param class any
---@return string|nil
local function extractClassName(class)
    local classType = type(class)
    if classType == "string" then
        return class
    end

    if classType == "table" then
        if class.__classDefinition then
            return class.__classDefinition.name
        end
        if class.__name then
            return class.__name
        end
    end
    return nil
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
    -- -- Adding many classes without table
    -- if type(classBody) == "string" then
    --     self[#self+1] = classBody
    --     return self
    -- end

    if type(classBody) ~= "table" then
        error("Class body isn't a table value (" .. tostring(type(classBody)) .. "). Please use:\nlass 'Class' : from {'ParentA', 'ParentB'} { }", 2)
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
    assertWithLevel(not lass.classIsDefined(className), "Class '" .. className .. "' is already defined")
    classMakingTable.upcomingClassName = className
    return classMakingTable
end

---Creates a new class instance
---@generic T
---@param className `T`
---@param ... unknown
---@return `T`
function lass.new(className, ...)
    local class = lass.classIsDefined(className)

    if not class then
        error("Class '" .. tostring(className) .. "' has not been defined", 2)
    end

    if type(class) == "function" then
        return class(...)
    end

    return generateClassInstance(className, ...)
end

---Defines a new mimic
---@param className string
---@param constructor function
function lass.defineMimic(className, constructor)
    assertType(className, "string", "Class name is of type " .. tostring(type(className)) .. " instead of string")
    assertType(constructor, "function", "Class constructor must be a function")
    assertWithLevel(not lass.classIsDefined(className), "Class '" .. className .. "' is already defined")
    lass.definedMimicClasses[className] = constructor
end

---Checks if the first argument is a subclass of or the same class as the second argument
---@param childClassInstanceOrName table|string
---@param parentClassInstanceOrName table|string
---@return boolean
function lass.is(childClassInstanceOrName, parentClassInstanceOrName)
    local childName = extractClassName(childClassInstanceOrName)
    local parentName = extractClassName(parentClassInstanceOrName)
    if not childName or not parentName then return false end
    return classIs(childName, parentName)
end
lass.implements = lass.is

-- Lists all classes that are a subclass of the input class (bit of an expensive operation)
function lass.allOf(classInstanceOrName)
    local className = extractClassName(classInstanceOrName)
    assert(className ~= "string", "Invalid input class")
    local subclasses = {}
    for name in pairs(lass.definedClasses) do
        if classIs(name, className) and (name ~= className) then
            subclasses[#subclasses+1] = name
        end
    end
    return subclasses
end

-- Gets the class name of an instance
function lass.getClassName(classInstance)
    return classInstance.__classDefinition.name
end

-- Resets all variables in an instance to their default values
-- Only resets variables that have been explicitly defined in the class, variables added to the instance after it was created are ignored.
function lass.reset(classInstance, ...)
    local classDefiniton = classInstance.__classDefinition
    local className = classDefiniton.name
    local classDefinitonVariables = classDefiniton.variables
    copyVariablesFromDefinition(classDefinitonVariables, classInstance.__variablesRaw)
    if rawget(classInstance.__variablesRaw, className) then classInstance[className](classInstance, ...) end
end

-- Ipairs that will iterate over numerical entries in class instances,
-- but still works as regular ipairs for other tables
function lass.ipairs(classInstanceOrTable)
    return ipairs(classInstanceOrTable.__variablesRaw or classInstanceOrTable)
end

return lass