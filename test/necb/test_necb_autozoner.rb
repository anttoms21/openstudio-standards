require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'


class NECB_Autozone_Tests < MiniTest::Test


  def test_fullserice_resturant()
    model = autozone("FullServiceRestaurant.osm")
  end

  def test_large_hotel()
    model = autozone("LargeHotel.osm")

  end

  def test_primary()
    model = autozone("PrimarySchool.osm")
  end

  def test_secondary()
    model = autozone("SecondarySchool.osm")
  end


  # Test to validate the heat pump performance curves
  def autozone(filename)
    output_folder = "#{File.dirname(__FILE__)}/output/autozoner"
    relative_geometry_path = "/../../lib/openstudio-standards/standards/necb/NECB2011/data/geometry/"
    epw_file = 'CAN_ON_Toronto.Pearson.Intl.AP.716240_CWEC2016.epw'
    FileUtils.rm_rf(output_folder)
    FileUtils.mkdir_p(output_folder)
    template = 'NECB2011'
    climate_zone = 'NECB HDD Method'
    standard = Standard.build(template)
    model = BTAP::FileIO.load_osm("#{File.dirname(__FILE__)}#{relative_geometry_path}#{filename}")
    return false unless standard.validate_initial_model(model)

    #Ensure that the space types names match the space types names in the code.
    return false unless standard.validate_space_types(model)


    #Ensure that the space types names match the space types names in the code.
    return false unless standard.validate_space_types(model)


    #Get rid of any existing Thermostats. We will only use the code schedules.
    model.getThermostatSetpointDualSetpoints(&:remove)

    #Set simulation start day to be consistent.
    model.yearDescription.get.setDayofWeekforStartDay('Sunday')

    #Set climate data.
    standard.model_add_design_days_and_weather_file(model, climate_zone, epw_file) # Standards
    standard.model_add_ground_temperatures(model, nil, climate_zone) # prototype candidate

    #Add Occ sensor schedule adjustments where needed.
    standard.set_occ_sensor_spacetypes(model)

    #Set Loads/Schedules
    standard.model_add_loads(model)

    #Add Infiltration
    standard.model_apply_infiltration_standard(model)

    #Modify_surface_convection_algorithm
    model.getInsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')
    model.getOutsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')

    #Add default constructions
    standard.model_add_constructions(model)
    standard.apply_standard_construction_properties(model)
    standard.auto_zoning(model)

    thermalzone_debug = []
    model.getThermalZones.each do |tz|
      hash = {}
      hash["thermal_zone_name"] = tz.name.to_s
      hash['spaces'] = []
      tz.spaces.each do |space|
        hash['spaces'] << space.name
        thermalzone_debug << hash
      end
    end
    puts JSON.pretty_generate(thermalzone_debug)
  end
end
