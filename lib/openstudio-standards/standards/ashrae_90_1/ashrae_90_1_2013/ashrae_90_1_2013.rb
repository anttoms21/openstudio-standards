# This class holds methods that apply ASHRAE 90.1-2013
# to a given model.
# @ref [References::ASHRAE9012013]
class ASHRAE9012013 < ASHRAE901
  @@template = '90.1-2013' # rubocop:disable Style/ClassVars
  register_standard @@template
  attr_reader :template

  def initialize
    super()
    @template = @@template
    load_standards_database
  end
end
