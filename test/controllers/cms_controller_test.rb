require_relative '../test_helper'

class CmsControllerTest < ActionDispatch::IntegrationTest

  include NoosferoTestHelper

  fixtures :environments

  def setup
    @profile = create_user_with_permission('testinguser', 'post_content')
    @user = @profile.user
    logout_rails5
    login_as_rails5 :testinguser
  end

  attr_reader :profile, :user

  should 'list top level documents on index' do
    get cms_index_path(profile.identifier)

    assert_template 'view'
    assert_equal profile, assigns(:profile)
    assert_nil assigns(:article)
    assert assigns(:articles)
  end

  should 'be able to view a particular document' do

    a = profile.articles.build(:name => 'blablabla')
    a.save!

    get view_cms_path(profile.identifier, a)

    assert_template 'view'
    assert_equal a, assigns(:article)
    assert_equal [], assigns(:articles)
  end

  should 'be able to edit a document' do
    a = profile.articles.build(:name => 'test')
    a.save!

    get edit_cms_path(profile.identifier, a)
    assert_template 'edit'
  end

  should 'be able to create a new document' do
    get new_cms_index_path(profile.identifier)
    assert_response :success
    assert_template 'select_article_type'

    # TODO add more types here !!
    [TextArticle ].each do |item|
      assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?type=#{item.name}" }
    end
  end

  should 'present edit screen after choosing article type' do
    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle'}
    assert_template 'edit'

    assert_tag :tag => 'form', :attributes => { :action => "/myprofile/#{profile.identifier}/cms/new", :method => /post/i }, :descendant => { :tag => "input", :attributes => { :type => 'hidden', :value => 'TextArticle' }}
  end

  should 'inherit parents visibility by default' do
    p1 = fast_create(Folder, :published => true, :profile_id => profile.id)
    get new_cms_index_path(profile.identifier), params: { :type => 'TextArticle', :parent_id => p1.id}
    assert_equal assigns(:article).published, p1.published

    p2 = fast_create(Folder, :published => false, :show_to_followers => true, :profile_id => profile.id)
    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => p2.id}
    assert_equal assigns(:article).published, p2.published
    assert_equal assigns(:article).show_to_followers, p2.show_to_followers

    p3 = fast_create(Folder, :published => false, :show_to_followers => false, :profile_id => profile.id)
    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => p3.id}
    assert_equal assigns(:article).published, p3.published
    assert_equal assigns(:article).show_to_followers, p3.show_to_followers
  end

  should 'be able to save a document' do
    assert_difference 'Article.count' do
      post new_cms_index_path(profile.identifier), params: { :type => 'TextArticle', :article => { :name => 'a test article', :body => 'the text of the article ...' }}
    end
  end

  should 'display set as home page link to non folder' do
    a = fast_create(TextArticle, :profile_id => profile.id, :updated_at => DateTime.now)
    Article.stubs(:short_description).returns('bli')
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :content => 'Use as homepage', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/set_home_page/#{a.id}" }
  end

  should 'display set as home page link to folder' do
    a = Folder.new(:name => 'article folder'); profile.articles << a;  a.save!
    Article.stubs(:short_description).returns('bli')
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :content => 'Use as homepage', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/set_home_page/#{a.id}" }
  end

  should 'not display set as home page if disabled in environment' do
    article = profile.articles.create!(:name => 'my new home page')
    folder = Folder.new(:name => 'article folder'); profile.articles << folder;  folder.save!
    Article.stubs(:short_description).returns('bli')
    env = Environment.default; env.enable('cant_change_homepage'); env.save!
    get cms_index_path(profile.identifier)
    !assert_tag :tag => 'a', :content => 'Use as homepage', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/set_home_page/#{article.id}" }
    !assert_tag :tag => 'a', :content => 'Use as homepage', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/set_home_page/#{folder.id}" }
  end

  should 'display the profile homepage if can change homepage' do
    env = Environment.default; env.disable('cant_change_homepage')
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'i', :attributes => { :class => "fa fa-undo"}
  end

  should 'display the profile homepage if logged user is an environment admin' do
    env = Environment.default; env.enable('cant_change_homepage'); env.save!
    env.add_admin(profile)
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'i', :attributes => { :class => "fa fa-undo"}
  end

  should 'not display the profile homepage if cannot change homepage' do
    env = Environment.default; env.enable('cant_change_homepage')
    get cms_index_path(profile.identifier)
    !assert_tag :tag => 'i', :attributes => { :class => "fa fa-undo"}
  end

  should 'not allow profile homepage changes if cannot change homepage' do
    env = Environment.default; env.enable('cant_change_homepage')
    a = profile.articles.create!(:name => 'my new home page')
    post set_home_page_cms_index_path(profile.identifier), params: {:id => a.id}
    assert_response 403
  end

  should 'be able to set home page' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!

    assert_not_equal a, profile.home_page

    post set_home_page_cms_index_path(profile.identifier), params: {:id => a.id}

    profile.reload
    assert_equal a, profile.home_page
    assert_match /configured/, session[:notice]
  end

  should 'be able to set home page even when profile description is invalid' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!

    profile.description = 'a' * 600
    profile.save(:validate => false)

    refute profile.valid?
    assert_not_equal a, profile.home_page

    post set_home_page_cms_index_path(profile.identifier), params: {:id => a.id}

    profile.reload
    assert_equal a, profile.home_page
  end

  should 'redirect to previous page after setting home page' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!

    post set_home_page_cms_index_path(profile.identifier), params: {:id => a.id},  headers: { "HTTP_REFERER" => "/random_page" }
    assert_redirected_to '/random_page'
  end

  should 'redirect to profile homepage after setting home page if no referer' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!

    post set_home_page_cms_index_path(profile.identifier), params: {:id => a.id}
    assert_redirected_to profile.url
  end

  should 'be able to reset home page' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!

    profile.home_page = a
    profile.save!

    post set_home_page_cms_index_path(profile.identifier), params: {:id => nil}

    profile.reload
    assert_nil profile.home_page
    assert_match /reseted/, session[:notice]
  end

  should 'display default home page' do
    profile.home_page = nil
    profile.save!
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'tr', :attributes => { :class => "textarticle", :title => "homepage" }
  end

  should 'display article as home page' do
    a = profile.articles.build(:name => 'my new home page')
    a.save!
    profile.home_page = a
    profile.save!
    Article.stubs(:short_description).returns('short description')
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'tr', :attributes => { :title => "my new home page" }, :descendant => { :tag => 'i', :attributes => { :class => "fa fa-home" } }
  end

  should 'set last_changed_by when creating article' do
    logout_rails5
    login_as_rails5(profile.identifier)

    post new_cms_index_path(profile.identifier, params: {:type => 'TextArticle', :article => { :name => 'changed by me', :body => 'content ...' }})

    a = profile.articles.find_by(path: 'changed-by-me')
    assert_not_nil a
    assert_equal profile, a.last_changed_by
  end

  should 'set last_changed_by when updating article' do
    other_person = create_user('otherperson').person

    a = profile.articles.build(:name => 'my article')
    a.last_changed_by = other_person
    a.save!

    logout_rails5
    login_as_rails5(profile.identifier)
    post edit_cms_path(profile.identifier, a), params: {:article => { :body => 'new content for this article' }}

    a.reload

    assert_equal profile, a.last_changed_by
  end

  should 'be able to set label to article image' do
    logout_rails5
    login_as_rails5(profile.identifier)
    post new_cms_index_path(profile.identifier), params: {:type => TextArticle.name, :article => {
           :name => 'adding-image-label',
           :image_builder => {
             :uploaded_data => fixture_file_upload('/files/tux.png', 'image/png'),
             :label => 'test-label'
           }
         }}
     a = Article.last
     assert_equal a.image.label, 'test-label'
  end

  should 'edit by using the correct template to display the editor depending on the mime-type' do
    a = profile.articles.build(:name => 'test document')
    a.save!
    assert_equal 'text/html', a.mime_type

    get edit_cms_path(profile.identifier, a)
    assert_response :success
    assert_template 'edit'
  end

  should 'convert mime-types to action names' do
    obj = mock
    obj.extend(CmsHelper)

    assert_equal 'text_html', obj.mime_type_to_action_name('text/html')
    assert_equal 'image', obj.mime_type_to_action_name('image')
    assert_equal 'application_xnoosferosomething', obj.mime_type_to_action_name('application/x-noosfero-something')
  end

  should 'be able to remove article' do
    a = profile.articles.build(:name => 'my-article')
    a.save!
    assert_difference 'Article.count', -1 do
      post destroy_cms_path(profile.identifier, a)
    end
  end

  should 'redirect to cms after remove article from content management' do
    a = profile.articles.build(:name => 'my-article')
    a.save!
    post destroy_cms_path(profile.identifier, a), headers: { "HTTP_REFERER" => "http://test.host/myprofile/testinguser/cms" }
    assert_redirected_to :controller => 'cms', :action => 'index', :profile => profile.identifier
  end

  should 'redirect to blog after remove article from content viewer' do
    a = profile.articles.build(:name => 'my-article')
    a.save!
    @request.env['HTTP_REFERER'] = 'http://colivre.net/testinguser'
    post destroy_cms_path(profile.identifier, a)
    assert_redirected_to :controller => 'content_viewer', :action => 'view_page', :profile => profile.identifier, :page => [], :host => profile.environment.default_hostname
  end

  should 'be able to acess Rss feed creation page' do
    logout_rails5  
    login_as_rails5(profile.identifier)
    assert_nothing_raised do
      post new_cms_index_path(profile.identifier), params: {:type => "RssFeed"}
    end
    assert_response 200
  end

  should 'be able to create a RSS feed' do
    logout_rails5  
    login_as_rails5(profile.identifier)
    assert_difference 'RssFeed.count' do
      post new_cms_index_path(profile.identifier), params: {:type => RssFeed.name, :article => { :name => 'new-feed', :limit => 15, :include => 'all' }}
      assert_response :redirect
    end
  end

  should 'be able to update a RSS feed' do
    logout_rails5	  
    login_as_rails5(profile.identifier)
    feed = create(RssFeed, :name => 'myfeed', :limit => 5, :include => 'all', :profile_id => profile.id)
    post edit_cms_path(profile.identifier, feed), params: {:article => { :limit => 77, :include => 'parent_and_children' }}
    assert_response :redirect

    updated = RssFeed.find(feed.id)
    assert_equal 77, updated.limit
    assert_equal 'parent_and_children', updated.include
  end

  should 'be able to upload a file' do
    assert_difference 'UploadedFile.count' do
      post new_cms_index_path(profile.identifier), params:{:type => UploadedFile.name, :article => { :uploaded_data => fixture_file_upload('/files/test.txt', 'text/plain')}}
    end
    assert_not_nil profile.articles.find_by(path: 'test')
    assigns(:article).destroy
  end

  should 'be able to update an uploaded file' do
    post new_cms_index_path(profile.identifier), params:{:type => UploadedFile.name, :article => { :uploaded_data => fixture_file_upload('/files/test.txt', 'text/plain')}}

    file = profile.articles.find_by(path: 'test')
    assert_equal 'test', file.name

    post edit_cms_path(profile.identifier, file), params: {:article => { :uploaded_data => fixture_file_upload('/files/test_another.txt', 'text/plain')}}

    assert_equal 2, file.versions.size
  end

  should 'be able to upload an image' do
    assert_difference 'UploadedFile.count' do
      post new_cms_index_path(profile.identifier), params: {:type => UploadedFile.name, :article => { :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')}}
    end
  end

  should 'be able to upload an image with crop' do
    assert_difference 'UploadedFile.count' do
      post new_cms_index_path(profile.identifier), params: {:type => UploadedFile.name, :article => { :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'),
                         :crop_x => 0,
                         :crop_y => 0,
                         :crop_w => 25,
                         :crop_h => 25 }}
    end
  end

  should 'be able to edit an image label' do
    image = create(Image, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'), :label => 'test_label')
    article = fast_create(Article, :profile_id => profile.id, :name => 'test_label_article', :body => 'test_content')
    article.image = image
    article.save
    assert_not_nil article
    assert_not_nil article.image
    assert_equal 'test_label', article.image.label

    post edit_cms_path(profile.identifier, article),  params: {:article => {:image_builder => { :label => 'test_label_modified'}}}
    article.reload
    assert_equal 'test_label_modified', article.image.label
  end

   should 'be able to upload more than one file at once' do
    assert_difference 'UploadedFile.count', 2 do
      post upload_files_cms_index_path(profile.identifier), params: {:uploaded_files => { '0' => { :file => fixture_file_upload('/files/test.txt', 'text/plain')},
                                '1' => { :file => fixture_file_upload('/files/rails.png', 'text/plain')}}}
    end
    assert_not_nil profile.articles.find_by(path: 'test')
    assert_not_nil profile.articles.find_by(path: 'rails')
  end

  should 'upload to right folder' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    post upload_files_cms_index_path(profile.identifier), params: {:parent_id => f.id,
         :uploaded_files => { '0' => { 'file' => fixture_file_upload('/files/test.txt') } }}
    f.reload

    assert_not_nil f.children[0]
    assert_equal 'test', f.children[0].name
  end

  should 'set author of uploaded files' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    post upload_files_cms_index_path(profile.identifier), params: {:parent_id => f.id,
         :uploaded_files => { '0' => { 'file' => fixture_file_upload('/files/test.txt')},
                              '1' => { 'file' => fixture_file_upload('/files/test_another.txt')}}}

    uf = profile.articles.find_by(name: 'test')
    assert_equal profile, uf.author
  end

  should 'display destination folder of files when uploading file in root folder' do
    get upload_files_cms_index_path(profile.identifier)

    assert_tag :tag => 'select', :descendant => { :tag => 'option', :content => /#{profile.identifier}/ }
  end

  should 'not display destination folder of files when uploading file in folder different than root' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    get upload_files_cms_index_path(profile.identifier), params: {:parent_id => f.id}

    !assert_tag :tag => 'select', :descendant => { :tag => 'option', :content => /#{profile.identifier}/ }
  end

  should 'not crash on empty file' do
    assert_nothing_raised do
      post upload_files_cms_index_path(profile.identifier), params: {
	      :uploaded_files => { "0" => { :file => fixture_file_upload('/files/test.txt', 'text/plain')},
                                "1" => { :file => "" }}}
    end
    assert_not_nil profile.articles.find_by(path: 'test')
  end

  should 'not crash when parent_id is blank' do
    assert_nothing_raised do
      post upload_files_cms_index_path(profile.identifier), params: { :parent_id => '',
           :uploaded_files => { "0" => { :file => fixture_file_upload('/files/test.txt', 'text/plain')},
                                "1" => { :file => "" }}}
    end
    assert_not_nil profile.articles.find_by(path: 'test')
  end

  should 'redirect to cms after uploading files' do
    post upload_files_cms_index_path(profile.identifier), params: {
         :uploaded_files => { "0" => { :file => fixture_file_upload('/files/test.txt', 'text/plain')}}}
    assert_redirected_to :action => 'index'
  end

  should 'redirect to folder after uploading files' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    post upload_files_cms_index_path(profile.identifier), params: { :parent_id => f.id,
         :uploaded_files => { "0" => { :file => fixture_file_upload('/files/test.txt', 'text/plain')}}}
    assert_redirected_to :action => 'view', :id => f.id
  end

  should 'display error message when file has more than max size' do
    UploadedFile.any_instance.stubs(:size).returns(UploadedFile.attachment_options[:max_size] + 1024)
    post upload_files_cms_index_path(profile.identifier), params: { :uploaded_files => { "0" => { :file => fixture_file_upload('/files/rails.png', 'image/png')}}}
    assert assigns(:uploaded_files).first.size > UploadedFile.attachment_options[:max_size]
    assert_tag :tag => 'div', :attributes => { :class => 'errorExplanation', :id => 'errorExplanation' }
  end

  should 'not display error message when file has less than max size' do
    UploadedFile.any_instance.stubs(:size).returns(UploadedFile.attachment_options[:max_size] - 1024)
    post upload_files_cms_index_path(profile.identifier), params: {:uploaded_files => { "0" => { :file => fixture_file_upload('/files/rails.png', 'image/png')}}}

    !assert_tag :tag => 'div', :attributes => { :class => 'errorExplanation', :id => 'errorExplanation' }
  end

  should 'not redirect when some file has errors' do
    UploadedFile.any_instance.stubs(:size).returns(UploadedFile.attachment_options[:max_size] + 1024)
    post upload_files_cms_index_path(profile.identifier), params: {:uploaded_files => { "0" => { :file => fixture_file_upload('/files/rails.png', 'image/png')}}}
    assert_response :success
    assert_template 'upload_files'
  end

  should 'offer to create new content' do
    get cms_index_path(profile.identifier)
    assert_response :success
    assert_template 'view'
    assert_tag :tag => 'a', :attributes => { :title => 'New content', :href => "/myprofile/#{profile.identifier}/cms/new?cms=true"}
  end

  should 'offer to create new content when viewing an article' do
    article = fast_create(Article, :profile_id => profile.id)
    get view_cms_path(profile.identifier, article)
    assert_response :success
    assert_template 'view'
    assert_tag :tag => 'a', :attributes => { :title => 'New content', :href => "/myprofile/#{profile.identifier}/cms/new?cms=true&parent_id=#{article.id}"}
  end

  should 'offer to create children' do
    Article.any_instance.stubs(:allow_children?).returns(true)

    article = Article.new(:name => 'test')
    article.profile = profile
    article.save!

    get new_cms_index_path(profile.identifier), params: {:parent_id => article.id, :cms => true}
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?parent_id=#{article.id}&type=TextArticle"}
  end

  should 'not offer to create children if article does not accept them' do
    Article.any_instance.stubs(:allow_children?).returns(false)

    article = Article.new(:name => 'test')
    article.profile = profile
    article.save!

    get view_cms_path(profile.identifier, article)
    assert_response :success
    assert_template 'view'
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?parent_id=#{article.id}"}
  end

  should 'refuse to create children of non-child articles' do
    Article.any_instance.stubs(:allow_children?).returns(false)

    article = Article.new(:name => 'test')
    article.profile = profile
    article.save!

    assert_no_difference 'UploadedFile.count' do
      assert_raise ArgumentError do
        post new_cms_index_path(profile.identifier), params: {:type => UploadedFile.name, :parent_id => article.id, :article => { :uploaded_data => fixture_file_upload('/files/test.txt', 'text/plain')}}
      end
    end
  end

  should 'display max size of uploaded file' do
    extend ActionView::Helpers::NumberHelper
    get upload_files_cms_index_path(profile.identifier)
    max_size = number_to_human_size(UploadedFile.max_size)
    assert_tag :tag => 'h3', :content => /max size #{max_size}/
  end

  should 'display link for selecting top categories' do
    env = Environment.default
    top = env.categories.build(:display_in_menu => true, :name => 'Top-Level category'); top.save!
    top2 = env.categories.build(:display_in_menu => true, :name => 'Top-Level category 2'); top2.save!
    c1  = env.categories.build(:display_in_menu => true, :name => "Test category 1", :parent_id => top.id); c1.save!
    c2  = env.categories.build(:display_in_menu => true, :name => "Test category 2", :parent_id => top.id); c2.save!
    c3  = env.categories.build(:display_in_menu => true, :name => "Test Category 3", :parent_id => top.id); c3.save!

    article = Article.new(:name => 'test')
    article.profile = profile
    article.save!

    get edit_cms_path(profile.identifier, article)

    [top, top2].each do |item|
      assert_tag :tag => 'a', :attributes => { :id => "select-category-#{item.id}-link" }
    end
  end

  should 'be able to associate articles with categories' do
    env = Environment.default
    c1 = env.categories.build(:name => "Test category 1"); c1.save!
    c2 = env.categories.build(:name => "Test category 2"); c2.save!
    c3 = env.categories.build(:name => "Test Category 3"); c3.save!

    # post is in c1 and c3
    post new_cms_index_path(profile.identifier), params: {:type => TextArticle.name, :article => { :name => 'adding-categories-test', :category_ids => [ c1.id, c3.id] }}

    saved = profile.articles.find_by(name: 'adding-categories-test')
    assert_includes saved.categories, c1
    assert_not_includes saved.categories, c2
    assert_includes saved.categories, c3
  end

  should 'not associate articles with category twice' do
    env = Environment.default
    c1 = env.categories.build(:name => "Test category 1"); c1.save!
    c2 = env.categories.build(:name => "Test category 2"); c2.save!
    c3 = env.categories.build(:name => "Test Category 3"); c3.save!

    # post is in c1, c3 and c3
    post new_cms_index_path(profile.identifier), params: {:type => TextArticle.name, :article => { :name => 'adding-categories-test', :category_ids => [ c1.id, c3.id, c3.id ] }}

    saved = profile.articles.find_by(name: 'adding-categories-test')
    assert_equivalent [c1, c3], saved.categories.all
  end

  should 'filter html with white_list from tiny mce article name' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => "<strong>test</strong>", :body => 'the text of the article ...' }}
    assert_equal "<strong>test</strong>", assigns(:article).name
  end

  should 'filter html with white_list from tiny mce article abstract' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'article', :abstract => "<script>alert('text')</script> article", :body => 'the text of the article ...' }}
    assert_equal "alert('text') article", assigns(:article).abstract
  end

  should 'filter html with white_list from tiny mce article body' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'article', :abstract => 'abstract', :body => "the <script>alert('text')</script> of article ..." }}
    assert_equal "the alert('text') of article ...", assigns(:article).body
  end

  should 'not filter html tags permitted from tiny mce article body' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'article', :abstract => 'abstract', :body => "<b>the</b> <script>alert('text')</script> <strong>of</strong> article ..." }}
    assert_equal "<b>the</b> alert('text') <strong>of</strong> article ...", assigns(:article).body
  end

  should 'sanitize tags' do
    post new_cms_index_path(profile.identifier), params: { :type => 'TextArticle', :article => { :name => 'a test article', :body => 'the text of the article ...', :tag_list => 'tag1, <strong>tag2</strong>' }}
    assert_sanitized assigns(:article).tag_list.join(', ')
  end

  should 'keep informed parent_id' do
    fast_create(:blog, :name=>"Sample blog", :profile_id=>@profile.id)

    profile.home_page = profile.blogs.find_by name: "Sample blog"
    profile.save!

    get new_cms_index_path(@profile.identifier), params: {:parent_id => profile.home_page.id, :type => 'TextArticle'}
    assert_tag :tag => 'select',
               :attributes => { :id => 'article_parent_id' },
               :child => {
                  :tag => "option", :attributes => {:value => profile.home_page.id, :selected => "selected"}
               }
  end

  should 'list folders before others' do
    profile.articles.destroy_all

    folder1 = fast_create(Folder, :profile_id => profile.id, :updated_at => DateTime.now - 1.hour)
    article = fast_create(TextArticle, :profile_id => profile.id, :updated_at => DateTime.now)
    folder2 = fast_create(Folder, :profile_id => profile.id, :updated_at => DateTime.now + 1.hour)

    get cms_index_path(profile.identifier)
    assert_equal [folder2, folder1, article], assigns(:articles)
  end

  should 'list folders inside another folder' do
    profile.articles.destroy_all

    parent = fast_create(Folder, :profile_id => profile.id)
    folder1 = fast_create(Folder, :parent_id => parent.id, :profile_id => profile.id, :updated_at => DateTime.now - 1.hour)
    article = fast_create(TextArticle, :parent_id => parent.id, :profile_id => profile.id, :updated_at => DateTime.now)
    folder2 = fast_create(Folder, :parent_id => parent.id, :profile_id => profile.id, :updated_at => DateTime.now + 1.hour)

    get view_cms_path(profile.identifier, parent)
    assert_equal [folder2, folder1, article], assigns(:articles)
  end

  should 'offer to create new top-level folder' do
    get new_cms_index_path(profile.identifier), params: {:cms => true}
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?type=Folder"}
  end

  should 'offer to create sub-folder' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    get new_cms_index_path(profile.identifier), params: {:parent_id => f.id, :cms => true}

    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?parent_id=#{f.id}&type=Folder" }
  end

  should 'redirect to article after creating top-level article' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'top-level-article' }}

    assert_redirected_to @profile.articles.find_by(name: 'top-level-article').url
  end

  should 'redirect to article after creating article inside a folder' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => f.id, :article => { :name => 'article-inside-folder' }}

    assert_redirected_to @profile.articles.find_by(name: 'article-inside-folder').url
  end

  should 'redirect back to article after editing top-level article' do
    f = Folder.new(:name => 'top-level-article'); profile.articles << f; f.save!
    post edit_cms_path(profile.identifier, f), params: {:article => {:access => '0' }}
    assert_redirected_to @profile.articles.find_by(name: 'top-level-article').url
  end

  should 'redirect back to article after editing article inside a folder' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    a = create(TextArticle, :parent => f, :name => 'article-inside-folder', :profile_id => profile.id)

    post edit_cms_path(profile.identifier, a), params: { :article => {:access => '0' } }
    assert_redirected_to @profile.articles.find_by(name: 'article-inside-folder').url
  end

  should 'point back to index when cancelling creation of top-level article' do
    get new_cms_index_path(profile.identifier), params: {:type => 'Folder'}
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms" }, :descendant => { :content => /Cancel/ }
  end

  should 'point back to index when cancelling edition of top-level article' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    get edit_cms_path(profile.identifier, f)

    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms" }, :descendant => { :content => /Cancel/ }
  end

  should 'point back to folder when cancelling creation of an article inside it' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    get new_cms_index_path(profile.identifier), params: {:type => 'Folder', :parent_id => f.id}

    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/view/#{f.id}" }, :descendant => { :content => /Cancel/ }
  end

  should 'point back to folder when cancelling edition of an article inside it' do
    f = Folder.new(:name => 'f'); profile.articles << f; f.save!
    a = create(TextArticle, :name => 'test', :parent => f, :profile_id => profile.id)
    get edit_cms_path(profile.identifier, a)

    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/view/#{f.id}" }, :descendant => { :content => /Cancel/ }
  end

  should 'link to page explaining about categorization' do
    get edit_cms_path(profile.identifier, profile.home_page)
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/why_categorize" }
  end

  should 'present popup' do
    get why_categorize_cms_index_path(profile.identifier)
    assert_template 'why_categorize'
    !assert_tag :tag => 'body'
  end

  should 'display OK (close) button on why_categorize popup' do
    get why_categorize_cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :attributes => {  :class => 'button icon-cancel with-text  modal-close',
                                              :title => 'Close' } # modal close button
  end

  should 'display slider options' do
    get edit_cms_path(profile.identifier, profile.home_page)
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'article[access]', :id => 'post-access', :value => '0'}
  end

 #should "display properly a private articles' status" do
 #  article = create(Article, :profile => profile, :name => 'test', :published => true)

 #  get edit_cms_path(profile.identifier, article)
 #  assert_select 'input#article_published_true[name=?][type="radio"]', 'article[published]'
 #  assert_select 'input#article_published_false[name=?][type="radio"]', 'article[published]' do |elements|
 #    assert elements.length > 0
 #    elements.each do |element|
 #      assert element["checked"]
 #    end
 #  end
 #end

  should "marks a article like archived" do
    article = create(Article, :profile => profile, :name => 'test', :published => true, :archived => false)

    post edit_cms_path(profile.identifier, article), params: {:article => {:archived => true}}
    get edit_cms_path(profile.identifier, article)
    assert_tag :tag => 'input', :attributes => { :type => 'checkbox', :name => 'article[archived]', :id => 'article_archived', :checked => 'checked' }

  end

  should "try add children into archived folders" do
    folder = create(Folder, :profile => profile, :name => 'test', :published => true, :archived => false)
    article_child = create(Article, :profile => profile, :name => 'test child', :parent_id => folder.id, :published => true, :archived => false)

    get edit_cms_path(profile.identifier, folder)
    assert_tag :tag => 'input', :attributes => { :type => 'checkbox', :name => 'article[archived]', :id => 'article_archived' }

    post edit_cms_path(profile.identifier, folder), params: {:article => {:archived => true}}

    get edit_cms_path(profile.identifier, article_child.id)
    assert_tag :tag => 'div', :attributes => { :class => 'text-warning'}

    err = assert_raises ActiveRecord::RecordInvalid do
      another_article_child = create(Article, :profile => profile, :name => 'other test child', :parent_id => folder.id, :published => true, :archived => false)
    end
    assert_match 'Parent folder is archived', err.message

  end

  should 'be able to add image with alignment' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'image-alignment', :body => "the text of the article with image <img src='#' align='right'/> right align..." }}
    saved = TextArticle.find_by(name: 'image-alignment')
    assert_match /<img.*src="#".*>/, saved.body
    assert_match /<img.*align="right".*>/, saved.body
  end

  should 'be able to add image with alignment when textile' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'image-alignment', :body => "the text of the article with image <img src='#' align='right'/> right align..." }}
    saved = TextArticle.find_by(name: 'image-alignment')
    assert_match /align="right"/, saved.body
  end

  should 'be able to create a new event document' do
    get new_cms_index_path(profile.identifier), params: {:type => 'Event'}
    assert_response :success
    assert_tag :input, :attributes => { :id => 'article_link' }
  end

  should 'update categories' do
    env = Environment.default
    top = env.categories.create!(:display_in_menu => true, :name => 'Top-Level category')
    c1  = env.categories.create!(:display_in_menu => true, :name => "Test category 1", :parent_id => top.id)
    c2  = env.categories.create!(:display_in_menu => true, :name => "Test category 2", :parent_id => top.id)
    get update_categories_cms_index_path(profile.identifier), params: {:category_id => top.id}, xhr: true
    assert_template 'shared/update_categories'
    assert_equal top, assigns(:current_category)
    assert_equivalent [c1, c2], assigns(:categories)
  end

  should 'record when coming from public view on edit' do
    article = @profile.articles.create!(:name => 'myarticle')

    get edit_cms_path('testinguser', article)
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => /^https?:\/\/colivre.net\/testinguser\/myarticle/ }
  end

  should 'detect when coming from home page' do
    get edit_cms_path('testinguser', @profile.home_page)
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => @request.referer }
  end

  should 'go back to public view when saving coming from there' do
    article = @profile.articles.create!(:name => 'myarticle')

    post edit_cms_path('testinguser', article), params: { :back_to => 'public_view', :article => {:access => 1}}
    assert_redirected_to article.url
  end

  should 'record as coming from public view when creating article' do
    get new_cms_index_path('testinguser'), params: {:type => 'TextArticle'}
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => 'http://colivre.net/testinguser/testingusers-home-page' }
  end

  should 'go to public view after creating article coming from there' do
    post new_cms_index_path('testinguser'), params: {:type => 'TextArticle', :back_to => 'public_view', :article => { :name => 'new-article-from-public-view' }}
    assert_response :redirect
    assert_redirected_to @profile.articles.find_by(name: 'new-article-from-public-view').url
  end

  should 'keep the back_to hint in unsuccessful saves' do
    post new_cms_index_path('testinguser'), params: {:type => 'TextArticle', :back_to => 'public_view', :article => { }}
    assert_response :success
    assert_tag :tag => "input", :attributes => { :type => 'hidden', :name => 'back_to', :value => 'public_view' }
  end

  should 'create a private article child of private folder' do
    folder = build(Folder, :name => 'my intranet', :published => false); profile.articles << folder; folder.save!

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => folder.id, :article => { :name => 'new-private-article'}}
    folder.reload

    refute assigns(:article).published?
    assert_equal 'new-private-article', folder.children[0].name
    refute folder.children[0].published?
  end

  should 'publish the article in the selected community if community is not moderated' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => false)
    c.affiliate(profile, Profile::Roles.all_roles(c.environment.id))
    article = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')

    assert_difference 'article.class.count' do
      post publish_on_communities_cms_path(profile.identifier, article), params: {:q => c.id.to_s}
      assert_includes  assigns(:marked_groups), c
    end
  end

  should 'create a new event after publishing an event' do
    c = fast_create(Community)
    c.affiliate(profile, Profile::Roles.all_roles(c.environment.id))
    a = Event.create!(:name => "Some event", :profile => profile, :start_date => Date.today)

    assert_difference 'Event.count' do
      post publish_on_communities_cms_path(profile.identifier, a), params: {:q => c.id.to_s}
    end
  end

  should 'not crash if no community is selected' do
    article = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')

    assert_nothing_raised do
      post publish_on_communities_cms_path(profile.identifier, article), params: { :q => '', :back_to => '/'}
    end
  end

  should "not crash if there is a post and no portal community defined" do
    Environment.any_instance.stubs(:portal_community).returns(nil)
    article = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')
    assert_nothing_raised do
      post publish_on_portal_community_cms_path(profile.identifier, article), params: {:name => article.name}
    end
  end

  should 'publish the article on portal community if it is not moderated' do
    portal_community = fast_create(Community)
    portal_community.moderated_articles = false
    portal_community.save
    environment = portal_community.environment
    environment.portal_community = portal_community
    environment.enable('use_portal_community')
    environment.save!
    article = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')

    assert_difference 'article.class.count' do
      post publish_on_portal_community_cms_path(profile.identifier, article), params: {:name => article.name}
    end
  end

  should 'create a task for article approval if community is moderated' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => true)
    c.affiliate(profile, Profile::Roles.all_roles(c.environment.id))
    a = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')

    assert_no_difference 'a.class.count' do
      assert_difference 'ApproveArticle.count' do
        assert_difference 'c.tasks.count' do
          post publish_on_communities_cms_path(profile.identifier, a), params: {:q => c.id.to_s}
          assert_includes assigns(:marked_groups), c
        end
      end
    end
  end

  should 'create a task for article approval if portal community is moderated' do
    portal_community = fast_create(Community)
    portal_community.moderated_articles = true
    portal_community.save!
    environment = portal_community.environment
    environment.portal_community = portal_community
    environment.enable('use_portal_community')
    environment.save!
    article = profile.articles.create!(:name => 'something intresting', :body => 'ruby on rails')

    assert_no_difference 'article.class.count' do
      assert_difference 'ApproveArticle.count' do
        assert_difference 'portal_community.tasks.count' do
          post publish_on_portal_community_cms_path(profile.identifier, article), params: {:name => article.name}
        end
      end
    end
  end

  should 'display categories if environment disable_categories disabled' do
    Environment.any_instance.stubs(:enabled?).with(anything).returns(false)
    a = profile.articles.create!(:name => 'test')
    get edit_cms_path(profile.identifier, a)
    assert_tag :tag => 'div', :descendant => { :tag => 'h4', :content => 'Categorize your article ' }
  end

  should 'not display categories if environment disable_categories enabled' do
    Environment.any_instance.stubs(:enabled?).with(anything).returns(true)
    a = profile.articles.create!(:name => 'test')
    get edit_cms_path(profile.identifier, a)
    !assert_tag :tag => 'div', :descendant => { :tag => 'h4', :content => 'Categorize your article' }
  end

  should 'display posts per page input with default value on edit blog' do
    n = Blog.new.posts_per_page.to_s
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    assert_select 'select[name=?] option[value=?]', 'article[posts_per_page]', n do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element["selected"]
      end
    end
  end

  should 'display options for blog visualization with default value on edit blog' do
    format = Blog.new.visualization_format
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    assert_select 'select[name=?] option[value=full]', 'article[visualization_format]' do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element["selected"]
      end
    end
  end

  should 'not offer to create special article types' do
    get new_cms_index_path(profile.identifier)
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?type=Blog"}
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?type=Forum"}
  end

  should 'not offer folders if in a blog' do
    blog = fast_create(Blog, :profile_id => profile.id)
    get new_cms_index_path(profile.identifier), params: {:parent_id => blog.id, :cms => true}
    types = assigns(:article_types).map {|t| t[:name]}
    Article.folder_types.each do |type|
      assert_not_includes types, type
    end
  end

  should 'offer to edit a blog' do
    profile.articles << Blog.new(:name => 'blog test', :profile => profile)

    profile.articles.reload
    assert profile.has_blog?

    b = profile.blog
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/edit/#{b.id}"}
  end

  should 'not offer to add folder to blog' do
    profile.articles << Blog.new(:name => 'blog test', :profile => profile)

    profile.articles.reload
    assert profile.has_blog?

    get view_cms_path(profile.identifier, profile.blog)
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?parent_id=#{profile.blog.id}&amp;type=Folder"}
  end

  should 'not show feed subitem for blog' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile)

    profile.articles.reload
    assert profile.has_blog?

    get view_cms_path(profile.identifier, profile.blog)

    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/edit/#{profile.blog.feed.id}" }
  end

  should 'remove the image of a blog' do
    blog = create(Blog, :profile_id => profile.id, :name=>'testblog', :image_builder => { :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')})
    blog.save!
    post edit_cms_path(profile.identifier, blog), params: {:article => {:image_builder => { :remove_image => true}}}
    blog.reload

    assert_nil blog.image
  end

  should 'remove the image of an article' do
    image = create(Image, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'), :label => 'test_label')
    article = fast_create(Article, :profile_id => profile.id, :name => 'test_label_article', :body => 'test_content')
    article.image = image
    article.save
    post edit_cms_path(profile.identifier, article), params: {:article => {:image_builder => { :remove_image => 'true'}}}
    article.reload

    assert_nil article.image
  end

  should 'update feed options by edit blog form' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile)
    post edit_cms_path(profile.identifier, profile.blog), params: {:article => { :feed => { :limit => 7 } }}
    assert_equal 7, profile.blog.feed.limit
  end

  should 'not offer folder to blog articles' do
    @controller = CmsController.new
    @controller.stubs(:profile).returns(fast_create(Enterprise, :name => 'test_ent', :identifier => 'test_ent'))
    @controller.stubs(:user).returns(profile)
    blog = Blog.create!(:name => 'Blog for test', :profile => profile)
    @controller.stubs(:params).returns({ :parent_id => blog.id })

    assert_not_includes available_article_types, Folder
  end

  should 'not offer rssfeed to blog articles' do
    @controller = CmsController.new
    @controller.stubs(:profile).returns(fast_create(Enterprise, :name => 'test_ent', :identifier => 'test_ent'))
    @controller.stubs(:user).returns(profile)
    blog = Blog.create!(:name => 'Blog for test', :profile => profile)
    @controller.stubs(:params).returns({ :parent_id => blog.id })

    assert_not_includes available_article_types, RssFeed
  end

  should 'update blog posts_per_page setting' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile)
    post edit_cms_path(profile.identifier, profile.blog), params: { :article => { :posts_per_page => 5 }}
    profile.blog.reload
    assert_equal 5, profile.blog.posts_per_page
  end

  should "display 'New content' when create children of folder" do
    a = Folder.new(:name => 'article folder'); profile.articles << a;  a.save!
    Article.stubs(:short_description).returns('bli')
    get view_cms_path(profile.identifier, a)
    assert_tag :tag => 'a', :content => 'New content'
  end

  should "display 'New content' when create children of blog" do
    a = Blog.create!(:name => 'blog_for_test', :profile => profile)
    Article.stubs(:short_description).returns('bli')
    get view_cms_path(profile.identifier, a)
    assert_tag :tag => 'a', :content => 'New content'
  end

  should 'display notify comments option' do
    a = profile.articles.create!(:name => 'test')
    get edit_cms_path(profile.identifier, a)
    assert :tag => 'input', :attributes => {:name => 'article[notify_comments]', :value => 1}
  end

  should 'go to blog after create it' do
    assert_difference 'Blog.count' do
      post new_cms_index_path(profile.identifier), params: {:type => Blog.name, :article => { :name => 'my-blog' }, :back_to => 'control_panel'}
    end
    assert_redirected_to @profile.articles.find_by(name: 'my-blog').view_url
  end

  should 'back to blog after config blog' do
    profile.articles << Blog.new(:name => 'my-blog',
                                 :profile => profile)
    post edit_cms_path(profile.identifier, profile.blog), params: {:article => {:access => '0' }}

    assert_redirected_to @profile.articles.find_by(name: 'my-blog').view_url
  end

  should 'back to control panel if cancel create blog' do
    get new_cms_index_path(profile.identifier), params: {:type => Blog.name}
    assert_tag :tag => 'a', :content => 'Cancel', :attributes => { :href => /\/myprofile\/#{profile.identifier}/ }
  end

  should 'back to control panel if cancel config blog' do
    profile.articles << Blog.new(:name => 'my-blog', :profile => profile)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_tag :tag => 'a', :content => 'Cancel', :attributes => { :href => /\/myprofile\/#{profile.identifier}/ }
  end

  should 'have only one mandatory field in the blog creation form' do
    get new_cms_index_path(profile.identifier), params: {:type => Blog.name}
    assert_select '.required-field .formfieldline', 1
  end

  should 'create icon upload file in folder' do
    f = Gallery.create!(:name => 'test_folder', :profile => profile)
    post new_cms_index_path(profile.identifier), params: { :type => UploadedFile.name,
               :parent_id => f.id,
               :article => {:uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')}}

    process_delayed_job_queue
    file = FilePresenter.for profile.articles.find_by(name: 'rails')
    assert File.exists?(file.icon_name)
    file.destroy
  end

  should 'create icon upload file' do
    post new_cms_index_path(profile.identifier), params: {
               :type => UploadedFile.name,
               :article => {:uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')}}

    process_delayed_job_queue
    file = FilePresenter.for profile.articles.find_by(name: 'rails')
    assert File.exists?(file.icon_name)
    file.destroy
  end

  should 'record when coming from public view on upload files' do
    folder = Folder.create!(:name => 'testfolder', :profile => profile)

#    @request.expects(:referer).returns("http://colivre.net/#{profile.identifier}/#{folder.slug}").at_least_once

    get upload_files_cms_index_path(profile.identifier), params: {:parent_id => folder.id}
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => /^https?:\/\/colivre.net\/#{profile.identifier}\/#{folder.slug}/ }
  end

  should 'detect when coming from home page to upload files' do
    folder = Folder.create!(:name => 'testfolder', :profile => profile)
#    @request.expects(:referer).returns("http://colivre.net/#{profile.identifier}").at_least_once
#    @controller.stubs(:profile).returns(profile)
    get upload_files_cms_index_path(profile.identifier), params: {:parent_id => folder.id}
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => @request.referer }
  end

  should 'go back to public view when upload files coming from there' do
    folder = Folder.create!(:name => 'test_folder', :profile => profile)
    @request.expects(:referer).returns(folder.view_url).at_least_once

    post upload_files_cms_index_path(profile.identifier), params: {:parent_id => folder.id, :back_to => @request.referer,
         :uploaded_files => { "0" => { :file => fixture_file_upload('files/rails.png', 'image/png')}}}
    assert_template nil
    assert_redirected_to "#{profile.environment.top_url}/testinguser/test-folder"
  end

  should 'record when coming from public view on edit files with view true' do
    file = UploadedFile.create!(:profile => profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))

    get edit_cms_path(profile.identifier, file)
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => /^https?:\/\/colivre.net\/#{profile.identifier}\/#{file.slug}?.*view=true/ }
  end

  should 'detect when coming from home page to edit files with view true' do
    file = UploadedFile.create!(:profile => profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))

#    @request.expects(:referer).returns("http://colivre.net/#{profile.identifier}?view=true").at_least_once
#    @controller.stubs(:profile).returns(profile)
    get edit_cms_path(profile.identifier, file)
    assert_tag :tag => 'input', :attributes => { :type => 'hidden', :name => 'back_to', :value => @request.referer }
    assert_tag :tag => 'a', :descendant => { :content => 'Cancel' }, :attributes => { :href => @request.referer }
  end

  should 'go back to public view when edit files coming from there with view true' do
    file = UploadedFile.create!(:profile => profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    @request.expects(:referer).returns("http://colivre.net/#{profile.identifier}/#{file.slug}?view=true").at_least_once

    post edit_cms_path(profile.identifier, file), params: {:back_to => @request.referer, :article => {:abstract => 'some description'}}
    assert_template nil
    assert_redirected_to file.url.merge(:view => true)
  end

  should 'display external feed options when edit blog' do
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    assert_tag :tag => 'input', :attributes => { :name => 'article[external_feed_builder][enabled]' }
    assert_tag :tag => 'input', :attributes => { :name => 'article[external_feed_builder][address]' }
  end

  should "display 'Fetch posts from an external feed' checked if blog has enabled external feed" do
    profile.articles << Blog.new(:name => 'test blog', :profile => profile)
    profile.blog.create_external_feed(:address => 'address', :enabled => true)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_select 'input[type=checkbox][name=?]',  'article[external_feed_builder][enabled]' do |elements|
      elements.length > 0
      elements.each do |element|
        assert element["checked"]
      end
    end
  end

  should "display 'Fetch posts from an external feed' unchecked if blog has disabled external feed" do
    profile.articles << Blog.new(:name => 'test blog', :profile => profile)
    profile.blog.create_external_feed(:address => 'address', :enabled => false)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_tag :tag => 'input', :attributes => { :name => 'article[external_feed_builder][enabled]', :checked => nil }
  end

  should "hide external feed options when 'Fetch posts from an external feed' unchecked" do
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    assert_tag :tag => 'input', :attributes => { :name => 'article[external_feed_builder][enabled]', :checked => nil }
    assert_tag :tag => 'div', :attributes => { :id => 'external-feed-options', :style => 'display: none' }
  end

  should 'only_once option marked by default' do
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    assert_select "input[name=?][value=true]", 'article[external_feed_builder][only_once]' do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element['checked']
      end
    end
  end

  should 'display media listing when it is TextArticle and enabled on environment' do
    e = Environment.default
    e.enable('media_panel')
    e.save!

    image_folder = Folder.create(:profile => profile, :name => 'Image folder')
    non_image_folder = Folder.create(:profile => profile, :name => 'Non image folder')

    image = UploadedFile.create!(:profile => profile, :parent => image_folder, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    file = UploadedFile.create!(:profile => profile, :parent => non_image_folder, :uploaded_data => fixture_file_upload('/files/test.txt', 'text/plain'))

    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle'}
    assert_tag :div, :attributes => { :class => "text-editor-sidebar" }
  end

  should 'not display media listing when it is Folder' do
    image_folder = Folder.create(:profile => profile, :name => 'Image folder')
    non_image_folder = Folder.create(:profile => profile, :name => 'Non image folder')

    image = UploadedFile.create!(:profile => profile, :parent => image_folder, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    file = UploadedFile.create!(:profile => profile, :parent => non_image_folder, :uploaded_data => fixture_file_upload('/files/test.txt', 'text/plain'))

    get new_cms_index_path(profile.identifier), params: {:type => 'Folder'}
    !assert_tag :div, :attributes => { :id => "text-editor-sidebar" }
  end

  should "display 'Publish' when profile is a person and is member of communities" do
    a = fast_create(TextArticle, :profile_id => profile.id, :updated_at => DateTime.now)
    c1 = fast_create(Community)
    c2 = fast_create(Community)
    c1.add_member(profile)
    c2.add_member(profile)
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :attributes => {:href => "/myprofile/#{profile.identifier}/cms/publish/#{a.id}"}
  end

  should "display 'Publish' when profile is a person and there is a portal community" do
    a = fast_create(TextArticle, :profile_id => profile.id, :updated_at => DateTime.now)
    environment = profile.environment
    environment.portal_community = fast_create(Community)
    environment.enable('use_portal_community')
    environment.save!
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :attributes => {:href => "/myprofile/#{profile.identifier}/cms/publish/#{a.id}"}
  end

  should "display 'Publish' when profile is a community" do
    community = fast_create(Community)
    community.add_admin(profile)
    a = fast_create(TextArticle, :profile_id => community.id, :updated_at => DateTime.now)
    Article.stubs(:short_description).returns('bli')
    get cms_index_path(community.identifier)
    assert_tag :tag => 'a', :attributes => {:href => "/myprofile/#{community.identifier}/cms/publish/#{a.id}"}
  end

  should 'not offer to upload files to blog' do
    profile.articles << Blog.new(:name => 'blog test', :profile => profile)

    profile.articles.reload
    assert profile.has_blog?

    get view_cms_path(profile.identifier, profile.blog)
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/upload_files?parent_id=#{profile.blog.id}"}
  end

  should 'not allow user without permission create an article in community' do
    c = Community.create!(:name => 'test_comm', :identifier => 'test_comm')
    u = create_user_with_permission('test_user', 'bogus_permission', c)
    logout_rails5
    login_as_rails5 :test_user

    get new_cms_index_path(c.identifier)
    assert_response :forbidden
    assert_template 'shared/access_denied'
  end

  should 'allow user with permission create an article in community' do
    c = Community.create!(:name => 'test_comm', :identifier => 'test_comm')
    u = create_user_with_permission('test_user', 'post_content', c)
    logout_rails5
    login_as_rails5 :test_user

    get new_cms_index_path(c.identifier), params: {:type => 'TextArticle'}
    assert_response :success
    assert_template 'edit'
  end

  should 'not allow user edit article if he is owner but has no publish permission' do
    c = Community.create!(:name => 'test_comm', :identifier => 'test_comm')
    u = create_user_with_permission('test_user', 'bogus_permission', c)
    a = create(Article, :profile => c, :name => 'test_article', :author => u)
    logout_rails5
    login_as_rails5 :test_user

    get edit_cms_path(c.identifier, a)
    assert_response :forbidden
    assert_template 'shared/access_denied'
  end

  should 'allow user edit article if he is owner and has publish permission' do
    c = Community.create!(:name => 'test_comm', :identifier => 'test_comm')
    u = create_user_with_permission('test_user', 'post_content', c)
    a = create(Article, :profile => c, :name => 'test_article', :author => u)
    logout_rails5
    login_as_rails5 :test_user

    get edit_cms_path(c.identifier, a)

    assert_response :success
    assert_template 'edit'
  end

  should 'allow community members to edit articles that allow it' do
    community = fast_create(Community)
    admin = create_user('community-admin').person
    member = create_user.person

    community.add_admin(admin)
    community.add_member(member)

    article = community.articles.create!(:name => 'test_article', :allow_members_to_edit => true)

    logout_rails5
    login_as_rails5 member.identifier
    get edit_cms_path(community.identifier, article)
    assert_response :success
  end

  should 'create thumbnails for images with delayed_job' do
    post upload_files_cms_index_path(profile.identifier), params: {
	    :uploaded_files => { "0" => { :file => fixture_file_upload('/files/rails.png', 'image/png')},
                              "1" => { :file => fixture_file_upload('/files/test.txt', 'text/plain')}}}
    file_1 = profile.articles.find_by(path: 'rails')
    file_2 = profile.articles.find_by(path: 'test')

    process_delayed_job_queue

    UploadedFile.attachment_options[:thumbnails].each do |suffix, size|
      assert File.exists?(UploadedFile.find(file_1.id).public_filename(suffix))
      refute File.exists?(UploadedFile.find(file_2.id).public_filename(suffix))
    end
    file_1.destroy
    file_2.destroy
  end

  # Forum

  should 'display posts per page input with default value on edit forum' do
    n = Forum.new.posts_per_page.to_s
    get new_cms_index_path(profile.identifier), params: {:type => 'Forum'}
    assert_select 'select[name=?] option[value=?]', 'article[posts_per_page]', n do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element['selected']
      end
    end
  end

  should 'offer to edit a forum' do
    profile.articles << Forum.new(:name => 'forum test', :profile => profile)

    profile.articles.reload
    assert profile.has_forum?

    b = profile.forum
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/edit/#{b.id}"}
  end

  should 'not offer to add folder to forum' do
    profile.articles << Forum.new(:name => 'forum test', :profile => profile)

    profile.articles.reload
    assert profile.has_forum?

    get view_cms_path(profile.identifier, profile.forum)
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/new?parent_id=#{profile.forum.id}&amp;type=Folder"}
  end

  should 'not show feed subitem for forum' do
    profile.articles << Forum.new(:name => 'Forum for test', :profile => profile)

    profile.articles.reload
    assert profile.has_forum?

    get view_cms_path(profile.identifier, profile.forum)

    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/edit/#{profile.forum.feed.id}" }
  end

  should 'update feed options by edit forum form' do
    profile.articles << Forum.new(:name => 'Forum for test', :profile => profile)
    post edit_cms_path(profile.identifier, profile.forum), params: {:article => { :feed => { :limit => 7 } }}
    assert_equal 7, profile.forum.feed.limit
  end

  should 'not offer folder to forum articles' do
    @controller = CmsController.new
    @controller.stubs(:profile).returns(fast_create(Enterprise, :name => 'test_ent', :identifier => 'test_ent'))
    @controller.stubs(:user).returns(profile)
    forum = Forum.create!(:name => 'Forum for test', :profile => profile)
    @controller.stubs(:params).returns({ :parent_id => forum.id })

    assert_not_includes available_article_types, Folder
  end

  should 'not offer rssfeed to forum articles' do
    @controller = CmsController.new
    @controller.stubs(:profile).returns(fast_create(Enterprise, :name => 'test_ent', :identifier => 'test_ent'))
    @controller.stubs(:user).returns(profile)
    forum = Forum.create!(:name => 'Forum for test', :profile => profile)
    @controller.stubs(:params).returns({ :parent_id => forum.id })

    assert_not_includes available_article_types, RssFeed
  end

  should 'update forum posts_per_page setting' do
    profile.articles << Forum.new(:name => 'Forum for test', :profile => profile)
    post edit_cms_path(profile.identifier, profile.forum), params: {:article => { :posts_per_page => 5 }}
    profile.forum.reload
    assert_equal 5, profile.forum.posts_per_page
  end

  should 'go to forum after create it' do
    assert_difference 'Forum.count' do
      post new_cms_index_path(profile.identifier), params: {:type => Forum.name, :article => { :name => 'my-forum' }, :back_to => 'control_panel'}
    end
    assert_redirected_to @profile.articles.find_by(name: 'my-forum').view_url
  end

  should 'back to forum after config forum' do
    assert_difference 'Forum.count' do
      post new_cms_index_path(profile.identifier), params: {:type => Forum.name, :article => { :name => 'my-forum' }, :back_to => 'control_panel'}
    end
    post edit_cms_path(profile.identifier, profile.forum), params: {:type => Forum.name, :article => { :name => 'my forum' }}
    assert_redirected_to @profile.articles.find_by(name: 'my forum').view_url
  end

  should 'back to control panel if cancel create forum' do
    get new_cms_index_path(profile.identifier), params: {:type => Forum.name}
    assert_tag :tag => 'a', :content => 'Cancel', :attributes => { :href => /\/myprofile\/#{profile.identifier}/ }
  end

  should 'back to control panel if cancel config forum' do
    profile.articles << Forum.new(:name => 'my-forum', :profile => profile)
    get edit_cms_path(profile.identifier, profile.forum)
    assert_tag :tag => 'a', :content => 'Cancel', :attributes => { :href => /\/myprofile\/#{profile.identifier}/ }
  end

  should 'not offer to upload files to forum' do
    profile.articles << Forum.new(:name => 'forum test', :profile => profile)

    profile.articles.reload
    assert profile.has_forum?

    get view_cms_path(profile.identifier, profile.forum)
    !assert_tag :tag => 'a', :attributes => { :href => "/myprofile/#{profile.identifier}/cms/upload_files?parent_id=#{profile.forum.id}"}
  end

  should 'not logged in to suggest an article' do
    logout_rails5
    get suggest_an_article_cms_index_path(profile.identifier), params: {:back_to => 'action_view'}

    assert_template 'suggest_an_article'
  end

  should 'display name and email when a not logged in user suggest an article' do
    logout_rails5
    get suggest_an_article_cms_index_path(profile.identifier), params: {:back_to => 'action_view'}

    assert_select '#task_name'
    assert_select '#task_email'
  end

  should 'do not display name and email when a logged in user suggest an article' do
    get suggest_an_article_cms_index_path(profile.identifier), params: {:back_to => 'action_view'}

    assert_select '#task_name', 0
    assert_select '#task_email', 0
  end

  should 'render TinyMce Editor on suggestion of article if editor is TinyMCE' do
    logout_rails5
    profile.editor = Article::Editor::TINY_MCE
    profile.save
    get suggest_an_article_cms_index_path(profile.identifier)

    assert_tag :tag => 'textarea', :attributes => { :name => /task\[article\]\[abstract\]/, :class => Article::Editor::TINY_MCE }
    assert_tag :tag => 'textarea', :attributes => { :name => /task\[article\]\[body\]/, :class => Article::Editor::TINY_MCE }
  end

  should 'create a task suggest task to a profile' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => true)

    assert_difference 'SuggestArticle.count' do
      post suggest_an_article_cms_index_path(c.identifier), params: {:back_to => 'action_view', :task => {:article => {:name => 'some name', :body => 'some body'}, :email => 'some@localhost.com', :name => 'some name'}}
    end
  end

  should 'create suggest task with logged in user as the article author' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => true)

    post suggest_an_article_cms_index_path(c.identifier), params: {:back_to => 'action_view', :task => {:article => {:name => 'some name', :body => 'some body'}}}
    assert_equal profile, SuggestArticle.last.requestor
  end

  should 'suggest an article from a profile' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => true)
    get suggest_an_article_cms_index_path(c.identifier), params: {:back_to => c.identifier}
    assert_response :success
    assert_template 'suggest_an_article'
    assert_tag :tag => 'input', :attributes => { :value => c.identifier, :id => 'back_to' }
  end

  should 'suggest an article accessing the url directly' do
    c = Community.create!(:name => 'test comm', :identifier => 'test_comm', :moderated_articles => true)
    get suggest_an_article_cms_index_path(c.identifier)
    assert_response :success
  end

  should 'article language should be selected' do
    e = Environment.default
    e.languages = ['ru']
    e.save
    textile = fast_create(TextArticle, :profile_id => @profile.id, :path => 'textile', :language => 'ru')
    get edit_cms_path(@profile.identifier, textile)
    assert_tag :option, :attributes => { :selected => 'selected', :value => 'ru' }, :parent => {
      :tag => 'select', :attributes => { :id => 'article_language'} }
  end

  should 'list possible languages and include blank option' do
    e = Environment.default
    e.languages = ['en', 'pt','fr','hy','de', 'ru', 'es', 'eo', 'it']
    e.save
    get new_cms_index_path(@profile.identifier), params: {:type => 'TextArticle'}
    assert_equal Noosfero.locales.invert, assigns(:locales)
    assert_tag :option, :attributes => { :value => '' }, :parent => {
      :tag => 'select', :attributes => { :id => 'article_language'} }
  end

  should 'add translation to an article' do
    textile = fast_create(TextArticle, :profile_id => @profile.id, :path => 'textile', :language => 'ru')
    assert_difference 'Article.count' do
      post new_cms_index_path(@profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'english translation', :translation_of_id => textile.id, :language => 'en' }}
    end
  end

  should 'not display language selection if article is not translatable' do
    blog = fast_create(Blog, :name => 'blog', :profile_id => @profile.id)
    get edit_cms_path(@profile.identifier, blog)
    !assert_tag :select, :attributes => { :id => 'article_language'}
  end

  should 'display display posts in current language input checked when editing blog' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile, :display_posts_in_current_language => true)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_select "input[type=checkbox][name=?]", 'article[display_posts_in_current_language]' do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element["checked"]
      end
    end
  end

  should 'display display posts in current language input not checked on new blog' do
    get new_cms_index_path(profile.identifier), params: {:type => 'Blog'}
    !assert_tag :tag => 'input', :attributes => { :type => 'checkbox', :name => 'article[display_posts_in_current_language]', :checked => 'checked' }
  end

  should 'update to false blog display posts in current language setting' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile, :display_posts_in_current_language => true)
    post edit_cms_path(profile.identifier, profile.blog), params: {:article => { :display_posts_in_current_language => false }}
    profile.blog.reload
    refute profile.blog.display_posts_in_current_language?
  end

  should 'update to true blog display posts in current language setting' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile, :display_posts_in_current_language => false)
    post edit_cms_path(profile.identifier, profile.blog), params: {:article => { :display_posts_in_current_language => true }}
    profile.blog.reload
    assert profile.blog.display_posts_in_current_language?
  end

  should 'be checked display posts in current language checkbox' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile, :display_posts_in_current_language => true)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_select 'input[type=checkbox][name=?]', 'article[display_posts_in_current_language]' do |elements|
      assert elements.length > 0
      elements.each do |element|
        assert element["checked"]
      end
    end
  end

  should 'be unchecked display posts in current language checkbox' do
    profile.articles << Blog.new(:name => 'Blog for test', :profile => profile, :display_posts_in_current_language => false)
    get edit_cms_path(profile.identifier, profile.blog)
    assert_tag :tag => 'input', :attributes => { :type => 'checkbox', :name => 'article[display_posts_in_current_language]' }
    !assert_tag :tag => 'input', :attributes => { :type => 'checkbox', :name => 'article[display_posts_in_current_language]', :checked => 'checked' }
  end

  should 'display accept comments option when creating forum post' do
    profile.articles << f = Forum.new(:name => 'Forum for test')
    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => f.id}
    !assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'hidden'}
    assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'checkbox'}
  end

  should 'display accept comments option when creating an article that is not a forum post' do
    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle'}
    !assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'hidden'}
    assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'checkbox'}
  end

  should 'display accept comments option when editing forum post' do
    profile.articles << f = Forum.new(:name => 'Forum for test')
    profile.articles << a = TextArticle.new(:name => 'Forum post for test', :parent => f)
    get edit_cms_path(profile.identifier, a)
    !assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'hidden'}
    assert_tag :tag => 'input', :attributes => {:name => 'article[accept_comments]', :value => 1, :type => 'checkbox'}
  end

  should 'logged in user NOT be able to create topic on forum when topic creation is set to Me' do
    u = create_user('linux')
    logout_rails5
    login_as_rails5 :linux
    profile.articles << f = Forum.new(:name => 'Forum for test',
                                      :topic_creation => Entitlement::Levels.levels[:self],
                                      :body => 'Forum Body')

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle',
               :article => {:name => 'New Topic by linux', :body => 'Article Body',
                            :parent_id => f.id}}

    assert_template :access_denied
    assert_not_equal 'New Topic by linux', Article.last.name
  end

  should 'logged in user NOT be able to create topic on forum when topic creation is set to Friends/Members' do
    u = create_user('linux')
    logout_rails5
    login_as_rails5 :linux
    profile.articles << f = Forum.new(:name => 'Forum for test',
                                      :topic_creation => Entitlement::Levels.levels[:related],
                                      :body => 'Forum Body')

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle',
               :article => {:name => 'New Topic by linux', :body => 'Article Body',
                            :parent_id => f.id}}

    assert_template :access_denied
    assert_not_equal 'New Topic by linux', Article.last.name
  end

  should 'logged in user be able to create topic on forum when topic creation is set to Logged in users' do
    u = create_user('linux')
    logout_rails5
    login_as_rails5 :linux
    profile.articles << f = Forum.new(:name => 'Forum for test',
                                      :topic_creation => '0',
                                      :body => 'Forum Body')

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle',
               :article => {:name => 'New Topic by linux', :body => 'Article Body',
                            :parent_id => f.id}}

    assert_equal 'New Topic by linux', Article.last.name
  end

  should 'display accept comments option when editing forum post with a different label' do
    profile.articles << f = Forum.new(:name => 'Forum for test')
    profile.articles << a = TextArticle.new(:name => 'Forum post for test', :parent => f)
    get edit_cms_path(profile.identifier, a)
    assert_tag :tag => 'label', :attributes => { :for => 'article_accept_comments' }, :content => _('This topic is opened for replies')
  end

  should 'display correct label for accept comments option for an article that is not a forum post' do
    profile.articles << a = TextArticle.new(:name => 'Forum post for test')
    get edit_cms_path(profile.identifier, a)
    assert_tag :tag => 'label', :attributes => { :for => 'article_accept_comments' }, :content => _('I want to receive comments about this article')
  end

  should 'display filename if uploaded file has not title' do
    file = UploadedFile.create!(:uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'), :profile => @profile)
    get cms_index_path(@profile.identifier)
    assert_tag :a, :content => "rails"
  end

  should 'display title if uploaded file has one' do
    file = UploadedFile.create!(:uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'), :profile => @profile, :title => 'An image')
    get cms_index_path(@profile.identifier)
    assert_tag :a, :content => "An image"
  end

  should 'update image and be redirected to view_page' do
    image = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('files/rails.png', 'image/png'))
    post edit_cms_path(@profile.identifier, image), params: {:article => { }}
    assert_redirected_to image.view_url
  end

  should 'update article and be redirected to view_page' do
    a = fast_create(TextArticle, :profile_id => @profile.id)
    post edit_cms_path(@profile.identifier, a), params: { :article => { }}
    assert_redirected_to a.view_url
  end

  should 'update file and be redirected to cms' do
    file = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('files/test.txt', 'text/plain'))
    post edit_cms_path(@profile.identifier, file), params: { :article => { }}
    assert_redirected_to :controller => 'cms', :profile => profile.identifier, :action => 'index', :id => nil
  end

  should 'update file and be redirected to cms folder' do
    f = fast_create(Folder, :profile_id => @profile.id, :name => 'foldername')
    file = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('files/test.txt', 'text/plain'), :parent_id => f.id)
    post edit_cms_path(@profile.identifier, file), params: {:article => { :title => 'text file' }}
    assert_redirected_to :action => 'view', :id => f
  end

  should 'render TinyMce Editor for events' do
    profile.editor = Article::Editor::TINY_MCE
    profile.save
    get new_cms_index_path(profile.identifier), params: {:type => 'Event'}
    assert_tag :tag => 'textarea', :attributes => { :class => Article::Editor::TINY_MCE }
  end

  should 'identify form with classname of edited article' do
    [Blog, TextArticle, Forum].each do |klass|
      a = fast_create(klass, :profile_id => profile.id)
      get edit_cms_path(profile.identifier, a)
      assert_tag :tag => 'form', :attributes => {:class => "#{a.type} #{a.type.to_css_class}"}
    end
  end

  should 'search for content for inclusion in articles' do
    file = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('files/test.txt', 'text/plain'))
    get search_cms_index_path(@profile.identifier), params: {:q => 'test'}
    assert_match /test/, @response.body
    assert_equal 'application/json', @response.content_type

    data = parse_json_response
    assert_equal 'test', data.first['title']
    assert_match /\/testinguser\/test$/, data.first['url']
    assert_match /text/, data.first['icon']
    assert_match /text/, data.first['content_type']
  end

  should 'upload media by AJAX' do
    assert_difference 'UploadedFile.count', 1 do
      post media_upload_cms_index_path(profile.identifier), params: {:format => 'js', :file => fixture_file_upload('/files/test.txt', 'text/plain')}
    end
  end

  should 'upload image with crop by AJAX' do
    assert_difference 'UploadedFile.count', 1 do
      post media_upload_cms_index_path(profile.identifier), params: { :format => 'js',
           :crop => { :file => fixture_file_upload('/files/rails.png', 'image/png'),
           :crop_x => 0,
           :crop_y => 0,
           :crop_h => 25,
           :crop_w => 25 }}
    end
  end

  should 'not when media upload via AJAX contains empty files' do
    post media_upload_cms_index_path(@profile.identifier)
  end

  should 'mark unsuccessful upload' do
    file = UploadedFile.create!(:profile => profile, :uploaded_data => fixture_file_upload('files/rails.png', 'image/png'))
    post media_upload_cms_index_path(profile.identifier), params: {:media_listing => true, :file => fixture_file_upload('files/rails.png', 'image/png')}
    assert_response :bad_request
  end

  should 'include new contents special types from plugins' do
    class TestContentTypesPlugin < Noosfero::Plugin
      def content_types
        [Integer, Float]
      end
    end

    Noosfero::Plugin::Manager.any_instance.stubs(:enabled_plugins).returns([TestContentTypesPlugin.new])

    get cms_index_path(profile.identifier)

    assert_includes special_article_types, Integer
    assert_includes special_article_types, Float
  end

  should 'be able to define license when updating article' do
    article = fast_create(Article, :profile_id => profile.id)
    license = License.create!(:name => 'GPLv3', :environment => profile.environment)
    logout_rails5
    login_as_rails5(profile.identifier)

    post edit_cms_path(profile.identifier, article), params: {:article => { :license_id => license.id }}

    article.reload
    assert_equal license, article.license
  end

  should 'not display license field if there is no license available in environment' do
    article = fast_create(Article, :profile_id => profile.id)
    License.delete_all
    logout_rails5
    login_as_rails5(profile.identifier)

    get new_cms_index_path(profile.identifier), params: {:type => 'TextArticle'}
    !assert_tag :tag => 'select', :attributes => {:id => 'article_license_id'}
  end

  should 'list folders options to move content' do
    article = fast_create(Article, :profile_id => profile.id)
    f1 = fast_create(Folder, :profile_id => profile.id)
    f2 = fast_create(Folder, :profile_id => profile.id)
    f3 = fast_create(Folder, :profile_id => profile, :parent_id => f2.id)
    logout_rails5
    login_as_rails5(profile.identifier)

    get edit_cms_path(profile.identifier, article)

    assert_tag :tag => 'option', :attributes => {:value => f1.id}, :content => "#{profile.identifier}/#{f1.name}"
    assert_tag :tag => 'option', :attributes => {:value => f2.id}, :content => "#{profile.identifier}/#{f2.name}"
    assert_tag :tag => 'option', :attributes => {:value => f3.id}, :content => "#{profile.identifier}/#{f2.name}/#{f3.name}"
  end

  should 'be able to move content' do
    f1 = fast_create(Folder, :profile_id => profile.id)
    f2 = fast_create(Folder, :profile_id => profile.id)
    article = fast_create(Article, :profile_id => profile.id, :parent_id => f1)
    logout_rails5
    login_as_rails5(profile.identifier)

    post edit_cms_path(profile.identifier, article), params: {:article => {:parent_id => f2.id}}
    article.reload

    assert_equal f2, article.parent
  end

  should 'set author when creating article' do
    logout_rails5
    login_as_rails5(profile.identifier)

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'Sample Article', :body => 'content ...' }}

    a = profile.articles.find_by(path: 'sample-article')
    assert_not_nil a
    assert_equal profile, a.author
  end

  should 'not allow user upload files if he can not create on the parent folder' do
    c = Community.create!(:name => 'test_comm', :identifier => 'test_comm')
    u = create_user('test_user')
    a = c.articles.create!(:name => 'test_article')
    a.stubs(:allow_create?).with(u).returns(true)
    logout_rails5
    login_as_rails5 :test_user

    get upload_files_cms_index_path(c.identifier), params: {:parent_id => a.id}
    assert_response :forbidden
    assert_template 'shared/access_denied'
  end

  should 'filter profile folders to select' do
    env = Environment.default
    env.enable 'media_panel'
    env.save!
    folder  = fast_create(Folder,  :name=>'a', :profile_id => profile.id)
    gallery = fast_create(Gallery, :name=>'b', :profile_id => profile.id)
    blog    = fast_create(Blog,    :name=>'c', :profile_id => profile.id)
    article = fast_create(TextArticle,      :profile_id => profile.id)
    get edit_cms_path(profile.identifier, article)
    assert_template 'edit'
    assert_tag :tag => 'select', :attributes => { :name => "parent_id" },
               :descendant => { :tag => "option",
                 :attributes => { :value => folder.id.to_s }}
    assert_tag :tag => 'select', :attributes => { :name => "parent_id" },
               :descendant => { :tag => "option",
                 :attributes => { :selected => 'selected', :value => gallery.id.to_s }}
    !assert_tag :tag => 'select', :attributes => { :name => "parent_id" },
                  :descendant => { :tag => "option",
                    :attributes => { :value => blog.id.to_s }}
    !assert_tag :tag => 'select', :attributes => { :name => "parent_id" },
                  :descendant => { :tag => "option",
                    :attributes => { :value => article.id.to_s }}
  end

  should 'remove users that agreed with forum terms after removing terms' do
    forum = Forum.create(:name => 'Forum test', :profile => profile, :has_terms_of_use => true)
    person = fast_create(Person)
    forum.users_with_agreement << person

    assert_difference 'Forum.find(forum.id).users_with_agreement.count', -1 do
      post edit_cms_path(profile.identifier, forum), params: {:article => { :has_terms_of_use => 'false' }}
    end
  end

  should 'go back to specified url when saving with success' do
    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle',
      :article => { :name => 'changed by me',
                    :body => 'content ...',
                    :access => '0'},
      :success_back_to => '/'}
    assert_redirected_to '/'
  end

  should 'redirect back to specified url when edit with success' do
    article = @profile.articles.create!(:name => 'myarticle')
    post edit_cms_path('testinguser', article), params: { :success_back_to => '/', :article => {:access => '0' }}
    assert_redirected_to '/'
  end

  should 'edit article with content from older version' do
    article = profile.articles.create(:name => 'first version')
    article.name = 'second version'; article.save

    get edit_cms_path(profile.identifier, article), params: {:version => 1}
    assert_equal 'second version', Article.find(article.id).name
    assert_equal 'first version', assigns(:article).name
  end

  should 'save article with content from older version' do
    article = profile.articles.create(:name => 'first version')
    article.name = 'second version'; article.save

    post edit_cms_path(profile.identifier, article), params: { :version => 1, :article => {:access => '0' }}
    assert_equal 'first version', Article.find(article.id).name
  end

  should 'set created_by when creating article' do
    logout_rails5
    login_as_rails5(profile.identifier)

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :article => { :name => 'changed by me', :body => 'content ...' }}

    a = profile.articles.find_by(path: 'changed-by-me')
    assert_not_nil a
    assert_equal profile, a.created_by
  end

  should 'not change created_by when updating article' do
    other_person = create_user('otherperson').person

    a = profile.articles.build(:name => 'my article')
    a.created_by = other_person
    a.save!

    logout_rails5
    login_as_rails5(profile.identifier)
    post edit_cms_path(profile.identifier, a), params: {:article => { :body => 'new content for this article' }}

    a.reload

    assert_equal other_person, a.created_by
  end

  should 'response of search_tags be json' do
    get search_tags_cms_index_path(profile.identifier), params: { :term => 'linux'}
    assert_equal 'application/json', @response.content_type
  end

  should 'return empty json if does not find tag' do
    get search_tags_cms_index_path(profile.identifier), params: { :term => 'linux'}
    assert_equal "[]", @response.body
  end

  should 'return tags found' do
    a = profile.articles.create(:name => 'blablabla')
    a.tags.create! name: 'linux'
    get search_tags_cms_index_path(profile.identifier), params: { :term => 'linux'}
    assert_equal '[{"label":"linux","value":"linux"}]', @response.body
  end

  should 'clone an article with its parent' do
    logout_rails5
    login_as_rails5(profile.identifier)

    f = Folder.new(:name => 'f')
    profile.articles << f
    f.save!

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => f.id,
               :article => { :name => 'Main Article', :body => 'some content' }}

    main_article = profile.articles.find_by(name: 'Main Article')
    assert_not_nil main_article

    post new_cms_index_path(profile.identifier), params: {:type => 'TextArticle', :parent_id => f.id,
               :id => main_article.id, :clone => true}

    cloned_main_article = profile.articles.find_by(name: 'Main Article')
    assert_not_nil cloned_main_article

    assert_equal main_article.parent_id, cloned_main_article.parent_id

    get new_cms_index_path(profile.identifier), params: {:id => cloned_main_article.id,
              :clone => true, :type => 'TextArticle'}

    assert_match main_article.body, @response.body
  end

  should 'set no_design_blocks as false when create a new document without type' do
    get new_cms_index_path(profile.identifier)
    assert !assigns(:no_design_blocks)
  end

  should 'set no_design_blocks as false when create a new document with invalid type' do
    assert_raise RuntimeError do
      get new_cms_index_path(profile.identifier), params: {type: 'InvalidType'}
      assert !assigns(:no_design_blocks)
    end
  end

  [TextArticle, Event].each do |klass|
    should "set no_design_blocks as true when create #{klass.name}" do
      get new_cms_index_path(profile.identifier), params: {type: klass.name}
      assert assigns(:no_design_blocks)
    end
  end

  should "set no_design_blocks as false when edit Article" do
    article = fast_create(Article, profile_id: profile.id)
    get edit_cms_path(profile.identifier, article)
    assert !assigns(:no_design_blocks)
  end

  [TextArticle, Event].each do |klass|
    should "set no_design_blocks as true when edit #{klass.name}" do
      article = fast_create(klass, profile_id: profile.id)
      get edit_cms_path(profile.identifier, article)
      assert assigns(:no_design_blocks)
    end
  end

  should 'save and display correct authors for article versions' do
    community = fast_create(Community)
    author1 = create_user('test1').person
    author2 = create_user('test2').person

    community.add_admin(author1)
    community.add_admin(author2)
    logout_rails5
    login_as_rails5(author1.identifier)
    post new_cms_index_path(community.identifier), params: {:type => 'TextArticle',
               :article => { :name => 'Main Article', :body => 'some content' }}

    article = community.articles.last
#    @controller.stubs(:user).returns(author2)
    logout_rails5
    login_as_rails5(author2.identifier)
    post edit_cms_path(community.identifier, article), params: {:article => { :name => 'Main Article', :body => 'edited' }}

    assert_equal 2, article.versions.count
    assert_equivalent [author1.id, author2.id], article.versions.map(&:last_changed_by_id)
  end

  should 'display CMS links for media panel images' do
    file = UploadedFile.create!(:profile => profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    get published_media_items_cms_index_path(profile.identifier)
    assert_tag 'img', attributes: { src: file.full_path }
  end

  should 'display a progress bar if profile has an upload quota' do
    @profile.update_attributes(upload_quota: 100.0)
    get cms_index_path(profile.identifier)
    assert_tag :tag => 'div', :attributes => { :class => 'quota-status' }
  end

  should 'not display a progress bar if profile upload quota is unlimited' do
    @profile.update_attributes(upload_quota: '')
    get cms_index_path(profile.identifier)
    !assert_tag :tag => 'div', :attributes => { :class => 'quota-status' }
  end

  should 'display all profile files' do
    file1 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    file2 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/shoes.png', 'image/png'))
    file3 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/tux.png', 'image/png'))

    get files_cms_index_path(profile.identifier)
    assert_tag tag: 'td', content: file1.name
    assert_tag tag: 'td', content: file2.name
    assert_tag tag: 'td', content: file3.name
  end

  should 'display files sorted by size' do
    file1 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    file2 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/shoes.png', 'image/png'))
    file3 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/tux.png', 'image/png'))

    get files_cms_index_path(profile.identifier), params: {sort_by: 'size ASC'}
    files = [file1, file2, file3].sort_by{ |f| f.size }
    assert_equal files.map(&:id), assigns(:files).map(&:id)

    get files_cms_index_path(profile.identifier), params: {sort_by: 'size DESC'}
    files = [file1, file2, file3].sort_by{ |f| -f.size }
    assert_equal files.map(&:id), assigns(:files).map(&:id)
  end

  should 'display files sorted by name if sort_by option is invalid' do
    file1 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))
    file2 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/shoes.png', 'image/png'))
    file3 = UploadedFile.create!(:profile => @profile, :uploaded_data => fixture_file_upload('/files/tux.png', 'image/png'))

    get files_cms_index_path(profile.identifier), params: {sort_by: 'invalid'}
    files = [file1, file2, file3].sort_by{ |f| f.name }
    assert_equal files.map(&:id), assigns(:files).map(&:id)
  end

  should 'not overwrite metadata when updating custom fields' do
    a = @profile.articles.build(:name => 'my article')
    a.metadata = {
      'mydata' => 'data',
      :custom_fields => { :field1 => { value: 1 } }
    }
    a.save!

    post edit_cms_path(@profile.identifier, a), params: { :article => {
      :body => 'new content for this article',
      :metadata => { :custom_fields => { :field1 => { value: 5 } } }
    }}

    a.reload
    assert_equal 'data', a.metadata['mydata']
    assert_equal '5', a.metadata['custom_fields']['field1']['value']
  end

  should 'update custom_fields even when it is empty' do
    a = @profile.articles.build(:name => 'my article')
    a.metadata = {
      'mydata' => 'data',
      :custom_fields => { :field1 => { value: 1 }, :field2 => { value: 5 } }
    }
    a.save!

    post edit_cms_path(@profile.identifier, a), params: { :article => {
      :body => 'new content for this article'}}

    a.reload

    assert a.metadata['custom_fields']['field1'].blank?
    assert a.metadata['custom_fields']['field2'].blank?
  end

  should 'execute upload_file method with single upload file option not exist in profile' do
    get upload_files_cms_index_path(profile.identifier)
    assert_template 'upload_files'
  end

  should 'execute upload_file method with single upload file option is false in profile' do
    profile.metadata['allow_single_file'] = "0"
    profile.save!
    get upload_files_cms_index_path(profile.identifier)
    assert_template 'upload_files'
  end

  should 'redirect to new article method in upload file if single upload file option is true in profile' do
    profile.metadata['allow_single_file'] = "1"
    profile.save!
    get upload_files_cms_index_path(profile.identifier)
    assert_redirected_to :action => 'new', :type => "UploadedFile"
  end

  should 'escape upload filename' do
    post media_upload_cms_index_path(profile.identifier), params: { media_listing: true, format: 'js',
      file: fixture_file_upload('files/fruits (2).png', 'image/png')}
    assert_response :success
    process_delayed_job_queue
    file = UploadedFile.last
    assert_equal 'fruits (2)', file.name
    assert_match /.*\/[0-9]+\/[0-9]+\/fruits-2.png/, file.public_filename
    assert_match /PNG image data, 320 x 240/, `file '#{file.public_filename}'`
  end

  should 'render sensitive content view' do
    get sensitive_content_cms_index_path(profile: profile.identifier)
    assert_template 'sensitive_content'
    assert_select 'span.publish-profile', profile.name
    assert_select 'span.publish-page', 0
  end

  should 'render sensitive content view with current page' do
    page = fast_create(Blog, profile_id: profile.id)
    get sensitive_content_cms_index_path(profile: profile.identifier, page: page.id)
    assert_template 'sensitive_content'
    assert_select 'span.publish-profile', profile.name
    assert_select 'span.publish-page', page.title
  end

  should 'render sensitive content view with user has\'t permission to publish in current page' do
    page = fast_create(Blog)
    get sensitive_content_cms_index_path(profile: profile.identifier, page: page.id)
    assert_template 'sensitive_content'
    assert_select 'span.publish-profile', profile.name
    assert_select 'span.publish-page', 0
  end

  should 'render select directory view if pass select_directory param' do
    get sensitive_content_cms_index_path(profile: profile.identifier, select_directory: true)
    assert_template 'select_directory'
    assert_select 'span.publish-profile', profile.name
    assert_select 'span.publish-page', 0
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/sensitive_content?select_directory=true']", 0
  end

  should 'render select profile view' do
    get select_profile_cms_index_path(profile: profile.identifier)
    assert_template 'select_profile'
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/sensitive_content']", 1
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/select_profile']", 0
  end

  should 'render select profile view with communities option' do
    community = fast_create(Community)
    community.add_admin(profile)
    get select_profile_cms_index_path(profile.identifier)
    assert_template 'select_profile'
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/select_profile?select_type=community']", 1
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/select_profile']", 0
  end

  should 'render select profile view with enterprises option' do
    enterprise = fast_create(Enterprise)
    enterprise.add_admin(profile)
    get select_profile_cms_index_path(profile: profile.identifier)
    assert_template 'select_profile'
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/select_profile?select_type=enterprise']", 1
    assert_select "a[href='/myprofile/#{profile.identifier}/cms/select_profile']", 0
  end

  should 'show back button in sensitive_content' do
    page = fast_create(Blog, profile_id: profile.id)
    get sensitive_content_cms_index_path(profile: profile.identifier, page: page.id)
    assert_template 'sensitive_content'
    assert_select 'a.icon-back.option-back', 1
    assert_select 'a.icon-none.option-not-back', 0
  end

  should 'not show back button in sensitive_content' do
    page = fast_create(Blog, profile_id: profile.id)
    get sensitive_content_cms_index_path(profile: profile.identifier, page: page.id, back: "true")
    assert_template 'sensitive_content'
    assert_select 'a.icon-back.option-back', 1
    assert_select 'a.icon-none.option-not-back', 0
  end

  protected

  # FIXME this is to avoid adding an extra dependency for a proper JSON parser.
  # For now we are assuming that the JSON is close enough to Ruby and just
  # making some adjustments.
  def parse_json_response
    eval(@response.body.gsub('":', '"=>').gsub('null', 'nil'))
  end

  def available_article_types
    @controller.send(:available_article_types)
  end

  def special_article_types
    @controller.send(:special_article_types)
  end

end
