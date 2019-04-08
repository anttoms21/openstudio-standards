require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'
require 'json'
require 'parallel'
require 'etc'
$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
#require 'Building.hpp'
#LargeOfficespace_type_objects[index]
class GeoTest < CreateDOEPrototypeBuildingTest
  #creating an empty model object
  model = OpenStudio::Model::Model.new()
  standard = Standard.build('NECB2015')

  #puts standard
  #get spacetypes that are not wildcard spacetypes.
  spacetypes_unfilterted = standard.standards_lookup_table_many(table_name: 'space_types').select {|spacetype| spacetype["necb_hvac_system_selection_type"] != "Wildcard" || spacetype['space_type'] != "- undefined -"}
  spacetypes= spacetypes_unfilterted.select{|spacetype| spacetype["necb_hvac_system_selection_type"] != "Wildcard" }
  #spacetypes =  spacetypes_w_sch_I.select{|spacetype| spacetype["exhaust_schedule"] != "NECB-I-FAN" }
  #for some reason the above does not work
  puts spacetypes_unfilterted.size
  puts spacetypes.size
  intermediatestep = spacetypes.drop(20)

  #raise 'hell'
  #puts "number of non-wildcard spacetypes : #{spacetypes.size}"
  #determine number of floors
  #
  #
  #

  first_20_spacetypes = intermediatestep[0 .. 5]
  puts intermediatestep.size
  puts first_20_spacetypes.size
  number_of_floors = first_20_spacetypes.size / 5
  model.getBuilding.setStandardsNumberOfStories(number_of_floors)
  model.getBuilding.setStandardsNumberOfAboveGroundStories(number_of_floors)

  #puts "Number of floors: #{number_of_floors}"
  #Adding geometry and spaces to the object
  #puts "creating a model geometry....."
  BTAP::Geometry::Wizards::create_shape_rectangle(model,
                                                  100.0,
                                                  100.0,
                                                  number_of_floors,
                                                  0,
                                                  3.8,
                                                  1,
                                                  25,
                                                  0.0,
                                                  )
  #puts model.getBuilding.standardsNumberOfStories
  #puts "Created model with #{number_of_floors*5} zones"
  space_type_objects = []
  first_20_spacetypes.each do |spacetype_info|

    spacetype = OpenStudio::Model::SpaceType.new(model)
    spacetype.setStandardsSpaceType(spacetype_info['space_type'])
    spacetype.setStandardsBuildingType(spacetype_info['building_type'])
    spacetype.setName(spacetype_info['building_type'] + " " + spacetype_info['space_type'])
    space_type_objects << spacetype
    #  puts "Created spacetype #{spacetype_info['space_type']} -#{spacetype_info['building_type']}"
  end
  #puts space_type_objects
  #raise 'hell'
  model.getSpaces.each_with_index do |space, index|
    space.setSpaceType(space_type_objects[index])

    space.setName("#{space_type_objects[index].standardsSpaceType.get}-#{space_type_objects[index].standardsBuildingType.get}")
    puts space.name
    #raise 'hell'

    #puts "set space #{space.name} with index #{index} spacetype #{space_type_objects[index].standardsSpaceType.get} -#{space_type_objects[index].standardsSpaceType.get}"
  end
  #raise 'hell'
  standard.model_create_thermal_zones(model)

  BTAP::FileIO::save_osm(model, '/home/osdev/rectangle.osm')

  test_dir = "#{File.dirname(__FILE__)}/models/geo_test"
  if !Dir.exists?(test_dir)
    Dir.mkdir(test_dir)
  end



  standard.model_apply_standard(model: model,
                                epw_file: 'CAN_AB_Fort.McMurray.AP.716890_CWEC2016.epw',
                                sizing_run_dir: test_dir,
                                new_auto_zoner: true)

  run_dir = "#{test_dir}/run_dir"
  if !Dir.exists?(run_dir)
    Dir.mkdir(run_dir)
  end
  standard.model_run_simulation_and_log_errors(model, run_dir)
  #puts space_type_objects
  model_out_path = "#{run_dir}/final.osm"
  model.save(model_out_path, true)

end