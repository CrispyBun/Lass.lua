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
You can inherit from a class to get all of its variables. You can also override methods, and still call the previous method in the override.
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
todo
