# encoding: UTF-8
require_relative "../test_helper"

class ArticleTest < ActiveSupport::TestCase

  fixtures :environments

  def setup
    ActiveSupport::TestCase::setup
    user = User.current = create_user 'testing'
    @profile = user.person
  end
  attr_reader :profile

  should 'have and require an associated profile' do
    a = Article.new
    a.valid?
    assert a.errors[:profile_id.to_s].present?

    a.profile = profile
    a.valid?
    refute a.errors[:profile_id.to_s].present?
  end

  should 'require value for name' do
    a = Article.new
    a.valid?
    assert a.errors[:name.to_s].present?

    a.name = 'my article'
    a.valid?
    refute a.errors[:name.to_s].present?
  end

  should 'limit length of names' do
    a = build(Article, :name => 'a'*151)
    a.valid?
    assert a.errors[:name.to_s].present?

    a.name = 'a'*150
    a.valid?
    refute a.errors[:name.to_s].present?
  end

  should 'require value for slug and path if name is filled' do
    a = build(Article, :name => 'test article')
    a.slug = nil
    a.path = nil
    a.valid?
    assert a.errors[:slug.to_s].present?
    assert a.errors[:path.to_s].present?
  end

  should 'not require value for slug and path if name is blank' do
    a = Article.new
    a.valid?
    refute a.errors[:slug.to_s].present?
    refute a.errors[:path.to_s].present?
  end

  should 'act as versioned' do
    a = create(Article, :name => 'my article',
               :body => 'my text', :profile_id => profile.id)
    assert_equal 1, a.versions.size
    a.name = 'some other name'
    a.save!
    assert_equal 2, a.versions.size
  end

  should 'act as taggable' do
    a = create(Article, :name => 'my article', :profile_id => profile.id)
    a.tag_list = ['one', 'two']
    tags = a.tag_list
    assert tags.include?('one')
    assert tags.include?('two')
  end

  should 'act as filesystem' do
    a = create(Article, :profile_id => profile.id)
    b = create(Article, :profile_id => profile.id, :parent_id => a.id)
    b.save!
    assert_equal "#{a.slug}/#{b.slug}", b.path

    a = Article.find(a.id);
    a.name = 'another name'
    a.save!
    b.reload

    assert_equal "another-name/#{b.slug}", b.path
  end

  should 'provide HTML version' do
    profile = create_user('testinguser').person
    a = fast_create(Article, :name => 'my article', :profile_id => profile.id)
    a.expects(:body).returns('the body of the article')
    assert_equal 'the body of the article', a.to_html
  end

  should 'provide HTML version when body is nil' do
    a = fast_create(Article, :profile_id => profile.id, :body => nil)
    assert_equal '', a.to_html
  end

  should 'provide short html version' do
    a = fast_create(Article, :body => 'full body',
                    :abstract => 'lead', :profile_id => profile.id)
    expects(:display_short_format).with(a).once
    instance_eval(&a.to_html(:format=>'short'))
  end

  should 'provide full html version' do
    a = fast_create(Article, :body => 'full body', :abstract => 'lead')
    assert_equal 'full body', a.to_html(:format=>'full body')
  end

  should 'provide first paragraph of HTML version' do
    profile = create_user('testinguser').person
    a = fast_create(Article, :name => 'my article', :profile_id => profile.id)
    a.expects(:body).returns('<p>the first paragraph of the article</p><p>The second paragraph</p>')
    assert_equal '<p>the first paragraph of the article</p>', a.first_paragraph
  end

  should 'inform the icon to be used' do
    assert_equal 'text-html', Article.icon_name
  end

  should 'provide a (translatable) description' do
    result = 'the description'

    a = Article.new
    a.expects(:_).returns(result)
    assert_same result, a.mime_type_description
  end

  should 'not accept articles with same slug under the same level' do

    # top level articles first
    profile = create_user('testinguser').person
    a1 = profile.articles.build(:name => 'test')
    a1.save!

    # cannot add another top level article with same slug
    a2 = profile.articles.build(:name => 'test')
    a2.valid?
    assert a2.errors[:slug.to_s].present?

    # now create a child of a1
    a3 = profile.articles.build(:name => 'test')
    a3.parent = a1
    a3.valid?
    refute a3.errors[:slug.to_s].present?
    a3.save!

    # cannot add another child of a1 with same slug
    a4 = profile.articles.build(:name => 'test')
    a4.parent = a1
    a4.valid?
    assert a4.errors[:slug.to_s].present?
  end

  should 'last_changed_by be a person' do
    a = profile.articles.build(:name => 'test')

    # must be a person
    assert_raise ActiveRecord::AssociationTypeMismatch do
      a.last_changed_by = Profile.new
    end
    assert_nothing_raised do
      a.last_changed_by = Person.new
      a.save!
    end
  end

  should 'created_by be a person' do
    a = profile.articles.build(:name => 'test')

    # must be a person
    assert_raise ActiveRecord::AssociationTypeMismatch do
      a.created_by = Profile.new
    end
    assert_nothing_raised do
      a.created_by = Person.new
      a.save!
    end
  end

  should 'require that subclasses define description' do
    assert_raise NotImplementedError do
      Article.description
    end
  end

  should 'require that subclasses define short description' do
    assert_raise NotImplementedError do
      Article.short_description
    end
  end

  should 'indicate whether children articles are allowed or not' do
    assert_equal true, Article.new.allow_children?
  end

  should 'provide a url to itself' do
    article = create(Article, :name => 'myarticle', :profile_id => profile.id)
    assert_equal(profile.url.merge(:page => ['myarticle']), article.url)
  end

  should 'provide a url to itself having a parent topic' do
    parent = create(Article, :name => 'parent', :profile_id => profile.id)
    child = create(Article, :name => 'child', :parent => parent, :profile_id => profile.id)

    assert_equal(profile.url.merge(:page => [ 'parent', 'child']), child.url)
  end

  should 'associate with categories' do
    env = Environment.default
    parent_cat = create(Category, :name => "parent category", :environment_id => env.id)
    c1 = create(Category, :name => "test category 1", :parent_id => parent_cat.id, :environment_id => env.id)
    c2 = create(Category, :name => "test category 2", :environment_id => env.id)

    article = create(Article, :name => 'withcategories', :profile_id => profile.id)
    article.save!

    article.add_category c1
    article.add_category c2

    assert_equivalent [c1,c2], article.categories
    assert_equivalent [c1, parent_cat, c2], article.categories_including_virtual
  end

  should 'remove comments when removing article' do
    assert_no_difference 'Comment.count' do
      a = create(Article, :name => 'test article', :profile_id => profile.id)

      assert_difference 'Comment.count', 1 do
        comment = a.comments.build
        comment.author = profile
        comment.title = 'test comment'
        comment.body = 'you suck!'
        comment.save!
      end

      a.destroy
    end
  end

  should 'list most commented articles' do
    Article.delete_all
    a1 = create(TextArticle, :name => "art 1", :profile_id => profile.id)
    a2 = create(TextArticle, :name => "art 2", :profile_id => profile.id)
    a3 = create(TextArticle, :name => "art 3", :profile_id => profile.id)

    2.times { create(Comment, :title => 'test', :body => 'asdsad', :author => profile, :source => a2).save! }
    4.times { create(Comment, :title => 'test', :body => 'asdsad', :author => profile, :source => a3).save! }

    # should respect the order (more commented comes first)
    assert_equal [a3, a2, a1], profile.articles.most_commented(3)
  end

  should 'identify itself as a non-folder' do
    refute Article.new.folder?, 'should identify itself as non-folder'
  end

  should 'identify itself as a non-blog' do
    refute Article.new.blog?, 'should identify itself as non-blog'
  end

  should 'cache children count' do
    owner = create_user('testuser').person
    art = create(Article, :name => 'ytest', :profile_id => owner.id)

    # two children articles
    create(Article, :profile => owner, :name => 'c1', :parent_id => art.id)
    create(Article, :profile => owner, :name => 'c2', :parent_id => art.id)

    art.reload

    assert_equal 2, art.children_count
    assert_equal 2, art.children.size

  end

  should 'categorize in the entire category hierarchy' do
    c1 = create(Category, :environment => Environment.default, :name => 'c1')
    c2 = create(Category, :environment => Environment.default, :name => 'c2', :parent_id => c1.id)
    c3 = create(Category, :environment => Environment.default, :name => 'c3', :parent_id => c2.id)

    owner = create_user('testuser').person
    art = create(Article, :name => 'ytest', :profile_id => owner.id)

    art.add_category(c3)

    assert_equal [c3], art.categories
    assert_equal [art], c2.articles

    assert_includes c3.articles, art
    assert_includes c2.articles, art
    assert_includes c1.articles, art

    assert_includes art.categories_including_virtual, c2
    assert_includes art.categories_including_virtual, c1
  end

  should 'redefine the entire category set at once' do
    c1 = create(Category, :environment => Environment.default, :name => 'c1')
    c2 = create(Category, :environment => Environment.default, :name => 'c2', :parent_id => c1.id)
    c3 = create(Category, :environment => Environment.default, :name => 'c3', :parent_id => c2.id)
    c4 = create(Category, :environment => Environment.default, :name => 'c4', :parent_id => c1.id)
    owner = create_user('testuser').person
    art = create(Article, :name => 'ytest', :profile_id => owner.id)

    art.add_category(c4)

    art.category_ids = [c2,c3].map(&:id)

    assert_equivalent [c2, c3], art.categories
    assert_includes art.categories_including_virtual, c1
    refute art.categories_including_virtual.include?(c4)
  end

  should 'be able to create an article already with categories' do
    parent1 = fast_create(Category, :environment_id => Environment.default.id, :name => 'parent1')
    c1 = fast_create(Category, :environment_id => Environment.default.id, :name => 'c1', :parent_id => parent1.id)
    c2 = fast_create(Category, :environment_id => Environment.default.id, :name => 'c2')

    p = create_user('testinguser').person
    a = create(Article, :name => 'test', :category_ids => [c1.id, c2.id], :profile_id => p.id)

    assert_equivalent [c1, c2], a.categories
    assert_includes a.categories_including_virtual, parent1
  end

  should 'not add a category twice to article' do
    c1 = fast_create(Category, :environment_id => Environment.default.id, :name => 'c1')
    c2 = create(Category, :environment => Environment.default, :name => 'c2', :parent_id => c1.id)
    c3 = create(Category, :environment => Environment.default, :name => 'c3', :parent_id => c1.id)
    owner = create_user('testuser').person
    art = create(Article, :name => 'ytest', :profile_id => owner.id)
    art.category_ids = [c2,c3,c3].map(&:id)

    categories = art.categories
    categories_including_virtual = art.categories_including_virtual
    assert_not_includes categories, c1
    assert_includes categories, c2
    assert_includes categories, c3
    assert_includes categories_including_virtual, c1
    assert_includes categories_including_virtual, c2
    assert_includes categories_including_virtual, c3
  end

  should 'accept published attribute' do
    assert_respond_to Article.new, :published
    assert_respond_to Article.new, :published=
  end

  should 'make a copy of the article as child of it' do
    person = create_user('test_user').person
    a = create(Article, :name => 'test article', :body => 'some text', :profile_id => person.id)
    b = a.copy(:parent => a, :profile => a.profile)

    assert_includes a.children, b
    assert_equal 'some text', b.body
  end

  should 'make a copy of the article to other profile' do
    p1 = create_user('test_user1').person
    p2 = create_user('test_user2').person
    a = create(Article, :name => 'test article', :body => 'some text', :profile_id => p1.id)
    b = a.copy(:parent => a, :profile => p2)

    p2 = Person.find(p2.id)
    assert_includes p2.articles, b
    assert_equal 'some text', b.body
  end

  should 'mantain the type in a copy' do
    p = create_user('test_user').person
    a = fast_create(Folder, :name => 'test folder', :profile_id => p.id)
    b = a.copy(:parent => a, :profile => p)

    assert_kind_of Folder, b
  end

  should 'not copy slug' do
    a = fast_create(Article, :slug => 'slug123')
    b = a.copy({})
    assert a.slug != b.slug
  end

  should 'load article under an old path' do
    p = create_user('test_user').person
    a = create(Article, :name => 'old-name', :profile_id => p.id)
    old_path = a.explode_path
    a.name = 'new-name'
    a.save!

    page = Article.find_by_old_path old_path

    assert_equal a.path, page.path
  end

  should 'load new article name equal of another article old name' do
    p = create_user('test_user').person
    a1 = create(Article, :name => 'old-name', :profile_id => p.id)
    old_path = a1.explode_path
    a1.name = 'new-name'
    a1.save!
    a2 = p.articles.create!(:name => 'old-name')

    page = Article.find_by_old_path old_path

    assert_equal a2.path, page.path
  end

  should 'article with most recent version with the name must be loaded if no aritcle with the name' do
    p = create_user('test_user').person
    a1 = create(Article, :name => 'old-name', :profile_id => p.id)
    old_path = a1.explode_path
    a1.name = 'new-name'
    a1.save!
    a2 = create(Article, :name => 'old-name', :profile_id => p.id)
    a2.name = 'other-new-name'
    a2.save!

    page = Article.find_by_old_path old_path

    assert_equal a2.path, page.path
  end

  should 'not return an article of a different user' do
    p1 = create_user('test_user').person
    a = create(Article, :name => 'old-name', :profile_id => p1.id)
    old_path = a.explode_path
    a.name = 'new-name'
    a.save!

    p2 = create_user('another_user').person

    page = p2.articles.find_by_old_path old_path

    assert_nil page
  end

  should 'identify if belongs to blog' do
    p = create_user('user_blog_test').person
    blog = fast_create(Blog, :name => 'Blog test', :profile_id => p.id)
    post = fast_create(TextArticle, :name => 'First post', :profile_id => p.id, :parent_id => blog.id)
    assert post.belongs_to_blog?
  end

  should 'not belongs to blog' do
    p = create_user('user_blog_test').person
    folder = fast_create(Folder, :name => 'Not Blog', :profile_id => p.id)
    a = fast_create(TextArticle, :name => 'Not blog post', :profile_id => p.id, :parent_id => folder.id)
    refute a.belongs_to_blog?
  end

  should 'has comments notifier true by default' do
    a = Article.new
    assert a.notify_comments?
  end

  should 'has moderate comments false by default' do
    a = create(Article, :name => 'my article', :body => 'my text', :profile_id => profile.id)
    a.reload
    assert a.moderate_comments == false
  end

  should 'save a article with moderate comments as true' do
    a = create(Article, :name => 'my article', :body => 'my text', :profile_id => profile.id, :moderate_comments => true)
    a.reload
    assert a.moderate_comments
  end

  should 'moderate_comments? return true if moderate_comments variable is true' do
    a = Article.new
    a.moderate_comments= true
    assert a.moderate_comments?
  end

  should 'moderate_comments? return false if moderate_comments variable is false' do
    a = Article.new
    a.moderate_comments= false
    refute a.moderate_comments?
  end

  should 'hold hits count' do
    a = fast_create(Article, :name => 'Test article', :profile_id => profile.id)
    a.hits = 10
    a.save!
    a.reload
    assert_equal 10, a.hits
  end

  should 'increment hit counter when hitted' do
    a = fast_create(Article, :name => 'Test article', :profile_id => profile.id, :hits => 10)
    a.hit
    assert_equal 11, a.hits
    a.reload
    assert_equal 11, a.hits
  end

  should 'have display_hits setting with default true' do
    a = fast_create(Article, :name => 'Test article', :profile_id => profile.id)
    assert_respond_to a, :display_hits
    assert_equal true, a.display_hits
  end

  should 'can display hits' do
    a = fast_create(Article, :name => 'Test article', :profile_id => profile.id)
    assert_respond_to a, :can_display_hits?
    assert_equal true, a.can_display_hits?
  end

  should 'return a view url when image' do
    image = create(UploadedFile, :profile => profile, :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png'))

    assert_equal image.url.merge(:view => true), image.view_url
  end

  should 'not return a view url when common article' do
    a = fast_create(Article, :name => 'Test article', :profile_id => profile.id)

    assert_equal a.url, a.view_url
  end

  should 'have published_at' do
    assert_respond_to Article.new, :published_at
  end

  should 'fill published_at with current date if not set' do
    now = Time.now.in_time_zone
    Time.stubs(:now).returns(now)
    a = create(Article, :name => 'Published at', :profile_id => profile.id)
    assert_equal now, a.published_at
  end

  should 'use npage to compose cache key' do
    a = fast_create(Article, :name => 'Published at', :profile_id => profile.id)
    assert_match(/-npage-2/,a.cache_key(:npage => 2))
  end

  should 'use year and month to compose cache key' do
    a = fast_create(Article, :name => 'Published at', :profile_id => profile.id)
    assert_match(/-year-2009-month-04/, a.cache_key(:year => '2009', :month => '04'))
  end

 should 'use revision number to compose cache key' do
    a = fast_create(Article, :name => 'Versioned article', :profile_id => profile.id)
    assert_match(/-version-2/,a.cache_key(:version => 2))
  end

 should 'use language in cache key' do
   a = Article.new
   assert_not_equal a.cache_key({}, nil, ''), a.cache_key({}, nil, 'pt')
 end

  should 'not be highlighted by default' do
    a = Article.new
    refute a.highlighted
  end

  should 'get tagged with tag' do
    a = create(Article, :name => 'Published at', :profile_id => profile.id, :tag_list => 'bli')
    as = Article.tagged_with('bli')

    assert_includes as, a
  end

  should 'get tagged with tag that contains special chars' do
    a = create(Article, :name => 'Published at', :profile_id => profile.id, :tag_list => 'Métodos Ágeis')
    as = Article.tagged_with('Métodos Ágeis')

    assert_includes as, a
  end

  should 'not get tagged with tag from other environment' do
    article_from_this_environment = create(Article, :profile => profile, :tag_list => 'bli')

    other_environment = fast_create(Environment)
    user_from_other_environment = create_user('other_user', :environment => other_environment).person
    article_from_other_environment = create(Article, :profile => user_from_other_environment, :tag_list => 'bli')

    tagged_articles_in_other_environment = other_environment.articles.tagged_with('bli')

    assert_includes tagged_articles_in_other_environment, article_from_other_environment
    assert_not_includes tagged_articles_in_other_environment, article_from_this_environment
  end

  should 'ignore category with zero as id' do
    a = create(Article, :name => 'a test article', :profile_id => profile.id)
    c = fast_create(Category, :name => 'test category', :environment_id => profile.environment.id, :parent_id => 0)
    a.category_ids = ['0', c.id, nil]
    assert a.save
    assert_equal [c], a.categories
    # also ignore parent with id = 0
    assert_equal [c], a.categories_including_virtual

    a = profile.articles.find_by name: 'a test article'
    assert_equal [c], a.categories
  end

  should 'add owner on cache_key when has profile' do
    a = create(Article, :name => 'a test article', :profile_id => profile.id)
    assert_match(/-owner/, a.cache_key({}, profile))
  end

  should 'not add owner on cache_key when has no profile' do
    a = create(Article, :name => 'a test article', :profile_id => profile.id)
    assert_no_match(/-owner/, a.cache_key({}))
  end

  should 'add owner on cache_key when profile is community' do
    c = fast_create(Community)
    a = create(Article, :name => 'a test article', :profile_id => c.id)
    assert_match(/-owner/, a.cache_key({}, c))
  end

  should 'allow author to edit if is publisher' do
    c = fast_create(Community)
    p = create_user_with_permission('test_user', 'post_content', c)
    a = create(Article, :name => 'a test article', :author => p, :profile_id => c.id)

    assert a.allow_post_content?(p)
  end

  should 'allow user with "Manage content" permissions to edit' do
    c = fast_create(Community)
    p = create_user_with_permission('test_user', 'post_content', c)
    a = create(Article, :name => 'a test article', :profile_id => c.id)

    assert a.allow_post_content?(p)
  end

  should 'update slug from name' do
    article = create(Article, :name => 'A test article', :profile_id => profile.id)
    assert_equal 'a-test-article', article.slug
    article.name = 'Changed name'
    assert_equal 'changed-name', article.slug
  end

  should 'find articles in a specific category' do
    env = Environment.default
    parent_category = create(Category, :name => "parent category", :environment_id => env.id)
    category_with_articles = create(Category, :name => "Category with articles", :parent_id => parent_category.id, :environment_id => env.id)
    category_without_articles = create(Category, :name => "Category without articles", :environment_id => env.id)

    article_in_category = create(Article, :name => 'Article in category', :profile_id => profile.id)

    article_in_category.add_category(category_with_articles)

    assert_includes profile.articles.in_category(category_with_articles), article_in_category
    assert_includes profile.articles.in_category(parent_category), article_in_category
    assert_not_includes profile.articles.in_category(category_without_articles), article_in_category
  end

  should 'has external_link attr' do
    assert_nothing_raised do
      build(Article, :external_link => 'http://some.external.link')
    end
  end

  should 'validates format of external_link' do
    article = build(Article, :external_link => 'http://invalid-url')
    article.valid?
    assert_not_nil article.errors[:external_link]
  end

  should 'put http in external_link' do
    article = build(Article, :external_link => 'url.without.http')
    assert_equal 'http://url.without.http', article.external_link
  end

  should 'list only published articles' do
    profile = fast_create(Person)

    published  = create(Article, :name => 'Published',  :published => true, :profile_id => profile.id)
    unpublished = create(Article, :name => 'Unpublished', :published => false, :profile_id => profile.id)

    assert_equal [ published ], profile.articles.published
  end

  should 'sanitize tags after save article' do
    article = fast_create(Article, :slug => 'article-with-tags', :profile_id => profile.id)
    tag = build(Tag, name: "TV Web w<script type='javascript'></script>")
    assert_match /[<>]/, tag.name
    article.tag_list.add(tag.name)
    article.save!
    assert_no_match /[<>]/, article.tags.last.name
  end

  should 'strip HTML from tag names after save article' do
    article = fast_create(Article, :slug => 'article-with-tags', :profile_id => profile.id)
    tag = build(Tag, name: "TV Web w<script type=...")
    assert_match /</, tag.name
    article.tag_list.add(tag.name)
    article.save!
    assert_no_match /</, article.tags.last.name
  end

  should 'sanitize name before validation' do
    article = Article.new
    article.name = "<h1 Bla </h1>"
    article.valid?

    assert_no_match /<[^>]*</, article.name
  end

  should 'not doubly escape quotes in the name' do
    person = fast_create(Person)
    community = fast_create(Community)
    community.add_member(profile)
    article = fast_create(Article, :name => 'article name', :profile_id => person.id)
    a = create(ApproveArticle, :article => article, :target => community, :requestor => profile)
    a.finish

    article = community.articles.find_by(name: 'article name')
    article.name = 'title with "quotes"'
    article.save
    assert_equal 'title with "quotes"', article.name
  end

  should 'remove script tags from name' do
    a = build(Article, :name => 'hello <script>alert(1)</script>')
    a.valid?

    assert_no_match(/<script>/, a.name)
  end

  should 'return truncated title in short_title' do
    article = Article.new
    article.name = 'a123456789abcdefghij'
    assert_equal 'a123456789ab...', article.short_title
  end

  should 'return abstract as lead' do
    a = build(Article, :abstract => 'lead')
    assert_equal 'lead', a.lead
  end

  should 'return first paragraph as lead by default' do
    a = Article.new
    a.stubs(:first_paragraph).returns('<p>first</p>')
    assert_equal '<p>first</p>', a.lead
  end

  should 'return first paragraph as lead with empty but non-null abstract' do
    a = build(Article, :abstract => '')
    a.stubs(:first_paragraph).returns('<p>first</p>')
    assert_equal '<p>first</p>', a.lead
  end

  should 'return blank as lead when article has no paragraphs' do
    a = build(Article, :body => "<div>an article with content <em>but without</em> a paragraph</div>")
    assert_equal '', a.lead
  end

  should 'have short lead' do
    a = fast_create(TextArticle, :body => '<p>' + ('a' *180) + '</p>')
    assert_equal 170, a.short_lead.length
  end

  should 'remove html from short lead' do
    a = build(Article, :body => "<p>an article with html that should be <em>removed</em></p>")
    assert_equal 'an article with html that should be removed', a.short_lead
  end

  should 'track action when a article is created outside a community' do
    article = create(TextArticle, :profile_id => profile.id)
    ta = article.activity
    assert_equal article.name, ta.get_name
    assert_equal article.url, ta.get_url
  end

  should 'track action when a article is created in a community' do
    community = fast_create(Community)
    p1 = create_user.person
    p2 = create_user.person
    p3 = create_user.person
    community.add_member(p1)
    community.add_member(p2)
    User.current = p1.user

    article = create(TextArticle, :profile_id => community.id)
    activity = article.activity

    process_delayed_job_queue
    assert_equal 3, ActionTrackerNotification.where(action_tracker_id: activity.id).count
    assert_equivalent [p1,p2,community], ActionTrackerNotification.where(action_tracker_id: activity.id).map(&:profile)
  end

  should 'destroy activity when an article is removed' do
    a = create(TextArticle, :profile_id => profile.id)
    assert_difference 'ActionTracker::Record.count', -1 do
      a.destroy
    end
  end

  should 'notifiable is false by default' do
    a = fast_create(Article)
    refute a.notifiable?
  end

  should 'not notify activity by default on create' do
    ActionTracker::Record.delete_all
    create Article, :name => 'test', :profile_id => profile.id
    assert_equal 0, ActionTracker::Record.count
  end

  should 'not notify activity by default on update' do
    ActionTracker::Record.delete_all
    a = create Article, :name => 'bar', :profile_id => profile.id
    a.name = 'foo'
    a.save!
    assert_equal 0, ActionTracker::Record.count
  end

  should 'not notify activity by default on destroy' do
    ActionTracker::Record.delete_all
    a = create Article, :name => 'bar', :profile_id => profile.id
    a.destroy
    assert_equal 0, ActionTracker::Record.count
  end

  should 'create activity' do
    a = create TextArticle, :name => 'bar', :profile_id => profile.id
    a.activity.destroy
    assert_nil a.activity

    a.create_activity
    assert_not_nil a.activity
  end

  should "the action_tracker_target method be defined" do
    assert Article.method_defined?(:action_tracker_target)
  end

  should "the action_tracker_target method return the article profile" do
    profile = fast_create(Person)
    article = fast_create(Article, :profile_id => profile.id)
    assert_equal profile, article.action_tracker_target

    profile = fast_create(Community)
    article = fast_create(Article, :profile_id => profile.id)
    assert_equal profile, article.action_tracker_target
  end

  should 'create the notification to organization and all organization members' do
    Profile.destroy_all
    ActionTracker::Record.destroy_all

    community = fast_create(Community)
    User.current = create_user
    member_1 = User.current.person
    community.add_member(member_1)

    article = create TextArticle, :name => 'Tracked Article 1', :profile_id => community.id
    first_activity = article.activity
    assert_equal [first_activity], ActionTracker::Record.where(verb: 'create_article')

    process_delayed_job_queue
    assert_equal 2, ActionTrackerNotification.where(action_tracker_id: first_activity.id).count

    member_2 = fast_create(Person)
    community.add_member(member_2)

    article2 = create TextArticle, :name => 'Tracked Article 2', :profile_id => community.id
    second_activity = article2.activity
    assert_equivalent [first_activity, second_activity], ActionTracker::Record.where(verb: 'create_article')

    process_delayed_job_queue
    assert_equal 3, ActionTrackerNotification.where(action_tracker_id: second_activity.id).count
  end

  should 'create notifications to followers when creating an article' do
    friend = fast_create(Person)
    circle = Circle.create!(:person=> friend, :name => "Zombies", :profile_type => 'Person')
    friend.follow(profile, circle)
    User.current = profile.user
    article = create(TextArticle, :profile_id => profile.id)

    process_delayed_job_queue
    assert_equal friend, ActionTrackerNotification.last.profile
  end

  should 'create the notification to the follower when one follower has the notification and the other no' do
    f1 = fast_create(Person)
    circle = Circle.create!(:person=> f1, :name => "Zombies", :profile_type => 'Person')
    f1.follow(profile, circle)

    User.current = profile.user
    article = create TextArticle, :name => 'Tracked Article 1', :profile_id => profile.id
    assert_equal 1, ActionTracker::Record.where(verb: 'create_article').count
    process_delayed_job_queue
    assert_equal 2, ActionTrackerNotification.where(action_tracker_id: article.activity.id).count

    f2 = fast_create(Person)
    circle2 = Circle.create!(:person=> f2, :name => "Zombies", :profile_type => 'Person')
    f2.follow(profile, circle2)

    article2 = create TextArticle, :name => 'Tracked Article 2', :profile_id => profile.id
    assert_equal 2, ActionTracker::Record.where(verb: 'create_article').count
    process_delayed_job_queue
    assert_equal 3, ActionTrackerNotification.where(action_tracker_id: article2.activity.id).count
  end

  should 'destroy activity and notifications of followers when destroying an article' do
    friend = fast_create(Person)

    circle = Circle.create!(:person=> friend, :name => "Zombies", :profile_type => 'Person')

    friend.follow(profile, circle)

    User.current = profile.user
    article = create(TextArticle, :profile_id => profile.id)
    activity = article.activity

    process_delayed_job_queue
    assert_equal 2, ActionTrackerNotification.where(action_tracker_id: activity.id).count

    assert_difference 'ActionTrackerNotification.count', -2 do
      article.destroy
    end

    assert_raise ActiveRecord::RecordNotFound do
      ActionTracker::Record.find(activity.id)
    end
  end

  should 'destroy action_tracker and notifications when an article is destroyed in a community' do
    community = fast_create(Community)
    p1 = create_user.person
    p2 = create_user.person
    community.add_member(p1)
    community.add_member(p2)
    User.current = p1.user

    article = create(TextArticle, :profile_id => community.id)
    activity = article.activity

    process_delayed_job_queue
    assert_equal 3, ActionTrackerNotification.where(action_tracker_id: activity.id).count

    assert_difference 'ActionTrackerNotification.count', -3 do
      article.destroy
    end

    assert_raise ActiveRecord::RecordNotFound do
      ActionTracker::Record.find(activity.id)
    end
  end

  should 'found articles with published date between a range' do
    start_date = DateTime.parse('2010-07-06')
    end_date = DateTime.parse('2010-08-02')

    article_found1 = fast_create(Article, :published_at => start_date)
    article_found2 = fast_create(Article, :published_at => end_date)
    article_not_found = fast_create(Article, :published_at => end_date + 1.month)

    assert_includes Article.by_range(start_date..end_date), article_found1
    assert_includes Article.by_range(start_date..end_date), article_found2
    assert_not_includes Article.by_range(start_date..end_date), article_not_found
  end

  should 'calculate first/end day of a month' do
    assert_equal 1, (DateTime.parse('2010-07-06')).at_beginning_of_month.day
    assert_equal 31, (DateTime.parse('2010-07-06')).at_end_of_month.day
  end

  should 'not be a forum by default' do
    refute fast_create(Article).forum?
  end

  should 'not have posts by default' do
    refute fast_create(Article).has_posts?
  end

  should 'get article galleries' do
    a = fast_create(Article, :profile_id => profile.id)
    g = fast_create(Gallery, :profile_id => profile.id)
    assert_equal [g], profile.articles.galleries
  end

  should 'has many translations' do
    a = build(Article)
    assert_raises(ActiveRecord::AssociationTypeMismatch) { a.translations << 1 }
    assert_nothing_raised { a.translations << build(Article) }
  end

  should 'belongs to translation of' do
    a = build(Article)
    assert_raises(ActiveRecord::AssociationTypeMismatch) { a.translation_of = 1 }
    assert_nothing_raised { a.translation_of = build(Article) }
  end

  should 'has language' do
    a = build(Article)
    assert_nothing_raised { a.language = 'en' }
  end

  should 'validate inclusion of language' do
    a = build(Article, :profile_id => profile.id)
    a.language = '12'
    a.valid?
    assert a.errors[:language.to_s].present?
    a.language = 'en'
    a.valid?
    refute a.errors[:language.to_s].present?
  end

  should 'language can be blank' do
    a = build(Article)
    a.valid?
    refute a.errors[:language.to_s].present?
    a.language = ''
    a.valid?
    refute a.errors[:language.to_s].present?
  end

  should 'article is not translatable' do
    a = build(Article)
    refute a.translatable?
  end

  should 'get native translation' do
    native_article = fast_create(Article)
    article_translation = fast_create(Article)
    native_article.translations << article_translation
    assert_equal native_article, native_article.native_translation
    assert_equal native_article, article_translation.native_translation
  end

  should 'list possible translations' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => profile.id             )
    article_translation = fast_create(Article, :language => 'en', :translation_of_id => native_article.id)
    possible_translations = native_article.possible_translations
    refute possible_translations.include?('en')
    assert possible_translations.include?('pt')
  end

  should 'verify if translation is already in use' do
    native_article = fast_create(Article, :language => 'pt')
    article_translation = fast_create(Article, :language => 'en', :translation_of_id => native_article.id)
    a = build(Article, :profile => profile)
    a.language = 'en'
    a.translation_of = native_article
    a.valid?
    assert a.errors[:language.to_s].present?
    a.language = 'es'
    a.valid?
    refute a.errors[:language.to_s].present?
  end

  should 'verify if native translation is already in use' do
    native_article = fast_create(Article, :language => 'pt')
    a = build(Article, :profile => profile)
    a.language = 'pt'
    a.translation_of = native_article
    a.valid?
    assert a.errors[:language.to_s].present?
    a.language = 'es'
    a.valid?
    refute a.errors[:language.to_s].present?
  end

  should 'translation have a language' do
    native_article = fast_create(Article, :language => 'pt')
    a = build(Article, :profile_id => profile.id)
    a.translation_of = native_article
    a.valid?
    assert a.errors[:language.to_s].present?
    a.language = 'en'
    a.valid?
    refute a.errors[:language.to_s].present?
  end

  should 'native translation have a language' do
    native_article = fast_create(Article, :profile_id => profile.id             )
    a = build(Article, :profile_id => profile.id)
    a.language = 'en'
    a.translation_of = native_article
    a.valid?
    n = a.errors.count
    native_article.language = 'pt'
    native_article.save
    a.valid?
    assert_equal n - 1, a.errors.count
  end

  should 'rotate translations when root article is destroyed' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    fast_create(Article, :language => 'en', :translation_of_id => native_article.id, :profile_id => @profile.id)
    fast_create(Article, :language => 'es', :translation_of_id => native_article.id, :profile_id => @profile.id)

    new_root = native_article.translations.order(:created_at).first
    child = (native_article.translations - [new_root]).first
    native_article.destroy

    assert new_root.translation_of.nil?
    assert new_root.translations.include?(child)
  end

  should 'rotate one translation when root article is destroyed' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    translation = fast_create(Article, :language => 'en', :translation_of_id => native_article.id, :profile_id => @profile.id)
    native_article.destroy
    assert translation.translation_of.nil?
    assert translation.translations.empty?
  end

  should 'get self if article does not a language' do
    article = fast_create(Article, :profile_id => @profile.id)
    assert_equal article, article.get_translation_to('en')
  end

  should 'get self if language article is blank' do
    article = fast_create(Article, :language => '', :profile_id => @profile.id)
    assert_equal article, article.get_translation_to('en')
  end

  should 'get self if article is the translation' do
    article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    assert_equal article, article.get_translation_to('pt')
  end

  should 'get the native translation if it is the translation' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    translation = fast_create(Article, :language => 'en', :translation_of_id => native_article.id, :profile_id => @profile.id)
    assert_equal native_article, translation.get_translation_to('pt')
  end

  should 'get the translation if article has translation' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    translation = fast_create(Article, :language => 'en', :translation_of_id => native_article.id, :profile_id => @profile.id)
    assert_equal translation, native_article.get_translation_to('en')
  end

  should 'get self if article does not has a translation' do
    native_article = fast_create(Article, :language => 'pt', :profile_id => @profile.id)
    assert_nil native_article.get_translation_to('en')
  end

  should 'get only non translated articles' do
    profile.articles.delete_all
    native = fast_create(Article, :language => 'pt', :profile_id => profile.id)
    translation = fast_create(Article, :language => 'en', :translation_of_id => native.id, :profile_id => profile.id)
    assert_equal [native], profile.articles.native_translations
  end

  should 'not list own language as a possible translation if language has changed' do
    a = build(Article, :language => 'pt', :profile_id => profile.id)
    refute a.possible_translations.include?('pt')
    a = fast_create(Article, :language => 'pt', :profile_id => profile.id             )
    a.language = 'en'
    refute a.possible_translations.include?('en')
  end

  should 'list own language as a possible translation if language has not changed' do
    a = fast_create(Article, :language => 'pt', :profile_id => profile.id)
    assert a.possible_translations.include?('pt')
  end

  should 'have the author_name method defined' do
    assert Article.method_defined?('author_name')
  end

  should "the author_name returns the name of the article's author" do
    author = fast_create(Person)
    a = create(Article, :name => 'a test article', :author => author, :profile_id => profile.id)
    assert_equal author.name, a.author_name
    author.destroy
    a = Article.find(a.id)
    a.author_name = 'some name'
    assert_equal 'some name', a.author_name
  end

  should 'retrieve latest info from topic when has no comments' do
    forum = fast_create(Forum, :name => 'Forum test', :profile_id => profile.id)
    post = fast_create(TextArticle, :name => 'First post', :profile_id => profile.id, :parent_id => forum.id, :updated_at => Time.now.in_time_zone, :author_id => profile.id)
    assert_equal post.updated_at, post.info_from_last_update[:date]
    assert_equal profile.name, post.info_from_last_update[:author_name]
    assert_equal profile.url, post.info_from_last_update[:author_url]
  end

  should 'retrieve latest info from comment when has comments' do
    forum = fast_create(Forum, :name => 'Forum test', :profile_id => profile.id)
    post = fast_create(TextArticle, :name => 'First post', :profile_id => profile.id, :parent_id => forum.id, :updated_at => Time.now.in_time_zone)
    post.comments << build(Comment, :name => 'Guest', :email => 'guest@example.com', :title => 'test comment', :body => 'hello!')
    assert_equal post.comments.last.created_at, post.info_from_last_update[:date]
    assert_equal "Guest", post.info_from_last_update[:author_name]
    assert_nil post.info_from_last_update[:author_url]
  end

  should 'return only folders' do
    not_folders = [RssFeed, TextArticle, Event, TextArticle]
    folders = [Folder, Blog, Gallery, Forum]

    not_folders.each do |klass|
      item = fast_create(klass)
      assert_not_includes Article.folders(profile), item
    end

    folders.each do |klass|
      item = fast_create(klass)
      assert_includes Article.folders(profile), item
    end
  end

  should 'return no folders' do
    not_folders = [RssFeed, TextArticle, Event, TextArticle]
    folders = [Folder, Blog, Gallery, Forum]

    not_folders.each do |klass|
      item = fast_create(klass)
      assert_includes Article.no_folders(profile), item
    end

    folders.each do |klass|
      item = fast_create(klass)
      assert_not_includes Article.no_folders(profile), item
    end
  end

  should 'return top folders' do

    parent_folder_1 = fast_create(Folder, profile_id: profile.id)
    sub_folder_1 = fast_create(Blog, parent_id: parent_folder_1.id,
                                profile_id: profile.id)

    parent_folder_2 = fast_create(Folder, profile_id: profile.id)
    sub_folder_2 = fast_create(Blog, parent_id: parent_folder_2.id,
                                profile_id: profile.id)

    assert_includes Article.top_folders(profile), parent_folder_1
    assert_includes Article.top_folders(profile), parent_folder_2

    assert_not_includes Article.top_folders(profile), sub_folder_1
    assert_not_includes Article.top_folders(profile), sub_folder_2

  end

  should 'return subfolders' do

    parent_folder_1 = fast_create(Folder, profile_id: profile.id)
    sub_folder_1 = fast_create(Blog, parent_id: parent_folder_1.id,
                                profile_id: profile.id)

    parent_folder_2 = fast_create(Folder, profile_id: profile.id)
    sub_folder_2 = fast_create(Blog, parent_id: parent_folder_2.id,
                                profile_id: profile.id)

    assert_includes Article.subfolders(profile, parent_folder_1), sub_folder_1
    assert_not_includes Article.subfolders(profile, parent_folder_1), parent_folder_1

    assert_includes Article.subfolders(profile, parent_folder_2), sub_folder_2
    assert_not_includes Article.subfolders(profile, parent_folder_2), parent_folder_2
  end

  should 'accept uploads if parent accept uploads' do
    folder = fast_create(Folder)
    child = fast_create(UploadedFile, :parent_id => folder.id)
    assert folder.accept_uploads?
    assert child.accept_uploads?
  end

  should 'not accept uploads if has no parent' do
    child = fast_create(UploadedFile)
    refute child.accept_uploads?
  end

  should 'not accept uploads if parent is a forum' do
    folder = fast_create(Forum)
    child = fast_create(UploadedFile, :parent_id => folder.id)
    refute child.accept_uploads?
  end

  should 'get images paths in article body' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = build TextArticle, :profile => @profile
    a.body = 'Noosfero <img src="http://noosfero.com/test.png" /> test <img src="http://test.com/noosfero.png" />'
    assert_includes a.body_images_paths, 'http://noosfero.com/test.png'
    assert_includes a.body_images_paths, 'http://test.com/noosfero.png'
  end

  should 'always put article image first in images paths list in article body' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = create(TextArticle, :name => 'test', :image_builder => {
      :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')
    }, :profile_id => @profile.id)
    a.save!
    a.body = 'Noosfero <img src="http://noosfero.com/test.png" /> test <img src="http://test.com/noosfero.png" />'
    a.image.stubs(:public_filename).returns('/files/rails.png')
    assert_equal 'http://noosfero.org/files/rails.png', a.body_images_paths[0]
  end

  should 'escape utf8 characters correctly' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = build TextArticle, profile: @profile
    a.body = 'Noosfero <img src="http://noosfero.com/cabeça.png" /> '
    assert_includes a.body_images_paths, 'http://noosfero.com/cabe%C3%A7a.png'

    # check if after save (that is, after xss_terminate run)
    a.save!
    assert_includes a.body_images_paths, 'http://noosfero.com/cabe%C3%A7a.png'
  end

  should 'get absolute images paths in article body' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = build TextArticle, :profile => @profile
    a.body = 'Noosfero <img src="test.png" alt="Absolute" /> test <img src="/relative/path.png" />'
    assert_includes a.body_images_paths, 'http://noosfero.org/test.png'
    assert_includes a.body_images_paths, 'http://noosfero.org/relative/path.png'
  end

  should 'return empty if there are no images in article body' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = build Event, :profile => @profile
    a.body = 'Noosfero test'
    assert_equal [], a.body_images_paths
  end

  should 'return empty if body is nil' do
    Environment.any_instance.stubs(:default_hostname).returns('noosfero.org')
    a = build Article, :profile => @profile
    assert_equal [], a.body_images_paths
  end

  should 'survive to a invalid src attribute while looking for images in body' do
    domain = Environment.default.domains.first || build(Domain, :name => 'localhost')
    article = build(Article, :body => "An article with invalid src in img tag <img src='path with spaces.png' />", :profile => @profile)
    assert_nothing_raised do
      assert_equal ["http://#{profile.environment.default_hostname}/path%20with%20spaces.png"], article.body_images_paths
    end
  end

  should 'find more recent contents' do
    Article.delete_all

    c1 = fast_create(TextArticle, :name => 'Testing article 1', :body => 'Article body 1', :profile_id => profile.id, :created_at => DateTime.now - 4)
    c2 = fast_create(TextArticle, :name => 'Testing article 2', :body => 'Article body 2', :profile_id => profile.id, :created_at => DateTime.now - 1)
    c3 = fast_create(TextArticle, :name => 'Testing article 3', :body => 'Article body 3', :profile_id => profile.id, :created_at => DateTime.now - 3)

    assert_equal [c2,c3,c1] , Article.more_recent

    c4 = fast_create(TextArticle, :name => 'Testing article 4', :body => 'Article body 4', :profile_id => profile.id, :created_at => DateTime.now - 2)
    assert_equal [c2,c4,c3,c1] , Article.more_recent
  end

  should 'respond to more comments' do
    assert_respond_to Article, :more_comments
  end

  should 'respond to more popular' do
    assert_respond_to Article, :more_popular
  end

  should "return the more recent label" do
    a = Article.new
    assert_equal "Created at: ", a.more_recent_label
  end

  should "return no comments if profile has 0 comments" do
    a = Article.new
    assert_equal 0, a.comments_count
    assert_equal "no comments", a.more_comments_label
  end

  should "return 1 comment on label if the content has 1 comment" do
    a = build(Article, :comments_count => 1)
    assert_equal 1, a.comments_count
    assert_equal "one comment", a.more_comments_label
  end

  should "return number of comments on label if the content has more than one comment" do
    a = build(Article, :comments_count => 4)
    assert_equal 4, a.comments_count
    assert_equal "4 comments", a.more_comments_label
  end

  should "return no views if profile has 0 views" do
    a = Article.new
    assert_equal 0, a.hits
    assert_equal "no views", a.more_popular_label
  end

  should "return 1 view on label if the content has 1 view" do
    a = build(Article, :hits => 1)
    assert_equal 1, a.hits
    assert_equal "one view", a.more_popular_label
  end

  should "return number of views on label if the content has more than one view" do
    a = build(Article, :hits => 4)
    assert_equal 4, a.hits
    assert_equal "4 views", a.more_popular_label
  end

  should 'delegate region info to profile' do
    Person.any_instance.expects(:region)
    Person.any_instance.expects(:region_id)
    article = fast_create(Article, :profile_id => profile.id)
    article.region
    article.region_id
  end

  should 'delegate environment info to profile' do
    Person.any_instance.expects(:environment)
    Person.any_instance.expects(:environment_id)
    article = fast_create(Article, :profile_id => profile.id)
    article.environment
    article.environment_id
  end

  should 'remove all categorizations when destroyed' do
    art = create(Article, :name => 'article 1', :profile_id => fast_create(Person).id)
    cat = create(Category, :name => 'category 1', :environment_id => Environment.default.id)
    art.add_category cat
    art.destroy
    assert cat.articles.reload.empty?
  end

  should 'show more popular articles' do
    art1 = create(Article, :name => 'article 1',
                  :profile_id => fast_create(Person).id)
    art2 = create(Article, :name => 'article 2',
                  :profile_id => fast_create(Person).id)
    art3 = create(Article, :name => 'article 3',
                  :profile_id => fast_create(Person).id)

    art1.hits = 56; art1.save!
    art3.hits = 92; art3.save!
    art2.hits = 3; art2.save!

    articles = Article.more_popular
    assert articles.index(art3) < articles.index(art1)
    assert articles.index(art1) < articles.index(art2)
  end

  should 'not allow all community members to edit by default' do
    community = fast_create(Community)
    admin = fast_create(Person)
    member = fast_create(Person)
    community.add_admin(admin)
    community.reload
    community.add_member(member)
    a = build(Article, :profile => community)

    assert_equal false, a.allow_members_to_edit
    assert_equal false, a.allow_edit?(member)
  end

  should 'be able to allow all members of a community to edit' do
    community = fast_create(Community)
    admin = create_user('community-admin').person
    member = create_user.person

    community.add_admin(admin)
    community.add_member(member)
    a = build(Article, :profile => community)

    a.allow_members_to_edit = true

    assert_equal true, a.allow_edit?(member)
  end

  should 'not crash on allow_edit without a current user' do
    a = build(Article)
    a.allow_members_to_edit = true
    refute a.allow_edit?(nil)
  end

  should 'allow author to edit topic' do
    community = fast_create(Community)
    admin = fast_create(Person)
    community.add_member(admin)
    author = fast_create(Person)
    community.add_member(author)
    forum = Forum.create(:profile => community, :name => 'Forum test', :body => 'Forum test')
    post = fast_create(TextArticle, :name => 'First post', :profile_id => community.id, :parent_id => forum.id, :author_id => author.id)

    assert post.allow_edit?(author)
  end

  should 'get first image from lead' do
    a = fast_create(Article, :body => '<p>Foo</p><p><img src="bar.png" />Bar<img src="foo.png" /></p>',
                             :abstract => '<p>Lead</p><p><img src="leadbar.png" />Bar<img src="leadfoo.png" /></p>')
    assert_equal 'leadbar.png', a.first_image
  end

  should 'get first image from body' do
    a = fast_create(Article, :body => '<p>Foo</p><p><img src="bar.png" />Bar<img src="foo.png" /></p>')
    assert_equal 'bar.png', a.first_image
  end

  should 'get first image from having_image' do
    a = fast_create(Article,
      :body => '<p>Foo</p><p><img src="bar.png" /></p>',
      :abstract => '<p>Lead</p><p><img src="lead.png" /></p>'
    )
    img = {}
    img.expects(:present?).returns true
    img.expects(:public_filename).with(:uploaded).returns 'pic.jpg'
    a.expects(:image).at_least_once.returns img
    assert_equal 'pic.jpg', a.first_image
  end

  should 'not get first image from anywhere' do
    a = fast_create(Article, :body => '<p>Foo</p><p>Bar</p>')
    assert_equal '', a.first_image
  end

  should 'store first image in tracked action' do
    a = create TextArticle, :name => 'Tracked Article', :body => '<p>Foo<img src="foo.png" />Bar</p>', :profile_id => profile.id
    assert_equal 'foo.png', a.first_image
    assert_equal 'foo.png', ActionTracker::Record.last.get_first_image
  end

  should 'be able to have a license' do
    license = create(License, :name => 'GPLv3', :environment => Environment.default)
    article = build(Article, :license_id => license.id)
    assert_equal license, article.license
  end

  should 'return license from a specific version' do
    cc = License.create!(:name => 'CC', :environment => Environment.default)
    gpl = License.create!(:name => 'GPLv3', :environment => Environment.default)
    article = create(Article, :name => 'first version', :profile => profile, :license => cc)
    article.license = gpl
    article.save
    assert_equal cc, article.version_license(1)
    assert_equal gpl, article.version_license(2)
  end

  should 'update path if parent is changed' do
    f1 = create(Folder, :name => 'Folder 1', :profile => profile)
    f2 = create(Folder, :name => 'Folder 2', :profile => profile)
    article = create(TextArticle, :name => 'Sample Article', :parent_id => f1.id, :profile => profile)
    assert_equal [f1.path,article.slug].join('/'), article.path

    article.parent = f2
    article.save!
    assert_equal [f2.path,article.slug].join('/'), article.path

    article.parent = nil
    article.save!
    assert_equal article.slug, article.path

    article.parent = f2
    article.save!
    assert_equal [f2.path,article.slug].join('/'), article.path
  end

  should 'not allow parent as itself' do
    article = create(Article, :name => 'Sample Article', :profile => profile)
    article.parent = article
    article.valid?

    assert article.errors[:parent_id.to_s].present?
  end

  should 'not allow cyclical paternity' do
    a1 = create(Article, :name => 'Sample Article 1', :profile => profile)
    a2 = create(Article, :name => 'Sample Article 2', :profile => profile, :parent => a1)
    a3 = create(Article, :name => 'Sample Article 3', :profile => profile, :parent => a2)
    a1.parent = a3
    a1.valid?

    assert a1.errors[:parent_id.to_s].present?
  end

  should 'set author_name before creating article if there is an author' do
    author = fast_create(Person)
    article = create(Article, :name => 'Test', :profile => profile, :author => author)
    assert_equal author.name, article.author_name

    author_name = author.name
    author.destroy
    article = Article.find(article.id)
    assert_equal author_name, article.author_name
  end

  should "author_id return the author id of the article's author" do
    author = fast_create(Person)
    article = create(Article, :name => 'Test', :profile => profile, :author => author)
    assert_equal author.id, article.author_id
  end

  should "author_id return nil if there is no article's author" do
    article = create(Article, :name => 'Test', :profile => profile, :author => nil)
    assert_nil article.author_id
  end

  should "return the author_name of a specific version" do
    author1 = fast_create(Person)
    author2 = fast_create(Person)
    article = create(Article, :name => 'first version', :profile => profile, :author => author1, :last_changed_by => author1)
    article.name = 'second version'
    article.last_changed_by = author2
    article.save
    assert_equal author1.name, article.author_name(1)
    assert_equal author2.name, article.author_name(2)
  end

  should 'identify if belongs to forum' do
    p = create_user('user_forum_test').person
    forum = fast_create(Forum, :name => 'Forum test', :profile_id => p.id)
    post = fast_create(TextArticle, :name => 'First post', :profile_id => p.id, :parent_id => forum.id)
    assert post.belongs_to_forum?
  end

  should 'not belongs to forum' do
    p = create_user('user_forum_test').person
    blog = fast_create(Blog, :name => 'Not Forum', :profile_id => p.id)
    a = fast_create(TextArticle, :name => 'Not forum post', :profile_id => p.id, :parent_id => blog.id)
    refute a.belongs_to_forum?
  end

  should 'not belongs to forum if do not have a parent' do
    p = create_user('user_forum_test').person
    a = fast_create(TextArticle, :name => 'Orphan post', :profile_id => p.id)
    refute a.belongs_to_forum?
  end

  should 'save image on create article' do
    assert_difference 'Article.count' do
      p = create(Article, :name => 'test', :image_builder => {
        :uploaded_data => fixture_file_upload('/files/rails.png', 'image/png')
      }, :profile_id => @profile.id)
      assert_equal p.image.filename, 'rails.png'
    end
  end

  should 'return articles with specific types' do
    Article.delete_all

    c1 = fast_create(TextArticle, :name => 'Testing article 1', :body => 'Article body 2', :profile_id => profile.id)
    c3 = fast_create(Event, :name => 'Testing article 3', :body => 'Article body 3', :profile_id => profile.id)
    c4 = fast_create(RssFeed, :name => 'Testing article 4', :body => 'Article body 4', :profile_id => profile.id)
    c5 = fast_create(TextArticle, :name => 'Testing article 5', :body => 'Article body 5', :profile_id => profile.id)

    assert_equivalent [c1,c5], Article.with_types(['TextArticle'])
    assert_equivalent [c3], Article.with_types(['Event'])
  end

  should 'not create version when receive a comment' do
    a = Article.new(:name => 'my article', :body => 'my text')
    a.profile = profile
    a.save!
    Comment.create!(:title => 'test', :body => 'asdsad', :author => profile, :source => a)
    assert_equal 1, a.versions.count
  end

  should 'get specific version' do
    article = Article.create!(:name => 'first version', :profile => profile)
    article.name = 'second version'
    article.save!
    article.name = 'third version'
    article.save!

    assert_equal 'first version',  article.get_version(1).name
    assert_equal 'second version', article.get_version(2).name
    assert_equal 'third version',  article.get_version(3).name
  end

  should 'get author by version' do
    p1 = fast_create(Person)
    p2 = fast_create(Person)
    p3 = fast_create(Person)
    article = create(Article, :name => 'first version', :profile => profile, :author => p1, :last_changed_by => p1)

    article.name = 'second version'
    article.last_changed_by = p2
    article.save!

    article.last_changed_by = p3
    article.name = 'third version'
    article.save!

    assert_equal p1, article.author_by_version(1)
    assert_equal p2, article.author_by_version(2)
    assert_equal p3, article.author_by_version(3)
  end

  should 'not allow article access requirement to be lower than the profile access' do
    user = create_user('someuser').person
    user2 = create_user('otheruser', {}, {:access => 10}).person
    refute user.is_a_friend?(user2)
    Article.delete_all
    assert_raises(ActiveRecord::RecordInvalid) do
      create(Article, access: user.access - 1, :profile_id => user2)
    end
  end

    should 'update access to match profile access when it becomes higher' do
    user = fast_create(Person)
    profile = fast_create(Profile)
    article_users = fast_create(Article, access: Entitlement::Levels.levels[:users], :profile_id => profile.id)
    article_visitors = fast_create(Article, access: Entitlement::Levels.levels[:visitors], :profile_id => profile.id)
    profile.access = Entitlement::Levels.levels[:self]
    profile.save!

    article_users.reload
    article_visitors.reload
    assert_equal article_users.access, profile.access
    assert_equal article_visitors.access, profile.access
  end

  should 'update hit attribute of article array' do
    a1 = fast_create(Article)
    a2 = fast_create(Article)
    a3 = fast_create(Article)
    Article.hit([a1, a2, a3])
    Article.hit([a2, a3])

    assert_equal [1, 2, 2], [a1.hits, a2.hits, a3.hits]
    assert_equal [1, 2, 2], [a1.reload.hits, a2.reload.hits, a3.reload.hits]
  end

  should 'not update hit attribute of archiveds articles' do
    a1 = fast_create(Article)
    a2 = fast_create(Article, :archived => true)
    a3 = fast_create(Article, :archived => true)
    Article.hit([a1, a2, a3])

    assert_equal [1, 0, 0], [a1.hits, a2.hits, a3.hits]
    assert_equal [1, 0, 0], [a1.reload.hits, a2.reload.hits, a3.reload.hits]
  end

  should 'vote in a article' do
    article = create(Article, :name => 'Test',
                     :profile => profile, :last_changed_by => nil)
    profile.vote(article, 5)
    assert_equal 1, article.voters_who_voted.length
    assert_equal 5, article.votes_total
  end

  should 'be able to remove a voted article' do
    article = create(Article, :name => 'Test',
                     :profile => profile, :last_changed_by => nil)
    profile.vote(article, 5)
    article.destroy
  end

  should 'be able to vote in an article without a user' do
    article = create(Article, :name => 'Test',
                     :profile => profile,
                     :last_changed_by => nil)
    assert_difference 'article.votes_for', 2 do
      Vote.create!(:voteable => article, :vote => 1)
      Vote.create!(:voteable => article, :vote => 1)
    end
  end

  should 'have can_display_media_panel with default false' do
    a = Article.new
    assert !a.can_display_media_panel?
  end

  should 'display media panel when allowed by the environment' do
    a = Article.new
    a.expects(:can_display_media_panel?).returns(true)
    environment = mock
    a.expects(:environment).returns(environment)
    environment.expects(:enabled?).with('media_panel').returns(true)
    assert a.display_media_panel?
  end

  should 'not display media panel when not allowed by the environment' do
    a = Article.new
    a.expects(:can_display_media_panel?).returns(true)
    environment = mock
    a.expects(:environment).returns(environment)
    environment.expects(:enabled?).with('media_panel').returns(false)
    assert !a.display_media_panel?
  end

  should 'have display_preview' do
    a = Article.new(:display_preview => false)
    assert !a.display_preview?
  end

  should 'return full_path' do
    p1 = fast_create(Profile)
    p2 = fast_create(Profile)
    p2.domains << Domain.create!(:name => 'p2.domain')
    a1 = fast_create(Article, :profile_id => p1.id)
    a2 = fast_create(Article, :profile_id => p2.id)

    assert_equal "/#{p1.identifier}/#{a1.path}", a1.full_path
    assert_equal "/#{a2.path}", a2.full_path
  end

  should "increment followers count when a person follow an article" do
    a = fast_create(Article)
    p = fast_create(Person)
    assert_difference "a.reload.followers_count" do
      a.person_followers << p
    end
  end

  should "decrement followers count when a person unfollow an article" do
    p = fast_create(Person)
    a = fast_create(Article, :profile_id => p)
    a.person_followers << p
    assert_difference "a.reload.followers_count", -1 do
      a.person_followers.destroy_all
    end
  end

  should 'the owner not in followers list' do
    person1 = create_user('article_owner').person
    person2 = create_user('article_follower').person

    article = fast_create(Article, :profile_id => person1.id)

    article.person_followers=[person2]
    article.save
    article.reload
    article.person_followers=[person2]
    article.save

    assert_equal [person2], article.reload.person_followers
  end

  should 'has a empty list of followers by default' do
    a = Article.new
    assert_equal [], a.person_followers
  end

  should 'a follower not be duplicated' do
    follower = create_user('article_follower').person

    article = fast_create(Article, :profile_id => fast_create(Person))

    article.person_followers<< follower
    assert_raises (ActiveRecord::RecordNotUnique)\
    { article.person_followers<< follower }
  end

  should 'an article be follower by many users' do
    article = fast_create(Article, :profile_id => fast_create(Person))

    1.upto(10).map do |n|
      article.person_followers<< fast_create(Person)
    end
    article.save
    assert_equal 10, article.reload.person_followers.count
  end

  should 'check if a article is archived' do
    folder = Folder.create!(:name => 'Parent Archived', :profile => profile)
    a1 = Article.create!(:name => 'Test',
                         :profile => profile,
                         :parent_id => folder.id, :archived => false)
    a2 = Article.create!(:name => 'Test 2',
                         :profile => profile,
                         :archived => true)
    folder.update_attributes(:archived => true)
    a1.reload

    assert a1.archived?
    assert a2.archived?
  end

  should 'try add a child article to a archived folder' do
    folder = Folder.create!(:name => 'Parent Archived',
                            :profile => profile, :archived => true)

    err = assert_raises ActiveRecord::RecordInvalid do
      a1 = Article.create!(:name => 'Test',
                           :profile => profile,
                           :parent_id => folder.id, :archived => false)
    end

    assert_match 'Parent folder is archived', err.message
  end

  should 'have can_display_blocks with default true' do
    assert Article.can_display_blocks?
  end

  should 'is_editor true if the article editor is the same as te editor parameter' do
    article = Article.new(:editor => Article::Editor::TEXTILE)
    assert article.editor?(Article::Editor::TEXTILE)
    article = Article.new(:editor => Article::Editor::TINY_MCE)
    assert article.editor?(Article::Editor::TINY_MCE)
    article = Article.new(:editor => Article::Editor::RAW_HTML)
    assert article.editor?(Article::Editor::RAW_HTML)
  end

  should 'is_editor false if the article editor is not the same as te editor parameter' do
    article = Article.new(:editor => Article::Editor::TEXTILE)
    assert !article.editor?(Article::Editor::TINY_MCE)
    article = Article.new(:editor => Article::Editor::TINY_MCE)
    assert !article.editor?(Article::Editor::TEXTILE)
    article = Article.new(:editor => Article::Editor::RAW_HTML)
    assert !article.editor?(Article::Editor::TINY_MCE)
  end

  RESERVED_SLUGS = %w[
    about
    activities
  ]

  RESERVED_SLUGS.map do |reserved|
    define_method "test_should_not_create_an_article_with_#{reserved}_title" do
      article = fast_create(Article)
      article.name = reserved
      article.valid?
      assert !article.errors[:title].empty?
    end
  end

  should 'not save custom fields without value' do
    article = fast_create(Article)
    article.metadata = {'custom_fields' => {'text_1' => {'value' => ''}}}
    refute article.valid?
  end

  should 'save custom fields' do
    article = fast_create(Article)
    article.metadata = {'custom_fields' => {'text_1' => {'value' => '10'}, 'text_2' => {'value' => '19'}}}
    assert article.valid?
  end

  should 'sanitize custom field keys' do
    article = fast_create(Article)
    article.metadata = {'custom_fields' => {'Text 1' => {'value' => '10'}}}
    article.save

    refute article.metadata['custom_fields']['Text 1'].present?
    assert article.metadata['custom_fields']['text-1'].present?
  end

  should 'return environment name as author if no author name available' do
    article = fast_create(Article)
    article.author = nil
    assert_equal article.environment.name, article.author_name
  end

  should 'filter contents for visitor' do
    visitors = fast_create(Article, access: Entitlement::Levels.levels[:visitors])
    users    = fast_create(Article, access: Entitlement::Levels.levels[:users])
    related  = fast_create(Article, access: Entitlement::Levels.levels[:related])
    selfie   = fast_create(Article, access: Entitlement::Levels.levels[:self])

    user = nil

    assert_includes Article.accessible_to(user), visitors
    assert_not_includes Article.accessible_to(user), users
    assert_not_includes Article.accessible_to(user), related
    assert_not_includes Article.accessible_to(user), selfie
  end

  should 'filter contents for user' do
    visitors = fast_create(Article, access: Entitlement::Levels.levels[:visitors])
    users    = fast_create(Article, access: Entitlement::Levels.levels[:users])
    related  = fast_create(Article, access: Entitlement::Levels.levels[:related])
    selfie   = fast_create(Article, access: Entitlement::Levels.levels[:self])

    user = fast_create(Person)

    assert_includes Article.accessible_to(user), visitors
    assert_includes Article.accessible_to(user), users
    assert_not_includes Article.accessible_to(user), related
    assert_not_includes Article.accessible_to(user), selfie
  end

  should 'filter contents for friend' do
    person   = fast_create(Person)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:related], profile_id: person.id)

    not_friend = fast_create(Person)
    friend = fast_create(Person)
    person.add_friend(friend)

    assert_includes Article.accessible_to(friend), article
    assert_not_includes Article.accessible_to(not_friend), article
  end

  should 'filter contents for member' do
    group    = fast_create(Organization)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:related], profile_id: group.id)

    not_member = fast_create(Person)
    member = fast_create(Person)
    group.add_member(member)

    assert_includes Article.accessible_to(member), article
    assert_not_includes Article.accessible_to(not_member), article
  end

  should 'filter contents for owner' do
    profile  = fast_create(Person)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:self], profile_id: profile.id)

    not_owner = fast_create(Person)
    owner = profile

    assert_includes Article.accessible_to(owner), article
    assert_not_includes Article.accessible_to(not_owner), article
  end

  should 'filter contents for profile administrator' do
    profile  = fast_create(Profile)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:self], profile_id: profile.id)

    not_admin = fast_create(Person)
    admin = fast_create(Person)
    profile.add_admin(admin)

    assert_includes Article.accessible_to(admin), article
    assert_not_includes Article.accessible_to(not_admin), article
  end

  should 'filter contents for environment administrator' do
    profile  = fast_create(Profile)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:self], profile_id: profile.id)

    not_admin = fast_create(Person)
    admin = fast_create(Person)
    profile.environment.add_admin(admin)

    assert_includes Article.accessible_to(admin), article
    assert_not_includes Article.accessible_to(not_admin), article
  end

  should 'filter contents for user with view_private_content permission' do
    profile  = fast_create(Profile)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:self], profile_id: profile.id)

    without_permission = fast_create(Person)
    with_permission = fast_create(Person)
    role = Role.create!(:name => 'role1', key: "test_role", permissions: ['view_private_content'])
    profile.affiliate(with_permission, role)

    assert_includes Article.accessible_to(with_permission), article
    assert_not_includes Article.accessible_to(without_permission), article
  end

  should 'filter contents for user that has a privacy exception' do
    profile  = fast_create(Profile)
    article  = fast_create(Article, access: Entitlement::Levels.levels[:self], profile_id: profile.id)

    without_privacy_exception = fast_create(Person)
    with_privacy_exception= fast_create(Person)
    article.article_privacy_exceptions << with_privacy_exception

    assert_includes Article.accessible_to(with_privacy_exception), article
    assert_not_includes Article.accessible_to(without_privacy_exception), article
  end

  should 'only return articles that are relevant as recent' do
    article1 = fast_create(TextArticle)
    article2 = fast_create(Article)
    blog = fast_create(Blog)
    gallery = fast_create(Gallery)
    feed = fast_create(RssFeed)
    file = fast_create(UploadedFile)

    articles = Article.relevant_as_recent
    assert_includes articles, article1
    assert_includes articles, article2
    assert_not_includes articles, blog
    assert_not_includes articles, gallery
    assert_not_includes articles, feed
    assert_not_includes articles, file
  end
end
