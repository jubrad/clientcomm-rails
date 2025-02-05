class User < ApplicationRecord
  has_many :reporting_relationships, dependent: :destroy
  has_many :clients, through: :reporting_relationships
  has_many :messages, through: :reporting_relationships
  belongs_to :department, optional: :true

  scope :active, -> { where(active: true) }

  scope :active_rr, lambda {
    joins(:reporting_relationships)
      .where(reporting_relationships: { active: true })
      .distinct
  }

  before_validation :normalize_phone_number, if: :phone_number_changed?
  validate :service_accepts_phone_number, if: :phone_number_changed?
  validate :no_active_reporting_relationships_if_inactive
  validates_associated :reporting_relationships, on: :update, message: I18n.t('activerecord.errors.models.user.attributes.reporting_relationships.invalid')

  validates :full_name, presence: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  after_save :broadcast_user_event

  def broadcast_user_event
    ActionCable.server.broadcast("events_#{id}", type: 'user', data: self.as_json)
  end

  def analytics_tracker_data
    {
      clients_count: clients_count,
      has_unread_messages: unread_messages_count > 0,
      unread_messages_count: unread_messages_count,
      symbols_count: symbols_count,
      court_dates_count: clients.where.not(next_court_date_at: nil).count
    }
  end

  def unread_messages_count
    # the number of messages received that are unread
    messages.unread.count
  end

  delegate :count, to: :clients, prefix: true

  def active_for_authentication?
    super && active
  end

  def inactive_message
    'Sorry, this account has been disabled. Please contact an administrator.'
  end

  def active_reporting_relationships
    reporting_relationships
      .includes(:client, :client_status)
      .active
      .order(Arel.sql('has_unread_messages DESC, COALESCE(reporting_relationships.last_contacted_at, reporting_relationships.created_at) DESC'))
  end

  def active_reporting_relationships_with_selection(selected_reporting_relationships: [])
    reporting_relationships
      .includes(:client)
      .active
      .sort_by do |rr|
        [selected_reporting_relationships.include?(rr.id) ? 1 : 0, rr.timestamp]
      end.reverse
  end

  def relationships_with_statuses_due_for_follow_up
    output = {}

    ClientStatus.where.not(followup_date: nil).map do |status|
      followup_date = Time.zone.now - status.followup_date.days
      warning_period = 5.days

      found_rrs = reporting_relationships
                  .active
                  .where(client_status: status)
                  .where('last_contacted_at < ?', followup_date + warning_period)

      output[status.name] = found_rrs.pluck(:id) if found_rrs.present?
    end

    output
  end

  def mark_messages_read
    reporting_relationships.each(&:mark_messages_read)
    self.update!(has_unread_messages: false)
  end

  def set_has_unread_messages
    self.update!(has_unread_messages: false) if reporting_relationships.active.where(has_unread_messages: true).empty?
  end

  private

  def symbols_count
    reporting_relationships.where.not(category: ReportingRelationship::CATEGORIES.keys.first).count
  end

  def no_active_reporting_relationships_if_inactive
    errors.add(:active, :active_reporting_relationships) if active == false && reporting_relationships.where(active: true).any?
  end

  def normalize_phone_number
    return unless self.phone_number

    self.phone_number = SMSService.instance.number_lookup(phone_number: self.phone_number)
  rescue SMSService::NumberNotFound
    @bad_number = true
  end

  def service_accepts_phone_number
    errors.add(:phone_number, :invalid) if @bad_number
  end
end
