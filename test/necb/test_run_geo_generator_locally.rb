require 'json'
require 'parallel'
require_relative '../helpers/minitest_helper'
class Run_geo_generator
  TestOutputFolder = File.join(File.dirname(__FILE__), 'local_test_output')
  ProcessorsUsed = (Parallel.processor_count * 1 / 2).floor

  def run_geo_test(file)
    did_all_tests_pass = true
    @file = nil
    FileUtils.rm_rf(TestOutputFolder)
    FileUtils.mkpath(TestOutputFolder)

    # load test files from file.
    @file = file
    puts "Running #{@file.size} tests suites in parallel using #{ProcessorsUsed} of available cpus."
    puts "To increase or decrease the ProcessorsUsed, please edit the test/test_run_all_locally.rb file."
    timings_json = Hash.new()
    Parallel.each(@file, in_threads: (ProcessorsUsed), progress: "Progress :") do |test_file|
      file_name = test_file.gsub(/^.+(openstudio-standards\/test\/)/, '')
      timings_json[file_name.to_s] = {}
      timings_json[file_name.to_s]['start'] = Time.now.to_i
      did_all_tests_pass = false unless write_results(Open3.capture3('bundle', 'exec', "ruby '#{test_file}'"), test_file)
      timings_json[file_name.to_s]['end'] = Time.now.to_i
      timings_json[file_name.to_s]['total'] = timings_json[file_name.to_s]['end'] - timings_json[file_name.to_s]['start']
    end
    #Sometimes the runs fail.intermediatestep + intermediatestep[0]
    #Load failed JSON files from folder local_test_output
    unless did_all_tests_pass
      did_all_tests_pass = true
      failed_runs = []
      files = Dir.glob("#{File.dirname(__FILE__)}/local_test_output/*.json").select {|e| File.file? e}
      files.each do |file|
        data = JSON.parse(File.read(file))
        failed_runs << data["test"]
      end
      puts "These files failed in the initial simulation. This may have been due to computer performance issues. Rerunning failed tests.."
      Parallel.each(failed_runs, in_threads: (ProcessorsUsed), progress: "Progress :") do |test_file|
        file_name = test_file.gsub(/^.+(openstudio-standards\/test\/)/, '')
        timings_json[file_name.to_s] = {}
        timings_json[file_name.to_s]['start'] = Time.now.to_i
        did_all_tests_pass = false unless write_results(Open3.capture3('bundle', 'exec', "ruby '#{test_file}'"), test_file)
        timings_json[file_name.to_s]['end'] = Time.now.to_i
        timings_json[file_name.to_s]['total'] = timings_json[file_name.to_s]['end'] - timings_json[file_name.to_s]['start']
      end
    end
    File.open(File.join(File.dirname(__FILE__), 'helpers', 'ci_test_helper', 'timings.json'), 'w') {|file| file.puts(JSON.pretty_generate(timings_json.sort {|a, z| a <=> z}.to_h))}
    return did_all_tests_pass
  end
end

class RunTests < Minitest::Test
  def test_space_types()
    filename = 'test_run_geo_generator_locally.rb'
    #file_in = File.read(filename)
    assert(Run_geo_generator.new.run_geo_test(filename), "Some tests failed please ensure all test pass and tests have been updated to reflect the changes you expect before issuing a pull request")

  end
end