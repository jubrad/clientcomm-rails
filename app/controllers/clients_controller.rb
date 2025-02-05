class ClientsController < ApplicationController
  before_action :authenticate_user!

  def index
    @highlight_blob = HighlightBlob.first
    @reporting_relationships = current_user.active_reporting_relationships
    @relationships_by_status = current_user.relationships_with_statuses_due_for_follow_up
    analytics_track(
      label: 'clients_view',
      data: current_user.analytics_tracker_data
    )

    respond_to do |format|
      format.html
      format.js
    end
  end

  def new
    @client = Client.new
    @reporting_relationship = @client.reporting_relationships.build(user: current_user)

    analytics_track(
      label: 'client_create_view'
    )
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      analytics_track(
        label: 'client_create_success',
        data: @client.reload.analytics_tracker_data
      )
      rr = current_user.reporting_relationships.find_by(client: @client)
      redirect_to reporting_relationship_path rr
    else
      
      @existing_client = Client.find_by(phone_number: @client.phone_number)

      @conflicting_user = @existing_client
        &.users&.active_rr
        &.where&.not(id: current_user.id)
        &.find_by(department: current_user.department)
      

      catch(:handled) do
        handle_new_relationship_with_existing_client
        handle_conflicting_user
        handle_existing_relationship
        handle_errors_other_than_phone_number_taken
      end
    end
  end

  def edit
    @client = current_user.clients.find(params[:id])
    @reporting_relationship = @client.reporting_relationships.find_by(user: current_user)
    @transfer_reporting_relationship = ReportingRelationship.new
    @transfer_users = ListMaker.transfer_users user: current_user
    @merge_reporting_relationship = MergeReportingRelationship.new
    @merge_clients = ListMaker.merge_clients user: current_user, client: @client

    analytics_track(
      label: 'client_edit_view',
      data: @client.analytics_tracker_data.merge(source: request.referer)
    )
  end

  def update
    @client = current_user.clients.find(params[:id])
    @client.assign_attributes(client_params)
    @reporting_relationship = @client.reporting_relationship(user: current_user)

    if @client.save
      catch(:handled) do
        handle_active_client
        handle_deactivated_client
      end
      return
    elsif @client.errors.of_kind?(:phone_number, :taken)
      @existing_client = Client.find_by(phone_number: @client.phone_number)
      error_text = phone_number_conflict_error_text

      if error_text
        @client.errors.delete(:phone_number)
        @client.errors.add(:phone_number, error_text)
      end
    end

    track_errors('edit')
    flash.now[:alert] = t('flash.errors.client.invalid')

    @transfer_reporting_relationship = ReportingRelationship.new
    @transfer_users = ListMaker.transfer_users user: current_user
    @merge_reporting_relationship = MergeReportingRelationship.new
    @merge_clients = ListMaker.merge_clients user: current_user, client: @client

    render :edit
  end

  private

  def track_errors(method)
    error_types = []
    @client.errors.details.each do |column, errors|
      errors.each do |item|
        error_types << "#{column}_#{item[:error]}"
      end
    end

    analytics_track(
      label: "client_#{method}_error",
      data: @client.analytics_tracker_data.merge(error_types: error_types)
    )
  end

  def phone_number_conflict_error_text
    active_current_rr = ReportingRelationship.find_by(user: current_user, client: @existing_client, active: true)
    conflicting_user = @existing_client.users.where.not(id: current_user.id).find_by(department: current_user.department)
    error_text = nil

    if active_current_rr
      error_text = t(
        'activerecord.errors.models.reporting_relationship.attributes.client.existing_user_relationship',
        client_full_name: "#{@existing_client.first_name} #{@existing_client.last_name}",
        href: reporting_relationship_url(active_current_rr)
      )
    elsif conflicting_user
      error_text = t(
        'activerecord.errors.models.reporting_relationship.attributes.client.existing_dept_relationship',
        user_full_name: conflicting_user.full_name
      )
    end

    error_text
  end

  def handle_active_client
    return unless @reporting_relationship.reload.active

    NotificationSender.notify_users_of_changes(user: current_user, client: @client)
    @client.update(next_court_date_set_by_user: @client.next_court_date_at_previous_change.last.present?) if @client.previous_changes.keys.include?('next_court_date_at')
    analytics_track(
      label: 'client_edit_success',
      data: @client.analytics_tracker_data
              .merge(@reporting_relationship.analytics_tracker_data)
    )
    redirect_to reporting_relationship_path(@reporting_relationship)
    throw :handled
  end

  def handle_deactivated_client
    return if @reporting_relationship.reload.active

    @reporting_relationship.deactivate
    analytics_track(
      label: 'client_deactivate_success',
      data: {
        client_id: @client.id,
        client_duration: (Date.current - @client.relationship_started(user: current_user).to_date).to_i
      }
    )

    redirect_to clients_path, notice: t('flash.notices.client.deactivated', client_full_name: @client.full_name)
    throw :handled
  end

  def handle_errors_other_than_phone_number_taken
    return if @client.errors.of_kind?(:phone_number, :taken)

    track_errors('create')
    flash.now[:alert] = t('flash.errors.client.invalid')
    render :new
    throw :handled
  end

  def handle_conflicting_user
    return unless @client.errors.of_kind?(:phone_number, :taken)
    return unless @conflicting_user

    @client.errors.delete(:phone_number)
    @client.errors.add(
      :phone_number,
      t(
        'activerecord.errors.models.reporting_relationship.attributes.client.existing_dept_relationship',
        user_full_name: @conflicting_user.full_name
      )
    )
    track_errors('create')
    flash.now[:alert] = t('flash.errors.client.invalid')
    render :new
    throw :handled
  end

  def handle_existing_relationship
    return unless @client.errors.of_kind?(:phone_number, :taken)
    return if @conflicting_user

    existing_relationship = current_user.reporting_relationships.find_by(client: @existing_client)
    return unless existing_relationship

    flash[:notice] = t('flash.notices.client.taken') if existing_relationship.active?
    existing_relationship.update(active: true)
    redirect_to reporting_relationship_path(existing_relationship)
    throw :handled
  end

  def handle_new_relationship_with_existing_client
    return unless @client.errors.of_kind?(:phone_number, :taken)
    return if @conflicting_user
    return if current_user.clients.include?(@existing_client)

    rr_params = client_params[:reporting_relationships_attributes]['0']
    @reporting_relationship = @existing_client.reporting_relationships.new(rr_params)
    if params[:user_confirmed] == 'true'
      @reporting_relationship.save!
      redirect_to reporting_relationship_path(@reporting_relationship)
    else
      render :confirm
    end
    throw :handled
  end

  def client_params
    params.fetch(:client)
          .permit(:first_name,
                  :last_name,
                  :client_status_id,
                  :id_number,
                  :phone_number,
                  :next_court_date_at,
                  :notes,
                  reporting_relationships_attributes: %i[
                    id notes client_status_id active
                  ],
                  surveys_attributes: [
                    survey_response_ids: []
                  ]).tap do |p|
      p[:reporting_relationships_attributes]['0'][:user_id] = current_user.id
      p[:surveys_attributes]['0'][:user_id] = current_user.id if p.dig(:surveys_attributes, '0')
    end
  end
end
