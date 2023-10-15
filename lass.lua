local lass = {}
local lassMetatable = {}
setmetatable(lass, lassMetatable)

-- Some handy local functions to be used within the library ----------------------------------------

local unpack = unpack or table.unpack -- 5.2 compat

local function assertType(value, desiredType, errorMessage, errorLevel)
    if type(value) ~= desiredType then
        error(errorMessage, 1 + (errorLevel or 2))
    end
end

-- The data that makes Lass churn ------------------------------------------------------------------

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

    local parents = self
    print(unpack(self))
end

-- Lass metatable metamethods and such go here -----------------------------------------------------

-- The initial class 'ClassName' call
lassMetatable.__call = function (callingTable, className)
    assertType(className, "string", "Class name is of type " .. tostring(type(className)) .. " instead of string \nTo create a class, use:\nlass 'ClassName' { }")
    return classMakingTable
end

return lass