# Lass
Lass is a sophisticated Lua class library which implements many object oriented features including marking variables as private or protected.

## Basic usage
You can create a class like you would create a table using the `class 'ClassName'` syntax, then instance it with the `new` (or `class.new`) keyword:

```lua
local class = require("lass")
local new = class.new -- Optional, for prettier code

class 'JuiceBottle' {
  volume = 10,
  saturation = 0.5,

  getFulfillment = function(self) -- "self" must always be present in methods before any other arguments
    return self.saturation * self.volume
  end
}

local juice = new 'JuiceBottle'
print(juice:getFulfillment()) --> 5
```

## Access levels
In the example above, we can change the variables before running the method:
```lua
local juice = new 'JuiceBottle'
print(juice:getFulfillment()) --> 5
juice.saturation = 1
print(juice:getFulfillment()) --> 10
```
If we want to prevent this, we can mark the variable as protected or private, like so:
```lua
class 'JuiceBottle' {
  public___volume = 10,
  private__saturation = 0.5,

  public__getFulfillment = function(self)
    return self.saturation * self.volume
  end
}

local juice = new 'JuiceBottle'
print(juice:getFulfillment()) --> 5
juice.saturation = 1 -- Error: Trying to access private variable 'saturation' in the public scope
```
The variable names remain the same, but we can add access modifiers to them by writing their keyword, followed by two or more underscores. The declaration of variables being public is optional - if we don't define otherwise, a variable will be public by default.

There are more things we can mark variables with other than access modifiers, which will be shown further down.

## Nil values
Lass will not allow you to access variables that have not been defined in the class (by default, but this can be configured).
```lua
class 'Pet' {
  name = "Luna"
}
local pet = new 'Pet'
pet.owner = "someone" -- Error: Trying to assign undefined variable 'owner'
```
However, sometimes, we may want to define a variable, but have its default value be nil. We can't set the value to actual nil in the definition, of course, because that is equivalent to not adding it to the table at all. Instead, we can use Lass' nilValue to define it, which will be replaced by actual nil when instancing the class:
```lua
class 'Pet' {
  name = "Luna",
  owner = class.nilValue
}
local pet = new 'Pet' --> pet.owner is nil here
pet.owner = "someone" --> pet.owner gets set to "someone"
```

## Inheritance
You can inherit from a class to get all of its variables and methods. You can also override methods, and still call the previous method in the override.
```lua
class 'Animal' {
  speak = function() print("Hi") end
}

class 'Cat' : from 'Animal' {
  speak = function(self)
    self.Animal.speak(self)
    print("Meow")
  end
}

local cat = new 'Cat'
cat:speak() --> Hi
            --> Meow
```
Note: in addition to the `class 'Child' : from 'Parent'` syntax, the syntax `class 'Child' :D 'Parent'` is also valid. You're welcome.

## Multiple inheritance
Multiple inheritance is also available. When inheriting from two classes that define the same variable, the first class in the list of classes has priority to set the default value of the variable.
```lua
class 'UIElement' {
  x = 100,
  y = 100,
  onClick = function(self) print("Clicked") end
}

class 'Rectangle' {
  x = 250,
  y = 250,
  width = 250,
  height = 250
}

-- Inherit both from UIElement and Rectangle
class 'Button' : from {'UIElement', 'Rectangle'} {
  height = 10 -- Overwrite the height
}

local btn = new 'Button'
print(btn.x, btn.y, btn.width, btn.height) --> 100  100  250  10
```

## Soft nil
Alongside the regular nilValue mentioned above, there is also one that behaves differently in multiple inheritance.
```lua
class 'Projectile' {
  onHit = class.nilValue,
  onTick = class.nilValue
}

class 'ExplodingProjectile' : from 'Projectile' {
  onHit = "explode"
}

class 'FlamingProjectile' : from 'Projectile' {
  onTick = "fire"
}

class 'ExplodingFlamingProjectile' : from {'ExplodingProjectile', 'FlamingProjectile'} {
}

local projectile = new 'ExplodingFlamingProjectile'
print(projectile.onHit)  --> explode
print(projectile.onTick) --> nil
```
Here, ExplodingProjectile has priority to set default values over FlamingProjectile, and its default value for onTick is nil (as set by lass.nilValue), which overwrites what otherwise would have been "fire".

We can set the default value to softNil instead, which will always be overwritten in multiple inheritance by any other value (and if it's not overwritten, the class instance will still have the field defined as nil).
```lua
class 'Projectile' {
  onHit = class.softNil, -- Soft nil instead of hard nil
  onTick = class.softNil
}

class 'ExplodingProjectile' : from 'Projectile' {
  onHit = "explode"
}

class 'FlamingProjectile' : from 'Projectile' {
  onTick = "fire"
}

class 'ExplodingFlamingProjectile' : from {'ExplodingProjectile', 'FlamingProjectile'} {
}

local projectile = new 'ExplodingFlamingProjectile'
print(projectile.onHit)  --> explode
print(projectile.onTick) --> fire
```
Also, instead of class.nilValue, you can write class.hardNil, which is the same thing.

## Constructors
You can define a constructor for a class by making a method with the same name as the class.
```lua
class 'Bullet' {
  velocity = 0,
  angle = 0,
  damage = 0,

  Bullet = function(self, velocity, angle)
    self.velocity = velocity
    self.angle = angle
    self.damage = velocity * 0.5
  end
}

-- 'new' can be called with parameters
local bullet = new ('Bullet', 20, 0)
print(bullet.damage) --> 10
```
Note that, if you don't define a constructor for a class, no constructor function is called. So, if you're inheriting from a class that has a constructor, be sure to also define a consturctor in the new child class that calls it:
```lua
class 'BigBullet' : from 'Bullet' {
  size = "girthy",

  -- Define constructor for BigBullet which calls Bullet's constructor, otherwise Bullet's constructor would never be called
  BigBullet = function(self, velocity, angle)
    self.Bullet(self, velocity, angle)
  end
}
```
There is, however, a shorter way to define the above constructor:
```lua
class 'BigBullet' : from 'Bullet' {
  size = "girthy",

  BigBullet = 'inherit' -- Functionally the same
}
```
By setting the constructor to "inherit", it will simply call the parent constructor (or all parent constructors, in the case of multiple inheritance) with the arguments passed into `new`.

## Instance modifier
As mentioned previously, there are more modifiers than just access modifiers. One of those is the instance modifier. Instance can either be the name of a class, or a function. If it is the name of a class, then the variable will be set to a new instance of that class each time the variable is created (if the class has a constructor, it will be called with no arguments). If it is a function, then upon creation of the variable, that function will be called and the variable will be set to its return value. The function is passed no arguments.

Since there are modifiers we may want to use alongside each other (e.g. an access modifier along with the instance modifier), we can put as many modifiers as we want, seperated by a single underscore.
```lua
class 'Item' {
}

class 'Character' {
  public_instance__heldItem = 'Item',
  public_instance__name = function() return "Laura" end
}

local inst = new 'Character'
print(inst.heldItem) --> table (instance of the Item class)
print(inst.name)     --> Laura
```

## Const and nonmethod
Another available prefix is const. This makes it impossible to overwrite a value and it will always stay the default one (however, inheriting classes can still override it):
```lua
class 'User' {
  const__permissions = "guest"
}

class 'SuperUser' : from 'User' {
  const__permissions = "admin"
}

local user = new 'User'
local superUser = new 'SuperUser'
print(user.permissions)       --> guest
print(superUser.permissions)  --> admin
user.permissions = "infinite" --> Error: Trying to overwrite a constant value
```
All methods in classes are constant. If you want to override this, and assign a function as a non-constant value, you can use the nonmethod modifier:
```lua
class 'Graph' {
  nonmethod__graphFunction = function(x) return 2 * x end
}

local graph = new 'Graph'
print(graph.graphFunction(6)) --> 12
graph.graphFunction = function(x) return x * x + 10 end -- Overwrite the function value, this would error if it was a method
print(graph.graphFunction(6)) --> 46
```
Do note that a method and a nonmethod are different. Firstly, methods always *must* receive their selfness or they will throw an error (`instance:method()` instead of `instance.method()`), where as for a nonmethod function, you decide if you want to pass in the selfness or not, so unlike in methods, the first parameter doesn't need to be `self`.

Secondly, and more importantly, function values do not always have access to protected and private variables. They have the access of wherever you're calling them from - if called directly on the instance, the access level is public. But if a method calls them, they gain private access.

## Reference
By default, tables defined in the class are copied over to each new instance.
```lua
class 'Lang' {
  translations = {
    ["game.sword"] = "Sword",
    ["game.armor"] = "Armor"
  }
}

local en = new 'Lang'
local fr = new 'Lang'
fr.translations["game.sword"] = "Epee"
print(en.translations["game.sword"]) --> Sword
print(fr.translations["game.sword"]) --> Epee
```
But, if you want to assign a table to a variable to be shared across all instances, use the reference modifier:
```lua
class 'Ally' {
  reference__enemies = {}
}

local allyA = new 'Ally'
local allyB = new 'Ally'
table.insert(allyA.enemies, "Slime")
table.insert(allyB.enemies, "Skelly")

local allyC = new 'Ally'
print(allyC.enemies[1], allyC.enemies[2]) --> Slime  Skelly
```
## Operator
You can define any operator that lua metatables support.
```lua
class 'Vector2' {
  x = 0,
  y = 0,

  Vector2 = function(self, x, y)
    self.x = x or self.x
    self.y = y or self.y
  end,

  operator__tostring = function(self)
    return string.format("(%s, %s)", self.x, self.y)
  end,

  operator__add = function(a, b)
    return new ('Vector2', a.x + b.x, a.y + b.y)
  end
}

local vecA = new ('Vector2', 2, 6)
local vecB = new ('Vector2', 4, 10)
print(vecA + vecB) --> (6, 16)
```
## Numeric fields
Instances require you to define a variable in the definition, otherwise you can't access that field in the instance. The exception to this are numeric fields - those are always accessible, even if they weren't explicitly defined, so that you can easily access the full array part of the table. This exception does extend to non-integer values too.
```lua
class 'Array' {
}

local arr = new 'Array'

arr[1] = "one"
arr[2] = "two"
arr[2.5] = "this works too"
print(arr[100]) --> nil
print(arr["str"]) -- Error: Trying to read undefined variable 'str'
```
Do note that Lass instances are a bit different from usual tables, and also different in a different way if you toggle the optimisation config (mentioned later). Because of this, you should use `class.ipairs(inst)` on class instances instead of regular lua ipairs - it works like regular ipairs (even works on regular tables), but will iterate correctly over the array part of the instance. class.pairs() doesn't exist, as it didn't make sense to me to iterate over variables, as well as extra fields Lass adds.

## Lass' functions
```lua
class.is(classChild, classParent)
```
Checks if the first argument is a child class of, or the same class as, the second argument. Arguments can be class instances or class names. You can alternatively also use class.implements(), which is the same thing.

```lua
class.getClassName(classInstance)
```
Returns the name of the class the instance was instanced from.

```lua
class.reset(classInstance, ...)
```
Returns all the class' variables to their default values, and calls the constructor (if present). Extra arguments get passed into the constructor.

```lua
class.ipairs(t)
```
ipairs which also works on class instances.

## Mimic-classes
In Lass, you can define a "mimic class", which simply pretends to be a defined class when using `class.new`. The defineMimic function takes the name of the mimic and a function, which gets passed constructor arguments and should return the new instance.

This can be useful for having a unified `new` keyword for your own classes as well as, for example, [LÖVE](https://love2d.org/) objects:
```lua
class.defineMimic('love.Quad', function(x, y, width, height, sw, sh) return love.graphics.newQuad(x, y, width, height, sw, sh) end)

local quad = new ('love.Quad', 0, 0, 16, 16, 256, 256)
print(quad) --> Quad (assuming this is ran in LÖVE)
```
Mimics also work with the "instance" modifier mentioned earlier.

## Lass config
Lass can be configured to behave differently by setting some specific global variables to true before loading Lass with require.
### Undefined returns nil
`LASSCONFIG_UNDEFINED_RETURNS_NIL`

By default, when accessing a field in a Lass instance that isn't defined in the class, Lass will error. Enabling this config will simply make it return nil instead.

### Disable undefined
`LASSCONFIG_DISABLE_UNDEFINED`

In addition to mirroring the functionality of "undefined returns nil", it also allows *setting* any undefined fields in a class instance.

### Simple mode
`LASSCONFIG_ENABLE_SIMPLE_MODE`

Drastically optimises Lass instances, but disables some Lass features. Described in more detail in the next section.

## Simple mode
Lass is not fast. Checks are in place to give meaningful error messages, and access to protected, private, or undefined variables is forbidden, which means a couple of function calls on every single class variable access (yucky and slow).

By turning on simple mode however, Lass instances will run **as fast as vanilla lua tables** as all the above mentioned checks are removed. This means that in simple mode, the idea of a private or protected variable means nothing. However, code written with simple mode disabled will also work with simple mode enabled. So, it is possible (and advisable) to work with Lass having simple mode off, and right before shipping, enabling it to boost performance (and quite significantly at that).
```lua
LASSCONFIG_ENABLE_SIMPLE_MODE = true
local class = require("lass") -- speedy (this must, of course, be done on the very first lass require)
```

## Lua language server
Lass is made to work well with the VSCode [lua-language-server extension](https://github.com/LuaLS/lua-language-server). `class.new` will define the returned table as an instance of a class with that name.
```lua
---@class Flower
---@field private color string
---@field getColor function

class 'Flower' {
    private__color = "red",
    getColor = function (self)
        return self.color
    end
}

-- 'flower' will be of type Flower here.
local flower = new 'Flower'
```

## A note on metatable protection
A Lass instance is its own metatable, and the metatable of a lass instance can be changed fairly easily. It is quite easy to mess with it, so Lass instances aren't too fit to be accessed by sandboxed environments running external code that shouldn't mess anything up.
