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
  spacetypes = spacetypes_unfilterted.select{|spacetype| spacetype["space_type"] != "- undefined -" }
  puts spacetypes_unfilterted.size
  puts spacetypes.size
  spacetypes.delete_at(25) # issues with religious building (size run)
  spacetypes.delete_at(41) # issues with Aterium (height< 6m) - sch - I - space function (size run)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - e - space function (autozone)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - f - space function (autozone)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - g - space function (autozone)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - h - space function (autozone)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - j - space function (autozone)
  spacetypes.delete_at(37) # issues with Aterium (height< 6m) - sch - k - space function (autozone)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-A-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-B-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-C-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-D-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-E-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-F-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-G-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-H-Space Function (size run error 1)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-I-Space Function (size run error 0)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-j-Space Function (autozone)
  spacetypes.delete_at(37) #Atrium (6 =< height <= 12m)-sch-k-Space Function (autozone)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-A-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-B-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-C-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-D-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-E-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-F-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-G-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-H-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-I-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-J-Space Function (size run 1)
  spacetypes.delete_at(37) #Atrium (height > 12m)-sch-k-Space Function (size run 1)
  spacetypes.delete_at(43) #Audience seating area permanent - religious building-Space Function
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-E-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-F-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-G-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-H-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-I-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-J-Space Function (autozone)
  spacetypes.delete_at(48) #Audience seating area permanent - other-sch-k-Space Function (autozone)
  spacetypes.delete_at(52) #Computer/Server room-sch-B-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-C-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-D-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-E-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-F-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-G-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-H-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-I-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-j-Space Function (size run 2)
  spacetypes.delete_at(52) #Computer/Server room-sch-j-Space Function (size run 2)
  spacetypes.delete_at(53) #Confinement cell-Space Function (size run 2)
  spacetypes.delete_at(53) #Copy/Print room-Space Function (size run 2)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-E-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-F-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-G-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-H-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-I-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-j-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - hospital-sch-k-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-A-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-B-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-C-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-d-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-e-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-f-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-G-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-H-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-I-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-J-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - manufacturing facility-sch-K-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-A-Space Function (autozone break undefined method)
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-B-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-C-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-D-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-E-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-F-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-G-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-H-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-I-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-J-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area - space designed to ANSI/IES RP-28 (and used primarily by residents)-sch-K-Space Function
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-A-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-B-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-C-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-D-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-E-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-F-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-G-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-H-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-I-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-J-Space Function (autozone)
  spacetypes.delete_at(57)#Corridor/Transition area other-sch-K-Space Function (autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-E-Space Function(autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-F-Space Function(autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-G-Space Function(autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-H-Space Function(autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-I-Space Function(size run 2)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-J-Space Function(autozone)
  spacetypes.delete_at(69)#Electrical/Mechanical room-sch-K-Space Function(size run 2)
  spacetypes.delete_at(69)#Emergency vehicle garage-Space Function (autozone)

  intermediatestep = spacetypes.drop(67)

  #raise 'hell'
  #puts "number of non-wildcard spacetypes : #{spacetypes.size}"
  #determine number of floors
  #
  #
  # 

  first_20_spacetypes = intermediatestep[0 .. 4]
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