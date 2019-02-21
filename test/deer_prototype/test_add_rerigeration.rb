require_relative '../helpers/minitest_helper'

class TestAddRefrigeration < Minitest::Test

  def test_add_swh_secondary



    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{File.dirname(__FILE__)}/models/GroStore.osm")
    model = translator.loadModel(path)
    model = model.get
    puts "Test building area is #{OpenStudio::convert(model.getBuilding.floorArea,"m^2","ft^2").get.round} ft^2."

    # gather inputs
    template = 'DEER Pre-1975'
    standard = Standard.build(template)

    tz = []
    # tz = model.getTher
    model.getThermalZones.sort.each do |zone|
      tz = zone
    end


    #
    # # add_typical_swh
    typical_swh = standard.model_add_refrigeration_case(model, 'MT_Fish', 6.1, tz)
    #
    # # check the capacity and volume of the water heaters against Table A.1. Water Heating Equipment in PrototypeModelEnhancements_2014_0.pdf
    # non_booster_capacity = 0.0 # combine kitchen and shared
    # non_booster_volume = 0.0 # combine kitchen and shared
    # typical_swh.each do |loop|
    #   # puts loop.name
    #
    #   # find water heater
    #   water_heater = nil
    #   loop.supplyComponents.each do |component|
    #     next if not component.to_WaterHeaterMixed.is_initialized
    #     water_heater = component.to_WaterHeaterMixed.get
    #   end
    #
    #   # check kitchen and shared systems
    #   if loop.name.to_s == "SecondarySchool Shared Service Water Loop"
    #     non_booster_capacity += water_heater.heaterMaximumCapacity.get
    #     non_booster_volume += water_heater.tankVolume.get
    #   elsif loop.name.to_s == "SecondarySchool Kitchen Service Water Loop"
    #     non_booster_capacity += water_heater.heaterMaximumCapacity.get
    #     non_booster_volume += water_heater.tankVolume.get
    #
    #     # get booster water heater and check values
    #     water_heater = nil
    #     loop.demandComponents.each do |component|
    #       next if not component.to_HeatExchangerFluidToFluid.is_initialized
    #       heat_exchanger = component.to_HeatExchangerFluidToFluid.get
    #       booster_loop = heat_exchanger.plantLoop.get
    #
    #       # find and test booster water heater
    #       booster_loop.supplyComponents.each do |component|
    #         next if not component.to_WaterHeaterMixed.is_initialized
    #         booster_water_heater = component.to_WaterHeaterMixed.get
    #         boost_capacity_si = booster_water_heater.heaterMaximumCapacity.get
    #         booster_capacity_ip = OpenStudio::convert(boost_capacity_si,"W","kBtu/hr").get
    #         assert_in_epsilon(19,booster_capacity_ip,0.25) # kBtu/hr
    #       end
    #     end
    #   end
    # end

    # # convert to IP
    # non_booster_capacity_ip = OpenStudio::convert(non_booster_capacity,"W","kBtu/hr").get
    # non_booster_volume_ip = OpenStudio::convert(non_booster_volume,"m^3","gal").get
    #
    # # check results
    # assert(typical_swh.size == 2)
    # # todo - getting size of around 430 vs. expected of 600. Check this on other prototypes. Formula may be valid, fraction flow schedules may be inaccurate
    # assert_in_epsilon(600,non_booster_capacity_ip,0.40) # kBtu/hr
    # assert_in_epsilon(600,non_booster_volume_ip,0.40) # Gallons
    # # todo - add test for peak water, on rough check model seems in ballpark of Table A.1
    #
    # output_dir = File.expand_path('output', File.dirname(__FILE__))
    # FileUtils.mkdir output_dir unless Dir.exist? output_dir
    # puts "saving file to #{output_dir}"
    # model.save("#{output_dir}/test_add_swh_secondary.osm", true)

  end

end
