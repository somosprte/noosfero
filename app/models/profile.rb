# A Profile is the representation and web-presence of an individual or an
# organization. Every Profile is attached to its Environment of origin,
# which by default is the one returned by Environment:default.
class Profile < ApplicationRecord

  attr_accessible :name, :identifier, :access, :nickname,
    :custom_footer, :custom_header, :address, :zip_code, :contact_phone,
    :image_builder, :top_image_builder, :description, :closed, :template_id, :environment, :lat,
    :lng, :is_template, :fields_privacy, :preferred_domain_id, :category_ids,
    :country, :city, :state, :national_region_code, :email, :contact_email,
    :redirect_l10n, :notification_time, :redirection_after_login,
    :custom_url_redirection, :layout_template, :email_suggestions,
    :allow_members_to_invite, :invite_friends_only, :secret,
    :profile_admin_mail_notification, :allow_followers, :wall_access,
    :profile_kinds, :tag_list, :boxes_attributes, :metadata

  attr_accessor :old_region_id

  # use for internationalizable human type names in search facets
  # reimplement on subclasses
  def self.type_name
    _('Profile')
  end

  SEARCHABLE_FIELDS = {
    :name => {:label => _('Name'), :weight => 10},
    :identifier => {:label => _('Username'), :weight => 5},
    :nickname => {:label => _('Nickname'), :weight => 2},
  }

  SEARCH_FILTERS = {
    :order => %w[more_recent alpha_az alpha_za],
    :display => %w[compact]
  }

  CAPTCHA_REQUIREMENTS = {
    create_comment: {label: _('Create a comment'), options: Entitlement::Levels.range_options(0, 3)},
    new_contact: {label: _('Make email contact'), options: Entitlement::Levels.range_options(0,3)},
    report_abuse: {label: _('Report an abuse'), options: Entitlement::Levels.range_options(0,3)},
  }

  NUMBER_OF_BOXES = 4

  def self.default_search_display
    'compact'
  end

  module Roles
    def self.admin(env_id)
      find_role('admin', env_id)
    end
    def self.member(env_id)
      find_role('member', env_id)
    end
    def self.moderator(env_id)
      find_role('moderator', env_id)
    end
    def self.owner(env_id)
      find_role('owner', env_id)
    end
    def self.editor(env_id)
      find_role('editor', env_id)
    end
    def self.organization_member_roles(env_id)
      all_roles(env_id).select{ |r| r.key.match(/^profile_/) unless r.key.blank? || !r.profile_id.nil?}
    end
    def self.organization_custom_roles(env_id, profile_id)
      all_roles(env_id).where('profile_id = ?', profile_id)
    end
    def self.organization_roles(env_id, profile_id)
      all_roles(env_id).where("profile_id = ?  or (key like 'profile_%' and profile_id is null)", profile_id)
    end
    def self.organization_member_and_custom_roles(env_id, profile_id)
      self.organization_member_roles(env_id) | self.organization_custom_roles(env_id, profile_id)
    end

    def self.all_roles(env_id)
      Role.where(environment_id: env_id)
    end
    def self.method_missing(m, *args, &block)
      role = find_role(m, args[0])
      return role unless role.nil?
      super
    end
    private
    def self.find_role(name, env_id)
      ::Role.find_by key: "profile_#{name}", environment_id: env_id
    end
  end

  PERMISSIONS['Profile'] = {
    'edit_profile'         => N_('Edit profile'),
    'destroy_profile'      => N_('Destroy profile'),
    'manage_memberships'   => N_('Manage memberships'),
    'post_content'         => N_('Manage/Publish content'), # changed only presentation name to keep already given permissions
    'edit_profile_design'  => N_('Edit profile design'),
    'manage_products'      => N_('Manage products'),
    'manage_friends'       => N_('Manage friends'),
    'validate_enterprise'  => N_('Validate enterprise'),
    'perform_task'         => N_('Perform task'),
    'view_tasks'           => N_('View tasks'),
    'moderate_comments'    => N_('Moderate comments'),
    'edit_appearance'      => N_('Edit appearance'),
    'view_private_content' => N_('View private content'),
    'invite_members'       => N_('Invite members'),
    'send_mail_to_members' => N_('Send e-Mail to members'),
    'manage_custom_roles'  => N_('Manage custom roles'),
    'manage_email_templates' => N_('Manage Email Templates'),
  }

  acts_as_accessible

  prepend SetProfileRegionFromCityState
  include Customizable
  acts_as_customizable

  include Noosfero::Plugin::HotSpot

  include HasUploadQuota

  include Entitlement::SliderHelper
  include Entitlement::ProfileJudge

  scope :memberships_of, -> person {
    distinct.select('profiles.*').
    joins(:role_assignments).
    where('role_assignments.accessor_type = ? AND role_assignments.accessor_id = ?', person.class.base_class.name, person.id)
  }
  #FIXME: these will work only if the subclass is already loaded
  scope :enterprises, -> {
    where((Enterprise.send(:subclasses).map(&:name) << 'Enterprise').map { |klass| "profiles.type = '#{klass}'"}.join(" OR "))
  }
  scope :communities, -> {
    where((Community.send(:subclasses).map(&:name) << 'Community').map { |klass| "profiles.type = '#{klass}'"}.join(" OR "))
  }
  scope :templates, -> template_id = nil {
    s = where is_template: true
    s = s.where id: template_id if template_id
    s
  }

  scope :with_templates, -> templates {
    where template_id: templates
  }
  scope :no_templates, -> { where is_template: false }

  scope :recent, -> limit=nil { order('id DESC').limit(limit) }

  # Returns a scoped object to select profiles in a given location or in a radius
  # distance from the given location center.
  # The parameter can be the `request.params` with the keys:
  # * `country`: Country code string.
  # * `state`: Second-level administrative country subdivisions.
  # * `city`: City full name for center definition, or as set by users.
  # * `lat`: The latitude to define the center of georef search.
  # * `lng`: The longitude to define the center of georef search.
  # * `distance`: Define the search radius in kilometers.
  # NOTE: This method may return an exception object, to inform filter error.
  # When chaining scopes, is hardly recommended you to add this as the last one,
  # if you can't be sure about the provided parameters.

  def self.distance_is_blank (params)
    where_code = []
    [ :city, :state, :country ].each do |place|
      unless params[place].blank?
       # ... So we must to find on this named location
       # TODO: convert location attrs to a table column
       where_code << "(profiles.data like '%#{place}: #{params[place]}%')"
     end
   end
   self.where where_code.join(' AND ')
  end

  def self.filter_in_a_georef_circle (params)
    unless params[:lat].blank? && params[:lng].blank?
      lat, lng = [ params[:lat].to_f, params[:lng].to_f ]
    end
    if !lat
      location = [ params[:city], params[:state], params[:country] ].compact.join(', ')
      if location.blank?
        return Exception.new (
        _('You must to provide `lat` and `lng`, or `city` and `country` to define the center of the search circle, defined by `distance`.')
        )
      end
      lat, lng = Noosfero::GeoRef.location_to_georef location
    end
    dist = params[:distance].to_f
    self.where "#{Noosfero::GeoRef.sql_dist lat, lng} <= #{dist}"
  end

  def self.by_location(params)
    params = params.with_indifferent_access
    if params[:distance].blank?
      distance_is_blank params
    else # Filter in a georef circle
      # location = Location.new(params[:lat], params[:lng], params[:city], params[:state], params[:country], params[:distance])
      self.filter_in_a_georef_circle(params)
    end
  end

  include TimeScopes

  def members(by_field = '')
    scopes = plugins.dispatch_scopes(:organization_members, self)
    scopes << Person.members_of(self,by_field)
    return scopes.first if scopes.size == 1
    ScopeTool.union *scopes
  end

  def members_by(field,value = nil)
    if value and !value.blank?
      members_like(field,value).order('profiles.name')
    else
      members.order('profiles.name')
    end
  end

  def members_like(field,value)
    members(field).where("LOWER(#{field}) LIKE ?", "%#{value.downcase}%") if value
  end

  def members_by_role(roles)
    Person.members_of(self).by_role(roles)
  end

  extend ActsAsHavingSettings::ClassMethods
  acts_as_having_settings field: :data

  store_accessor :metadata
  include MetadataScopes

  metadata_items :allow_single_file

  def settings
    data
  end

  settings_items :redirect_l10n, :type => :boolean, :default => false
  settings_items :description
  settings_items :fields_privacy, :type => :hash, :default => {}
  settings_items :email_suggestions, :type => :boolean, :default => false
  settings_items :profile_admin_mail_notification, :type => :boolean, :default => true

  settings_items :profile_kinds, :type => :hash, :default => {}
  after_save do |profile|
    profile.profile_kinds.each do |key, value|
      environment = profile.environment
      kind = environment.kinds.where(:id => key.to_s).first
      next unless kind.present?

      value == '1' ? kind.add_profile(profile) : kind.remove_profile(profile)
    end
  end
  before_save do |profile|
    unless profile.setting_changed?(:profile_kinds)
      profile.profile_kinds = {}
    end
  end

  def kinds_style_classes
    return nil if kinds.blank?
    kinds.map(&:style_class).join(' ')
  end

  extend ActsAsHavingBoxes::ClassMethods
  acts_as_having_boxes

  acts_as_taggable

  def self.qualified_column_names
    Profile.column_names.map{|n| [Profile.table_name, n].join('.')}.join(',')
  end

  scope :visible, -> { where visible: true, secret: false }
  scope :disabled, -> { where visible: false }
  scope :enabled, -> { where enabled: true }

  scope :higher_disk_usage, -> { order("metadata->>'disk_usage' DESC NULLS LAST") }
  scope :lower_disk_usage, -> { order("metadata->>'disk_usage' ASC NULLS LAST") }

  # subclass specific
  scope :more_popular, -> { }
  scope :more_active, -> { order 'profiles.activities_count DESC' }
  scope :more_recent, -> { order "profiles.created_at DESC" }
  scope :alpha_az, -> { order "profiles.name ASC" }
  scope :alpha_za, -> { order "profiles.name DESC" }

  scope :followed_by, -> person{
    distinct.select('profiles.*').
    joins('left join profiles_circles ON profiles_circles.profile_id = profiles.id').
    joins('left join circles ON circles.id = profiles_circles.circle_id').
    where('circles.person_id = ?', person.id)
  }

  scope :in_circle, -> circle{
    distinct.select('profiles.*').
    joins('left join profiles_circles ON profiles_circles.profile_id = profiles.id').
    joins('left join circles ON circles.id = profiles_circles.circle_id').
    where('circles.id = ?', circle.id)
  }

  settings_items :wall_access, :type => :integer, :default => Entitlement::Levels.levels[:users]
  settings_items :allow_followers, :type => :boolean, :default => true
  alias_method :allow_followers?, :allow_followers

  acts_as_trackable dependent: :destroy

  has_many :profile_activities
  has_many :action_tracker_notifications, foreign_key: 'profile_id'
  has_many :tracked_notifications, -> { order 'updated_at DESC' }, through: :action_tracker_notifications, source: :action_tracker
  has_many :scraps_received, -> { order 'updated_at DESC' }, class_name: 'Scrap', foreign_key: :receiver_id, dependent: :destroy
  belongs_to :template, class_name: 'Profile', foreign_key: 'template_id', optional: true


  has_many :email_templates, foreign_key: :owner_id

  has_many :profile_followers
  has_many :followers, -> { distinct }, class_name: 'Person', through:  :profile_followers, source:  :person

  # Although this should be a has_one relation, there are no non-silly names for
  # a foreign key on article to reference the template to which it is
  # welcome_page... =P
  belongs_to :welcome_page, class_name: 'Article', dependent: :destroy, optional: true

  def welcome_page_content
    welcome_page && welcome_page.access == Entitlement::Levels.levels[:visitors] ? welcome_page.body : nil
  end

  has_many :search_terms, :as => :context

  def scraps(scrap=nil)
    scrap = scrap.is_a?(Scrap) ? scrap.id : scrap
    scrap.nil? ? Scrap.all_scraps(self) : Scrap.all_scraps(self).find(scrap)
  end

  validates_length_of :description, :maximum => 550, :allow_nil => true

  # Valid identifiers must match this format.
  IDENTIFIER_FORMAT = /\A#{Noosfero.identifier_format}\Z/

  # These names cannot be used as identifiers for Profiles
  RESERVED_IDENTIFIERS = %w[
    admin
    system
    myprofile
    profile
    cms
    community
    test
    search
    not_found
    cat
    tag
    tags
    environment
    webmaster
    info
    root
    assets
    doc
    chat
    plugin
    site
  ]

  belongs_to :user, optional: true

  has_many :domains, :as => :owner
  belongs_to :preferred_domain, class_name: 'Domain', foreign_key: 'preferred_domain_id', optional: true
  belongs_to :environment, optional: true

  has_many :articles, dependent: :destroy
  has_many :comments_received, class_name: 'Comment', through:  :articles, source:  :comments
  belongs_to :home_page, class_name: Article.name, foreign_key: 'home_page_id', optional: true

  has_many :files, class_name: 'UploadedFile', dependent: :destroy

  extend ActsAsHavingImage::ClassMethods
  acts_as_having_image
  acts_as_having_image field: :top_image

  has_many :tasks, dependent:  :destroy, :as => 'target'

  has_many :events, -> { order 'start_date' }, source: 'articles', class_name: 'Event'

  def find_in_all_tasks(task_id)
    begin
      Task.to(self).find(task_id)
    rescue
      nil
    end
  end

  has_many :profile_categorizations, -> { where 'categories_profiles.virtual = ?', false }
  has_many :categories, through:  :profile_categorizations
  has_many :regions, -> { where(:type => ['Region', 'State', 'City']) }, through:  :profile_categorizations, source:  :category

  has_many :profile_categorizations_including_virtual, class_name:  'ProfileCategorization'
  has_many :categories_including_virtual, through:  :profile_categorizations_including_virtual, source:  :category

  has_many :abuse_complaints, foreign_key:  'requestor_id', dependent:  :destroy

  has_many :profile_suggestions, foreign_key:  :suggestion_id, dependent:  :destroy

  has_and_belongs_to_many :kinds

  scope :with_kind, -> kind { joins(:kinds).where("kinds.id = ?", kind.id) }

  def top_level_categorization
    ret = {}
    self.profile_categorizations.each do |c|
      p = c.category.top_ancestor
      ret[p] = (ret[p] || []) + [c.category]
    end
    ret
  end

  def interests
    categories.select {|item| !item.is_a?(Region)}
  end

  belongs_to :region, optional: true

  LOCATION_FIELDS = %w[address address_reference district city state country zip_code]
  metadata_items *(LOCATION_FIELDS - %w[address])

  before_save :save_old_region
  def save_old_region
    self.old_region_id = self.region_id_was || self.region_id
  end

  before_save :match_articles_access
  def match_articles_access
    if access_changed?
      articles.where('access < ?', access).update_all(access: access)
    end
  end

  before_validation :update_wall_access
  def update_wall_access
    if access > wall_access
      self.wall_access = access
    end
  end

  def location(separator = ' - ')
    myregion = self.region
    if myregion
      myregion.hierarchy.reverse.first(2).map(&:name).join(separator)
    else
      full_address(separator)
    end
  end

  def full_address(separator = ' - ')
    LOCATION_FIELDS.map do |item|
      (self.respond_to?(item) && !self.send(item).blank?) ? self.send(item) : nil
    end.compact.join(separator)
  end

  def city
    NationalRegion.name_or_default(metadata['city'])
  end

  def state
    NationalRegion.name_or_default(metadata['state'])
  end

  def country
    NationalRegion.name_or_default(metadata['country'])
  end

  def geolocation
    unless location.blank?
      location
    else
      if environment.location.blank?
        environment.location = "BRA"
      end
      environment.location
    end
  end

  def country_name
    CountriesHelper::Object.instance.lookup(country) if respond_to?(:country)
  end

  def pending_categorizations
    @pending_categorizations ||= []
  end

  def add_category(c)
    if new_record?
      pending_categorizations << c
    else
      ProfileCategorization.add_category_to_profile(c, self)
      self.categories
    end
    self.categories
  end

  def category_ids=(ids)
    ProfileCategorization.remove_all_for(self)
    ids.uniq.each do |item|
      add_category(Category.find(item)) unless item.to_i.zero?
    end
  end

  after_create :create_pending_categorizations
  def create_pending_categorizations
    pending_categorizations.each do |item|
      ProfileCategorization.add_category_to_profile(item, self)
    end
    pending_categorizations.clear
  end

  def top_level_articles(reload = false)
    if reload
      @top_level_articles = nil
    end
    @top_level_articles ||= Article.top_level_for(self)
  end

  def self.is_available?(identifier, environment, profile_id=nil)
    return false unless !Profile::RESERVED_IDENTIFIERS.include?(identifier) &&
      (NOOSFERO_CONF['exclude_profile_identifier_pattern'].blank? || identifier !~ /#{NOOSFERO_CONF['exclude_profile_identifier_pattern']}/)
    return true if environment.nil?

    environment.is_identifier_available?(identifier, profile_id)
  end

  validates_presence_of :identifier, :name
  validates_length_of :nickname, :maximum => 16, :allow_nil => true
  validate :valid_template
  validate :valid_identifier
  validate :wall_access_value

  def valid_identifier
    errors.add(:identifier, :invalid) unless identifier =~ IDENTIFIER_FORMAT
    errors.add(:identifier, :not_available) unless Profile.is_available?(identifier, environment, id)
  end

  def valid_template
    if template_id.present? && template && !template.is_template
      errors.add(:template, _('is not a template.'))
    end
  end

  def wall_access_value
    if wall_access < access
      self.errors.add(:wall_access, _('can not be less restrictive than access which is: %s.') % Entitlement::Levels.label(access, self))
    end
  end

  before_create :set_default_environment
  def set_default_environment
    if self.environment.nil?
      self.environment = Environment.default
    end
    true
  end

  # registar callback for creating boxes after the object is created.
  after_create :create_default_set_of_boxes

  # creates the initial set of boxes when the profile is created. Can be
  # overridden for each subclass to create a custom set of boxes for its
  # instances.
  def create_default_set_of_boxes
    if template
      apply_template(template, :copy_articles => false)
    else
      NUMBER_OF_BOXES.times do
        self.boxes << Box.new
      end

      if self.respond_to?(:default_set_of_blocks)
        default_set_of_blocks.each_with_index do |blocks,i|
          blocks.each do |block|
            self.boxes[i].blocks << block
          end
        end
      end
    end

    true
  end

  def copy_blocks_from(profile)
    template_boxes = profile.boxes.select{|box| box.position}
    self.boxes.destroy_all
    self.boxes = template_boxes.size.times.map { Box.new }

    template_boxes.each_with_index do |box, i|
      new_box = self.boxes[i]
      new_box.position = box.position
      box.blocks.each do |block|
        new_block = block.class.new(:title => block[:title])
        new_block.copy_from(block)
        new_box.blocks << new_block
        if block.mirror?
          block.add_observer(new_block)
        end
      end
    end
  end

  # this method should be overwritten to provide the correct template
  def default_template
    nil
  end

  def template_with_default
    template_without_default || default_template
  end
  alias_method :template_without_default, :template
  alias_method :template, :template_with_default

  def apply_template(template, options = {:copy_articles => true})
    raise "#{template.identifier} is not a template" if !template.is_template

    self.template = template
    copy_blocks_from(template)
    copy_articles_from(template) if options[:copy_articles]
    self.apply_type_specific_template(template)

    # copy interesting attributes
    self.layout_template = template.layout_template
    self.theme = template.theme
    self.custom_footer = template[:custom_footer]
    self.custom_header = template[:custom_header]
    self.access = template.access
    self.fields_privacy = template.fields_privacy
    self.image = template.image.dup if template.image
    # flush
    self.save(:validate => false)
  end

  def apply_type_specific_template(template)
  end

  xss_terminate only: [ :name, :nickname, :address, :contact_phone, :description ], on: :validation
  xss_terminate only: [ :custom_footer, :custom_header ], with: :white_list

  include SanitizeTags

  include WhiteListFilter
  filter_iframes :custom_header, :custom_footer
  def iframe_whitelist
    environment && environment.trusted_sites_for_iframe
  end

  # returns the contact email for this profile.
  #
  # Subclasses may -- and should -- override this method.
  def contact_email
    raise NotImplementedError
  end

  # This method must return a list of e-mail adresses to which notification messages must be sent.
  # The implementation in this class just delegates to +contact_email+. Subclasse may override this method.
  def notification_emails
    [contact_email]
  end

  def last_articles limit = 10
    self.articles.limit(limit).where(
      "advertise = ? AND published = ? AND
      ((articles.type != ? and articles.type != ? and articles.type != ?) OR
      articles.type is NULL)",
      true, true, 'UploadedFile', 'RssFeed', 'Blog'
    ).order('articles.published_at desc, articles.id desc')
  end

  def to_liquid
    HashWithIndifferentAccess.new :name => name, :identifier => identifier
  end

  class << self

    # finds a profile by its identifier. This method is a shortcut to
    # +find_by_identifier+.
    #
    # Examples:
    #
    #  person = Profile['username']
    #  org = Profile.['orgname']
    def [](identifier)
      self.find_by identifier: identifier
    end

  end

  def superior_instance
    environment
  end

  # returns +false+
  def person?
    self.kind_of?(Person)
  end

  def enterprise?
    self.kind_of?(Enterprise)
  end

  def organization?
    self.kind_of?(Organization)
  end

  def community?
    self.kind_of?(Community)
  end

  # returns false.
  def is_validation_entity?
    false
  end

  def url
    @url ||= generate_url(:controller => 'content_viewer', :action => 'view_page', :page => [])
  end

  def admin_url
    { :profile => identifier, :controller => 'profile_editor', :action => 'index' }
  end

  def tasks_url
    { :profile => identifier, :controller => 'tasks', :action => 'index', :host => default_hostname }
  end

  def leave_url(reload = false)
    { :profile => identifier, :controller => 'profile', :action => 'leave', :reload => reload }
  end

  def join_url
    { :profile => identifier, :controller => 'profile', :action => 'join' }
  end

  def join_not_logged_url
    { :profile => identifier, :controller => 'profile', :action => 'join_not_logged' }
  end

  def check_membership_url
    { :profile => identifier, :controller => 'profile', :action => 'check_membership' }
  end

  def add_url
    { :profile => identifier, :controller => 'profile', :action => 'add' }
  end

  def check_friendship_url
    { :profile => identifier, :controller => 'profile', :action => 'check_friendship' }
  end

  def public_profile_url
    generate_url(:profile => identifier, :controller => 'profile', :action => 'index')
  end

  def people_suggestions_url
    generate_url(:profile => identifier, :controller => 'friends', :action => 'suggest')
  end

  def communities_suggestions_url
    generate_url(:profile => identifier, :controller => 'memberships', :action => 'suggest')
  end

  def generate_url(options)
    url_options.merge(options)
  end

  def url_options
    options = { :host => default_hostname, :profile => (own_hostname ? nil : self.identifier) }
    options.merge(Noosfero.url_options)
  end

  def top_url(scheme = 'http')
    url = scheme + '://'
    url << url_options[:host]
    url << ':' << url_options[:port].to_s if url_options.key?(:port)
    url << Noosfero.root('')
    url.html_safe
  end

private :generate_url, :url_options

  def default_hostname
    @default_hostname ||= (hostname || environment.default_hostname)
  end

  def hostname
    if preferred_domain
      return preferred_domain.name
    else
      own_hostname
    end
  end

  def own_hostname
    domain = self.domains.first
    domain ? domain.name : nil
  end

  def possible_domains
    environment.domains + domains
  end

  def article_tags
    articles.tag_counts.inject({}) do |memo,tag|
      memo[tag.name] = tag.count
      memo
    end
  end

  # Tells whether a specified profile has members or nor.
  #
  # On this class, returns <tt>false</tt> by default.
  def has_members?
    false
  end

  after_create :insert_default_article_set
  def insert_default_article_set
    if template
      self.save! if copy_articles_from template
    else
      default_set_of_articles.each do |article|
        article.profile = self
        article.advertise = false
        article.access = access
        article.save!
      end
      self.save!
    end
  end

  # Override this method in subclasses of Profile to create a default article
  # set upon creation. Note that this method will be called *only* if there is
  # no template for the type of profile (i.e. if the template was removed or in
  # the creation of the template itself).
  #
  # This method must return an array of pre-populated articles, which will be
  # associated to the profile before being saved. Example:
  #
  #   def default_set_of_articles
  #     [Blog.new(:name => 'Blog'), Gallery.new(:name => 'Gallery')]
  #   end
  #
  # By default, this method returns an empty array.
  def default_set_of_articles
    []
  end

  def copy_articles_from other
    return false if other.top_level_articles.empty?
    other.top_level_articles.each do |a|
      copy_article_tree a
    end
    self.articles.reload
    true
  end

  def copy_article_tree(article, parent=nil)
    return if !copy_article?(article)
    original_article = self.articles.find_by name: article.name
    if original_article
      num = 2
      new_name = original_article.name + ' ' + num.to_s
      while self.articles.find_by name: new_name
        num = num + 1
        new_name = original_article.name + ' ' + num.to_s
      end
      original_article.update!(:name => new_name)
    end
    article_copy = article.copy(:profile => self, :parent => parent, :advertise => false)
    if article.profile.home_page == article
      self.home_page = article_copy
    end
    article.children.each do |a|
      copy_article_tree a, article_copy
    end
  end

  def copy_article?(article)
    !article.is_a?(RssFeed) &&
    !(is_template && article.slug=='welcome-page')
  end

  # Adds a person as member of this Profile.
  def add_member(person, invited=false, **attributes)
    if self.has_members? && (!self.secret || invited)
      if self.closed? && members.count > 0
        AddMember.create!(:person => person, :organization => self) unless self.already_request_membership?(person)
      else
        self.affiliate(person, Profile::Roles.admin(environment.id), attributes) if members.count == 0
        self.affiliate(person, Profile::Roles.member(environment.id), attributes)
        plugins.dispatch(:member_added, self, person)
      end
      person.tasks.pending.of("InviteMember").select { |t| t.data[:community_id] == self.id }.each { |invite| invite.cancel }
      remove_from_suggestion_list person
    else
      raise _("%s can't have members") % self.class.name
    end
  end

  def remove_member(person)
    self.disaffiliate(person, Profile::Roles.all_roles(environment.id))
    plugins.dispatch(:member_removed, self, person)
  end

  # adds a person as administrator os this profile
  def add_admin(person)
    self.affiliate(person, Profile::Roles.admin(environment.id))
  end

  def remove_admin(person)
    self.disaffiliate(person, Profile::Roles.admin(environment.id))
  end

  def add_moderator(person)
    if self.has_members?
      self.affiliate(person, Profile::Roles.moderator(environment.id))
    else
      raise _("%s can't has moderators") % self.class.name
    end
  end

  after_save :update_category_from_region
  def update_category_from_region
    ProfileCategorization.remove_region(self)
    if region
      self.add_category(region)
    end
  end

  def accept_category?(cat)
    true
  end

  include ActionView::Helpers::TextHelper
  def short_name(chars = 40)
    if self[:nickname].blank?
      if chars
        truncate self.name, length: chars, omission: '...'
      else
        self.name
      end
    else
      self[:nickname]
    end
  end

  def custom_header
    self[:custom_header] || environment && environment.custom_header
  end

  def custom_header_expanded
    header = custom_header
    if header
      %w[name short_name].each do |att|
        if self.respond_to?(att) && header.include?("{#{att}}")
          header.gsub!("{#{att}}", self.send(att))
        end
      end
      header
    end
  end

  def custom_footer
    self[:custom_footer] || environment && environment.custom_footer
  end

  def custom_footer_expanded
    footer = custom_footer
    if footer
      %w[contact_person contact_email contact_phone location address district address_reference economic_activity city state country zip_code].each do |att|
        if self.respond_to?(att) && footer.match(/\{[^{]*#{att}\}/)
          if !self.send(att).nil? && !self.send(att).blank?
            footer = footer.gsub(/\{([^{]*)#{att}\}/, '\1' + self.send(att))
          else
            footer = footer.gsub(/\{[^}]*#{att}\}/, '')
          end
        end
      end
      footer
    end
  end

  def privacy_setting
    _('Profile accessible to %s') % Entitlement::Levels.label(access, self)
  end

  def themes
    Theme.find_by_owner(self)
  end

  def find_theme(the_id)
    themes.find { |item| item.id == the_id }
  end

  settings_items :layout_template, :type => String, :default => 'default'

  has_many :blogs, source: 'articles', class_name: 'Blog'
  has_many :forums, source: 'articles', class_name: 'Forum'
  has_many :galleries, source: 'articles', class_name: 'Gallery'

  def blog
    self.has_blog? ? self.blogs.order(:id).first : nil
  end

  def has_blog?
    self.blogs.count.nonzero?
  end

  def forum
    self.has_forum? ? self.forums.order(:id).first : nil
  end

  def has_forum?
    self.forums.count.nonzero?
  end

  def gallery
    self.has_blog? ? self.galleries.order(:id).first : nil
  end

  def has_gallery?
    self.galleries.count.nonzero?
  end

  def admins
    return [] if environment.blank?
    admin_role = Profile::Roles.admin(environment.id)
    return [] if admin_role.blank?
    self.members_by_role(admin_role)
  end

  def enable_contact?
    !environment.enabled?('disable_contact_' + self.class.name.downcase)
  end

  include Noosfero::Plugin::HotSpot

  def folder_types
    types = Article.folder_types
    plugins.dispatch(:content_types).each {|type|
      if type < Folder
        types << type.name
      end
    }
    types
  end

  def folders
    articles.folders(self)
  end

  def image_galleries
    articles.galleries
  end

  def blocks_to_expire_cache
    []
  end

  def cache_keys(params = {})
    []
  end

  validate :image_valid

  def image_valid
    unless self.image.nil?
      self.image.valid?
      self.image.errors.delete(:empty) # dont validate here if exists uploaded data
      self.image.errors.each do |attr,msg|
        self.errors.add(attr, msg)
      end
    end
  end

  # FIXME: horrible workaround to circular dependency in environment.rb
  after_update do |profile|
    ProfileSweeper.new().after_update(profile)
  end

  # FIXME: horrible workaround to circular dependency in environment.rb
  after_create do |profile|
    ProfileSweeper.new().after_create(profile)
  end

  def update_header_and_footer(header, footer)
    self.custom_header = header
    self.custom_footer = footer
    self.save(:validate => false)
  end

  def update_theme(theme)
    self.update_attribute(:theme, theme)
  end

  def update_layout_template(template)
    self.update_attribute(:layout_template, template)
  end

  def members_cache_key(params = {})
    page = params[:npage] || '1'
    sort = (params[:sort] ==  'desc') ? params[:sort] : 'asc'
    cache_key + '-members-page-' + page + '-' + sort
  end

  def more_recent_label
    _("Since: ")
  end

  def alpha_az_label
  end

  def alpha_za_label
  end

  def recent_actions
    tracked_actions.recent
  end

  def recent_notifications
    tracked_notifications.recent
  end

  def more_active_label
    amount = recent_actions.count
    amount += recent_notifications.count if organization?
    {
      0 => _('no activity'),
      1 => _('one activity')
    }[amount] || _("%s activities") % amount
  end

  def more_popular_label
    amount = self.members_count
    {
      0 => _('no members'),
      1 => _('one member')
    }[amount] || _("%s members") % amount
  end

  include Noosfero::Gravatar

  def profile_custom_icon(gravatar_default=nil)
    image.public_filename(:icon) if image.present?
  end

  def profile_custom_image(size = :icon)
    image_path = profile_custom_icon if size == :icon
    image_path ||= image.public_filename(size) if image.present?
    image_path
  end

  def jid(options = {})
    domain = options[:domain] || environment.default_hostname
    "#{identifier}@#{domain}"
  end
  def full_jid(options = {})
    "#{jid(options)}/#{short_name}"
  end

  def is_on_homepage?(url, page=nil)
    if page
      page == self.home_page
    else
      url == '/' + self.identifier
    end
  end

  def opened_abuse_complaint
    abuse_complaints.opened.first
  end

  def disable
    self.visible = false
    self.save
  end

  def enable
    self.visible = true
    self.save
  end

  def self.identification
    name
  end

  def exclude_verbs_on_activities
    %w[]
  end

  # Customize in subclasses
  def activities
    self.profile_activities.includes(:activity).order('updated_at DESC')
  end

  def may_display_field_to? field, user = nil
    # display if it isn't a field that can be enabled
    return true if !self.class.fields.include?(field.to_s) &&
                   !self.active_fields.include?(field.to_s)

    self.public_fields.include?(field.to_s) ||
      (user.present? && (user == self || user.is_a_friend?(self)))
  end

  # field => privacy (e.g.: "address" => "public")
  def fields_privacy
    self.data[:fields_privacy] ||= {}
    custom_field_privacy = {}
    self.custom_field_values.includes(:custom_field).pluck("custom_fields.name", :public).to_h.map do |field, is_public|
      custom_field_privacy[field] = 'public' if is_public
    end
    self.data[:fields_privacy].merge!(custom_field_privacy)

    self.data[:fields_privacy]
  end

  def custom_field_value(field_name)
    value = nil
    begin
     value = self.send(field_name)
    rescue NoMethodError
      value = self.custom_field_values.by_field(field_name).pluck(:value).first
    end
    value
  end

  def self.fields
    []
  end

  # abstract
  def active_fields
    []
  end

  def public_fields
    self.active_fields
  end

  def followed_by?(person)
    (person == self) || (person.is_member_of?(self)) || (person.in? self.followers)
  end

  def in_social_circle?(person)
    (person == self) || (person.is_member_of?(self))
  end

  validates_inclusion_of :redirection_after_login, :in => Environment.login_redirection_options.keys, :allow_nil => true
  def preferred_login_redirection
    redirection_after_login.blank? ? environment.redirection_after_login : redirection_after_login
  end
  settings_items :custom_url_redirection, type: String, default: nil

  def remove_from_suggestion_list(person)
    suggestion = person.suggested_profiles.find_by suggestion_id: self.id
    suggestion.disable if suggestion
  end

  def allow_invitation_from(person)
    false
  end

  def allow_post_content?(person = nil)
    person.kind_of?(Profile) && person.has_permission?('post_content', self)
  end

  def allow_edit?(person = nil)
    person.kind_of?(Profile) && person.has_permission?('edit_profile', self)
  end

  def allow_destroy?(person = nil)
    person.kind_of?(Profile) && person.has_permission?('destroy_profile', self)
  end

  def allow_edit_design?(person = nil )
    person.kind_of?(Profile) && person.has_permission?('edit_profile_design', self)
  end

  def in_circle?(circle, follower)
    ProfileFollower.with_follower(follower).with_circle(circle).with_profile(self).present?
  end

  def available_blocks(person)
    blocks = [ ArticleBlock, TagsCloudBlock, InterestTagsBlock, RecentDocumentsBlock, ProfileInfoBlock, LinkListBlock, MyNetworkBlock, FeedReaderBlock, ProfileImageBlock, LocationBlock, SlideshowBlock, ProfileSearchBlock, HighlightsBlock, MenuBlock ]
    # block exclusive to profiles that have blog
    blocks << BlogArchivesBlock if self.has_blog?
    # block exclusive for environment admin
    blocks << RawHTMLBlock if person.present? && person.is_admin?(self.environment)
    blocks + plugins.dispatch(:extra_blocks, type: self.class)
  end

  def self.default_quota
    # In megabytes
    nil
  end

  def disk_usage
    self.files.sum('size')
  end

  def update_disk_usage!
    self.metadata['disk_usage'] = self.disk_usage
    self.save
  end

  def allow_single_file?
    self.metadata["allow_single_file"] == "1"
  end

  #FIXME make this test
  def boxes_with_blocks
    self.boxes.with_blocks
  end

  DEFAULT_EXPORTABLE_FIELDS = %w(id name)

  N_('id')
  N_('name')

  def exportable_fields
    plugin_extra_fields = plugins.dispatch(:extra_exportable_fields, self)
    fields = active_fields + DEFAULT_EXPORTABLE_FIELDS + plugin_extra_fields
    first_fields = %w(id name email)
    fields -= first_fields
    fields.sort!
    ordered_fields = first_fields + fields
  end

  def method_missing(method, *args, &block)
    if method.to_s =~ /^(.+)_captcha_requirement$/
      environment.send(method)
    else
      super
    end
  end

  def display_private_info_to?(person)
    person.present? && (person.is_admin? || (person == self))
  end

  private

  def super_upload_quota
    if kinds.present?
      # Returns 'unlimited' if one of the kinds has an unlimited quota.
      # Otherwise, returns the biggest quota
      quotas = kinds.map(&:upload_quota)
      (nil.in? quotas) ? nil : quotas.max
    else
      environment.quota_for(self.class)
    end
  end
end
