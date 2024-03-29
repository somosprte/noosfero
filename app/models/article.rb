class Article < ApplicationRecord

  module Editor
    TEXTILE = 'textile'
    TINY_MCE = 'tiny_mce'
    RAW_HTML = 'raw_html'
  end

  include SanitizeHelper
  include SanitizeTags
  include Entitlement::SliderHelper
  include Entitlement::ArticleJudge

  attr_accessible :name, :body, :abstract, :profile, :tag_list, :parent,
                  :allow_members_to_edit, :translation_of_id, :language,
                  :license_id, :parent_id, :display_posts_in_current_language,
                  :category_ids, :posts_per_page, :moderate_comments,
                  :accept_comments, :feed, :published, :source, :source_name,
                  :highlighted, :notify_comments, :display_hits, :slug,
                  :external_feed_builder, :display_versions, :external_link,
                  :image_builder, :show_to_followers, :archived,
                  :author, :display_preview, :published_at, :person_followers,
                  :editor, :metadata, :position, :access

  extend ActsAsHavingImage::ClassMethods
  acts_as_having_image
  acts_as_list scope: :profile

  include Noosfero::Plugin::HotSpot

  SEARCHABLE_FIELDS = {
    :name => {:label => _('Name'), :weight => 10},
    :abstract => {:label => _('Abstract'), :weight => 3},
    :body => {:label => _('Content'), :weight => 2},
    :slug => {:label => _('Slug'), :weight => 1},
    :filename => {:label => _('Filename'), :weight => 1},
  }

  SEARCH_FILTERS = {
    :order => %w[more_recent more_popular more_comments more_relevant],
    :display => %w[full]
  }

  N_('article')

  def self.inherited(subclass)
    subclass.prepend StringTemplate
    super
  end

  def initialize(*params)
    super
    if params.present? && params.first.present?
      if params.first.symbolize_keys.has_key?(:published)
        self.published = params.first.symbolize_keys[:published]
      end
    end
  end

  def self.default_search_display
    'full'
  end

  #FIXME This is necessary because html is being generated on the model...
  include ActionView::Helpers::TagHelper

  # use for internationalizable human type names in search facets
  # reimplement on subclasses
  def self.type_name
    _('Content')
  end

  track_actions :create_article, :after_create, :keep_params => [:name, :title, :url, :lead, :first_image], :if => Proc.new { |a| a.notifiable? }

  before_create do |article|
    if article.author
      article.author_name = article.author.name
    end
  end

  belongs_to :profile, optional: true
  validates_presence_of :profile_id, :name
  validates_presence_of :slug, :path, :if => lambda { |article| !article.name.blank? }

  validates_length_of :name, :maximum => 150
  validate :validate_custom_fields

  before_save :sanitize_custom_field_keys

  validates_uniqueness_of :slug, :scope => ['profile_id', 'parent_id'], :message => N_('The title (article name) is already being used by another article, please use another title.'), :if => lambda { |article| !article.slug.blank? }

  belongs_to :author, class_name: 'Person', optional: true
  belongs_to :last_changed_by, class_name: 'Person', foreign_key: 'last_changed_by_id', optional: true
  belongs_to :created_by, class_name: 'Person', foreign_key: 'created_by_id', optional: true

  has_many :comments, -> { order 'created_at asc' }, class_name: 'Comment', as: 'source', dependent: :destroy

  has_many :article_followers, dependent: :destroy
  has_many :person_followers, class_name: 'Person', through: :article_followers, source: :person
  has_many :person_followers_emails, -> { select :email }, class_name: 'User', through: :person_followers, source: :user

  has_many :article_categorizations, -> { where 'articles_categories.virtual = ?', false }
  has_many :categories, through: :article_categorizations

  has_many :article_categorizations_including_virtual, class_name: 'ArticleCategorization'
  has_many :categories_including_virtual, through: :article_categorizations_including_virtual, source: :category

  extend ActsAsHavingSettings::ClassMethods
  acts_as_having_settings field: :setting

  store_accessor :metadata
  include MetadataScopes

  settings_items :display_hits, :type => :boolean, :default => true
  settings_items :author_name, :type => :string, :default => ""
  settings_items :allow_members_to_edit, :type => :boolean, :default => false
  settings_items :moderate_comments, :type => :boolean, :default => false
  has_and_belongs_to_many :article_privacy_exceptions, class_name:  'Person', :join_table => 'article_privacy_exceptions'

  belongs_to :reference_article, class_name: "Article", foreign_key: 'reference_article_id', optional: true

  belongs_to :license, optional: true

  has_many :translations, class_name: 'Article', foreign_key: :translation_of_id
  belongs_to :translation_of, class_name: 'Article', foreign_key: :translation_of_id, optional: true
  before_destroy :rotate_translations

  acts_as_voteable

  before_create do |article|
    article.published_at ||= Time.now
    if article.reference_article && !article.parent
      parent = article.reference_article.parent
      if parent && parent.blog? && article.profile.has_blog?
        article.parent = article.profile.blog
      end
    end

    if article.created_by
      article.author_name = article.created_by.name
    end

  end

  after_destroy :destroy_activity
  def destroy_activity
    self.activity.destroy if self.activity
  end

  after_destroy :destroy_link_article
  def destroy_link_article
    Article.where(reference_article_id: self.id, type: 'LinkArticle').destroy_all
  end

  xss_terminate only: [ :name ], on: :validation, with: :white_list

  scope :in_category, -> category {
    includes('categories_including_virtual').where('categories.id' => category.id)
  }

  scope :relevant_as_recent, -> {
    where "(articles.type != 'UploadedFile' and articles.type != 'RssFeed' and
            articles.type != 'Gallery' and articles.type != 'Blog') OR
           articles.type is NULL"
  }

  include TimeScopes

  scope :by_range, -> range {
    where 'articles.published_at BETWEEN :start_date AND :end_date', { start_date: range.first, end_date: range.last }
  }

  URL_FORMAT = /\A(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(([0-9]{1,5})?\/.*)?\Z/ix

  validates_format_of :external_link, :with => URL_FORMAT, :if => lambda { |article| !article.external_link.blank? }
  validate :known_language
  validate :used_translation
  validate :native_translation_must_have_language
  validate :translation_must_have_language

  validate :no_self_reference
  validate :no_cyclical_reference, :if => 'parent_id.present?'

  validate :parent_archived?

  validate :valid_slug
  validate :access_value

  RESERVED_SLUGS = %w[
    about
    activities
  ]

  def valid_slug
    errors.add(:title, _('is not available as article name.')) unless Article.is_slug_available?(slug)
  end

  def access_value
    if profile.present? && access < profile.access
      self.errors.add(:access, _('can not be less restrictive than this profile access which is: %s.') % Entitlement::Levels.label(profile.access, profile))
    end
  end

  def self.is_slug_available?(slug)
    !RESERVED_SLUGS.include?(slug)
  end

  def no_self_reference
    errors.add(:parent_id, _('self-reference is not allowed.')) if id && parent_id == id
  end

  def no_cyclical_reference
    current_parent = Article.find(parent_id)
    while current_parent
      if current_parent == self
        errors.add(:parent_id, _('cyclical reference is not allowed.'))
        break
      end
      current_parent = current_parent.parent
    end
  end

  def external_link=(link)
    if !link.blank? && link !~ /^[a-z]+:\/\//i
      link = 'http://' + link
    end
    self[:external_link] = link
  end

  def action_tracker_target
    self.profile
  end

  def self.human_attribute_name_with_customization(attrib, options={})
    case attrib.to_sym
    when :name
      _('Title')
    else
      _(self.human_attribute_name_without_customization(attrib))
    end
  end
  class << self
    alias_method :human_attribute_name_without_customization, :human_attribute_name
    alias_method :human_attribute_name, :human_attribute_name_with_customization
  end

  def css_class_list
    [self.class.name.to_css_class]
  end

  def css_class_name
    [css_class_list].flatten.compact.join(' ')
  end

  def pending_categorizations
    @pending_categorizations ||= []
  end

  def add_category(c)
    if new_record?
      pending_categorizations << c
    else
      ArticleCategorization.add_category_to_article(c, self)
      self.categories
    end
  end

  def category_ids=(ids)
    ArticleCategorization.remove_all_for(self)
    ids.uniq.each do |item|
      add_category(Category.find(item)) unless item.to_i.zero?
    end
    self.categories
  end

  after_create :create_pending_categorizations
  def create_pending_categorizations
    pending_categorizations.each do |item|
      ArticleCategorization.add_category_to_article(item, self)
    end
    self.categories
    pending_categorizations.clear
  end

  acts_as_taggable
  N_('Tag list')

  extend ActsAsFilesystem::ActsMethods
  acts_as_filesystem

  acts_as_versioned
  self.non_versioned_columns << 'setting'

  def version_condition_met?
    (['name', 'body', 'abstract', 'filename', 'start_date', 'end_date', 'image_id', 'license_id'] & changed).length > 0
  end

  def comment_data
    comments.map {|item| [item.title, item.body].join(' ') }.join(' ')
  end

  before_update do |article|
    article.advertise = true
  end

  before_save do |article|
    article.parent = article.parent_id ? Article.find(article.parent_id) : nil
    parent_path = article.parent ? article.parent.path : nil
    article.path = [parent_path, article.slug].compact.join('/')
  end

  # retrieves all articles belonging to the given +profile+ that are not
  # sub-articles of any other article.
  scope :top_level_for, -> profile {
    where 'parent_id is null and profile_id = ?', profile.id
  }

  # retrives the most commented articles, sorted by the comment count (largest
  # first)
  def self.most_commented(limit)
    order('comments_count DESC').paginate(page: 1, per_page: limit)
  end

  # produces the HTML code that is to be displayed as this article's contents.
  #
  # The implementation in this class just provides the +body+ attribute as the
  # HTML.  Other article types can override this method to provide customized
  # views of themselves.
  # (To override short format representation, override the lead method)
  def to_html(options = {})
    if options[:format] == 'short'
      article = self
      proc do
        display_short_format(article)
      end
    else
      body || ''
    end
  end

  # returns the data of the article. Must be overridden in each subclass to
  # provide the correct content for the article.
  def data
    body
  end

  # provides the icon name to be used for this article. In this class this
  # method just returns 'text-html', but subclasses may (and should) override
  # to return their specific icons.
  #
  # FIXME use mime_type and generate this name dinamically
  def self.icon_name(article = nil)
    'text-html'
  end

  # TODO Migrate the class method icon_name to instance methods.
  def icon_name
    self.class.icon_name(self)
  end

  def mime_type
    'text/html'
  end

  def mime_type_description
    _('HTML Text document')
  end

  def self.description
    raise NotImplementedError, "#{self} does not implement #description"
  end

  def self.short_description
    raise NotImplementedError, "#{self} does not implement #short_description"
  end

  def title
    name
  end

  include ActionView::Helpers::TextHelper
  def short_title
    truncate self.title, :length => 15, :omission => '...'
  end

  def belongs_to_blog?
    self.parent and self.parent.blog?
  end

  def belongs_to_forum?
    self.parent and self.parent.forum?
  end

  def person_followers_email_list
    person_followers_emails.map{|p|p.email}
  end

  def info_from_last_update
    last_comment = comments.last
    if last_comment
      {:date => last_comment.created_at, :author_name => last_comment.author_name, :author_url => last_comment.author_url}
    else
      {:date => updated_at, :author_name => author_name, :author_url => author_url}
    end
  end

  def full_path
    profile.hostname.blank? ? "/#{profile.identifier}/#{path}" : "/#{path}"
  end

  def url
    @url ||= self.profile.url.merge(:page => path.split('/'))
  end

  def page_path
    path.split('/')
  end

  def view_url
    @view_url ||= is_a?(UploadedFile) ? url.merge(:view => true) : url
  end

  def comment_url_structure(comment, action = :edit)
    if comment.new_record?
      profile.url.merge(:page => path.split("/"), :controller => :comment, :action => :create)
    else
      profile.url.merge(:page => path.split("/"), :controller => :comment, :action => action || :edit, :id => comment.id)
    end
  end

  def allow_children?
    true
  end

  def has_posts?
    false
  end

  def download? view = nil
    false
  end

  def is_followed_by?(user)
    self.person_followers.include? user
  end

  def download_disposition
    'inline'
  end

  def download_headers
    { :filename => filename, :type => mime_type, :disposition => download_disposition}
  end

  def alternate_languages
    self.translations.map(&:language)
  end

  scope :native_translations, -> { where :translation_of_id => nil }

  def translatable?
    false
  end

  def native_translation
    self.translation_of.nil? ? self : self.translation_of
  end

  def possible_translations
    possibilities = environment.locales.keys - self.native_translation.translations.map(&:language) - [self.native_translation.language]
    possibilities << self.language unless self.language_changed?
    possibilities
  end

  def known_language
    unless self.language.blank?
      errors.add(:language, N_('Language not supported by the environment.')) unless environment.locales.key?(self.language)
    end
  end

  def used_translation
    unless self.language.blank? or self.translation_of.nil?
      errors.add(:language, N_('Language is already used')) unless self.possible_translations.include?(self.language)
    end
  end

  def translation_must_have_language
    unless self.translation_of.nil?
      errors.add(:language, N_('Language must be chosen')) if self.language.blank?
    end
  end

  def native_translation_must_have_language
    unless self.translation_of.nil?
      errors.add(:base, N_('A language must be chosen for the native article')) if self.translation_of.language.blank?
    end
  end

  def rotate_translations
    unless self.translations.empty?
      rotate = self.translations.to_a
      root = rotate.shift
      root.update_attribute(:translation_of_id, nil)
      root.translations = rotate
    end
  end

  def get_translation_to(locale)
    if self.language.nil? || self.language.blank? || self.language == locale
      self
    elsif self.native_translation.language == locale
      self.native_translation
    else
      self.native_translation.translations.where(:language => locale).first
    end
  end

  def published?
    published && (parent.blank? || parent.published?)
  end

  def archived?
    (self.parent && self.parent.archived) || self.archived
  end

  def self.folder_types
    ['Folder', 'Blog', 'Forum', 'Gallery']
  end

  scope :published, -> { where 'articles.published = ?', true }
  scope :folders, -> profile { where 'articles.type IN (?)', profile.folder_types }
  scope :no_folders, -> profile { where 'articles.type NOT IN (?)', profile.folder_types }
  scope :top_folders, -> profile { where 'articles.type IN (?) and profile_id = ? and ' +
                                         'parent_id IS NULL', profile.folder_types, profile }
  scope :subfolders, -> profile, parent { where 'articles.type IN (?) and profile_id = ? and ' +
                                          'parent_id = ?', profile.folder_types, profile, parent }
  scope :galleries, -> { where "articles.type IN ('Gallery')" }
  scope :images, -> { where :is_image => true }
  scope :no_images, -> { where :is_image => false }
  scope :files, -> { where :type => 'UploadedFile' }
  scope :no_files, -> { where "type != 'UploadedFile'" }
  scope :with_types, -> types { where 'articles.type IN (?)', types }

  scope :more_popular, -> { order 'articles.hits DESC' }
  scope :more_comments, -> { order "articles.comments_count DESC" }
  scope :more_recent, -> { order "articles.created_at DESC, articles.id DESC" }

  scope :news, -> profile, limit, highlight {
      no_folders(profile).
      no_files.
      where(highlighted: highlight).
      limit(limit).
      order("articles.metadata->'order' NULLS FIRST, published_at DESC")
  }

  def allow_post_content?(user = nil)
    return true if allow_edit_topic?(user)
    user && profile.allow_post_content?(user)
  end

  def allow_view_private_content?(user = nil)
    user && user.has_permission?('view_private_content', profile)
  end

  alias :allow_delete?  :allow_post_content?

  def allow_spread?(user = nil)
    user
  end

  def allow_create?(user)
    allow_post_content?(user)
  end

  def allow_edit?(user)
    return true if allow_edit_topic?(user)
    allow_post_content?(user) || user && allow_members_to_edit && user.is_member_of?(profile)
  end

  def allow_edit_topic?(user)
    self.belongs_to_forum? && (user == author) && user.present? && user.is_member_of?(profile)
  end

  def moderate_comments?
    moderate_comments == true
  end

  def comments_updated
    solr_save
  end

  def accept_category?(cat)
    true
  end

  def copy_without_save(options = {})
    attrs = attributes.reject! { |key, value| ATTRIBUTES_NOT_COPIED.include?(key.to_sym) }
    attrs.merge!(options)
    object = self.class.new
    attrs.each do |key, value|
      object.send(key.to_s+'=', value)
    end
    object
  end

  def copy(options = {})
    object = copy_without_save(options)
    object.save
    object
  end

  def copy!(options = {})
    object = copy_without_save(options)
    object.save!
    object
  end

  ATTRIBUTES_NOT_COPIED = [
    :id,
    :profile_id,
    :parent_id,
    :path,
    :slug,
    :updated_at,
    :created_at,
    :version,
    :lock_version,
    :type,
    :children_count,
    :comments_count,
    :hits,
    :translation_of_id,
  ]

  def self.find_by_old_path(old_path)
    self.includes(:versions).where('article_versions.path = ?', old_path).order('article_versions.id DESC').first
  end

  def hit
    if !archived?
      self.class.connection.execute('update articles set hits = hits + 1 where id = %d' % self.id.to_i)
      self.hits += 1
    end
  end

  def self.hit(articles)
    ids = []
    articles.each do |article|
      if !article.archived?
        ids << article.id
        article.hits += 1
      end
    end
    Article.where(:id => ids).update_all('hits = hits + 1') if !ids.empty?
  end

  def can_display_hits?
    true
  end

  def display_hits?
    can_display_hits? && display_hits
  end

  def display_media_panel?
    can_display_media_panel? && environment.enabled?('media_panel')
  end

  def can_display_media_panel?
    false
  end

  settings_items :display_preview, :type => :boolean, :default => false

  def display_preview?
    false
  end

  def image?
    false
  end

  def event?
    false
  end

  def gallery?
    false
  end

  def folder?
    false
  end

  def blog?
    false
  end

  def forum?
    false
  end

  def uploaded_file?
    false
  end

  settings_items :display_versions, :type => :boolean, :default => false

  def can_display_versions?
    false
  end

  def display_versions?
    can_display_versions? && display_versions
  end

  def get_version(version_number = nil)
    if version_number then self.versions.order('version').offset(version_number - 1).first else self.versions.earliest end
  end

  def author_by_version(version_number = nil)
    return author unless version_number
    author_id = get_version(version_number).last_changed_by_id
    profile.environment.people.where(id: author_id).first
  end

  def author_name(version_number = nil)
    person = author_by_version(version_number)
    if version_number
      person ? person.name : environment.name
    else
      person ? person.name : (setting[:author_name] || environment.name)
    end
  end

  def author_url(version_number = nil)
    person = author_by_version(version_number)
    person ? person.url : nil
  end

  def author_id(version_number = nil)
    person = author_by_version(version_number)
    person ? person.id : nil
  end

  #FIXME make this test
  def author_custom_image(size = :icon)
    author ? author.profile_custom_image(size) : nil
  end

  def version_license(version_number = nil)
    return license if version_number.nil?
    profile.environment.licenses.find_by(id: get_version(version_number).license_id)
  end

  alias :active_record_cache_key :cache_key
  def cache_key(params = {}, the_profile = nil, language = 'en')
    active_record_cache_key+'-'+language +
      (allow_post_content?(the_profile) ? "-owner" : '') +
      (params[:npage] ? "-npage-#{params[:npage]}" : '') +
      (params[:year] ? "-year-#{params[:year]}" : '') +
      (params[:month] ? "-month-#{params[:month]}" : '') +
      (params[:version] ? "-version-#{params[:version]}" : '')

  end

  def first_paragraph
    paragraphs = Nokogiri::HTML.fragment(to_html).css('p')
    paragraphs.empty? ? '' : paragraphs.first.to_html
  end

  def lead(length = nil)
    content = abstract.blank? ? first_paragraph.html_safe : abstract.html_safe
    length.present? ? content.truncate(length) : content
  end

  def short_lead
    truncate sanitize_html(self.lead), :length => 170, :omission => '...'
  end

  def notifiable?
    false
  end

  def accept_uploads?
    self.parent && self.parent.accept_uploads?
  end

  def body_images_paths
    paths = Nokogiri::HTML.fragment(self.body.to_s).css('img[src]').collect do |i|
      src = i['src']
      src = URI.escape src if self.new_record? # xss_terminate runs on save
      (self.profile && self.profile.environment) ? URI.join(self.profile.environment.top_url, src).to_s : src
    end
    paths.unshift(URI.join(self.profile.environment.top_url, self.image.public_filename).to_s) if self.image.present?
    paths
  end

  def more_comments_label
    amount = self.comments_count
    {
      0 => _('no comments'),
      1 => _('one comment')
    }[amount] || _("%s comments") % amount

  end

  def more_popular_label
    amount = self.hits
    {
      0 => _('no views'),
      1 => _('one view')
    }[amount] || _("%s views") % amount

  end

  def more_recent_label
    _('Created at: ')
  end

  def activity
    ActionTracker::Record.where(target_type: 'Article', target_id: self.id).first
  end

  def create_activity
    if notifiable? && !image?
      save_action_for_verb 'create_article', [:name, :title, :url, :lead, :first_image], Proc.new{}, :author
    end
  end

  def first_image
    img = ( image.present? && { 'src' => File.join([Noosfero.root, image.public_filename(:uploaded)].join) } ) ||
      Nokogiri::HTML.fragment(self.lead.to_s).css('img[src]').first ||
      Nokogiri::HTML.fragment(self.body.to_s).search('img').first
    img.nil? ? '' : img['src']
  end

  delegate :lat, :lng, :region, :region_id, :environment, :environment_id, :to => :profile, :allow_nil => true

  def has_macro?
    true
  end

  def to_liquid
    HashWithIndifferentAccess.new :name => name, :abstract => abstract, :body => body, :id => id, :parent_id => parent_id, :author => author
  end

  def self.can_display_blocks?
    true
  end

  def editor?(editor)
    self.editor == editor
  end

  def icon
    'file'
  end

  def custom_title
    false
  end

  def self.switch_orders(first_article, second_article)
    return unless first_article.profile == second_article.profile &&
                  first_article.position >= second_article.position

    ActiveRecord::Base.transaction do
      first_order = first_article.position
      where('profile_id = ?', first_article.profile_id)
        .where('position > ? OR (position = ? AND published_at > ?)',
            first_order, first_order, first_article.published_at)
        .update_all('position = (position + 1)')

      first_article.update!(position: first_order)
      second_article.update!(position: first_order + 1)
    end
  end

  private

  def parent_archived?
    if self.parent_id_changed? && self.parent && self.parent.archived?
      errors.add(:parent_folder, N_('is archived!!'))
    end
  end

  def validate_custom_fields
    if metadata.has_key?('custom_fields')
      custom_fields = metadata['custom_fields']
      if custom_fields.present?
        custom_fields.each do |key, field|
          if field['value'].blank?
            errors.add(:metadata, _('Custom fields must have values'))
          end
        end
      end
    end
  end

  def sanitize_custom_field_keys
    if metadata.has_key?('custom_fields')
      custom_fields = metadata['custom_fields'] || {}
      metadata['custom_fields'] = custom_fields.keys.map do |field|
        [field.to_slug, metadata['custom_fields'][field]]
      end.to_h
    end
  end
end
