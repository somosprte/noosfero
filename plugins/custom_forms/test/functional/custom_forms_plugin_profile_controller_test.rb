require 'test_helper'
require_relative '../../controllers/custom_forms_plugin_profile_controller'

class CustomFormsPluginProfileControllerTest < ActionController::TestCase
  def setup
    @controller = CustomFormsPluginProfileController.new

    @profile = create_user('profile').person
    login_as(@profile.identifier)
    environment = Environment.default
    environment.enable_plugin(CustomFormsPlugin)
  end

  attr_reader :profile

  should 'save submission if fields are ok' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field1 = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form, :mandatory => true)
    field2 = CustomFormsPlugin::TextField.create(:name => 'License', :form => form)

    assert_difference 'CustomFormsPlugin::Submission.count', 1 do
      post :show, :profile => profile.identifier, :id => form.identifier, :submission => {field1.id.to_s => 'Noosfero', field2.id.to_s => 'GPL'}
    end
    refute session[:notice].include?('not saved')
    assert_redirected_to :action => 'show'
  end

  should 'save submission if fields are ok and user is not logged in' do
    logout
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form)

    assert_difference 'CustomFormsPlugin::Submission.count', 1 do
      post :show, :profile => profile.identifier, :id => form.identifier, :author_name => "john", :author_email => 'john@example.com', :submission => {field.id.to_s => 'Noosfero'}
    end
    assert_redirected_to :action => 'show'
  end

  should 'display errors if user is not logged in and author_name is not uniq' do
    logout
    form = CustomFormsPlugin::Form.create(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form)
    submission = CustomFormsPlugin::Submission.create(:form => form, :author_name => "john", :author_email => 'john@example.com')

    assert_no_difference 'CustomFormsPlugin::Submission.count' do
      post :show, :profile => profile.identifier, :id => form.identifier, :author_name => "john", :author_email => 'john@example.com', :submission => {field.id.to_s => 'Noosfero'}
    end
    assert_equal "Submission could not be saved", session[:notice]
    assert_tag :tag => 'div', :attributes => { :class => 'errorExplanation', :id => 'errorExplanation' }
  end

  should 'disable fields if form expired' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :begining => Time.now + 1.day, :identifier => 'free-software')
    form.fields << CustomFormsPlugin::TextField.create(:name => 'Field Name', :form => form, :default_value => "First Field")

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'input', :attributes => {:disabled => 'disabled'}
  end

  should 'show expired message' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :begining => Time.now + 1.day, :identifier => 'free-software')
    form.fields << CustomFormsPlugin::TextField.create(:name => 'Field Name', :form => form, :default_value => "First Field")

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h2', :content => 'Sorry, you can\'t fill this form yet'

    form.begining = Time.now - 2.days
    form.ending = Time.now - 1.days
    form.save

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h2', :content => 'Sorry, you can\'t fill this form anymore'
  end

  should 'show query review page' do

    form = CustomFormsPlugin::Form.create!(:profile => profile,
                                            :name => 'Free Software',
                                            :identifier => 'free')
    submission = CustomFormsPlugin::Submission.create!(:form => form,
                                                       :profile => profile)
    radio_field = CustomFormsPlugin::Field.create!(
      :name => 'What is your favorite food?',
      :form => form,
      :show_as => 'radio'
    )


    CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                           :label => 'rice')
    CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                           :label => 'beans')

    alt = CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                                 :label => 'bread')

    CustomFormsPlugin::Answer.create!(:field => radio_field,
                                      :value => alt.id,
                                      :submission => submission)

    get :review, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h6', :attributes => {:class => 'review_text_align'},
      :content => ' What is your favorite food?'
  end
end
