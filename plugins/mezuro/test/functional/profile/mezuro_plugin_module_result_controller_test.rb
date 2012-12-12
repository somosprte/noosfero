require 'test_helper'

require "#{RAILS_ROOT}/plugins/mezuro/test/fixtures/module_result_fixtures"
require "#{RAILS_ROOT}/plugins/mezuro/test/fixtures/metric_result_fixtures"
require "#{RAILS_ROOT}/plugins/mezuro/test/fixtures/date_metric_result_fixtures"
require "#{RAILS_ROOT}/plugins/mezuro/test/fixtures/date_module_result_fixtures"

class MezuroPluginModuleResultControllerTest < ActionController::TestCase

  def setup
    @controller = MezuroPluginModuleResultController.new
    @request = ActionController::TestRequest.new
    @response = ActionController::TestResponse.new
    @profile = fast_create(Community)

    @module_result_hash = ModuleResultFixtures.module_result_hash
    @metric_result_hash = MetricResultFixtures.native_metric_result_hash
    @date_metric_result_hash = DateMetricResultFixtures.date_metric_result_hash
    @date_module_result_hash = DateModuleResultFixtures.date_module_result_hash
  end

  should 'find module result on kalibro' do
    Kalibro::ModuleResult.expects(:request).with(:get_module_result, { :module_result_id => @module_result_hash[:id] }).
        returns({:module_result => @module_result_hash})
    get :module_result, :profile => @profile.identifier, :module_result_id => @module_result_hash[:id]
    assert_equal @module_result_hash[:grade], assigns(:module_result).grade
    assert_response 200
    #TODO assert_select('h5', 'Metric results for: Qt-Calculator (APPLICATION)')
  end

  should 'get metric_results' do
    Kalibro::MetricResult.expects(:request).with(:metric_results_of, { :module_result_id => @module_result_hash[:id] }).
        returns({:metric_result => @metric_result_hash})
    get :metric_results, :profile => @profile.identifier, :module_result_id => @module_result_hash[:id]
    assert_equal @metric_result_hash[:value], assigns(:metric_results).first.value
    assert_equal @module_result_hash[:id], assigns(:module_result_id)
    assert_response 200
    #TODO assert_select('h5', 'Metric results for: Qt-Calculator (APPLICATION)')
  end

  should 'get metric result history' do
    metric_name = @metric_result_hash[:configuration][:metric][:name]
    Kalibro::MetricResult.expects(:request).with(:history_of, { :metric_name => metric_name, :module_result_id => @module_result_hash[:id] }).
        returns({:date_metric_result => @date_metric_result_hash})
    get :metric_result_history, :profile => @profile.identifier, :module_result_id => @module_result_hash[:id], :metric_name => metric_name
    assert_equal @date_metric_result_hash[:date], assigns(:date_metric_results).first.date
    assert_response 200
    #TODO assert_select
  end

  should 'get module result history' do
    Kalibro::ModuleResult.expects(:request).with(:history_of_module, { :module_result_id => @module_result_hash[:id] }).
        returns({:date_module_result => @date_module_result_hash})
    get :module_result_history, :profile => @profile.identifier, :module_result_id => @module_result_hash[:id]
    assert_equal @date_module_result_hash[:date], assigns(:date_module_results).first.date
    assert_response 200
    #TODO assert_select
  end
  
end
