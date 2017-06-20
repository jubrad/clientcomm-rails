module TwilioHelper
  def twilio_post_sms(tw_params = twilio_new_message_params)
    twilio_post tw_params, correct_signature(tw_params), '/incoming/sms'
  end

  def twilio_post_sms_status(tw_params = twilio_status_update_params)
    twilio_post tw_params, correct_signature(tw_params), '/incoming/sms/status'
  end

  def twilio_post(tw_params, post_sig, post_url)
    if Capybara.current_session.server
      conn = Faraday.new("#{myhost}")
      conn.post do |req|
        req.url post_url
        req.headers[post_header_name] = post_sig
        req.body = tw_params
      end
    elsif defined?(page)
      page.driver.header post_header_name, post_sig
      page.driver.post post_url, tw_params
    else
      post post_url, params: tw_params, headers: {post_header_name => post_sig}
    end
  end

  def twilio_clear_after
    if defined?(page)
      page.driver.header post_header_name, nil
    end
  end

  def post_header_name
    'X-Twilio-Signature'
  end

  def twilio_message_text
    "This is a test message."
  end

  def twilio_new_message_params(
    from_number = '+12425551212',
    sms_sid = SecureRandom.hex(17),
    msg_txt = twilio_message_text
  )
    {
      "ToCountry"=>"US",
      "ToState"=>"CA",
      "SmsMessageSid"=>sms_sid,
      "NumMedia"=>"0",
      "ToCity"=>"",
      "FromZip"=>"94005",
      "SmsSid"=>sms_sid,
      "FromState"=>"CA",
      "SmsStatus"=>"received",
      "FromCity"=>"SAN FRANCISCO",
      "Body"=>msg_txt,
      "FromCountry"=>"US",
      "To"=>"+12435551212",
      "ToZip"=>"",
      "AddOns"=>"{\"status\":\"successful\",\"message\":null,\"code\":null,\"results\":{}}",
      "NumSegments"=>"1",
      "MessageSid"=>sms_sid,
      "AccountSid"=>"077541f41cce52ea6c4944fa6823a4a277",
      "From"=>from_number,
      "ApiVersion"=>"2010-04-01",
      "controller"=>"twilio",
      "action"=>"incoming_sms"
    }
  end

  def twilio_status_update_params(
    from_number = '+12425551212',
    sms_sid = SecureRandom.hex(17),
    sms_status = 'delivered'
  )
    {
      "SmsSid"=>sms_sid,
      "SmsStatus"=>sms_status,
      "MessageStatus"=>sms_status,
      "To"=>"+12435551212",
      "MessageSid"=>sms_sid,
      "AccountSid"=>"077541f41cce52ea6c4944fa6823a4a277",
      "From"=>from_number,
      "ApiVersion"=>"2010-04-01",
      "controller"=>"twilio",
      "action"=>"incoming_sms_status"
    }
  end

  private

  def myhost
    if Capybara.current_session.server
      return "http://#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}"
    end
    Capybara.current_host || Capybara.default_host
  end

  def correct_signature(tw_params = twilio_new_message_params)
    Twilio::Util::RequestValidator.new(ENV['TWILIO_AUTH_TOKEN'])
      .build_signature_for("#{myhost}/incoming/sms", tw_params)
  end
end
