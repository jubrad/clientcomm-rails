require 'levenshtein'

module AnalyticsHelper
  # Send the provided tracking data through to the AnalyticsService
  def analytics_track(label:, data: {})
    # NOTE: May eventually want to diverge distinct and visitor IDs, so
    #       tracking them separately for now.
    tracking_data = data.merge(
      ip: visitor_ip,
      deploy: deploy_prefix,
      visitor_id: visitor_id,
      treatment_group: treatment_group
    ).merge(utm)
    tracking_id = distinct_id
    tracking_data = tracking_data.except(:current_user_id)

    AnalyticsService.track(
      distinct_id: tracking_id,
      label: label,
      user_agent: user_agent,
      data: tracking_data
    )
  end

  private

  def treatment_group
    current_user&.treatment_group
  end

  def utm
    utm_params = {}
    request.GET.each do |k, v|
      utm_params[k] = v if /^utm_(.*)/.match?(k)
    end
    utm_params
  end

  def user_agent
    request.env['HTTP_USER_AGENT']
  rescue NameError
    nil
  end

  def visitor_id
    session[:visitor_id]
  rescue NameError
    nil
  end

  def visitor_ip
    request.remote_ip
  rescue NameError
    nil
  end

  def distinct_id
    if current_user
      "#{deploy_prefix}-#{current_user.id}"
    else
      "#{deploy_prefix}-#{visitor_id}"
    end
  end

  def deploy_prefix
    return URI.parse(Rails.configuration.x.deploy_base_url).hostname.split('.')[0...-1].join('_')
    #return "test"
  end

  def analytics_message_track(message:, send_at:, has_attachment:)
    if send_at.present?
      analytics_track(
        label: 'message_scheduled',
        data: message.analytics_tracker_data.merge(mass_message: false)
      )
    else
      tracking_data = { mass_message: false }
      tracking_data[:positive_template] = params[:positive_template_type].present?
      tracking_data[:positive_template_type] = params[:positive_template_type]
      tracking_data[:attachment] = has_attachment

      tracking_data[:welcome_template] = false
      if params[:welcome_message_original].present?
        distance = 1 - Levenshtein.normalized_distance(params[:welcome_message_original], message.body)
        tracking_data[:welcome_template] = true if distance >= 0.85
        analytics_track(
          label: 'welcome_prompt_send',
          data: message.analytics_tracker_data.merge(tracking_data)
        )
      end

      analytics_track(
        label: 'message_send',
        data: message.analytics_tracker_data.merge(tracking_data)
      )
    end
  end
end
