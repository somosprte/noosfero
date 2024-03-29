# Task is the base class of ... tasks! Its instances represents tasks that must
# be confirmed by someone (like an environment administrator) or by noosfero
# itself.
#
# The specific types of tasks <em>must</em> override the #perform method, so
# the actual action associated to the type of task can be performed. See the
# documentation of the #perform method for details.
#
# This class has a +data+ field of type <tt>text</tt>, where you can store any
# type of data (as serialized Ruby objects) you need for your subclass (which
# will need to declare <ttserialize</tt> itself).
class Task < ApplicationRecord

  extend ActsAsHavingSettings::ClassMethods
  acts_as_having_settings field: :data

  store_accessor :metadata
  include MetadataScopes

  include Notifiable

  will_notify :generic_message
  will_notify :target_notification
  will_notify :invitation_notification

  module Status
    # the status of tasks just created
    ACTIVE = 1

    # the status of a task that was cancelled.
    CANCELLED = 2

    # the status of a task that was successfully finished
    FINISHED = 3

    # the status of a task that was created but is not displayed yet
    HIDDEN = 4

    def self.names
      [nil, N_('Active'), N_('Cancelled'), N_('Finished'), N_('Hidden')]
    end
  end

  include Noosfero::Plugin::HotSpot

  belongs_to :requestor, class_name: 'Profile', foreign_key: :requestor_id, optional: true
  belongs_to :target, foreign_key: :target_id, polymorphic: true, optional: true
  belongs_to :responsible, class_name: 'Person', foreign_key: :responsible_id, optional: true
  belongs_to :closed_by, class_name: 'Person', foreign_key: :closed_by_id, optional: true

  validates_uniqueness_of :code, :on => :create
  validates_presence_of :code

  attr_protected :status

  settings_items :email_template_id, :type => :integer

  def initialize(*args)
    super
    self.status = (args.first ? args.first[:status] : nil) || Task::Status::ACTIVE
  end

  attr_accessor :code_length
  before_validation(:on => :create) do |task|
    if task.code.nil?
      task.code = Task.generate_code(task.code_length)
      while Task.from_code(task.code).first
        task.code = Task.generate_code(task.code_length)
      end
    end
  end

  after_create do |task|
    unless task.status == Task::Status::HIDDEN
      task.send(:send_notification, :created)

      begin
        target_msg = task.target_notification_message
        if target_msg && task.target && !task.target.notification_emails.empty?
          if target_profile_accepts_notification?(task)
            notify(:target_notification, task, target_msg)
          end
        end
      rescue NotImplementedError => ex
        Rails.logger.info ex.to_s
      end
    end
  end

  def display_api_content_by_default?
    false
  end

  def api_content(options = {})
    nil
  end

  def api_content=(values = {})
  end

  def target_profile_accepts_notification?(task)
    if task.target.kind_of? Organization
      return task.target.profile_admin_mail_notification
    else
      true
    end
  end

  # this method finished the task. It calls #perform, which must be overridden
  # by subclasses. At the end a message (as returned by #finish_message) is
  # sent to the requestor with #notify_requestor.
  def finish(closed_by=nil)
    transaction do
      close(Task::Status::FINISHED, closed_by)
      self.perform
      send_notification(:finished)
    end
    after_finish
  end

  # :nodoc:
  def after_finish
  end

  def reject_explanation=(reject_explanation='')
    self.data[:reject_explanation] = reject_explanation
  end

  def reject_explanation
    self.data[:reject_explanation]
  end

  # this method cancels the task. At the end a message (as returned by
  # #cancel_message) is sent to the requestor with #notify_requestor.
  def cancel(closed_by=nil)
    transaction do
      close(Task::Status::CANCELLED, closed_by)
      send_notification(:cancelled)
    end
  end

  class KindOfValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      environment = record.environment || Environment.default
      klass = options[:kind]
      group = klass.to_s.downcase.pluralize
      id = attribute.to_s + "_id"
      if environment.respond_to?(group)
        attrb = value || environment.send(group).find_by(id: record.send(id))
      else
        attrb = value || klass.find_by(id: record.send(id))
      end
      if attrb.respond_to?(klass.to_s.downcase + "?")
        unless attrb.send(klass.to_s.downcase + "?")
          record.errors[attribute] << (options[:message] || "should be "+ klass.to_s.downcase)
        end
      else
        unless attrb.class == klass
          record.errors[attribute] << (options[:message] || "should be "+ klass.to_s.downcase)
        end
      end
    end
  end

  def close(status, closed_by)
    self.status = status
    self.end_date = Time.now
    self.closed_by = closed_by
    self.save!
  end

  # Here are the tasks customizable options.

  def title
    _("Task")
  end

  def subject
    nil
  end

  def linked_subject
    nil
  end

  def information
    {:message => _('%{requestor} sent you a task.')}
  end

  def accept_details
    false
  end

  def reject_details
    false
  end

  def custom_fields_moderate
    false
  end

  def custom_action_bar
    false
  end

  def footer
    false
  end

  def icon
    {:type => :defined_image, :src => "/images/icons-app/user-minor.png", :name => requestor.name, :url => requestor.url}
  end

  def default_decision
    'skip'
  end

  def accept_disabled?
    false
  end

  def reject_disabled?
    false
  end

  def skip_disabled?
    false
  end

  # The message that will be sent to the requestor of the task when the task is
  # created.
  def task_created_message
    raise NotImplementedError, "#{self} does not implement #task_created_message"
  end

  # The message that will be sent to the requestor of the task when its
  # finished.
  def task_finished_message
    raise NotImplementedError, "#{self} does not implement #task_finished_message"
  end

  # The message that will be sent to the requestor of the task when its
  # cancelled.
  def task_cancelled_message
    raise NotImplementedError, "#{self} does not implement #task_cancelled_message"
  end

  # The message that will be sent to the requestor of the task when its
  # activated.
  def task_activated_message
    raise NotImplementedError, "#{self} does not implement #task_cancelled_message"
  end

  # The message that will be sent to the *target* of the task when it is
  # created. The indent of this message is to notify the target about the
  # request that was just created for him/her.
  #
  # The implementation in this class returns +nil+, what makes the notification
  # not to be sent. If you want to send a notification to the target upon task
  # creation, override this method and return a String.
  def target_notification_message
    raise NotImplementedError, "#{self} does not implement #target_notification_message"
  end

  def target_notification_description
    ''
  end

  # What permission is required to perform task?
  def permission
    :perform_task
  end

  def environment
    return target if target.kind_of?(Environment)
    self.target.environment unless self.target.nil?
  end

  def activate
    self.status = Task::Status::ACTIVE
    save!
    self.send(:send_notification, :activated)

    begin
      target_msg = target_notification_message
       if target_msg && self.target && !self.target.notification_emails.empty?
         notify(:target_notification, self, target_msg)
       end
    rescue NotImplementedError => ex
      Rails.logger.info ex.to_s
    end
  end

  def email_template
    @email_template ||= email_template_id.present? ? EmailTemplate.find_by_id(email_template_id) : nil
  end

  def to_liquid
    HashWithIndifferentAccess.new({
      :requestor => requestor,
      :reject_explanation => reject_explanation,
      :code => code
    })
  end

  scope :pending, -> { where status: Task::Status::ACTIVE }
  scope :hidden, -> { where status: Task::Status::HIDDEN }
  scope :finished, -> { where status: Task::Status::FINISHED }
  scope :canceled, -> { where status: Task::Status::CANCELLED }
  scope :closed, -> { where status: [Task::Status::CANCELLED, Task::Status::FINISHED] }
  scope :opened, -> { where status: [Task::Status::ACTIVE, Task::Status::HIDDEN] }
  scope :of, -> type { where :type => type  if type }
  scope :order_by, -> attribute, ord {
      if ord.downcase.include? 'desc'
        order attribute.to_sym => :desc
      else
        order attribute.to_sym
      end
  }
  scope :like, -> field, value {
      if value and Task.column_names.include? field
        where "LOWER(#{field}) LIKE ?", "%#{value.downcase}%"
      end
  }

  scope :pending_all_by_filter, -> filter_type, filter_text {
    self.without_spam.pending.of(filter_type).like('data', filter_text)
  }

  scope :pending_all_by_profile_and_filter, -> profile, filter_type, filter_text {
    self.to(profile).without_spam.pending.of(filter_type).like('data', filter_text)
  }

  scope :to, lambda { |profile|
    environment_condition = nil
    if profile.person?
      envs_ids = Environment.all.select{ |env| profile.is_admin?(env) }.map{ |env| "target_id = #{env.id}"}.join(' OR ')
      environment_condition = envs_ids.blank? ? nil : "(target_type = 'Environment' AND (#{envs_ids}))"

      organizations = profile.memberships.all.select do |organization| 
        profile.has_permission?(:perform_task, organization) 
      end
      organization_ids = organizations.map{ |organization| "target_id = #{organization.id}"}.join(' OR ')

      organization_conditions = organization_ids.blank? ? nil : "(target_type = 'Profile' AND (#{organization_ids}))"
    end
    profile_condition = "(target_type = 'Profile' AND target_id = #{profile.id})"

    where [environment_condition, organization_conditions, profile_condition].compact.join(' OR ')
  }

  scope :from_closed_date, -> closed_from {
    where('tasks.end_date >= ?', closed_from.beginning_of_day) unless closed_from.blank?
  }

  scope :until_closed_date, -> closed_until {
    where('tasks.end_date <= ?', closed_until.end_of_day) unless closed_until.blank?
  }

  scope :from_creation_date, -> created_from {
    where('tasks.created_at >= ?', created_from.beginning_of_day) unless created_from.blank?
  }

  scope :until_creation_date, -> created_until {
    where('tasks.created_at <= ?', created_until.end_of_day) unless created_until.blank?
  }

  def self.pending_types_for(profile)
    Task.to(profile).pending.select('distinct type').map { |t| [t.class.name, t.title] }
  end

  def self.closed_types_for(profile)
    Task.to(profile).closed.select('distinct type').map { |t| [t.class.name, t.title] }
  end

  def opened?
    status == Task::Status::ACTIVE || status == Task::Status::HIDDEN
  end

  include Spammable

  #FIXME make this test
  def display_to?(user = nil)
    return true if self.target == user
    return false if !self.target.kind_of?(Environment) && self.target.person?

    if self.target.kind_of?(Environment)
      user.is_admin?(self.target)
    else
      self.target.members.by_role(self.target.roles.reject {|r| !r.has_permission?('perform_task')}).include?(user)
    end
  end


  protected

  # This method must be overrided in subclasses, and its implementation must do
  # the job the task is intended to. This method will be called when the finish
  # method is called.
  #
  # To cancel the finish of the task, you can throw an exception in perform.
  #
  # The implementation on Task class just does nothing.
  def perform
  end

  # Tells whether e-mail notifications must be sent or not. Returns
  # <tt>true</tt> by default (i.e. notification are sent), but can be overridden
  # in subclasses to disable notifications or even to send notifications based
  # on some conditions.
  def sends_email?
    true
  end

  # sends notification e-mail about a task, if the task has a requestor.
  #
  # If
  def send_notification(action)
    if sends_email?
      begin
        if self.requestor && !self.requestor.notification_emails.empty?
          notify(:generic_message, "task_#{action}", self)
        end
      rescue NotImplementedError => ex
        Rails.logger.info ex.to_s
      end
    end
  end

  # finds a task by its (generated) code. Only returns a task with the
  # specified code AND with status = Task::Status::ACTIVE.
  #
  # Can be used in subclasses to find only their instances.
  scope :from_code, -> code { where code: code, status: Task::Status::ACTIVE }

  class << self

    # generates a random code string consisting of length characters (or 36 by
    # default) in the ranges a-z and 0-9
    def generate_code(length = nil)
      chars = ('a'..'z').to_a + ('0'..'9').to_a
      code = ""
      (length || chars.size).times do |n|
        code << chars[rand(chars.size)]
      end
      code
    end

    def per_page
      10
    end

  end

end
