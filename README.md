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

  getFulfillment = function(self)
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

  getFulfillment = function(self)
    return self.saturation * self.volume
  end
}

local juice = new 'JuiceBottle'
print(juice:getFulfillment()) --> 5
juice.saturation = 1 -- Error: Trying to access private variable 'saturation' in the public scope
```
The variable names remain the same, but we can add access modifiers to them by writing their keyword, followed by two or more underscores. The declaration of `volume` being public is optional - if we don't define otherwise, a variable will be public by default.

There are more things we can mark variables with other than access modifiers, which will be shown further down.

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
