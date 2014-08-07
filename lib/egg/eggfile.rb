require 'egg/assertion'

##############################################
# Class to represent an Eggfile
class Eggfile
  attr_reader :name, :eggs

  def initialize(name)
    @name = name
    @eggs = []
  end

  def self.read(filepath)
    assert {$currentEggfile == nil}
    name = File.basename(filepath, File.extname(filepath))
    $currentEggfile = Eggfile.new(name)
    load(filepath)
    eggfile = $currentEggfile
    $currentEggfile = nil
    return eggfile
  end

  def addEgg(egg)
    @eggs << egg
  end
end

##############################################
# Eggfile DSL
def egg(name, config)
  egg = Egg.new(name, config)
  $currentEggfile.addEgg(egg)
end
