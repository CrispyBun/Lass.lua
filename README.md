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
